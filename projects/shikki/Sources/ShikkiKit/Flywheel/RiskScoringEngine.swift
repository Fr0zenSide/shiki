import Foundation

// MARK: - RiskFactor

/// Individual risk signal extracted from a PR or file change.
public struct RiskFactor: Codable, Sendable, Equatable {
    public let name: String
    public let weight: Double
    public let value: Double
    public let description: String

    public init(name: String, weight: Double, value: Double, description: String) {
        self.name = name
        self.weight = weight
        self.value = value
        self.description = description
    }

    /// Weighted contribution to the total risk score.
    public var contribution: Double { weight * value }
}

// MARK: - RiskScore

/// Computed risk score for a file or PR.
public struct RiskScore: Codable, Sendable, Equatable {
    public let subject: String
    public let score: Double
    public let level: RiskLevel
    public let factors: [RiskFactor]
    public let timestamp: Date

    public init(subject: String, score: Double, factors: [RiskFactor], timestamp: Date = Date()) {
        self.subject = subject
        self.score = score
        self.level = RiskLevel.from(score: score)
        self.factors = factors
        self.timestamp = timestamp
    }
}

// MARK: - RiskLevel

/// Categorical risk classification.
public enum RiskLevel: String, Codable, Sendable, Equatable, Comparable {
    case low
    case medium
    case high
    case critical

    public static func from(score: Double) -> RiskLevel {
        switch score {
        case ..<0.25: return .low
        case 0.25..<0.50: return .medium
        case 0.50..<0.75: return .high
        default: return .critical
        }
    }

    public static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool {
        lhs.ordinal < rhs.ordinal
    }

    private var ordinal: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        case .critical: return 3
        }
    }
}

// MARK: - FileChange

/// Metadata about a changed file used for risk assessment.
public struct FileChange: Sendable {
    public let path: String
    public let linesAdded: Int
    public let linesDeleted: Int
    public let isNewFile: Bool
    public let isTestFile: Bool
    public let hasTestCoverage: Bool
    public let fileExtension: String
    public let directoryDepth: Int

    public init(
        path: String,
        linesAdded: Int,
        linesDeleted: Int,
        isNewFile: Bool = false,
        isTestFile: Bool = false,
        hasTestCoverage: Bool = false
    ) {
        self.path = path
        self.linesAdded = linesAdded
        self.linesDeleted = linesDeleted
        self.isNewFile = isNewFile
        self.isTestFile = isTestFile
        self.hasTestCoverage = hasTestCoverage
        self.fileExtension = (path as NSString).pathExtension.lowercased()
        self.directoryDepth = path.components(separatedBy: "/").count - 1
    }

    /// Total churn (lines changed).
    public var churn: Int { linesAdded + linesDeleted }
}

// MARK: - RiskScoringEngine

/// Heuristic-based risk scoring engine.
/// Starts with rule-based scoring, designed for future ML model replacement.
/// Weights are adjustable via CalibrationStore.
public actor RiskScoringEngine {
    private var weights: RiskWeights
    private let calibrationStore: CalibrationStore

    public init(calibrationStore: CalibrationStore) async {
        self.calibrationStore = calibrationStore
        self.weights = await calibrationStore.riskWeights()
    }

    /// Score a single file change.
    public func scoreFile(_ change: FileChange) -> RiskScore {
        var factors: [RiskFactor] = []

        // Factor 1: Churn size
        let churnScore = normalizeChurn(change.churn)
        factors.append(RiskFactor(
            name: "churn",
            weight: weights.churnWeight,
            value: churnScore,
            description: "\(change.churn) lines changed"
        ))

        // Factor 2: Test coverage
        let coverageScore: Double = change.hasTestCoverage ? 0.0 : 1.0
        if !change.isTestFile {
            factors.append(RiskFactor(
                name: "test_coverage",
                weight: weights.testCoverageWeight,
                value: coverageScore,
                description: change.hasTestCoverage ? "has tests" : "no test coverage"
            ))
        }

        // Factor 3: File type risk
        let typeScore = fileTypeRisk(change.fileExtension)
        factors.append(RiskFactor(
            name: "file_type",
            weight: weights.fileTypeWeight,
            value: typeScore,
            description: ".\(change.fileExtension) file"
        ))

        // Factor 4: Directory depth (deep nesting = higher coupling risk)
        let depthScore = min(Double(change.directoryDepth) / 8.0, 1.0)
        factors.append(RiskFactor(
            name: "nesting_depth",
            weight: weights.nestingDepthWeight,
            value: depthScore,
            description: "\(change.directoryDepth) levels deep"
        ))

        // Factor 5: Deletion-heavy changes (risky refactors)
        let deleteRatio = change.churn > 0
            ? Double(change.linesDeleted) / Double(change.churn)
            : 0.0
        if deleteRatio > 0.6 {
            factors.append(RiskFactor(
                name: "deletion_heavy",
                weight: weights.deletionHeavyWeight,
                value: deleteRatio,
                description: "\(Int(deleteRatio * 100))% deletions"
            ))
        }

        // Factor 6: New file bonus (new files are generally lower risk than modifications)
        if change.isNewFile {
            factors.append(RiskFactor(
                name: "new_file",
                weight: weights.newFileWeight,
                value: -0.3,
                description: "new file (lower risk)"
            ))
        }

        // Compute weighted sum, clamped to [0, 1]
        let totalWeight = factors.reduce(0.0) { $0 + abs($1.weight) }
        let rawScore = totalWeight > 0
            ? factors.reduce(0.0) { $0 + $1.contribution } / totalWeight
            : 0.0
        let clampedScore = min(max(rawScore, 0.0), 1.0)

        return RiskScore(
            subject: change.path,
            score: clampedScore,
            factors: factors
        )
    }

    /// Score a PR (collection of file changes).
    public func scorePR(files: [FileChange], prTitle: String = "") -> RiskScore {
        guard !files.isEmpty else {
            return RiskScore(subject: prTitle, score: 0.0, factors: [])
        }

        let fileScores = files.map { scoreFile($0) }
        var factors: [RiskFactor] = []

        // Aggregate: max file risk
        let maxFileScore = fileScores.map(\.score).max() ?? 0.0
        factors.append(RiskFactor(
            name: "max_file_risk",
            weight: 0.35,
            value: maxFileScore,
            description: "highest file risk"
        ))

        // Aggregate: average file risk
        let avgFileScore = fileScores.map(\.score).reduce(0, +) / Double(fileScores.count)
        factors.append(RiskFactor(
            name: "avg_file_risk",
            weight: 0.25,
            value: avgFileScore,
            description: "average file risk"
        ))

        // PR size factor
        let totalChurn = files.reduce(0) { $0 + $1.churn }
        let sizeScore = normalizePRSize(totalChurn)
        factors.append(RiskFactor(
            name: "pr_size",
            weight: 0.20,
            value: sizeScore,
            description: "\(totalChurn) total lines changed"
        ))

        // File count factor
        let fileCountScore = min(Double(files.count) / 20.0, 1.0)
        factors.append(RiskFactor(
            name: "file_count",
            weight: 0.10,
            value: fileCountScore,
            description: "\(files.count) files changed"
        ))

        // Test ratio factor
        let testFiles = files.filter(\.isTestFile).count
        let sourceFiles = files.filter { !$0.isTestFile }.count
        let testRatio = sourceFiles > 0 ? Double(testFiles) / Double(sourceFiles) : 1.0
        let testRatioScore = max(1.0 - testRatio, 0.0)
        factors.append(RiskFactor(
            name: "test_ratio",
            weight: 0.10,
            value: testRatioScore,
            description: "\(testFiles) test files / \(sourceFiles) source files"
        ))

        let totalWeight = factors.reduce(0.0) { $0 + abs($1.weight) }
        let rawScore = totalWeight > 0
            ? factors.reduce(0.0) { $0 + $1.contribution } / totalWeight
            : 0.0
        let clampedScore = min(max(rawScore, 0.0), 1.0)

        return RiskScore(
            subject: prTitle.isEmpty ? "PR" : prTitle,
            score: clampedScore,
            factors: factors
        )
    }

    /// Refresh weights from calibration store.
    public func refreshWeights() async {
        weights = await calibrationStore.riskWeights()
    }

    // MARK: - Normalization Helpers

    private func normalizeChurn(_ churn: Int) -> Double {
        // 0-10 lines: low, 10-100: medium, 100-500: high, 500+: critical
        switch churn {
        case ..<10: return 0.1
        case 10..<50: return 0.3
        case 50..<100: return 0.5
        case 100..<300: return 0.7
        case 300..<500: return 0.85
        default: return 1.0
        }
    }

    private func normalizePRSize(_ totalChurn: Int) -> Double {
        switch totalChurn {
        case ..<50: return 0.1
        case 50..<200: return 0.3
        case 200..<500: return 0.5
        case 500..<1000: return 0.7
        default: return 1.0
        }
    }

    private func fileTypeRisk(_ ext: String) -> Double {
        switch ext {
        // High-risk: configuration, build, security
        case "yml", "yaml", "toml", "json", "plist": return 0.6
        case "swift", "go", "rs": return 0.4
        case "ts", "js": return 0.5
        // Lower-risk: documentation, tests
        case "md", "txt", "rst": return 0.1
        case "test", "spec": return 0.2
        // Unknown
        default: return 0.4
        }
    }
}

// MARK: - RiskWeights

/// Adjustable weights for risk factors. Stored in CalibrationStore.
public struct RiskWeights: Codable, Sendable, Equatable {
    public var churnWeight: Double
    public var testCoverageWeight: Double
    public var fileTypeWeight: Double
    public var nestingDepthWeight: Double
    public var deletionHeavyWeight: Double
    public var newFileWeight: Double

    public init(
        churnWeight: Double = 0.30,
        testCoverageWeight: Double = 0.25,
        fileTypeWeight: Double = 0.15,
        nestingDepthWeight: Double = 0.10,
        deletionHeavyWeight: Double = 0.10,
        newFileWeight: Double = 0.10
    ) {
        self.churnWeight = churnWeight
        self.testCoverageWeight = testCoverageWeight
        self.fileTypeWeight = fileTypeWeight
        self.nestingDepthWeight = nestingDepthWeight
        self.deletionHeavyWeight = deletionHeavyWeight
        self.newFileWeight = newFileWeight
    }

    public static let `default` = RiskWeights()
}
