import Foundation
import Testing
@testable import ShikkiKit

@Suite("RiskScoringEngine")
struct RiskScoringEngineTests {

    let engine = RiskScoringEngine()

    // MARK: - Single File Scoring

    @Test("Low risk for small doc change")
    func lowRiskDocChange() {
        let file = FileChangeInput(
            path: "README.md",
            linesAdded: 5,
            linesRemoved: 2,
            totalLines: 100,
            testCoverage: 0.9,
            daysSinceLastChange: 120,
            recentBugCount: 0,
            fileExtension: ".md"
        )
        let profile = engine.score(file: file)
        #expect(profile.tier == .low)
        #expect(profile.score < 0.25)
    }

    @Test("High risk for large Swift change with no tests")
    func highRiskNoTests() {
        let file = FileChangeInput(
            path: "Core.swift",
            linesAdded: 200,
            linesRemoved: 150,
            totalLines: 300,
            testCoverage: 0.0,
            daysSinceLastChange: 2,
            recentBugCount: 3,
            fileExtension: ".swift"
        )
        let profile = engine.score(file: file)
        #expect(profile.tier >= .medium)
        #expect(profile.score > 0.4)
    }

    @Test("Critical risk for SQL migration with bug history")
    func criticalRiskSQL() {
        let file = FileChangeInput(
            path: "migration.sql",
            linesAdded: 50,
            linesRemoved: 30,
            totalLines: 50,
            testCoverage: 0.0,
            daysSinceLastChange: 1,
            recentBugCount: 5,
            fileExtension: ".sql"
        )
        let profile = engine.score(file: file)
        #expect(profile.tier >= .high)
    }

    @Test("Signals are all present")
    func allSignalsPresent() {
        let file = FileChangeInput(
            path: "test.swift",
            linesAdded: 10,
            linesRemoved: 5,
            totalLines: 100,
            fileExtension: ".swift"
        )
        let profile = engine.score(file: file)
        let signalNames = Set(profile.signals.map(\.name))

        #expect(signalNames.contains("churn"))
        #expect(signalNames.contains("complexity"))
        #expect(signalNames.contains("test_coverage_deficit"))
        #expect(signalNames.contains("file_age"))
        #expect(signalNames.contains("hotspot"))
        #expect(signalNames.contains("extension_risk"))
        #expect(profile.signals.count == 6)
    }

    @Test("Score is normalized between 0 and 1")
    func scoreNormalized() {
        // Extreme high-risk case
        let worstCase = FileChangeInput(
            path: "bad.js",
            linesAdded: 1000,
            linesRemoved: 500,
            totalLines: 100,
            testCoverage: 0.0,
            daysSinceLastChange: 1,
            recentBugCount: 10,
            fileExtension: ".js"
        )
        let profile = engine.score(file: worstCase)
        #expect(profile.score >= 0.0)
        #expect(profile.score <= 1.0)

        // Extreme low-risk case
        let bestCase = FileChangeInput(
            path: "readme.md",
            linesAdded: 1,
            linesRemoved: 0,
            totalLines: 1000,
            testCoverage: 1.0,
            daysSinceLastChange: 365,
            recentBugCount: 0,
            fileExtension: ".md"
        )
        let bestProfile = engine.score(file: bestCase)
        #expect(bestProfile.score >= 0.0)
        #expect(bestProfile.score <= 1.0)
    }

    // MARK: - PR-Level Scoring

    @Test("PR scoring aggregates files")
    func prScoring() {
        let files = [
            FileChangeInput(path: "a.swift", linesAdded: 10, linesRemoved: 5, totalLines: 100, fileExtension: ".swift"),
            FileChangeInput(path: "b.swift", linesAdded: 20, linesRemoved: 10, totalLines: 200, fileExtension: ".swift"),
            FileChangeInput(path: "c.md", linesAdded: 3, linesRemoved: 1, totalLines: 50, fileExtension: ".md"),
        ]
        let summary = engine.scorePR(files: files)

        #expect(summary.files.count == 3)
        #expect(summary.overallScore >= 0.0)
        #expect(summary.overallScore <= 1.0)
    }

    @Test("Empty PR returns low risk")
    func emptyPR() {
        let summary = engine.scorePR(files: [])
        #expect(summary.overallTier == .low)
        #expect(summary.overallScore == 0.0)
        #expect(summary.files.isEmpty)
    }

    @Test("Top risks are sorted by score descending")
    func topRisksSorted() {
        let files = [
            FileChangeInput(path: "safe.md", linesAdded: 1, linesRemoved: 0, totalLines: 100, testCoverage: 1.0, daysSinceLastChange: 365, recentBugCount: 0, fileExtension: ".md"),
            FileChangeInput(path: "risky.js", linesAdded: 500, linesRemoved: 200, totalLines: 100, testCoverage: 0.0, daysSinceLastChange: 1, recentBugCount: 5, fileExtension: ".js"),
            FileChangeInput(path: "medium.swift", linesAdded: 50, linesRemoved: 30, totalLines: 200, testCoverage: 0.3, daysSinceLastChange: 10, recentBugCount: 1, fileExtension: ".swift"),
        ]
        let summary = engine.scorePR(files: files)

        if summary.topRisks.count >= 2 {
            #expect(summary.topRisks[0].score >= summary.topRisks[1].score)
        }
    }

    // MARK: - Heuristic Functions

    @Test("Churn normalization")
    func churnNormalization() {
        #expect(engine.normalizeChurn(added: 0, removed: 0, total: 100) == 0.0)
        #expect(engine.normalizeChurn(added: 50, removed: 50, total: 100) == 1.0)
        #expect(engine.normalizeChurn(added: 200, removed: 200, total: 100) == 1.0) // capped
    }

    @Test("Complexity normalization")
    func complexityNormalization() {
        // Pure additions = low complexity
        #expect(engine.normalizeComplexity(added: 100, removed: 0, total: 200) == 0.0)
        // Balanced modifications = higher complexity
        let balanced = engine.normalizeComplexity(added: 50, removed: 50, total: 200)
        #expect(balanced > 0.4) // Should be significant
        // No changes
        #expect(engine.normalizeComplexity(added: 0, removed: 0, total: 100) == 0.0)
    }

    @Test("Age normalization")
    func ageNormalization() {
        #expect(engine.normalizeAge(daysSinceLastChange: nil) == 0.5)
        #expect(engine.normalizeAge(daysSinceLastChange: 1) == 0.8)
        #expect(engine.normalizeAge(daysSinceLastChange: 7) == 0.8)
        #expect(engine.normalizeAge(daysSinceLastChange: 15) == 0.5)
        #expect(engine.normalizeAge(daysSinceLastChange: 60) == 0.3)
        #expect(engine.normalizeAge(daysSinceLastChange: 365) == 0.1)
    }

    @Test("Hotspot normalization")
    func hotspotNormalization() {
        #expect(engine.normalizeHotspot(bugCount: 0) == 0.0)
        #expect(engine.normalizeHotspot(bugCount: 1) == 0.3)
        #expect(engine.normalizeHotspot(bugCount: 2) == 0.6)
        #expect(engine.normalizeHotspot(bugCount: 3) == 0.8)
        #expect(engine.normalizeHotspot(bugCount: 10) == 1.0)
    }

    @Test("Extension risk ratings")
    func extensionRisk() {
        // Type-safe languages are lower risk
        #expect(engine.extensionRisk(".swift") < engine.extensionRisk(".js"))
        #expect(engine.extensionRisk(".rs") < engine.extensionRisk(".py"))

        // SQL is high risk (migrations)
        #expect(engine.extensionRisk(".sql") > engine.extensionRisk(".swift"))

        // Docs are minimal risk
        #expect(engine.extensionRisk(".md") < 0.1)

        // Unknown defaults to moderate
        #expect(engine.extensionRisk(".xyz") == 0.3)
    }

    // MARK: - RiskTier

    @Test("RiskTier from score")
    func riskTierFromScore() {
        #expect(RiskTier.from(score: 0.0) == .low)
        #expect(RiskTier.from(score: 0.24) == .low)
        #expect(RiskTier.from(score: 0.25) == .medium)
        #expect(RiskTier.from(score: 0.49) == .medium)
        #expect(RiskTier.from(score: 0.50) == .high)
        #expect(RiskTier.from(score: 0.74) == .high)
        #expect(RiskTier.from(score: 0.75) == .critical)
        #expect(RiskTier.from(score: 1.0) == .critical)
    }

    @Test("RiskTier is comparable")
    func riskTierComparable() {
        #expect(RiskTier.low < RiskTier.medium)
        #expect(RiskTier.medium < RiskTier.high)
        #expect(RiskTier.high < RiskTier.critical)
    }

    // MARK: - Custom Weights

    @Test("Custom weights affect scoring")
    func customWeights() {
        let heavyChurn = RiskWeights(
            churnWeight: 0.90,
            complexityWeight: 0.02,
            testCoverageWeight: 0.02,
            fileAgeWeight: 0.02,
            hotspotWeight: 0.02,
            extensionWeight: 0.02
        )
        let churnEngine = RiskScoringEngine(weights: heavyChurn)

        let file = FileChangeInput(
            path: "big.swift",
            linesAdded: 500,
            linesRemoved: 200,
            totalLines: 100,
            testCoverage: 1.0,
            daysSinceLastChange: 365,
            recentBugCount: 0,
            fileExtension: ".swift"
        )

        let churnScore = churnEngine.score(file: file)
        let defaultScore = engine.score(file: file)

        // Heavy churn weighting should produce different score than default
        #expect(churnScore.score != defaultScore.score)
    }

    @Test("Weights total is accessible")
    func weightTotal() {
        let weights = RiskWeights.default
        let total = weights.totalWeight
        #expect(total > 0.99)
        #expect(total < 1.01)
    }

    // MARK: - RiskSignal

    @Test("RiskSignal contribution")
    func signalContribution() {
        let signal = RiskSignal(name: "test", weight: 0.5, value: 0.8)
        #expect(signal.contribution == 0.4)
    }
}
