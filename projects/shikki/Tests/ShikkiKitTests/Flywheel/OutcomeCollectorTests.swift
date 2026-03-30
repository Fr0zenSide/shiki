import Foundation
import Testing
@testable import ShikkiKit

@Suite("OutcomeCollector")
struct OutcomeCollectorTests {

    // MARK: - Collection

    @Test("Collects outcome when telemetry is local")
    func collectLocal() {
        let config = TelemetryConfig(level: .local)
        let collector = OutcomeCollector(telemetryConfig: config)

        let outcome = collector.collect(
            taskType: .feature,
            language: "swift",
            fileExtension: ".swift",
            linesChanged: 100,
            filesChanged: 5,
            testCoverage: 0.85,
            durationSeconds: 600,
            outcome: .clean,
            riskPrediction: 0.3,
            riskTier: .medium
        )

        #expect(outcome != nil)
        #expect(outcome?.taskType == .feature)
        #expect(outcome?.language == "swift")
    }

    @Test("Collects outcome when telemetry is community")
    func collectCommunity() {
        let config = TelemetryConfig(level: .community)
        let collector = OutcomeCollector(telemetryConfig: config)

        let outcome = collector.collect(
            taskType: .bugfix,
            language: "typescript",
            fileExtension: ".ts",
            linesChanged: 50,
            filesChanged: 3,
            testCoverage: nil,
            durationSeconds: 300,
            outcome: .minorBug,
            riskPrediction: 0.6,
            riskTier: .high
        )

        #expect(outcome != nil)
        #expect(outcome?.taskType == .bugfix)
    }

    @Test("Returns nil when telemetry is off")
    func collectOff() {
        let config = TelemetryConfig(level: .off)
        let collector = OutcomeCollector(telemetryConfig: config)

        let outcome = collector.collect(
            taskType: .feature,
            language: "swift",
            fileExtension: ".swift",
            linesChanged: 100,
            filesChanged: 5,
            testCoverage: 0.85,
            durationSeconds: 600,
            outcome: .clean,
            riskPrediction: 0.3,
            riskTier: .medium
        )

        #expect(outcome == nil)
    }

    // MARK: - Anonymization Buckets

    @Test("Size buckets")
    func sizeBuckets() {
        #expect(SizeBucket.from(count: 0) == .tiny)
        #expect(SizeBucket.from(count: 5) == .tiny)
        #expect(SizeBucket.from(count: 10) == .tiny)
        #expect(SizeBucket.from(count: 11) == .small)
        #expect(SizeBucket.from(count: 50) == .small)
        #expect(SizeBucket.from(count: 51) == .medium)
        #expect(SizeBucket.from(count: 200) == .medium)
        #expect(SizeBucket.from(count: 201) == .large)
        #expect(SizeBucket.from(count: 500) == .large)
        #expect(SizeBucket.from(count: 501) == .huge)
    }

    @Test("Coverage buckets")
    func coverageBuckets() {
        #expect(CoverageBucket.from(percentage: 0.0) == .none)
        #expect(CoverageBucket.from(percentage: 0.15) == .low)
        #expect(CoverageBucket.from(percentage: 0.30) == .low)
        #expect(CoverageBucket.from(percentage: 0.45) == .medium)
        #expect(CoverageBucket.from(percentage: 0.60) == .medium)
        #expect(CoverageBucket.from(percentage: 0.75) == .high)
        #expect(CoverageBucket.from(percentage: 0.90) == .high)
        #expect(CoverageBucket.from(percentage: 0.95) == .full)
        #expect(CoverageBucket.from(percentage: 1.0) == .full)
    }

    @Test("Duration buckets")
    func durationBuckets() {
        #expect(DurationBucket.from(seconds: 60) == .quick)
        #expect(DurationBucket.from(seconds: 299) == .quick)
        #expect(DurationBucket.from(seconds: 300) == .short)
        #expect(DurationBucket.from(seconds: 899) == .short)
        #expect(DurationBucket.from(seconds: 900) == .medium)
        #expect(DurationBucket.from(seconds: 3599) == .medium)
        #expect(DurationBucket.from(seconds: 3600) == .long)
        #expect(DurationBucket.from(seconds: 14399) == .long)
        #expect(DurationBucket.from(seconds: 14400) == .extended)
    }

    // MARK: - Extension Anonymization

    @Test("Known extensions are preserved")
    func knownExtensions() {
        let config = TelemetryConfig(level: .local)
        let collector = OutcomeCollector(telemetryConfig: config)

        #expect(collector.anonymizeExtension(".swift") == ".swift")
        #expect(collector.anonymizeExtension(".ts") == ".ts")
        #expect(collector.anonymizeExtension(".py") == ".py")
        #expect(collector.anonymizeExtension(".SQL") == ".sql")  // case-insensitive
    }

    @Test("Unknown extensions are generalized")
    func unknownExtensions() {
        let config = TelemetryConfig(level: .local)
        let collector = OutcomeCollector(telemetryConfig: config)

        #expect(collector.anonymizeExtension(".proprietary") == ".other")
        #expect(collector.anonymizeExtension(".abc123") == ".other")
    }

    // MARK: - Rounding

    @Test("Risk prediction is rounded")
    func riskRounding() {
        let config = TelemetryConfig(level: .local)
        let collector = OutcomeCollector(telemetryConfig: config)

        let outcome = collector.collect(
            taskType: .feature,
            language: "swift",
            fileExtension: ".swift",
            linesChanged: 100,
            filesChanged: 5,
            testCoverage: nil,
            durationSeconds: 600,
            outcome: .clean,
            riskPrediction: 0.33333,
            riskTier: .medium
        )

        // Should be rounded to 2 decimal places
        #expect(outcome?.riskPrediction == 0.33)
    }

    // MARK: - PR-Level Collection

    @Test("Collect PR outcome")
    func collectPROutcome() {
        let config = TelemetryConfig(level: .community)
        let collector = OutcomeCollector(telemetryConfig: config)
        let riskSummary = PRRiskSummary(
            files: [],
            overallScore: 0.4,
            overallTier: .medium,
            topRisks: []
        )

        let outcome = collector.collectPR(
            files: [
                (extension: ".swift", linesChanged: 100),
                (extension: ".swift", linesChanged: 50),
                (extension: ".md", linesChanged: 10),
            ],
            taskType: .feature,
            language: "swift",
            totalDuration: 3600,
            outcome: .clean,
            riskSummary: riskSummary
        )

        #expect(outcome != nil)
        #expect(outcome?.linesChangedBucket == .medium) // 160 total
        #expect(outcome?.filesChangedBucket == .tiny)   // 3 files
        #expect(outcome?.fileExtension == ".swift")      // primary extension
    }

    // MARK: - Agent Behavior Signals

    @Test("Agent behavior signals captured")
    func agentBehaviorSignals() {
        let config = TelemetryConfig(level: .local)
        let collector = OutcomeCollector(telemetryConfig: config)

        let outcome = collector.collect(
            taskType: .feature,
            language: "swift",
            fileExtension: ".swift",
            linesChanged: 100,
            filesChanged: 5,
            testCoverage: 0.8,
            durationSeconds: 600,
            outcome: .clean,
            riskPrediction: 0.3,
            riskTier: .medium,
            contextResets: 2,
            watchdogEscalations: 1,
            retries: 3
        )

        #expect(outcome?.contextResetsCount == 2)
        #expect(outcome?.watchdogEscalations == 1)
        #expect(outcome?.retryCount == 3)
    }

    // MARK: - Codable

    @Test("AnonymizedOutcome round-trips via JSON")
    func outcomeCodable() throws {
        let outcome = AnonymizedOutcome(
            taskType: .feature,
            language: "swift",
            fileExtension: ".swift",
            linesChangedBucket: .medium,
            filesChangedBucket: .small,
            testCoverageBucket: .high,
            durationBucket: .medium,
            outcome: .clean,
            riskPrediction: 0.35,
            riskTierPredicted: .medium
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(outcome)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AnonymizedOutcome.self, from: data)

        #expect(decoded.taskType == outcome.taskType)
        #expect(decoded.language == outcome.language)
        #expect(decoded.linesChangedBucket == outcome.linesChangedBucket)
        #expect(decoded.riskPrediction == outcome.riskPrediction)
    }

    @Test("TaskCategory values")
    func taskCategories() {
        let categories: [TaskCategory] = [.feature, .bugfix, .refactor, .test, .docs, .config, .ci, .unknown]
        #expect(categories.count == 8)
    }
}
