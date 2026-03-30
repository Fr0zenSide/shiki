import Foundation
import Logging

// MARK: - AggregationBatch

/// A batch of anonymized outcomes ready for sync.
public struct AggregationBatch: Codable, Sendable {
    public let batchId: UUID
    public let timestamp: Date
    public let installId: String
    public let outcomes: [OutcomeRecord]
    public let summary: BatchSummary

    public init(
        batchId: UUID = UUID(),
        timestamp: Date = Date(),
        installId: String,
        outcomes: [OutcomeRecord]
    ) {
        self.batchId = batchId
        self.timestamp = timestamp
        self.installId = installId
        self.outcomes = outcomes
        self.summary = BatchSummary.compute(from: outcomes)
    }
}

// MARK: - BatchSummary

/// Statistical summary of a batch for quick analysis.
public struct BatchSummary: Codable, Sendable, Equatable {
    public var totalOutcomes: Int
    public var successCount: Int
    public var failureCount: Int
    public var successRate: Double
    public var categoryBreakdown: [String: Int]

    public static func compute(from outcomes: [OutcomeRecord]) -> BatchSummary {
        let total = outcomes.count
        let successes = outcomes.filter { $0.outcome == .success }.count
        let failures = outcomes.filter { $0.outcome == .failure }.count

        var categoryBreakdown: [String: Int] = [:]
        for outcome in outcomes {
            categoryBreakdown[outcome.category.rawValue, default: 0] += 1
        }

        return BatchSummary(
            totalOutcomes: total,
            successCount: successes,
            failureCount: failures,
            successRate: total > 0 ? Double(successes) / Double(total) : 0.0,
            categoryBreakdown: categoryBreakdown
        )
    }
}

// MARK: - CommunityAggregator

/// EventPersister implementation that anonymizes, batches, and (in future) syncs
/// outcome data to the community cloud API.
///
/// Architecture:
/// ```
/// EventBus → CommunityAggregator (anonymize + batch)
///         → Local CalibrationStore (update weights from outcomes)
///         → [Future] Cloud API (sync anonymized batches)
/// ```
public actor CommunityAggregator: EventPersister {
    private let telemetryStore: TelemetryConfigStore
    private let outcomeCollector: OutcomeCollector
    private let calibrationStore: CalibrationStore
    private let logger: Logger

    private var pendingBatches: [AggregationBatch] = []
    private let batchSize: Int
    private var eventCount: Int = 0

    public init(
        telemetryStore: TelemetryConfigStore,
        outcomeCollector: OutcomeCollector,
        calibrationStore: CalibrationStore,
        batchSize: Int = 100,
        logger: Logger = Logger(label: "shikki.community-aggregator")
    ) {
        self.telemetryStore = telemetryStore
        self.outcomeCollector = outcomeCollector
        self.calibrationStore = calibrationStore
        self.batchSize = batchSize
        self.logger = logger
    }

    /// EventPersister conformance: persist an event by extracting its outcome.
    nonisolated public func persist(_ event: ShikkiEvent) async throws {
        await collectEvent(event)
    }

    /// Internal collection with actor isolation.
    private func collectEvent(_ event: ShikkiEvent) async {
        let config = await telemetryStore.current()
        guard config.level != .off else { return }

        await outcomeCollector.collectFromEvent(event)
        eventCount += 1

        // Check if we should batch
        let bufferedCount = await outcomeCollector.bufferedCount()
        if bufferedCount >= batchSize {
            await createBatch()
        }
    }

    /// Create a batch from buffered outcomes.
    public func createBatch() async {
        let records = await outcomeCollector.bufferedRecords()
        guard !records.isEmpty else { return }

        let config = await telemetryStore.current()

        // Filter records by sharing consent
        let shareable: [OutcomeRecord]
        if config.level == .community {
            shareable = records.filter { config.sharedCategories.contains($0.category) }
        } else {
            shareable = records
        }

        guard !shareable.isEmpty else { return }

        let batch = AggregationBatch(installId: config.installId, outcomes: shareable)
        pendingBatches.append(batch)

        // Flush the collector
        await outcomeCollector.flush()

        logger.debug("Created batch \(batch.batchId) with \(shareable.count) outcomes")
    }

    /// Get pending batches (for future cloud sync).
    public func pendingBatchCount() -> Int {
        pendingBatches.count
    }

    /// Get all pending batches.
    public func allPendingBatches() -> [AggregationBatch] {
        pendingBatches
    }

    /// Mark batches as synced (remove from pending).
    public func markSynced(batchIds: Set<UUID>) {
        pendingBatches.removeAll { batchIds.contains($0.batchId) }
    }

    /// Get the total event count processed.
    public func totalEventsProcessed() -> Int {
        eventCount
    }

    /// Get a status summary for the TUI.
    public func statusSummary() async -> FlywheelStatus {
        let config = await telemetryStore.current()
        let buffered = await outcomeCollector.bufferedCount()
        let calibration = await calibrationStore.current()

        return FlywheelStatus(
            telemetryLevel: config.level,
            bufferedOutcomes: buffered,
            pendingBatches: pendingBatches.count,
            totalEventsProcessed: eventCount,
            calibrationVersion: calibration.version,
            lastSyncDate: config.lastSyncDate
        )
    }
}

// MARK: - FlywheelStatus

/// Status snapshot for the flywheel subsystem.
public struct FlywheelStatus: Sendable, Equatable {
    public let telemetryLevel: TelemetryLevel
    public let bufferedOutcomes: Int
    public let pendingBatches: Int
    public let totalEventsProcessed: Int
    public let calibrationVersion: Int
    public let lastSyncDate: Date?

    public init(
        telemetryLevel: TelemetryLevel,
        bufferedOutcomes: Int,
        pendingBatches: Int,
        totalEventsProcessed: Int,
        calibrationVersion: Int,
        lastSyncDate: Date?
    ) {
        self.telemetryLevel = telemetryLevel
        self.bufferedOutcomes = bufferedOutcomes
        self.pendingBatches = pendingBatches
        self.totalEventsProcessed = totalEventsProcessed
        self.calibrationVersion = calibrationVersion
        self.lastSyncDate = lastSyncDate
    }
}
