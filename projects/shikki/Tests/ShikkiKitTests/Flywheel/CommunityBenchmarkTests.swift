import Foundation
import Testing

@testable import ShikkiKit

@Suite("CommunityBenchmark")
struct CommunityBenchmarkTests {

    // MARK: - BenchmarkComparison

    @Test("BenchmarkComparison computes delta")
    func comparisonDelta() {
        let comparison = BenchmarkComparison(
            metric: "Success Rate",
            localValue: 0.85,
            communityBaseline: 0.80
        )
        #expect(abs(comparison.delta - 0.05) < 0.001)
    }

    @Test("BenchmarkComparison percentile for above average")
    func percentileAboveAverage() {
        let comparison = BenchmarkComparison(
            metric: "Test",
            localValue: 1.3,
            communityBaseline: 1.0
        )
        #expect(comparison.percentile == .aboveAverage)
    }

    @Test("BenchmarkComparison percentile for top 25%")
    func percentileTop25() {
        let comparison = BenchmarkComparison(
            metric: "Test",
            localValue: 2.0,
            communityBaseline: 1.0
        )
        #expect(comparison.percentile == .top25)
    }

    @Test("BenchmarkComparison percentile for average")
    func percentileAverage() {
        let comparison = BenchmarkComparison(
            metric: "Test",
            localValue: 1.0,
            communityBaseline: 1.0
        )
        #expect(comparison.percentile == .average)
    }

    @Test("BenchmarkComparison percentile for below average")
    func percentileBelowAverage() {
        let comparison = BenchmarkComparison(
            metric: "Test",
            localValue: 0.6,
            communityBaseline: 1.0
        )
        #expect(comparison.percentile == .belowAverage)
    }

    @Test("BenchmarkComparison percentile for bottom 25%")
    func percentileBottom25() {
        let comparison = BenchmarkComparison(
            metric: "Test",
            localValue: 0.3,
            communityBaseline: 1.0
        )
        #expect(comparison.percentile == .bottom25)
    }

    @Test("BenchmarkComparison percentile unknown when no baseline")
    func percentileUnknown() {
        let comparison = BenchmarkComparison(
            metric: "Test",
            localValue: 0.5,
            communityBaseline: 0.0
        )
        #expect(comparison.percentile == .unknown)
    }

    // MARK: - BenchmarkReport

    @Test("BenchmarkReport health score all good")
    func healthScoreAllGood() {
        let report = BenchmarkReport(
            comparisons: [
                BenchmarkComparison(metric: "A", localValue: 1.0, communityBaseline: 1.0),
                BenchmarkComparison(metric: "B", localValue: 1.5, communityBaseline: 1.0),
            ],
            localSampleCount: 10,
            communitySampleCount: 1000
        )
        #expect(report.healthScore == 1.0)
    }

    @Test("BenchmarkReport health score mixed")
    func healthScoreMixed() {
        let report = BenchmarkReport(
            comparisons: [
                BenchmarkComparison(metric: "A", localValue: 1.0, communityBaseline: 1.0),  // average
                BenchmarkComparison(metric: "B", localValue: 0.3, communityBaseline: 1.0),  // bottom 25%
            ],
            localSampleCount: 10,
            communitySampleCount: 1000
        )
        #expect(report.healthScore == 0.5)
    }

    @Test("BenchmarkReport health score empty")
    func healthScoreEmpty() {
        let report = BenchmarkReport(
            comparisons: [],
            localSampleCount: 0,
            communitySampleCount: 0
        )
        #expect(report.healthScore == 0.0)
    }

    // MARK: - CommunityBenchmark Generate

    @Test("Benchmark report with no baselines returns empty comparisons")
    func reportNoBaselines() async {
        let telemetryPath = NSTemporaryDirectory() + "shikki-bench-\(UUID().uuidString).json"
        let calibrationPath = NSTemporaryDirectory() + "shikki-bench-cal-\(UUID().uuidString).json"

        let telemetryStore = TelemetryConfigStore(filePath: telemetryPath)
        let calibrationStore = CalibrationStore(filePath: calibrationPath)
        let collector = OutcomeCollector(telemetryStore: telemetryStore)
        let benchmark = CommunityBenchmark(
            calibrationStore: calibrationStore,
            outcomeCollector: collector
        )

        let report = await benchmark.generateReport()
        #expect(report.comparisons.isEmpty)
        #expect(report.communitySampleCount == 0)
    }

    @Test("Benchmark report with baselines generates comparisons")
    func reportWithBaselines() async throws {
        let telemetryPath = NSTemporaryDirectory() + "shikki-bench2-\(UUID().uuidString).json"
        let calibrationPath = NSTemporaryDirectory() + "shikki-bench2-cal-\(UUID().uuidString).json"

        let telemetryStore = TelemetryConfigStore(filePath: telemetryPath)
        let calibrationStore = CalibrationStore(filePath: calibrationPath)

        // Set baselines
        try await calibrationStore.updateBenchmarkBaselines(BenchmarkBaselines(
            riskScoreAccuracy: 0.7,
            taskSuccessRate: 0.8,
            avgContextResetsPerSession: 2.0,
            sampleCount: 5000
        ))

        let collector = OutcomeCollector(telemetryStore: telemetryStore)

        // Add some local outcomes
        for i in 0..<10 {
            let record = OutcomeRecord(
                category: .taskOutcomes,
                outcome: i < 7 ? .success : .failure,
                metrics: OutcomeMetrics(
                    predictedRiskScore: Double(i) / 10.0,
                    contextResets: i % 3
                )
            )
            await collector.record(record)
        }

        let benchmark = CommunityBenchmark(
            calibrationStore: calibrationStore,
            outcomeCollector: collector
        )

        let report = await benchmark.generateReport()
        #expect(!report.comparisons.isEmpty)
        #expect(report.localSampleCount == 10)
        #expect(report.communitySampleCount == 5000)

        // Should have task success rate comparison
        let successComparison = report.comparisons.first { $0.metric == "Task Success Rate" }
        #expect(successComparison != nil)
        #expect(abs(successComparison!.localValue - 0.7) < 0.01)
    }
}
