import Foundation
import Testing

@testable import ShikkiKit

@Suite("CalibrationStore")
struct CalibrationStoreTests {

    private func makeTempPath() -> String {
        NSTemporaryDirectory() + "shikki-cal-test-\(UUID().uuidString).json"
    }

    // MARK: - CalibrationData

    @Test("Default calibration data has version 1")
    func defaultVersion() {
        let data = CalibrationData()
        #expect(data.version == 1)
        #expect(data.riskWeights == .default)
        #expect(data.watchdogThresholds == .default)
        #expect(data.benchmarkBaselines == .default)
    }

    @Test("CalibrationData JSON roundtrip")
    func dataRoundTrip() throws {
        // Use a whole-second date to avoid ISO8601 sub-second precision loss
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let data = CalibrationData(
            version: 3,
            updatedAt: fixedDate,
            riskWeights: RiskWeights(churnWeight: 0.5),
            watchdogThresholds: WatchdogThresholds(defaultIdleTimeout: 180),
            benchmarkBaselines: BenchmarkBaselines(taskSuccessRate: 0.85, sampleCount: 1000)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let json = try encoder.encode(data)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(CalibrationData.self, from: json)
        #expect(decoded == data)
    }

    // MARK: - WatchdogThresholds

    @Test("WatchdogThresholds default timeout")
    func defaultTimeout() {
        let thresholds = WatchdogThresholds.default
        #expect(thresholds.timeout() == 120)
    }

    @Test("WatchdogThresholds language override")
    func languageOverride() {
        let thresholds = WatchdogThresholds(
            defaultIdleTimeout: 120,
            languageOverrides: ["swift": 150, "typescript": 90]
        )
        #expect(thresholds.timeout(language: "swift") == 150)
        #expect(thresholds.timeout(language: "typescript") == 90)
        #expect(thresholds.timeout(language: "go") == 120)
    }

    @Test("WatchdogThresholds task type override takes precedence")
    func taskTypeOverridePrecedence() {
        let thresholds = WatchdogThresholds(
            defaultIdleTimeout: 120,
            languageOverrides: ["swift": 150],
            taskTypeOverrides: ["refactoring": 240]
        )
        // Task type override wins over language override
        #expect(thresholds.timeout(language: "swift", taskType: "refactoring") == 240)
        // Language override used when no task type match
        #expect(thresholds.timeout(language: "swift", taskType: "test") == 150)
    }

    // MARK: - BenchmarkBaselines

    @Test("Default baselines have zero sample count")
    func defaultBaselines() {
        let baselines = BenchmarkBaselines.default
        #expect(baselines.sampleCount == 0)
        #expect(baselines.taskSuccessRate == 0.0)
    }

    // MARK: - CalibrationStore Persistence

    @Test("CalibrationStore saves and loads")
    func persistenceRoundTrip() async throws {
        let path = makeTempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let store = CalibrationStore(filePath: path)
        let newWeights = RiskWeights(churnWeight: 0.45, testCoverageWeight: 0.35)
        try await store.updateRiskWeights(newWeights)

        // Reload from disk
        let store2 = CalibrationStore(filePath: path)
        let loaded = await store2.riskWeights()
        #expect(loaded == newWeights)
    }

    @Test("CalibrationStore version increments on update")
    func versionIncrement() async throws {
        let path = makeTempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let store = CalibrationStore(filePath: path)
        let v1 = await store.version()
        #expect(v1 == 1)

        try await store.updateRiskWeights(RiskWeights(churnWeight: 0.5))
        let v2 = await store.version()
        #expect(v2 == 2)

        try await store.updateWatchdogThresholds(WatchdogThresholds(defaultIdleTimeout: 200))
        let v3 = await store.version()
        #expect(v3 == 3)
    }

    @Test("CalibrationStore update watchdog thresholds")
    func updateWatchdog() async throws {
        let path = makeTempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let store = CalibrationStore(filePath: path)
        let thresholds = WatchdogThresholds(
            defaultIdleTimeout: 180,
            languageOverrides: ["swift": 200]
        )
        try await store.updateWatchdogThresholds(thresholds)

        let loaded = await store.watchdogThresholds()
        #expect(loaded == thresholds)
    }

    @Test("CalibrationStore update benchmark baselines")
    func updateBaselines() async throws {
        let path = makeTempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let store = CalibrationStore(filePath: path)
        let baselines = BenchmarkBaselines(
            riskScoreAccuracy: 0.75,
            taskSuccessRate: 0.82,
            sampleCount: 5000
        )
        try await store.updateBenchmarkBaselines(baselines)

        let loaded = await store.benchmarkBaselines()
        #expect(loaded == baselines)
    }

    @Test("CalibrationStore applyUpdate respects version")
    func applyUpdateVersionCheck() async throws {
        let path = makeTempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let store = CalibrationStore(filePath: path)

        // Older version should be ignored
        let old = CalibrationData(
            version: 0,
            riskWeights: RiskWeights(churnWeight: 0.9)
        )
        try await store.applyUpdate(old)
        let weights = await store.riskWeights()
        #expect(weights.churnWeight != 0.9)

        // Newer version should be applied
        let newer = CalibrationData(
            version: 10,
            riskWeights: RiskWeights(churnWeight: 0.8)
        )
        try await store.applyUpdate(newer)
        let updatedWeights = await store.riskWeights()
        #expect(updatedWeights.churnWeight == 0.8)
    }

    @Test("CalibrationStore returns current data snapshot")
    func currentSnapshot() async {
        let path = makeTempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let store = CalibrationStore(filePath: path)
        let data = await store.current()
        #expect(data.version == 1)
        #expect(data.riskWeights == .default)
    }
}
