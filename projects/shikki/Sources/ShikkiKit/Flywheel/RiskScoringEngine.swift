import Foundation

// MARK: - RiskSignal

/// A single risk signal extracted from a file change.
public struct RiskSignal: Codable, Sendable, Equatable {
    public let name: String
    public let weight: Double
    public let value: Double

    public init(name: String, weight: Double, value: Double) {
        self.name = name
        self.weight = weight
        self.value = value
    }

    /// Weighted contribution to the final score.
    public var contribution: Double {
        weight * value
    }
}

// MARK: - FileRiskProfile

/// Risk assessment for a single file in a PR.
public struct FileRiskProfile: Codable, Sendable, Equatable {
    public let path: String
    public let signals: [RiskSignal]
    public let score: Double
    public let tier: RiskTier

    public init(path: String, signals: [RiskSignal], score: Double, tier: RiskTier) {
        self.path = path
        self.signals = signals
        self.score = score
        self.tier = tier
    }
}

// MARK: - RiskTier

/// Discrete risk levels derived from the continuous score.
public enum RiskTier: String, Codable, Sendable, Equatable, Comparable {
    case low
    case medium
    case high
    case critical

    public static func from(score: Double) -> RiskTier {
        switch score {
        case ..<0.25: return .low
        case ..<0.50: return .medium
        case ..<0.75: return .high
        default: return .critical
        }
    }

    public static func < (lhs: RiskTier, rhs: RiskTier) -> Bool {
        lhs.ordinal < rhs.ordinal
    }

    var ordinal: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        case .critical: return 3
        }
    }
}

// MARK: - RiskWeights

/// Configurable weights for each heuristic signal.
/// These start as hardcoded defaults and can be replaced by
/// community-trained weights via `shikki update --models`.
public struct RiskWeights: Codable, Sendable, Equatable {
    public var churnWeight: Double
    public var complexityWeight: Double
    public var testCoverageWeight: Double
    public var fileAgeWeight: Double
    public var hotspotWeight: Double
    public var extensionWeight: Double

    public static let `default` = RiskWeights(
        churnWeight: 0.20,
        complexityWeight: 0.25,
        testCoverageWeight: 0.20,
        fileAgeWeight: 0.10,
        hotspotWeight: 0.15,
        extensionWeight: 0.10
    )

    public init(
        churnWeight: Double = 0.20,
        complexityWeight: Double = 0.25,
        testCoverageWeight: Double = 0.20,
        fileAgeWeight: Double = 0.10,
        hotspotWeight: Double = 0.15,
        extensionWeight: Double = 0.10
    ) {
        self.churnWeight = churnWeight
        self.complexityWeight = complexityWeight
        self.testCoverageWeight = testCoverageWeight
        self.fileAgeWeight = fileAgeWeight
        self.hotspotWeight = hotspotWeight
        self.extensionWeight = extensionWeight
    }

    /// Sum of all weights — used for normalization.
    public var totalWeight: Double {
        churnWeight + complexityWeight + testCoverageWeight
            + fileAgeWeight + hotspotWeight + extensionWeight
    }
}

// MARK: - FileChangeInput

/// Input data for risk scoring a single file.
public struct FileChangeInput: Sendable {
    public let path: String
    public let linesAdded: Int
    public let linesRemoved: Int
    public let totalLines: Int
    public let testCoverage: Double?   // 0.0–1.0, nil if unknown
    public let daysSinceLastChange: Int?
    public let recentBugCount: Int     // bugs found in this file recently
    public let fileExtension: String

    public init(
        path: String,
        linesAdded: Int,
        linesRemoved: Int,
        totalLines: Int = 0,
        testCoverage: Double? = nil,
        daysSinceLastChange: Int? = nil,
        recentBugCount: Int = 0,
        fileExtension: String = ""
    ) {
        self.path = path
        self.linesAdded = linesAdded
        self.linesRemoved = linesRemoved
        self.totalLines = totalLines
        self.testCoverage = testCoverage
        self.daysSinceLastChange = daysSinceLastChange
        self.recentBugCount = recentBugCount
        self.fileExtension = fileExtension
    }
}

// MARK: - PRRiskSummary

/// Aggregate risk assessment for an entire PR.
public struct PRRiskSummary: Codable, Sendable, Equatable {
    public let files: [FileRiskProfile]
    public let overallScore: Double
    public let overallTier: RiskTier
    public let topRisks: [FileRiskProfile]

    public init(files: [FileRiskProfile], overallScore: Double, overallTier: RiskTier, topRisks: [FileRiskProfile]) {
        self.files = files
        self.overallScore = overallScore
        self.overallTier = overallTier
        self.topRisks = topRisks
    }
}

// MARK: - RiskScoringEngine

/// ML-ready risk scoring engine. Starts with heuristics, designed to
/// accept community-trained weights as a drop-in replacement.
///
/// Architecture:
/// 1. Extract signals from file change metadata
/// 2. Apply weighted heuristics (or learned weights)
/// 3. Normalize to 0.0–1.0 score
/// 4. Classify into risk tiers
///
/// When community data is available, `weights` can be replaced with
/// learned values from `CalibrationStore`.
public struct RiskScoringEngine: Sendable {
    public let weights: RiskWeights

    public init(weights: RiskWeights = .default) {
        self.weights = weights
    }

    // MARK: - Single File Scoring

    /// Score a single file change.
    public func score(file: FileChangeInput) -> FileRiskProfile {
        var signals: [RiskSignal] = []

        // Signal 1: Churn — large changes are riskier
        let churnRatio = normalizeChurn(
            added: file.linesAdded,
            removed: file.linesRemoved,
            total: file.totalLines
        )
        signals.append(RiskSignal(
            name: "churn",
            weight: weights.churnWeight,
            value: churnRatio
        ))

        // Signal 2: Complexity proxy — deletions + additions vs file size
        let complexitySignal = normalizeComplexity(
            added: file.linesAdded,
            removed: file.linesRemoved,
            total: file.totalLines
        )
        signals.append(RiskSignal(
            name: "complexity",
            weight: weights.complexityWeight,
            value: complexitySignal
        ))

        // Signal 3: Test coverage — lower = riskier
        let coverageSignal = 1.0 - (file.testCoverage ?? 0.5)
        signals.append(RiskSignal(
            name: "test_coverage_deficit",
            weight: weights.testCoverageWeight,
            value: min(1.0, max(0.0, coverageSignal))
        ))

        // Signal 4: File age — recently changed files are riskier
        let ageSignal = normalizeAge(daysSinceLastChange: file.daysSinceLastChange)
        signals.append(RiskSignal(
            name: "file_age",
            weight: weights.fileAgeWeight,
            value: ageSignal
        ))

        // Signal 5: Hotspot — bug history
        let hotspotSignal = normalizeHotspot(bugCount: file.recentBugCount)
        signals.append(RiskSignal(
            name: "hotspot",
            weight: weights.hotspotWeight,
            value: hotspotSignal
        ))

        // Signal 6: Extension risk — some file types are inherently riskier
        let extSignal = extensionRisk(file.fileExtension)
        signals.append(RiskSignal(
            name: "extension_risk",
            weight: weights.extensionWeight,
            value: extSignal
        ))

        // Combine: weighted sum normalized to 0.0–1.0
        let rawScore = signals.reduce(0.0) { $0 + $1.contribution }
        let normalizedScore = min(1.0, max(0.0, rawScore / weights.totalWeight))
        let tier = RiskTier.from(score: normalizedScore)

        return FileRiskProfile(
            path: file.path,
            signals: signals,
            score: normalizedScore,
            tier: tier
        )
    }

    // MARK: - PR-Level Scoring

    /// Score all files in a PR and produce a summary.
    public func scorePR(files: [FileChangeInput]) -> PRRiskSummary {
        let profiles = files.map { score(file: $0) }

        guard !profiles.isEmpty else {
            return PRRiskSummary(
                files: [],
                overallScore: 0,
                overallTier: .low,
                topRisks: []
            )
        }

        // Overall = weighted average by churn size
        let totalChurn = profiles.reduce(0.0) { acc, p in
            let churnSignal = p.signals.first { $0.name == "churn" }
            return acc + (churnSignal?.value ?? 0.0) + 1.0
        }
        let weightedScore = profiles.reduce(0.0) { acc, p in
            let churnSignal = p.signals.first { $0.name == "churn" }
            let fileWeight = (churnSignal?.value ?? 0.0) + 1.0
            return acc + p.score * fileWeight
        }
        let overallScore = min(1.0, max(0.0, weightedScore / totalChurn))
        let overallTier = RiskTier.from(score: overallScore)

        // Top risks: files above medium threshold, sorted by score descending
        let topRisks = profiles
            .filter { $0.tier >= .medium }
            .sorted { $0.score > $1.score }
            .prefix(5)

        return PRRiskSummary(
            files: profiles,
            overallScore: overallScore,
            overallTier: overallTier,
            topRisks: Array(topRisks)
        )
    }

    // MARK: - Heuristic Normalization

    /// Churn ratio: lines changed / total file size, capped at 1.0.
    func normalizeChurn(added: Int, removed: Int, total: Int) -> Double {
        let changed = Double(added + removed)
        let fileSize = max(Double(total), 1.0)
        return min(1.0, changed / fileSize)
    }

    /// Complexity proxy: ratio of changes that are modifications (not pure additions).
    func normalizeComplexity(added: Int, removed: Int, total: Int) -> Double {
        let modifications = Double(min(added, removed))
        let totalChanges = Double(added + removed)
        guard totalChanges > 0 else { return 0.0 }
        // High modification ratio = more complex change (refactoring vs new code)
        let ratio = modifications / totalChanges
        // Scale: pure additions (0.0) are low risk, balanced modifications (1.0) are higher
        return min(1.0, ratio)
    }

    /// File age: recently changed files are riskier (more churn = more bugs).
    func normalizeAge(daysSinceLastChange: Int?) -> Double {
        guard let days = daysSinceLastChange else { return 0.5 }
        // Files changed in last 7 days = high risk, >90 days = low risk
        if days <= 7 { return 0.8 }
        if days <= 30 { return 0.5 }
        if days <= 90 { return 0.3 }
        return 0.1
    }

    /// Bug history hotspot signal.
    func normalizeHotspot(bugCount: Int) -> Double {
        switch bugCount {
        case 0: return 0.0
        case 1: return 0.3
        case 2: return 0.6
        case 3: return 0.8
        default: return 1.0
        }
    }

    /// File extension risk rating.
    func extensionRisk(_ ext: String) -> Double {
        let normalized = ext.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        switch normalized {
        case "swift", "rs", "go":
            // Compiled, type-safe — lower inherent risk
            return 0.2
        case "ts", "kt":
            return 0.3
        case "js", "jsx", "tsx":
            // Dynamic typing areas
            return 0.5
        case "py", "rb":
            return 0.5
        case "yml", "yaml", "json", "toml":
            // Config files — low churn risk but high blast radius
            return 0.4
        case "sh", "bash", "zsh":
            // Scripts — high risk if in CI
            return 0.6
        case "sql":
            // Migrations — very high blast radius
            return 0.8
        case "md", "txt":
            return 0.05
        default:
            return 0.3
        }
    }
}
