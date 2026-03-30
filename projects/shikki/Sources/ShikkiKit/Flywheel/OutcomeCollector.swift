import Foundation

// MARK: - OutcomeRecord

/// An anonymized outcome record from a completed task or PR.
/// Contains NO PII, no file paths, no source code — only statistical data.
public struct OutcomeRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let category: OutcomeCategory
    public let outcome: OutcomeType
    public let metrics: OutcomeMetrics

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        category: OutcomeCategory,
        outcome: OutcomeType,
        metrics: OutcomeMetrics
    ) {
        self.id = id
        self.timestamp = timestamp
        self.category = category
        self.outcome = outcome
        self.metrics = metrics
    }
}

// MARK: - OutcomeType

/// What happened: success, failure, or partial.
public enum OutcomeType: String, Codable, Sendable, Equatable {
    case success
    case failure
    case partial
    case timeout
    case recovered
}

// MARK: - OutcomeMetrics

/// Anonymized statistical metrics for an outcome.
public struct OutcomeMetrics: Codable, Sendable, Equatable {
    /// Duration in seconds (bucketed).
    public var durationBucket: DurationBucket?
    /// Risk score that was predicted vs actual outcome.
    public var predictedRiskScore: Double?
    /// Whether a bug was found post-merge.
    public var postMergeBug: Bool?
    /// Number of context resets during the task.
    public var contextResets: Int?
    /// Watchdog recovery count.
    public var watchdogRecoveries: Int?
    /// Language/platform identifier (anonymized).
    public var platform: String?
    /// Task type identifier.
    public var taskType: String?
    /// File count bucket.
    public var fileCountBucket: SizeBucket?
    /// Total churn bucket.
    public var churnBucket: SizeBucket?

    public init(
        durationBucket: DurationBucket? = nil,
        predictedRiskScore: Double? = nil,
        postMergeBug: Bool? = nil,
        contextResets: Int? = nil,
        watchdogRecoveries: Int? = nil,
        platform: String? = nil,
        taskType: String? = nil,
        fileCountBucket: SizeBucket? = nil,
        churnBucket: SizeBucket? = nil
    ) {
        self.durationBucket = durationBucket
        self.predictedRiskScore = predictedRiskScore
        self.postMergeBug = postMergeBug
        self.contextResets = contextResets
        self.watchdogRecoveries = watchdogRecoveries
        self.platform = platform
        self.taskType = taskType
        self.fileCountBucket = fileCountBucket
        self.churnBucket = churnBucket
    }
}

// MARK: - Duration Buckets

/// Bucketed duration to prevent fingerprinting.
public enum DurationBucket: String, Codable, Sendable, Equatable {
    case under1min = "<1m"
    case under5min = "1-5m"
    case under15min = "5-15m"
    case under30min = "15-30m"
    case under1hr = "30-60m"
    case over1hr = ">1h"

    public static func from(seconds: TimeInterval) -> DurationBucket {
        switch seconds {
        case ..<60: return .under1min
        case 60..<300: return .under5min
        case 300..<900: return .under15min
        case 900..<1800: return .under30min
        case 1800..<3600: return .under1hr
        default: return .over1hr
        }
    }
}

// MARK: - Size Buckets

/// Bucketed size to prevent fingerprinting.
public enum SizeBucket: String, Codable, Sendable, Equatable {
    case tiny = "1-5"
    case small = "6-20"
    case medium = "21-50"
    case large = "51-200"
    case huge = ">200"

    public static func from(count: Int) -> SizeBucket {
        switch count {
        case ..<6: return .tiny
        case 6..<21: return .small
        case 21..<51: return .medium
        case 51..<201: return .large
        default: return .huge
        }
    }
}

// MARK: - OutcomeCollector

/// Collects anonymized outcome data from agent events.
/// Listens to the EventBus and extracts outcome signals.
/// All data is stripped of PII before storage.
public actor OutcomeCollector {
    private var records: [OutcomeRecord] = []
    private let maxBufferSize: Int
    private let telemetryStore: TelemetryConfigStore
    private var flushHandler: (@Sendable ([OutcomeRecord]) async -> Void)?

    public init(
        telemetryStore: TelemetryConfigStore,
        maxBufferSize: Int = 1000
    ) {
        self.telemetryStore = telemetryStore
        self.maxBufferSize = maxBufferSize
    }

    /// Set a handler called when the buffer needs flushing.
    public func setFlushHandler(_ handler: @escaping @Sendable ([OutcomeRecord]) async -> Void) {
        self.flushHandler = handler
    }

    /// Record an outcome from a completed event.
    public func record(_ outcome: OutcomeRecord) async {
        guard await telemetryStore.isCollectionEnabled() else { return }

        let sharingAllowed = await telemetryStore.isSharingAllowed(for: outcome.category)
        let isLocal = await telemetryStore.current().level == .local
        guard sharingAllowed || isLocal else { return }

        records.append(outcome)

        if records.count >= maxBufferSize {
            await flush()
        }
    }

    /// Create an outcome record from a ShikkiEvent.
    public func collectFromEvent(_ event: ShikkiEvent) async {
        guard await telemetryStore.isCollectionEnabled() else { return }

        guard let record = Self.extractOutcome(from: event) else { return }
        await self.record(record)
    }

    /// Flush buffered records to the flush handler.
    public func flush() async {
        guard !records.isEmpty else { return }
        let batch = records
        records = []
        await flushHandler?(batch)
    }

    /// Get current buffer count.
    public func bufferedCount() -> Int {
        records.count
    }

    /// Get all buffered records (for local analysis).
    public func bufferedRecords() -> [OutcomeRecord] {
        records
    }

    // MARK: - Event → Outcome Extraction

    /// Extract an anonymized outcome from a raw event.
    /// Returns nil if the event doesn't represent a completable outcome.
    static func extractOutcome(from event: ShikkiEvent) -> OutcomeRecord? {
        switch event.type {
        case .prVerdictSet:
            return extractPROutcome(from: event)
        case .shipCompleted, .shipAborted:
            return extractShipOutcome(from: event)
        case .testRun:
            return extractTestOutcome(from: event)
        case .codeGenPipelineCompleted, .codeGenPipelineFailed:
            return extractCodeGenOutcome(from: event)
        case .scheduledTaskCompleted, .scheduledTaskFailed:
            return extractTaskOutcome(from: event)
        default:
            return nil
        }
    }

    private static func extractPROutcome(from event: ShikkiEvent) -> OutcomeRecord {
        let verdict = event.payload["verdict"]?.stringValue ?? "unknown"
        let outcomeType: OutcomeType = verdict == "approved" ? .success : .failure
        let riskScore = event.payload["riskScore"]?.doubleValue

        return OutcomeRecord(
            category: .riskScores,
            outcome: outcomeType,
            metrics: OutcomeMetrics(
                predictedRiskScore: riskScore,
                platform: event.payload["language"]?.stringValue
            )
        )
    }

    private static func extractShipOutcome(from event: ShikkiEvent) -> OutcomeRecord {
        let outcomeType: OutcomeType = event.type == .shipCompleted ? .success : .failure
        let duration = event.metadata?.duration

        return OutcomeRecord(
            category: .taskOutcomes,
            outcome: outcomeType,
            metrics: OutcomeMetrics(
                durationBucket: duration.map { DurationBucket.from(seconds: $0) },
                taskType: "ship"
            )
        )
    }

    private static func extractTestOutcome(from event: ShikkiEvent) -> OutcomeRecord {
        let passed = event.payload["passed"]?.boolValue ?? false

        return OutcomeRecord(
            category: .taskOutcomes,
            outcome: passed ? .success : .failure,
            metrics: OutcomeMetrics(
                platform: event.payload["language"]?.stringValue,
                taskType: "test"
            )
        )
    }

    private static func extractCodeGenOutcome(from event: ShikkiEvent) -> OutcomeRecord {
        let outcomeType: OutcomeType = event.type == .codeGenPipelineCompleted ? .success : .failure
        let duration = event.metadata?.duration

        return OutcomeRecord(
            category: .taskOutcomes,
            outcome: outcomeType,
            metrics: OutcomeMetrics(
                durationBucket: duration.map { DurationBucket.from(seconds: $0) },
                taskType: "codegen"
            )
        )
    }

    private static func extractTaskOutcome(from event: ShikkiEvent) -> OutcomeRecord {
        let outcomeType: OutcomeType = event.type == .scheduledTaskCompleted ? .success : .failure
        let duration = event.metadata?.duration

        return OutcomeRecord(
            category: .taskOutcomes,
            outcome: outcomeType,
            metrics: OutcomeMetrics(
                durationBucket: duration.map { DurationBucket.from(seconds: $0) },
                taskType: "scheduled"
            )
        )
    }
}
