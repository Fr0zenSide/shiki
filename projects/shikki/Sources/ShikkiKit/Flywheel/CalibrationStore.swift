import Foundation

// MARK: - CalibrationData

/// Root container for all calibration data — weights, thresholds, and version info.
public struct CalibrationData: Codable, Sendable, Equatable {
    public var version: Int
    public var updatedAt: Date
    public var riskWeights: RiskWeights
    public var watchdogThresholds: WatchdogThresholds
    public var benchmarkBaselines: BenchmarkBaselines

    public init(
        version: Int = 1,
        updatedAt: Date = Date(),
        riskWeights: RiskWeights = .default,
        watchdogThresholds: WatchdogThresholds = .default,
        benchmarkBaselines: BenchmarkBaselines = .default
    ) {
        self.version = version
        self.updatedAt = updatedAt
        self.riskWeights = riskWeights
        self.watchdogThresholds = watchdogThresholds
        self.benchmarkBaselines = benchmarkBaselines
    }
}

// MARK: - WatchdogThresholds

/// Per-language, per-task-type idle thresholds for the watchdog.
public struct WatchdogThresholds: Codable, Sendable, Equatable {
    /// Default idle timeout in seconds before watchdog intervenes.
    public var defaultIdleTimeout: TimeInterval
    /// Language-specific overrides (e.g., "swift" → 120s, "typescript" → 90s).
    public var languageOverrides: [String: TimeInterval]
    /// Task-type overrides (e.g., "refactoring" → 180s, "test" → 60s).
    public var taskTypeOverrides: [String: TimeInterval]

    public init(
        defaultIdleTimeout: TimeInterval = 120,
        languageOverrides: [String: TimeInterval] = [:],
        taskTypeOverrides: [String: TimeInterval] = [:]
    ) {
        self.defaultIdleTimeout = defaultIdleTimeout
        self.languageOverrides = languageOverrides
        self.taskTypeOverrides = taskTypeOverrides
    }

    public static let `default` = WatchdogThresholds()

    /// Resolve the idle timeout for a specific context.
    public func timeout(language: String? = nil, taskType: String? = nil) -> TimeInterval {
        // Task type overrides take precedence over language overrides.
        if let taskType, let override = taskTypeOverrides[taskType] {
            return override
        }
        if let language, let override = languageOverrides[language] {
            return override
        }
        return defaultIdleTimeout
    }
}

// MARK: - BenchmarkBaselines

/// Community baseline metrics for comparison.
public struct BenchmarkBaselines: Codable, Sendable, Equatable {
    /// Average risk score accuracy (predicted vs actual).
    public var riskScoreAccuracy: Double
    /// Average task success rate.
    public var taskSuccessRate: Double
    /// Average context resets per session.
    public var avgContextResetsPerSession: Double
    /// Median task duration bucket.
    public var medianTaskDuration: String
    /// Sample count these baselines are derived from.
    public var sampleCount: Int

    public init(
        riskScoreAccuracy: Double = 0.0,
        taskSuccessRate: Double = 0.0,
        avgContextResetsPerSession: Double = 0.0,
        medianTaskDuration: String = "unknown",
        sampleCount: Int = 0
    ) {
        self.riskScoreAccuracy = riskScoreAccuracy
        self.taskSuccessRate = taskSuccessRate
        self.avgContextResetsPerSession = avgContextResetsPerSession
        self.medianTaskDuration = medianTaskDuration
        self.sampleCount = sampleCount
    }

    public static let `default` = BenchmarkBaselines()
}

// MARK: - CalibrationStore

/// Actor-isolated persistent store for calibration data.
/// Stores weights, thresholds, and community baselines.
/// Supports versioned updates from `shiki update --models`.
public actor CalibrationStore {
    private var data: CalibrationData
    private let filePath: String

    public init(filePath: String? = nil) {
        let path = filePath ?? Self.defaultPath()
        self.filePath = path
        self.data = Self.load(from: path) ?? CalibrationData()
    }

    /// Get the current calibration data.
    public func current() -> CalibrationData {
        data
    }

    /// Get current risk weights.
    public func riskWeights() -> RiskWeights {
        data.riskWeights
    }

    /// Get current watchdog thresholds.
    public func watchdogThresholds() -> WatchdogThresholds {
        data.watchdogThresholds
    }

    /// Get current benchmark baselines.
    public func benchmarkBaselines() -> BenchmarkBaselines {
        data.benchmarkBaselines
    }

    /// Update risk weights (e.g., from community model update).
    public func updateRiskWeights(_ weights: RiskWeights) throws {
        data.riskWeights = weights
        data.version += 1
        data.updatedAt = Date()
        try save()
    }

    /// Update watchdog thresholds.
    public func updateWatchdogThresholds(_ thresholds: WatchdogThresholds) throws {
        data.watchdogThresholds = thresholds
        data.version += 1
        data.updatedAt = Date()
        try save()
    }

    /// Update benchmark baselines from community data.
    public func updateBenchmarkBaselines(_ baselines: BenchmarkBaselines) throws {
        data.benchmarkBaselines = baselines
        data.version += 1
        data.updatedAt = Date()
        try save()
    }

    /// Apply a full calibration update (e.g., from `shiki update --models`).
    public func applyUpdate(_ newData: CalibrationData) throws {
        guard newData.version > data.version else { return }
        data = newData
        try save()
    }

    /// Get the current version.
    public func version() -> Int {
        data.version
    }

    // MARK: - Persistence

    private func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(data)
        let url = URL(fileURLWithPath: filePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try jsonData.write(to: url)
    }

    private static func load(from path: String) -> CalibrationData? {
        guard let jsonData = FileManager.default.contents(atPath: path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CalibrationData.self, from: jsonData)
    }

    private static func defaultPath() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.config/shikki/calibration.json"
    }
}
