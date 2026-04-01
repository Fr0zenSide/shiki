import Foundation

// MARK: - AnonymizedOutcome

/// A fully anonymized outcome record safe for community sharing.
/// Contains NO: source code, file paths, project names, PII.
/// Contains: statistical signals about what happened.
public struct AnonymizedOutcome: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let timestamp: Date

    // Task metadata (anonymized)
    public let taskType: TaskCategory
    public let language: String?         // "swift", "typescript", etc.
    public let fileExtension: String     // ".swift", ".ts", etc.

    // Quantitative signals
    public let linesChangedBucket: SizeBucket
    public let filesChangedBucket: SizeBucket
    public let testCoverageBucket: CoverageBucket?
    public let durationBucket: DurationBucket

    // Outcome
    public let outcome: OutcomeType
    public let riskPrediction: Double    // 0.0–1.0 predicted by engine
    public let riskTierPredicted: RiskTier

    // Agent behavior signals
    public let contextResetsCount: Int
    public let watchdogEscalations: Int
    public let retryCount: Int

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        taskType: TaskCategory,
        language: String?,
        fileExtension: String,
        linesChangedBucket: SizeBucket,
        filesChangedBucket: SizeBucket,
        testCoverageBucket: CoverageBucket?,
        durationBucket: DurationBucket,
        outcome: OutcomeType,
        riskPrediction: Double,
        riskTierPredicted: RiskTier,
        contextResetsCount: Int = 0,
        watchdogEscalations: Int = 0,
        retryCount: Int = 0
    ) {
        self.id = id
        self.timestamp = timestamp
        self.taskType = taskType
        self.language = language
        self.fileExtension = fileExtension
        self.linesChangedBucket = linesChangedBucket
        self.filesChangedBucket = filesChangedBucket
        self.testCoverageBucket = testCoverageBucket
        self.durationBucket = durationBucket
        self.outcome = outcome
        self.riskPrediction = riskPrediction
        self.riskTierPredicted = riskTierPredicted
        self.contextResetsCount = contextResetsCount
        self.watchdogEscalations = watchdogEscalations
        self.retryCount = retryCount
    }
}

// MARK: - Anonymization Buckets

/// Bucketed size ranges to prevent re-identification from exact line counts.
public enum SizeBucket: String, Codable, Sendable, Equatable {
    case tiny       // 1–10
    case small      // 11–50
    case medium     // 51–200
    case large      // 201–500
    case huge       // 501+

    public static func from(count: Int) -> SizeBucket {
        switch count {
        case ...10: return .tiny
        case ...50: return .small
        case ...200: return .medium
        case ...500: return .large
        default: return .huge
        }
    }
}

/// Bucketed coverage ranges.
public enum CoverageBucket: String, Codable, Sendable, Equatable {
    case none       // 0%
    case low        // 1–30%
    case medium     // 31–60%
    case high       // 61–90%
    case full       // 91–100%

    public static func from(percentage: Double) -> CoverageBucket {
        switch percentage {
        case ...0: return .none
        case ...0.30: return .low
        case ...0.60: return .medium
        case ...0.90: return .high
        default: return .full
        }
    }
}

/// Bucketed duration ranges.
public enum DurationBucket: String, Codable, Sendable, Equatable {
    case quick      // <5 min
    case short      // 5–15 min
    case medium     // 15–60 min
    case long       // 1–4 hours
    case extended   // 4+ hours

    public static func from(seconds: TimeInterval) -> DurationBucket {
        switch seconds {
        case ..<300: return .quick
        case ..<900: return .short
        case ..<3600: return .medium
        case ..<14400: return .long
        default: return .extended
        }
    }
}

/// Task categories for community data.
public enum TaskCategory: String, Codable, Sendable, Equatable {
    case feature
    case bugfix
    case refactor
    case test
    case docs
    case config
    case ci
    case unknown
}

// MARK: - OutcomeCollector

/// Collects and anonymizes outcome data from completed tasks.
/// Converts raw event data into anonymized records safe for sharing.
public struct OutcomeCollector: Sendable {
    private let telemetryConfig: TelemetryConfig

    public init(telemetryConfig: TelemetryConfig = TelemetryConfig()) {
        self.telemetryConfig = telemetryConfig
    }

    /// Convert a completed task's data into an anonymized outcome.
    /// Returns nil if telemetry is disabled.
    public func collect(
        taskType: TaskCategory,
        language: String?,
        fileExtension: String,
        linesChanged: Int,
        filesChanged: Int,
        testCoverage: Double?,
        durationSeconds: TimeInterval,
        outcome: OutcomeType,
        riskPrediction: Double,
        riskTier: RiskTier,
        contextResets: Int = 0,
        watchdogEscalations: Int = 0,
        retries: Int = 0
    ) -> AnonymizedOutcome? {
        guard telemetryConfig.isCollectionEnabled else { return nil }

        return AnonymizedOutcome(
            taskType: taskType,
            language: language,
            fileExtension: anonymizeExtension(fileExtension),
            linesChangedBucket: SizeBucket.from(count: linesChanged),
            filesChangedBucket: SizeBucket.from(count: filesChanged),
            testCoverageBucket: testCoverage.map { CoverageBucket.from(percentage: $0) },
            durationBucket: DurationBucket.from(seconds: durationSeconds),
            outcome: outcome,
            riskPrediction: roundToDecimal(riskPrediction, places: 2),
            riskTierPredicted: riskTier,
            contextResetsCount: contextResets,
            watchdogEscalations: watchdogEscalations,
            retryCount: retries
        )
    }

    /// Batch collect outcomes from multiple files in a PR.
    public func collectPR(
        files: [(extension: String, linesChanged: Int)],
        taskType: TaskCategory,
        language: String?,
        totalDuration: TimeInterval,
        outcome: OutcomeType,
        riskSummary: PRRiskSummary,
        contextResets: Int = 0,
        watchdogEscalations: Int = 0,
        retries: Int = 0
    ) -> AnonymizedOutcome? {
        let totalLines = files.reduce(0) { $0 + $1.linesChanged }
        let primaryExtension = files
            .max { $0.linesChanged < $1.linesChanged }?
            .extension ?? ""

        return collect(
            taskType: taskType,
            language: language,
            fileExtension: primaryExtension,
            linesChanged: totalLines,
            filesChanged: files.count,
            testCoverage: nil,
            durationSeconds: totalDuration,
            outcome: outcome,
            riskPrediction: riskSummary.overallScore,
            riskTier: riskSummary.overallTier,
            contextResets: contextResets,
            watchdogEscalations: watchdogEscalations,
            retries: retries
        )
    }

    // MARK: - Anonymization Helpers

    /// Strip path information, keep only the extension.
    func anonymizeExtension(_ ext: String) -> String {
        let normalized = ext.lowercased()
        // Only keep known safe extensions
        let allowed: Set<String> = [
            ".swift", ".ts", ".tsx", ".js", ".jsx", ".py", ".rb", ".go",
            ".rs", ".kt", ".java", ".sql", ".yml", ".yaml", ".json",
            ".toml", ".md", ".sh", ".bash", ".css", ".html",
        ]
        if allowed.contains(normalized) {
            return normalized
        }
        // Unknown extension — generalize
        return ".other"
    }

    /// Round to avoid fingerprinting via exact decimal values.
    func roundToDecimal(_ value: Double, places: Int) -> Double {
        let multiplier = pow(10.0, Double(places))
        return (value * multiplier).rounded() / multiplier
    }
}
