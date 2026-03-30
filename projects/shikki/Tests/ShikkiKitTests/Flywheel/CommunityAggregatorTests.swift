import Foundation
import Testing
@testable import ShikkiKit

@Suite("CommunityAggregator")
struct CommunityAggregatorTests {

    private func makeTempPaths() -> (telemetryPath: String, calibrationPath: String, cleanup: URL) {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shikki-aggregator-test-\(UUID().uuidString)")
        let telemetryPath = tmpDir.appendingPathComponent("telemetry.json").path
        let calibrationPath = tmpDir.appendingPathComponent("calibration.jsonl").path
        return (telemetryPath, calibrationPath, tmpDir)
    }

    private func setupTelemetry(path: String, level: TelemetryLevel) throws {
        let store = TelemetryConfigStore(configPath: path)
        _ = try store.setLevel(level)
    }

    // MARK: - Event Filtering

    @Test("Processes PR verdict events")
    func processPRVerdict() async throws {
        let (telemetryPath, calibrationPath, tmpDir) = makeTempPaths()
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        try setupTelemetry(path: telemetryPath, level: .local)

        let aggregator = CommunityAggregator(
            config: AggregatorConfig(minBatchSize: 100),
            telemetryStore: TelemetryConfigStore(configPath: telemetryPath),
            calibrationStore: CalibrationStore(filePath: calibrationPath)
        )

        let event = ShikkiEvent(
            source: .system,
            type: .prVerdictSet,
            scope: .pr(number: 42),
            payload: [
                "verdict": .string("approve"),
                "riskScore": .double(0.3),
            ]
        )

        try await aggregator.persist(event)
        let count = await aggregator.pendingCount
        #expect(count == 1)
    }

    @Test("Ignores non-outcome events")
    func ignoresNonOutcomeEvents() async throws {
        let (telemetryPath, calibrationPath, tmpDir) = makeTempPaths()
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        try setupTelemetry(path: telemetryPath, level: .local)

        let aggregator = CommunityAggregator(
            config: AggregatorConfig(minBatchSize: 100),
            telemetryStore: TelemetryConfigStore(configPath: telemetryPath),
            calibrationStore: CalibrationStore(filePath: calibrationPath)
        )

        // Heartbeat — not an outcome event
        let event = ShikkiEvent(
            source: .system,
            type: .heartbeat,
            scope: .global
        )

        try await aggregator.persist(event)
        let count = await aggregator.pendingCount
        #expect(count == 0)
    }

    @Test("Ignores events when telemetry is off")
    func ignoresWhenOff() async throws {
        let (telemetryPath, calibrationPath, tmpDir) = makeTempPaths()
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        try setupTelemetry(path: telemetryPath, level: .off)

        let aggregator = CommunityAggregator(
            config: AggregatorConfig(minBatchSize: 100),
            telemetryStore: TelemetryConfigStore(configPath: telemetryPath),
            calibrationStore: CalibrationStore(filePath: calibrationPath)
        )

        let event = ShikkiEvent(
            source: .system,
            type: .prVerdictSet,
            scope: .pr(number: 42),
            payload: ["verdict": .string("approve")]
        )

        try await aggregator.persist(event)
        let count = await aggregator.pendingCount
        #expect(count == 0)
    }

    // MARK: - Batch Creation

    @Test("Creates batch when threshold reached")
    func createsBatchAtThreshold() async throws {
        let (telemetryPath, calibrationPath, tmpDir) = makeTempPaths()
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        try setupTelemetry(path: telemetryPath, level: .community)

        let aggregator = CommunityAggregator(
            config: AggregatorConfig(minBatchSize: 3, maxStoredOutcomes: 100),
            telemetryStore: TelemetryConfigStore(configPath: telemetryPath),
            calibrationStore: CalibrationStore(filePath: calibrationPath)
        )

        // Send 3 outcome events (meets minBatchSize)
        for i in 0..<3 {
            let event = ShikkiEvent(
                source: .system,
                type: .prVerdictSet,
                scope: .pr(number: i),
                payload: ["verdict": .string("approve"), "riskScore": .double(0.3)]
            )
            try await aggregator.persist(event)
        }

        let batchCount = await aggregator.batchCount
        #expect(batchCount == 1)

        // Pending should be cleared after batch creation
        let pending = await aggregator.pendingCount
        #expect(pending == 0)
    }

    @Test("Drain batches clears them")
    func drainBatches() async throws {
        let (telemetryPath, calibrationPath, tmpDir) = makeTempPaths()
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        try setupTelemetry(path: telemetryPath, level: .community)

        let aggregator = CommunityAggregator(
            config: AggregatorConfig(minBatchSize: 2),
            telemetryStore: TelemetryConfigStore(configPath: telemetryPath),
            calibrationStore: CalibrationStore(filePath: calibrationPath)
        )

        for i in 0..<2 {
            let event = ShikkiEvent(
                source: .system,
                type: .shipCompleted,
                scope: .project(slug: "test"),
                payload: ["gatesPassed": .bool(true), "linesChanged": .int(i * 10)]
            )
            try await aggregator.persist(event)
        }

        let batches = await aggregator.drainBatches()
        #expect(batches.count == 1)
        #expect(batches[0].outcomes.count == 2)
        #expect(batches[0].schemaVersion == AggregationBatch.currentSchemaVersion)

        // After drain, batch count should be 0
        let remaining = await aggregator.batchCount
        #expect(remaining == 0)
    }

    // MARK: - Buffer Overflow

    @Test("Buffer overflow drops oldest")
    func bufferOverflow() async throws {
        let (telemetryPath, calibrationPath, tmpDir) = makeTempPaths()
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        try setupTelemetry(path: telemetryPath, level: .local)

        let aggregator = CommunityAggregator(
            config: AggregatorConfig(minBatchSize: 1000, maxStoredOutcomes: 5),
            telemetryStore: TelemetryConfigStore(configPath: telemetryPath),
            calibrationStore: CalibrationStore(filePath: calibrationPath)
        )

        for i in 0..<10 {
            let event = ShikkiEvent(
                source: .system,
                type: .prVerdictSet,
                scope: .pr(number: i),
                payload: ["verdict": .string("approve")]
            )
            try await aggregator.persist(event)
        }

        let count = await aggregator.pendingCount
        #expect(count == 5) // maxStoredOutcomes enforced
    }

    // MARK: - Event Type Extraction

    @Test("Extracts from shipCompleted")
    func extractShipCompleted() async throws {
        let (telemetryPath, calibrationPath, tmpDir) = makeTempPaths()
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        try setupTelemetry(path: telemetryPath, level: .local)

        let aggregator = CommunityAggregator(
            config: AggregatorConfig(minBatchSize: 100),
            telemetryStore: TelemetryConfigStore(configPath: telemetryPath),
            calibrationStore: CalibrationStore(filePath: calibrationPath)
        )

        let event = ShikkiEvent(
            source: .system,
            type: .shipCompleted,
            scope: .project(slug: "test"),
            payload: ["gatesPassed": .bool(true)]
        )

        try await aggregator.persist(event)
        let count = await aggregator.pendingCount
        #expect(count == 1)
    }

    @Test("Extracts from codeGenPipelineCompleted")
    func extractCodeGenCompleted() async throws {
        let (telemetryPath, calibrationPath, tmpDir) = makeTempPaths()
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        try setupTelemetry(path: telemetryPath, level: .local)

        let aggregator = CommunityAggregator(
            config: AggregatorConfig(minBatchSize: 100),
            telemetryStore: TelemetryConfigStore(configPath: telemetryPath),
            calibrationStore: CalibrationStore(filePath: calibrationPath)
        )

        let event = ShikkiEvent(
            source: .system,
            type: .codeGenPipelineCompleted,
            scope: .project(slug: "test"),
            payload: ["language": .string("swift")]
        )

        try await aggregator.persist(event)
        let count = await aggregator.pendingCount
        #expect(count == 1)
    }

    @Test("Extracts from codeGenPipelineFailed")
    func extractCodeGenFailed() async throws {
        let (telemetryPath, calibrationPath, tmpDir) = makeTempPaths()
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        try setupTelemetry(path: telemetryPath, level: .local)

        let aggregator = CommunityAggregator(
            config: AggregatorConfig(minBatchSize: 100),
            telemetryStore: TelemetryConfigStore(configPath: telemetryPath),
            calibrationStore: CalibrationStore(filePath: calibrationPath)
        )

        let event = ShikkiEvent(
            source: .system,
            type: .codeGenPipelineFailed,
            scope: .project(slug: "test"),
            payload: ["retries": .int(2)]
        )

        try await aggregator.persist(event)
        let count = await aggregator.pendingCount
        #expect(count == 1)
    }

    @Test("Extracts from scheduledTaskCompleted")
    func extractSchedulerCompleted() async throws {
        let (telemetryPath, calibrationPath, tmpDir) = makeTempPaths()
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        try setupTelemetry(path: telemetryPath, level: .local)

        let aggregator = CommunityAggregator(
            config: AggregatorConfig(minBatchSize: 100),
            telemetryStore: TelemetryConfigStore(configPath: telemetryPath),
            calibrationStore: CalibrationStore(filePath: calibrationPath)
        )

        let event = ShikkiEvent(
            source: .system,
            type: .scheduledTaskCompleted,
            scope: .global
        )

        try await aggregator.persist(event)
        let count = await aggregator.pendingCount
        #expect(count == 1)
    }

    // MARK: - AggregationBatch

    @Test("Batch has schema version")
    func batchSchemaVersion() {
        let batch = AggregationBatch(outcomes: [])
        #expect(batch.schemaVersion == 1)
    }

    @Test("Batch codable round-trip")
    func batchCodable() throws {
        let outcome = AnonymizedOutcome(
            taskType: .feature,
            language: "swift",
            fileExtension: ".swift",
            linesChangedBucket: .medium,
            filesChangedBucket: .small,
            testCoverageBucket: nil,
            durationBucket: .medium,
            outcome: .clean,
            riskPrediction: 0.3,
            riskTierPredicted: .medium
        )
        let batch = AggregationBatch(outcomes: [outcome])

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(batch)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AggregationBatch.self, from: data)

        #expect(decoded.batchId == batch.batchId)
        #expect(decoded.outcomes.count == 1)
        #expect(decoded.outcomes[0].taskType == .feature)
    }

    // MARK: - AggregatorConfig

    @Test("Default config values")
    func defaultConfig() {
        let config = AggregatorConfig.default
        #expect(config.minBatchSize == 10)
        #expect(config.maxBatchAge == 86400)
        #expect(config.maxStoredOutcomes == 1000)
    }
}
