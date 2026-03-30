import Foundation
import Testing

@testable import ShikkiKit

@Suite("OutcomeCollector")
struct OutcomeCollectorTests {

    private func makeStore() -> TelemetryConfigStore {
        let path = NSTemporaryDirectory() + "shikki-oc-test-\(UUID().uuidString).json"
        return TelemetryConfigStore(filePath: path)
    }

    // MARK: - OutcomeRecord

    @Test("OutcomeRecord JSON roundtrip")
    func outcomeRecordRoundTrip() throws {
        // Use a whole-second date to avoid ISO8601 sub-second precision loss
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let record = OutcomeRecord(
            id: UUID(),
            timestamp: fixedDate,
            category: .riskScores,
            outcome: .success,
            metrics: OutcomeMetrics(
                durationBucket: .under5min,
                predictedRiskScore: 0.35,
                platform: "swift"
            )
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(OutcomeRecord.self, from: data)
        #expect(decoded == record)
    }

    // MARK: - DurationBucket

    @Test("DurationBucket maps correctly")
    func durationBuckets() {
        #expect(DurationBucket.from(seconds: 30) == .under1min)
        #expect(DurationBucket.from(seconds: 60) == .under5min)
        #expect(DurationBucket.from(seconds: 300) == .under15min)
        #expect(DurationBucket.from(seconds: 900) == .under30min)
        #expect(DurationBucket.from(seconds: 1800) == .under1hr)
        #expect(DurationBucket.from(seconds: 7200) == .over1hr)
    }

    // MARK: - SizeBucket

    @Test("SizeBucket maps correctly")
    func sizeBuckets() {
        #expect(SizeBucket.from(count: 1) == .tiny)
        #expect(SizeBucket.from(count: 5) == .tiny)
        #expect(SizeBucket.from(count: 6) == .small)
        #expect(SizeBucket.from(count: 20) == .small)
        #expect(SizeBucket.from(count: 21) == .medium)
        #expect(SizeBucket.from(count: 50) == .medium)
        #expect(SizeBucket.from(count: 51) == .large)
        #expect(SizeBucket.from(count: 200) == .large)
        #expect(SizeBucket.from(count: 201) == .huge)
    }

    // MARK: - Collector Behavior

    @Test("Collector records outcomes when collection enabled")
    func recordsWhenEnabled() async throws {
        let store = makeStore()
        // Default is .local (collection enabled)
        let collector = OutcomeCollector(telemetryStore: store, maxBufferSize: 100)

        let record = OutcomeRecord(
            category: .taskOutcomes,
            outcome: .success,
            metrics: OutcomeMetrics(taskType: "test")
        )
        await collector.record(record)

        let count = await collector.bufferedCount()
        #expect(count == 1)
    }

    @Test("Collector does not record when telemetry off")
    func noRecordWhenOff() async throws {
        let store = makeStore()
        try await store.setLevel(.off)
        let collector = OutcomeCollector(telemetryStore: store, maxBufferSize: 100)

        let record = OutcomeRecord(
            category: .taskOutcomes,
            outcome: .success,
            metrics: OutcomeMetrics()
        )
        await collector.record(record)

        let count = await collector.bufferedCount()
        #expect(count == 0)
    }

    @Test("Collector flushes when buffer full")
    func flushOnBufferFull() async throws {
        let store = makeStore()
        let collector = OutcomeCollector(telemetryStore: store, maxBufferSize: 3)

        let spy = FlushSpy()
        await collector.setFlushHandler { records in
            await spy.receive(records)
        }

        for i in 0..<3 {
            let record = OutcomeRecord(
                category: .taskOutcomes,
                outcome: i % 2 == 0 ? .success : .failure,
                metrics: OutcomeMetrics()
            )
            await collector.record(record)
        }

        let flushedCount = await spy.recordCount
        #expect(flushedCount == 3)
        let count = await collector.bufferedCount()
        #expect(count == 0)
    }

    @Test("Flush with empty buffer is no-op")
    func flushEmptyBuffer() async {
        let store = makeStore()
        let collector = OutcomeCollector(telemetryStore: store)

        let spy = FlushSpy()
        await collector.setFlushHandler { records in
            await spy.receive(records)
        }
        await collector.flush()
        let flushed = await spy.wasCalled
        #expect(!flushed)
    }

    // MARK: - Event Extraction

    @Test("Extract outcome from PR verdict event")
    func extractPRVerdict() {
        let event = ShikkiEvent(
            source: .system,
            type: .prVerdictSet,
            scope: .pr(number: 42),
            payload: [
                "verdict": .string("approved"),
                "riskScore": .double(0.3),
                "language": .string("swift"),
            ]
        )
        let outcome = OutcomeCollector.extractOutcome(from: event)
        #expect(outcome != nil)
        #expect(outcome?.category == .riskScores)
        #expect(outcome?.outcome == .success)
        #expect(outcome?.metrics.predictedRiskScore == 0.3)
        #expect(outcome?.metrics.platform == "swift")
    }

    @Test("Extract outcome from ship completed event")
    func extractShipCompleted() {
        let event = ShikkiEvent(
            source: .system,
            type: .shipCompleted,
            scope: .global,
            metadata: EventMetadata(duration: 120)
        )
        let outcome = OutcomeCollector.extractOutcome(from: event)
        #expect(outcome != nil)
        #expect(outcome?.category == .taskOutcomes)
        #expect(outcome?.outcome == .success)
        #expect(outcome?.metrics.durationBucket == .under5min)
        #expect(outcome?.metrics.taskType == "ship")
    }

    @Test("Extract outcome from ship aborted event")
    func extractShipAborted() {
        let event = ShikkiEvent(
            source: .system,
            type: .shipAborted,
            scope: .global
        )
        let outcome = OutcomeCollector.extractOutcome(from: event)
        #expect(outcome?.outcome == .failure)
    }

    @Test("Extract outcome from test run — passed")
    func extractTestRunPassed() {
        let event = ShikkiEvent(
            source: .system,
            type: .testRun,
            scope: .global,
            payload: ["passed": .bool(true)]
        )
        let outcome = OutcomeCollector.extractOutcome(from: event)
        #expect(outcome?.outcome == .success)
        #expect(outcome?.metrics.taskType == "test")
    }

    @Test("Extract outcome from test run — failed")
    func extractTestRunFailed() {
        let event = ShikkiEvent(
            source: .system,
            type: .testRun,
            scope: .global,
            payload: ["passed": .bool(false)]
        )
        let outcome = OutcomeCollector.extractOutcome(from: event)
        #expect(outcome?.outcome == .failure)
    }

    @Test("Extract outcome from codegen completed")
    func extractCodeGenCompleted() {
        let event = ShikkiEvent(
            source: .system,
            type: .codeGenPipelineCompleted,
            scope: .global,
            metadata: EventMetadata(duration: 600)
        )
        let outcome = OutcomeCollector.extractOutcome(from: event)
        #expect(outcome?.outcome == .success)
        #expect(outcome?.metrics.taskType == "codegen")
        #expect(outcome?.metrics.durationBucket == .under15min)
    }

    @Test("Extract outcome from scheduled task")
    func extractScheduledTask() {
        let event = ShikkiEvent(
            source: .system,
            type: .scheduledTaskCompleted,
            scope: .global
        )
        let outcome = OutcomeCollector.extractOutcome(from: event)
        #expect(outcome?.outcome == .success)
        #expect(outcome?.metrics.taskType == "scheduled")
    }

    @Test("Non-outcome events return nil")
    func nonOutcomeEvents() {
        let heartbeat = ShikkiEvent(source: .system, type: .heartbeat, scope: .global)
        #expect(OutcomeCollector.extractOutcome(from: heartbeat) == nil)

        let session = ShikkiEvent(source: .system, type: .sessionStart, scope: .global)
        #expect(OutcomeCollector.extractOutcome(from: session) == nil)
    }

    // MARK: - collectFromEvent Integration

    @Test("collectFromEvent records extracted outcome")
    func collectFromEventIntegration() async throws {
        let store = makeStore()
        let collector = OutcomeCollector(telemetryStore: store)

        let event = ShikkiEvent(
            source: .system,
            type: .shipCompleted,
            scope: .global,
            metadata: EventMetadata(duration: 60)
        )
        await collector.collectFromEvent(event)

        let count = await collector.bufferedCount()
        #expect(count == 1)
    }

    @Test("collectFromEvent ignores non-outcome event")
    func collectFromEventIgnoresNonOutcome() async {
        let store = makeStore()
        let collector = OutcomeCollector(telemetryStore: store)

        let event = ShikkiEvent(source: .system, type: .heartbeat, scope: .global)
        await collector.collectFromEvent(event)

        let count = await collector.bufferedCount()
        #expect(count == 0)
    }
}

// MARK: - Test Helpers

/// Actor-based spy for capturing flush handler calls (Sendable-safe).
private actor FlushSpy {
    var records: [OutcomeRecord] = []
    var wasCalled = false

    var recordCount: Int { records.count }

    func receive(_ batch: [OutcomeRecord]) {
        wasCalled = true
        records.append(contentsOf: batch)
    }
}
