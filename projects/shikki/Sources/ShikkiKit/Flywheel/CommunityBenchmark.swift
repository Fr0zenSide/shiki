import Foundation

// MARK: - BenchmarkComparison

/// Result of comparing local metrics against community baselines.
public struct BenchmarkComparison: Sendable, Equatable {
    public let metric: String
    public let localValue: Double
    public let communityBaseline: Double
    public let delta: Double
    public let percentile: BenchmarkPercentile

    public init(
        metric: String,
        localValue: Double,
        communityBaseline: Double
    ) {
        self.metric = metric
        self.localValue = localValue
        self.communityBaseline = communityBaseline
        self.delta = localValue - communityBaseline
        self.percentile = Self.computePercentile(local: localValue, baseline: communityBaseline)
    }

    /// Rough percentile estimate using baseline as median.
    private static func computePercentile(local: Double, baseline: Double) -> BenchmarkPercentile {
        guard baseline > 0 else { return .unknown }
        let ratio = local / baseline
        switch ratio {
        case ..<0.5: return .bottom25
        case 0.5..<0.85: return .belowAverage
        case 0.85..<1.15: return .average
        case 1.15..<1.5: return .aboveAverage
        default: return .top25
        }
    }
}

// MARK: - BenchmarkPercentile

/// Rough percentile range for comparison display.
public enum BenchmarkPercentile: String, Sendable, Equatable {
    case top25 = "top 25%"
    case aboveAverage = "above average"
    case average = "average"
    case belowAverage = "below average"
    case bottom25 = "bottom 25%"
    case unknown = "insufficient data"
}

// MARK: - BenchmarkReport

/// Complete benchmark report comparing local against community.
public struct BenchmarkReport: Sendable, Equatable {
    public let comparisons: [BenchmarkComparison]
    public let generatedAt: Date
    public let localSampleCount: Int
    public let communitySampleCount: Int

    public init(
        comparisons: [BenchmarkComparison],
        generatedAt: Date = Date(),
        localSampleCount: Int,
        communitySampleCount: Int
    ) {
        self.comparisons = comparisons
        self.generatedAt = generatedAt
        self.localSampleCount = localSampleCount
        self.communitySampleCount = communitySampleCount
    }

    /// Overall health: how many metrics are at or above average.
    public var healthScore: Double {
        guard !comparisons.isEmpty else { return 0.0 }
        let good = comparisons.filter {
            $0.percentile == .top25 || $0.percentile == .aboveAverage || $0.percentile == .average
        }.count
        return Double(good) / Double(comparisons.count)
    }
}

// MARK: - CommunityBenchmark

/// Generates benchmark comparisons between local outcomes and community baselines.
public actor CommunityBenchmark {
    private let calibrationStore: CalibrationStore
    private let outcomeCollector: OutcomeCollector

    public init(
        calibrationStore: CalibrationStore,
        outcomeCollector: OutcomeCollector
    ) {
        self.calibrationStore = calibrationStore
        self.outcomeCollector = outcomeCollector
    }

    /// Generate a benchmark report comparing local outcomes to community baselines.
    public func generateReport() async -> BenchmarkReport {
        let baselines = await calibrationStore.benchmarkBaselines()
        let localRecords = await outcomeCollector.bufferedRecords()
        let localMetrics = computeLocalMetrics(from: localRecords)

        var comparisons: [BenchmarkComparison] = []

        // Compare task success rate
        if baselines.taskSuccessRate > 0 {
            comparisons.append(BenchmarkComparison(
                metric: "Task Success Rate",
                localValue: localMetrics.successRate,
                communityBaseline: baselines.taskSuccessRate
            ))
        }

        // Compare risk score accuracy
        if baselines.riskScoreAccuracy > 0 {
            comparisons.append(BenchmarkComparison(
                metric: "Risk Score Accuracy",
                localValue: localMetrics.riskAccuracy,
                communityBaseline: baselines.riskScoreAccuracy
            ))
        }

        // Compare context resets per session
        if baselines.avgContextResetsPerSession > 0 {
            // Lower is better, so we invert for comparison
            let localInverted = baselines.avgContextResetsPerSession > 0
                ? (baselines.avgContextResetsPerSession * 2 - localMetrics.avgContextResets)
                : 0
            let baselineInverted = baselines.avgContextResetsPerSession
            comparisons.append(BenchmarkComparison(
                metric: "Context Efficiency",
                localValue: max(localInverted, 0),
                communityBaseline: baselineInverted
            ))
        }

        return BenchmarkReport(
            comparisons: comparisons,
            localSampleCount: localRecords.count,
            communitySampleCount: baselines.sampleCount
        )
    }

    // MARK: - Local Metrics Computation

    private func computeLocalMetrics(from records: [OutcomeRecord]) -> LocalMetrics {
        let total = records.count
        guard total > 0 else {
            return LocalMetrics(successRate: 0, riskAccuracy: 0, avgContextResets: 0)
        }

        let successes = records.filter { $0.outcome == .success }.count
        let successRate = Double(successes) / Double(total)

        // Risk accuracy: how close predicted risk was to actual outcome
        let riskRecords = records.filter { $0.metrics.predictedRiskScore != nil }
        let riskAccuracy: Double
        if riskRecords.isEmpty {
            riskAccuracy = 0
        } else {
            let accuracies = riskRecords.map { record -> Double in
                let predicted = record.metrics.predictedRiskScore ?? 0
                let actual: Double = record.outcome == .failure ? 1.0 : 0.0
                return 1.0 - abs(predicted - actual)
            }
            riskAccuracy = accuracies.reduce(0, +) / Double(accuracies.count)
        }

        // Average context resets
        let resets = records.compactMap(\.metrics.contextResets)
        let avgResets = resets.isEmpty ? 0.0 : Double(resets.reduce(0, +)) / Double(resets.count)

        return LocalMetrics(
            successRate: successRate,
            riskAccuracy: riskAccuracy,
            avgContextResets: avgResets
        )
    }
}

// MARK: - LocalMetrics

/// Computed local metrics for benchmark comparison.
private struct LocalMetrics {
    let successRate: Double
    let riskAccuracy: Double
    let avgContextResets: Double
}
