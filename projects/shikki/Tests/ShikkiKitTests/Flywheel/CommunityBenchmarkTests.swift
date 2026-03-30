import Foundation
import Testing

@testable import ShikkiKit

@Suite("CommunityBenchmark")
struct CommunityBenchmarkTests {

    // MARK: - BenchmarkMetric

    @Test("BenchmarkMetric stores fields")
    func metricFields() {
        let metric = BenchmarkMetric(name: "Accuracy", value: 0.85, unit: "%")
        #expect(metric.name == "Accuracy")
        #expect(metric.value == 0.85)
        #expect(metric.unit == "%")
        #expect(metric.percentile == nil)
    }

    @Test("BenchmarkMetric with percentile")
    func metricPercentile() {
        let metric = BenchmarkMetric(name: "MAE", value: 0.1, unit: "score", percentile: 0.75)
        #expect(metric.percentile == 0.75)
    }

    @Test("BenchmarkMetric Codable round-trip")
    func metricCodable() throws {
        let metric = BenchmarkMetric(name: "Test", value: 42.0, unit: "ms", percentile: 0.5)
        let data = try JSONEncoder().encode(metric)
        let decoded = try JSONDecoder().decode(BenchmarkMetric.self, from: data)
        #expect(decoded == metric)
    }

    // MARK: - CommunityBaseline

    @Test("CommunityBaseline empty has zero samples")
    func emptyBaseline() {
        let baseline = CommunityBaseline.empty
        #expect(baseline.sampleSize == 0)
    }

    @Test("CommunityBaseline Codable round-trip")
    func baselineCodable() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let baseline = CommunityBaseline(
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            sampleSize: 500,
            medianRiskAccuracy: 0.8,
            medianBugRate: 0.05,
            medianTimeToMerge: 3600,
            riskWeights: nil
        )
        let data = try encoder.encode(baseline)
        let decoded = try decoder.decode(CommunityBaseline.self, from: data)
        #expect(decoded.sampleSize == baseline.sampleSize)
        #expect(decoded.medianRiskAccuracy == baseline.medianRiskAccuracy)
    }

    // MARK: - RecommendationPriority

    @Test("RecommendationPriority raw values")
    func priorityRawValues() {
        #expect(RecommendationPriority.info.rawValue == "info")
        #expect(RecommendationPriority.suggestion.rawValue == "suggestion")
        #expect(RecommendationPriority.warning.rawValue == "warning")
        #expect(RecommendationPriority.critical.rawValue == "critical")
    }

    // MARK: - BenchmarkReport

    @Test("BenchmarkReport with empty metrics")
    func emptyReport() {
        let report = BenchmarkReport(
            recordCount: 0,
            metrics: [],
            riskAccuracy: nil,
            recommendations: []
        )
        #expect(report.metrics.isEmpty)
        #expect(report.recommendations.isEmpty)
        #expect(report.recordCount == 0)
    }

    @Test("BenchmarkReport with data")
    func fullReport() {
        let report = BenchmarkReport(
            recordCount: 50,
            metrics: [
                BenchmarkMetric(name: "Accuracy", value: 0.85, unit: "%"),
            ],
            riskAccuracy: nil,
            recommendations: [
                BenchmarkRecommendation(priority: .suggestion, area: "Testing", message: "Add more tests"),
            ]
        )
        #expect(report.metrics.count == 1)
        #expect(report.recommendations.count == 1)
        #expect(report.recommendations[0].priority == .suggestion)
    }

    // MARK: - CommunityBenchmark Generate

    @Test("Benchmark from empty records")
    func emptyRecords() {
        let benchmark = CommunityBenchmark()
        let report = benchmark.generateReport(from: [])
        #expect(report.metrics.isEmpty)
        #expect(report.recordCount == 0)
    }

    @Test("Benchmark from records produces metrics")
    func recordsProduceMetrics() {
        let records = [
            CalibrationRecord(
                predictedScore: 0.2,
                predictedTier: .low,
                actualOutcome: .clean,
                fileExtension: "swift",
                linesChanged: 50
            ),
            CalibrationRecord(
                predictedScore: 0.6,
                predictedTier: .medium,
                actualOutcome: .majorBug,
                fileExtension: "swift",
                linesChanged: 200
            ),
        ]
        let benchmark = CommunityBenchmark()
        let report = benchmark.generateReport(from: records)
        #expect(report.recordCount == 2)
    }

    @Test("Benchmark with baseline")
    func withBaseline() {
        let baseline = CommunityBaseline(
            updatedAt: Date(),
            sampleSize: 1000,
            medianRiskAccuracy: 0.8,
            medianBugRate: 0.05,
            medianTimeToMerge: 3600,
            riskWeights: nil
        )
        let benchmark = CommunityBenchmark(baseline: baseline)
        let records = [
            CalibrationRecord(
                predictedScore: 0.2,
                predictedTier: .low,
                actualOutcome: .clean,
                fileExtension: "swift",
                linesChanged: 30
            ),
        ]
        let report = benchmark.generateReport(from: records)
        #expect(report.recordCount == 1)
    }
}
