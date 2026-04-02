import Foundation

// MARK: - BenchmarkMetric

/// A single metric in the community benchmark.
public struct BenchmarkMetric: Codable, Sendable, Equatable {
    public let name: String
    public let value: Double
    public let unit: String
    public let percentile: Double?    // Where this instance sits vs community (0–100)

    public init(name: String, value: Double, unit: String, percentile: Double? = nil) {
        self.name = name
        self.value = value
        self.unit = unit
        self.percentile = percentile
    }
}

// MARK: - BenchmarkReport

/// A complete benchmark report comparing local performance to community baselines.
public struct BenchmarkReport: Codable, Sendable, Equatable {
    public let generatedAt: Date
    public let recordCount: Int
    public let metrics: [BenchmarkMetric]
    public let riskAccuracy: CalibrationStats?
    public let recommendations: [BenchmarkRecommendation]

    public init(
        generatedAt: Date = Date(),
        recordCount: Int,
        metrics: [BenchmarkMetric],
        riskAccuracy: CalibrationStats?,
        recommendations: [BenchmarkRecommendation]
    ) {
        self.generatedAt = generatedAt
        self.recordCount = recordCount
        self.metrics = metrics
        self.riskAccuracy = riskAccuracy
        self.recommendations = recommendations
    }
}

// MARK: - BenchmarkRecommendation

/// Actionable recommendation from benchmark analysis.
public struct BenchmarkRecommendation: Codable, Sendable, Equatable {
    public let priority: RecommendationPriority
    public let area: String
    public let message: String

    public init(priority: RecommendationPriority, area: String, message: String) {
        self.priority = priority
        self.area = area
        self.message = message
    }
}

/// Priority level for benchmark recommendations.
public enum RecommendationPriority: String, Codable, Sendable, Equatable {
    case info
    case suggestion
    case warning
    case critical
}

// MARK: - CommunityBaseline

/// Community-wide baseline statistics (downloaded via `shi update --models`).
/// Starts empty — populated when community data becomes available.
public struct CommunityBaseline: Codable, Sendable, Equatable {
    public let updatedAt: Date
    public let sampleSize: Int
    public let medianRiskAccuracy: Double
    public let medianBugRate: Double
    public let medianTimeToMerge: TimeInterval
    public let riskWeights: RiskWeights?

    public static let empty = CommunityBaseline(
        updatedAt: Date.distantPast,
        sampleSize: 0,
        medianRiskAccuracy: 0,
        medianBugRate: 0,
        medianTimeToMerge: 0,
        riskWeights: nil
    )

    public init(
        updatedAt: Date,
        sampleSize: Int,
        medianRiskAccuracy: Double,
        medianBugRate: Double,
        medianTimeToMerge: TimeInterval,
        riskWeights: RiskWeights?
    ) {
        self.updatedAt = updatedAt
        self.sampleSize = sampleSize
        self.medianRiskAccuracy = medianRiskAccuracy
        self.medianBugRate = medianBugRate
        self.medianTimeToMerge = medianTimeToMerge
        self.riskWeights = riskWeights
    }
}

// MARK: - CommunityBenchmark

/// Generates benchmark reports comparing local calibration data
/// against community baselines. When no community data is available,
/// produces self-assessment reports from local data only.
public struct CommunityBenchmark: Sendable {
    private let baseline: CommunityBaseline

    public init(baseline: CommunityBaseline = .empty) {
        self.baseline = baseline
    }

    /// Generate a full benchmark report from local calibration data.
    public func generateReport(from records: [CalibrationRecord]) -> BenchmarkReport {
        guard !records.isEmpty else {
            return BenchmarkReport(
                recordCount: 0,
                metrics: [],
                riskAccuracy: nil,
                recommendations: [
                    BenchmarkRecommendation(
                        priority: .info,
                        area: "data",
                        message: "No calibration data yet. Complete some tasks to start benchmarking."
                    ),
                ]
            )
        }

        var metrics: [BenchmarkMetric] = []
        var recommendations: [BenchmarkRecommendation] = []

        // Metric 1: Risk prediction accuracy
        let correctPredictions = records.filter { record in
            CalibrationStore.expectedTier(for: record.actualOutcome) == record.predictedTier
        }
        let accuracy = Double(correctPredictions.count) / Double(records.count)
        metrics.append(BenchmarkMetric(
            name: "risk_accuracy",
            value: accuracy,
            unit: "ratio",
            percentile: baseline.sampleSize > 0
                ? percentileVsBaseline(accuracy, baseline: baseline.medianRiskAccuracy) : nil
        ))

        // Metric 2: Bug rate (non-clean outcomes / total)
        let bugRecords = records.filter { $0.actualOutcome != .clean }
        let bugRate = Double(bugRecords.count) / Double(records.count)
        metrics.append(BenchmarkMetric(
            name: "bug_rate",
            value: bugRate,
            unit: "ratio",
            percentile: baseline.sampleSize > 0
                ? invertedPercentile(bugRate, baseline: baseline.medianBugRate) : nil
        ))

        // Metric 3: Mean absolute error
        let totalError = records.reduce(0.0) { acc, r in
            acc + abs(r.predictedScore - CalibrationStore.outcomeScore(r.actualOutcome))
        }
        let mae = totalError / Double(records.count)
        metrics.append(BenchmarkMetric(
            name: "mean_absolute_error",
            value: mae,
            unit: "score_delta"
        ))

        // Metric 4: Tier distribution skew
        let tierCounts = Dictionary(grouping: records, by: \.predictedTier)
        let lowCount = tierCounts[.low]?.count ?? 0
        let highCount = (tierCounts[.high]?.count ?? 0) + (tierCounts[.critical]?.count ?? 0)
        let skew = records.isEmpty ? 0.0 : Double(highCount - lowCount) / Double(records.count)
        metrics.append(BenchmarkMetric(
            name: "risk_tier_skew",
            value: skew,
            unit: "ratio"
        ))

        // Metric 5: Language diversity
        let languages = Set(records.compactMap(\.language))
        metrics.append(BenchmarkMetric(
            name: "language_diversity",
            value: Double(languages.count),
            unit: "count"
        ))

        // Recommendations
        if accuracy < 0.5 {
            recommendations.append(BenchmarkRecommendation(
                priority: .warning,
                area: "risk_scoring",
                message: "Risk prediction accuracy is \(String(format: "%.0f", accuracy * 100))% — below 50%. Consider recalibrating weights."
            ))
        }

        if bugRate > 0.3 {
            recommendations.append(BenchmarkRecommendation(
                priority: .warning,
                area: "quality",
                message: "Bug rate is \(String(format: "%.0f", bugRate * 100))% — above 30% threshold. Review test coverage strategy."
            ))
        }

        if mae > 0.4 {
            recommendations.append(BenchmarkRecommendation(
                priority: .suggestion,
                area: "calibration",
                message: "Mean prediction error is \(String(format: "%.2f", mae)). More calibration data will improve accuracy."
            ))
        }

        if records.count < 50 {
            recommendations.append(BenchmarkRecommendation(
                priority: .info,
                area: "data",
                message: "Only \(records.count) calibration records. 50+ recommended for reliable benchmarks."
            ))
        }

        if baseline.sampleSize == 0 {
            recommendations.append(BenchmarkRecommendation(
                priority: .info,
                area: "community",
                message: "No community baseline available. Enable community telemetry to compare against peers."
            ))
        }

        // Compute calibration stats
        let tierDist = Dictionary(grouping: records, by: \.predictedTier)
            .mapValues(\.count)
            .reduce(into: [String: Int]()) { $0[$1.key.rawValue] = $1.value }
        let outcomeDist = Dictionary(grouping: records, by: \.actualOutcome)
            .mapValues(\.count)
            .reduce(into: [String: Int]()) { $0[$1.key.rawValue] = $1.value }

        let calibrationStats = CalibrationStats(
            totalRecords: records.count,
            accuracy: accuracy,
            meanAbsoluteError: mae,
            tierDistribution: tierDist,
            outcomeDistribution: outcomeDist
        )

        return BenchmarkReport(
            recordCount: records.count,
            metrics: metrics,
            riskAccuracy: calibrationStats,
            recommendations: recommendations
        )
    }

    // MARK: - Percentile Helpers

    /// Where does `value` sit vs the community median? Higher is better.
    func percentileVsBaseline(_ value: Double, baseline: Double) -> Double {
        guard baseline > 0 else { return 50.0 }
        let ratio = value / baseline
        // Simple linear mapping: 0.5x baseline = p25, 1.0x = p50, 1.5x = p75
        return min(100.0, max(0.0, ratio * 50.0))
    }

    /// Inverted percentile: lower value is better (e.g., bug rate).
    func invertedPercentile(_ value: Double, baseline: Double) -> Double {
        guard baseline > 0 else { return 50.0 }
        let ratio = value / baseline
        // Invert: 0.5x baseline bug rate = p75, 1.0x = p50, 1.5x = p25
        return min(100.0, max(0.0, 100.0 - ratio * 50.0))
    }
}
