import Foundation
import Testing

@testable import ShikkiKit

@Suite("CommunityAggregator")
struct CommunityAggregatorTests {

    private func makeComponents() -> (TelemetryConfigStore, OutcomeCollector, CalibrationStore, CommunityAggregator) {
        let telemetryPath = NSTemporaryDirectory() + "shikki-agg-tel-\(UUID().uuidString).json"
        let calibrationPath = NSTemporaryDirectory() + "shikki-agg-cal-\(UUID().uuidString).json"

        let telemetryStore = TelemetryConfigStore(filePath: telemetryPath)
        let calibrationStore = CalibrationStore(filePath: calibrationPath)
        let collector = OutcomeCollector(telemetryStore: telemetryStore, maxBufferSize: 1000)
        let aggregator = CommunityAggregator(
            telemetryStore: telemetryStore,
            outcomeCollector: collector,
            calibrationStore: calibrationStore,
            batchSize: 5
        )
        return (telemetryStore, collector, calibrationStore, aggregator)
    }

    // MARK: - BatchSummary

    @Test("BatchSummary computes from outcomes")
    func batchSummaryComputation() {
        let records = [
            OutcomeRecord(category: .riskScores, outcome: .success, metrics: OutcomeMetrics()),
            OutcomeRecord(category: .riskScores, outcome: .failure, metrics: OutcomeMetrics()),
            OutcomeRecord(category: .taskOutcomes, outcome: .success, metrics: OutcomeMetrics()),
        ]
        let summary = BatchSummary.compute(from: records)
        #expect(summary.totalOutcomes == 3)
        #expect(summary.successCount == 2)
        #expect(summary.failureCount == 1)
        #expect(abs(summary.successRate - 2.0 / 3.0) < 0.01)
        #expect(summary.categoryBreakdown["riskScores"] == 2)
        #expect(summary.categoryBreakdown["taskOutcomes"] == 1)
    }

    @Test("BatchSummary from empty outcomes")
    func batchSummaryEmpty() {
        let summary = BatchSummary.compute(from: [])
        #expect(summary.totalOutcomes == 0)
        #expect(summary.successRate == 0.0)
    }

    // MARK: - AggregationBatch

    @Test("AggregationBatch creates with summary")
    func batchCreation() {
        let records = [
            OutcomeRecord(category: .taskOutcomes, outcome: .success, metrics: OutcomeMetrics()),
        ]
        let batch = AggregationBatch(installId: "test-install", outcomes: records)
        #expect(batch.installId == "test-install")
        #expect(batch.outcomes.count == 1)
        #expect(batch.summary.totalOutcomes == 1)
    }

    // MARK: - CommunityAggregator EventPersister

    @Test("Aggregator persists events as outcomes")
    func persistEvent() async throws {
        let (_, collector, _, aggregator) = makeComponents()

        let event = ShikkiEvent(
            source: .system,
            type: .shipCompleted,
            scope: .global,
            metadata: EventMetadata(duration: 120)
        )

        try await aggregator.persist(event)

        let total = await aggregator.totalEventsProcessed()
        #expect(total == 1)

        let buffered = await collector.bufferedCount()
        #expect(buffered == 1)
    }

    @Test("Aggregator ignores events when telemetry off")
    func ignoresWhenOff() async throws {
        let (telemetryStore, collector, _, aggregator) = makeComponents()
        try await telemetryStore.setLevel(.off)

        let event = ShikkiEvent(
            source: .system,
            type: .shipCompleted,
            scope: .global
        )

        try await aggregator.persist(event)

        let buffered = await collector.bufferedCount()
        #expect(buffered == 0)
    }

    @Test("Aggregator creates batch when threshold reached")
    func batchCreationOnThreshold() async throws {
        let (_, _, _, aggregator) = makeComponents()

        // batchSize is 5, send 5 outcome-producing events
        for _ in 0..<5 {
            let event = ShikkiEvent(
                source: .system,
                type: .shipCompleted,
                scope: .global,
                metadata: EventMetadata(duration: 60)
            )
            try await aggregator.persist(event)
        }

        let batches = await aggregator.pendingBatchCount()
        #expect(batches == 1)
    }

    @Test("Aggregator batch contains correct outcomes")
    func batchContents() async throws {
        let (_, _, _, aggregator) = makeComponents()

        for _ in 0..<5 {
            let event = ShikkiEvent(
                source: .system,
                type: .shipCompleted,
                scope: .global,
                metadata: EventMetadata(duration: 120)
            )
            try await aggregator.persist(event)
        }

        let allBatches = await aggregator.allPendingBatches()
        #expect(allBatches.count == 1)
        #expect(allBatches[0].outcomes.count == 5)
        #expect(allBatches[0].summary.successCount == 5)
    }

    @Test("Aggregator markSynced removes batches")
    func markSynced() async throws {
        let (_, _, _, aggregator) = makeComponents()

        for _ in 0..<5 {
            let event = ShikkiEvent(
                source: .system,
                type: .shipCompleted,
                scope: .global
            )
            try await aggregator.persist(event)
        }

        let batches = await aggregator.allPendingBatches()
        #expect(batches.count == 1)
        let batchId = batches[0].batchId

        await aggregator.markSynced(batchIds: [batchId])
        let remaining = await aggregator.pendingBatchCount()
        #expect(remaining == 0)
    }

    @Test("Aggregator non-outcome events counted but not buffered")
    func nonOutcomeEventsCounted() async throws {
        let (_, collector, _, aggregator) = makeComponents()

        let event = ShikkiEvent(source: .system, type: .heartbeat, scope: .global)
        try await aggregator.persist(event)

        let total = await aggregator.totalEventsProcessed()
        #expect(total == 1)

        let buffered = await collector.bufferedCount()
        #expect(buffered == 0)
    }

    // MARK: - FlywheelStatus

    @Test("Status summary reports correct state")
    func statusSummary() async throws {
        let (_, _, _, aggregator) = makeComponents()

        let event = ShikkiEvent(
            source: .system,
            type: .shipCompleted,
            scope: .global
        )
        try await aggregator.persist(event)

        let status = await aggregator.statusSummary()
        #expect(status.telemetryLevel == .local)
        #expect(status.totalEventsProcessed == 1)
        #expect(status.bufferedOutcomes == 1)
        #expect(status.pendingBatches == 0)
        #expect(status.calibrationVersion == 1)
    }

    // MARK: - Community Level Filtering

    @Test("Aggregator filters by shared categories in community mode")
    func communityFiltering() async throws {
        let telemetryPath = NSTemporaryDirectory() + "shikki-agg-filter-\(UUID().uuidString).json"
        let calibrationPath = NSTemporaryDirectory() + "shikki-agg-filter-cal-\(UUID().uuidString).json"

        let telemetryStore = TelemetryConfigStore(filePath: telemetryPath)
        try await telemetryStore.setLevel(.community)
        // Default shared: riskScores, watchdogPatterns, taskOutcomes

        let calibrationStore = CalibrationStore(filePath: calibrationPath)
        let collector = OutcomeCollector(telemetryStore: telemetryStore, maxBufferSize: 1000)
        let aggregator = CommunityAggregator(
            telemetryStore: telemetryStore,
            outcomeCollector: collector,
            calibrationStore: calibrationStore,
            batchSize: 10
        )

        // Ship events produce taskOutcomes (in default shared)
        let event = ShikkiEvent(
            source: .system,
            type: .shipCompleted,
            scope: .global
        )
        try await aggregator.persist(event)

        let buffered = await collector.bufferedCount()
        #expect(buffered == 1)
    }
}
