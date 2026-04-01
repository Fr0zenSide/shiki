import Foundation
import Logging

// MARK: - AggregationBatch

/// A batch of anonymized outcomes ready for sync.
public struct AggregationBatch: Codable, Sendable, Equatable {
    public let batchId: UUID
    public let createdAt: Date
    public let outcomes: [AnonymizedOutcome]
    public let schemaVersion: Int

    public static let currentSchemaVersion = 1

    public init(
        batchId: UUID = UUID(),
        createdAt: Date = Date(),
        outcomes: [AnonymizedOutcome],
        schemaVersion: Int = AggregationBatch.currentSchemaVersion
    ) {
        self.batchId = batchId
        self.createdAt = createdAt
        self.outcomes = outcomes
        self.schemaVersion = schemaVersion
    }
}

// MARK: - AggregatorConfig

/// Configuration for the community aggregator.
public struct AggregatorConfig: Sendable {
    /// Minimum outcomes before a batch is created.
    public let minBatchSize: Int
    /// Maximum time before forcing a batch (even if under minBatchSize).
    public let maxBatchAge: TimeInterval
    /// Maximum stored outcomes before oldest are dropped.
    public let maxStoredOutcomes: Int

    public static let `default` = AggregatorConfig(
        minBatchSize: 10,
        maxBatchAge: 86400,      // 24 hours
        maxStoredOutcomes: 1000
    )

    public init(
        minBatchSize: Int = 10,
        maxBatchAge: TimeInterval = 86400,
        maxStoredOutcomes: Int = 1000
    ) {
        self.minBatchSize = minBatchSize
        self.maxBatchAge = maxBatchAge
        self.maxStoredOutcomes = maxStoredOutcomes
    }
}

// MARK: - CommunityAggregator

/// EventPersister implementation that anonymizes events, batches them,
/// and stores them for periodic community sync.
///
/// Architecture:
/// 1. Receives raw ShikkiEvents via EventPersister protocol
/// 2. Filters for outcome-relevant events only
/// 3. Anonymizes into statistical buckets
/// 4. Accumulates in a local buffer
/// 5. Produces AggregationBatch when threshold reached
///
/// The actual network sync to Shiki Cloud is post-launch.
/// This implementation handles everything up to batch creation.
public actor CommunityAggregator: EventPersister {
    private var pendingOutcomes: [AnonymizedOutcome] = []
    private var pendingBatches: [AggregationBatch] = []
    private var lastBatchTime: Date = Date()
    private let config: AggregatorConfig
    private let telemetryStore: TelemetryConfigStore
    private let calibrationStore: CalibrationStore
    private let riskEngine: RiskScoringEngine
    private let logger: Logger

    public init(
        config: AggregatorConfig = .default,
        telemetryStore: TelemetryConfigStore = TelemetryConfigStore(),
        calibrationStore: CalibrationStore = CalibrationStore(),
        riskEngine: RiskScoringEngine = RiskScoringEngine(),
        logger: Logger = Logger(label: "shikki.community-aggregator")
    ) {
        self.config = config
        self.telemetryStore = telemetryStore
        self.calibrationStore = calibrationStore
        self.riskEngine = riskEngine
        self.logger = logger
    }

    // MARK: - EventPersister

    /// Process a raw event from the event bus.
    /// Only outcome-relevant events are processed.
    public func persist(_ event: ShikkiEvent) async throws {
        // Check telemetry level
        let telemetry = try telemetryStore.load()
        guard telemetry.isCollectionEnabled else { return }

        // Filter: only process outcome-relevant events
        guard let outcome = extractOutcome(from: event) else { return }

        pendingOutcomes.append(outcome)

        // Enforce max buffer size
        if pendingOutcomes.count > config.maxStoredOutcomes {
            pendingOutcomes.removeFirst(pendingOutcomes.count - config.maxStoredOutcomes)
        }

        // Check if batch threshold reached
        if shouldCreateBatch() {
            try createBatch()
        }
    }

    // MARK: - Batch Management

    /// Check whether a new batch should be created.
    func shouldCreateBatch() -> Bool {
        if pendingOutcomes.count >= config.minBatchSize {
            return true
        }
        let elapsed = Date().timeIntervalSince(lastBatchTime)
        if elapsed >= config.maxBatchAge && !pendingOutcomes.isEmpty {
            return true
        }
        return false
    }

    /// Create a batch from pending outcomes.
    func createBatch() throws {
        guard !pendingOutcomes.isEmpty else { return }

        let batch = AggregationBatch(outcomes: pendingOutcomes)
        pendingBatches.append(batch)
        pendingOutcomes.removeAll()
        lastBatchTime = Date()

        logger.debug("Created batch \(batch.batchId) with \(batch.outcomes.count) outcomes")
    }

    /// Get pending batches for sync (and clear them).
    public func drainBatches() -> [AggregationBatch] {
        let batches = pendingBatches
        pendingBatches.removeAll()
        return batches
    }

    /// Current number of pending (unbatched) outcomes.
    public var pendingCount: Int {
        pendingOutcomes.count
    }

    /// Current number of pending batches.
    public var batchCount: Int {
        pendingBatches.count
    }

    // MARK: - Event → Outcome Extraction

    /// Extract an anonymized outcome from a ShikkiEvent, if applicable.
    func extractOutcome(from event: ShikkiEvent) -> AnonymizedOutcome? {
        switch event.type {
        case .prVerdictSet:
            return extractPROutcome(from: event)
        case .shipCompleted:
            return extractShipOutcome(from: event)
        case .codeGenPipelineCompleted:
            return extractCodeGenOutcome(from: event)
        case .codeGenPipelineFailed:
            return extractCodeGenFailureOutcome(from: event)
        case .scheduledTaskCompleted, .scheduledTaskFailed:
            return extractSchedulerOutcome(from: event)
        default:
            return nil
        }
    }

    private func extractPROutcome(from event: ShikkiEvent) -> AnonymizedOutcome? {
        let verdict = event.payload["verdict"]?.stringValue ?? "unknown"
        let outcome: OutcomeType = verdict == "approve" ? .clean : .minorBug
        let riskScore = event.payload["riskScore"]?.doubleValue ?? 0.3

        return AnonymizedOutcome(
            taskType: .feature,
            language: event.payload["language"]?.stringValue,
            fileExtension: event.payload["primaryExtension"]?.stringValue ?? ".other",
            linesChangedBucket: extractSizeBucket(from: event, key: "linesChanged"),
            filesChangedBucket: extractSizeBucket(from: event, key: "filesChanged"),
            testCoverageBucket: nil,
            durationBucket: extractDurationBucket(from: event),
            outcome: outcome,
            riskPrediction: riskScore,
            riskTierPredicted: RiskTier.from(score: riskScore),
            contextResetsCount: event.payload["contextResets"]?.intValue ?? 0,
            watchdogEscalations: event.payload["watchdogEscalations"]?.intValue ?? 0,
            retryCount: event.payload["retries"]?.intValue ?? 0
        )
    }

    private func extractShipOutcome(from event: ShikkiEvent) -> AnonymizedOutcome? {
        let gatesPassed = event.payload["gatesPassed"]?.boolValue ?? true
        let outcome: OutcomeType = gatesPassed ? .clean : .testFailure

        return AnonymizedOutcome(
            taskType: .feature,
            language: event.payload["language"]?.stringValue,
            fileExtension: ".swift",
            linesChangedBucket: extractSizeBucket(from: event, key: "linesChanged"),
            filesChangedBucket: extractSizeBucket(from: event, key: "filesChanged"),
            testCoverageBucket: nil,
            durationBucket: extractDurationBucket(from: event),
            outcome: outcome,
            riskPrediction: event.payload["riskScore"]?.doubleValue ?? 0.3,
            riskTierPredicted: .medium
        )
    }

    private func extractCodeGenOutcome(from event: ShikkiEvent) -> AnonymizedOutcome? {
        AnonymizedOutcome(
            taskType: .feature,
            language: event.payload["language"]?.stringValue,
            fileExtension: event.payload["primaryExtension"]?.stringValue ?? ".other",
            linesChangedBucket: extractSizeBucket(from: event, key: "linesChanged"),
            filesChangedBucket: extractSizeBucket(from: event, key: "filesChanged"),
            testCoverageBucket: nil,
            durationBucket: extractDurationBucket(from: event),
            outcome: .clean,
            riskPrediction: event.payload["riskScore"]?.doubleValue ?? 0.2,
            riskTierPredicted: .low
        )
    }

    private func extractCodeGenFailureOutcome(from event: ShikkiEvent) -> AnonymizedOutcome? {
        AnonymizedOutcome(
            taskType: .feature,
            language: event.payload["language"]?.stringValue,
            fileExtension: event.payload["primaryExtension"]?.stringValue ?? ".other",
            linesChangedBucket: extractSizeBucket(from: event, key: "linesChanged"),
            filesChangedBucket: extractSizeBucket(from: event, key: "filesChanged"),
            testCoverageBucket: nil,
            durationBucket: extractDurationBucket(from: event),
            outcome: .majorBug,
            riskPrediction: event.payload["riskScore"]?.doubleValue ?? 0.5,
            riskTierPredicted: .high,
            retryCount: event.payload["retries"]?.intValue ?? 0
        )
    }

    private func extractSchedulerOutcome(from event: ShikkiEvent) -> AnonymizedOutcome? {
        let isSuccess = event.type == .scheduledTaskCompleted
        return AnonymizedOutcome(
            taskType: .config,
            language: nil,
            fileExtension: ".other",
            linesChangedBucket: .tiny,
            filesChangedBucket: .tiny,
            testCoverageBucket: nil,
            durationBucket: extractDurationBucket(from: event),
            outcome: isSuccess ? .clean : .minorBug,
            riskPrediction: 0.1,
            riskTierPredicted: .low
        )
    }

    // MARK: - Payload Helpers

    private func extractSizeBucket(from event: ShikkiEvent, key: String) -> SizeBucket {
        if let count = event.payload[key]?.intValue {
            return SizeBucket.from(count: count)
        }
        return .small
    }

    private func extractDurationBucket(from event: ShikkiEvent) -> DurationBucket {
        if let duration = event.metadata?.duration {
            return DurationBucket.from(seconds: duration)
        }
        return .medium
    }
}
