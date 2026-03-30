import Foundation
import Testing

@testable import ShikkiKit

@Suite("RiskScoringEngine")
struct RiskScoringEngineTests {

    private func makeEngine() async -> RiskScoringEngine {
        let store = CalibrationStore(filePath: NSTemporaryDirectory() + "shikki-risk-test-\(UUID().uuidString).json")
        return await RiskScoringEngine(calibrationStore: store)
    }

    // MARK: - RiskLevel

    @Test("RiskLevel thresholds are correct")
    func riskLevelThresholds() {
        #expect(RiskLevel.from(score: 0.0) == .low)
        #expect(RiskLevel.from(score: 0.24) == .low)
        #expect(RiskLevel.from(score: 0.25) == .medium)
        #expect(RiskLevel.from(score: 0.49) == .medium)
        #expect(RiskLevel.from(score: 0.50) == .high)
        #expect(RiskLevel.from(score: 0.74) == .high)
        #expect(RiskLevel.from(score: 0.75) == .critical)
        #expect(RiskLevel.from(score: 1.0) == .critical)
    }

    @Test("RiskLevel is comparable")
    func riskLevelComparable() {
        #expect(RiskLevel.low < .medium)
        #expect(RiskLevel.medium < .high)
        #expect(RiskLevel.high < .critical)
    }

    // MARK: - File Scoring

    @Test("Small file change scores low")
    func smallFileChange() async {
        let engine = await makeEngine()
        let change = FileChange(
            path: "src/Utils/Helper.swift",
            linesAdded: 3,
            linesDeleted: 1,
            hasTestCoverage: true
        )
        let score = await engine.scoreFile(change)
        #expect(score.level == .low)
        #expect(score.score < 0.25)
    }

    @Test("Large file without tests scores higher")
    func largeUncoveredFile() async {
        let engine = await makeEngine()
        let change = FileChange(
            path: "src/Core/CriticalService.swift",
            linesAdded: 200,
            linesDeleted: 50,
            hasTestCoverage: false
        )
        let score = await engine.scoreFile(change)
        #expect(score.level >= .medium)
        #expect(score.score >= 0.25)
    }

    @Test("Test file does not get test coverage factor")
    func testFileNoTestCoverageFactor() async {
        let engine = await makeEngine()
        let change = FileChange(
            path: "Tests/MyTests.swift",
            linesAdded: 50,
            linesDeleted: 10,
            isTestFile: true,
            hasTestCoverage: false
        )
        let score = await engine.scoreFile(change)
        let hasTestFactor = score.factors.contains { $0.name == "test_coverage" }
        #expect(!hasTestFactor)
    }

    @Test("New file gets negative risk factor")
    func newFileBonus() async {
        let engine = await makeEngine()
        let change = FileChange(
            path: "src/NewFeature.swift",
            linesAdded: 50,
            linesDeleted: 0,
            isNewFile: true,
            hasTestCoverage: true
        )
        let score = await engine.scoreFile(change)
        let newFileFactor = score.factors.first { $0.name == "new_file" }
        #expect(newFileFactor != nil)
        #expect(newFileFactor!.value < 0)
    }

    @Test("Deletion-heavy change adds risk factor")
    func deletionHeavy() async {
        let engine = await makeEngine()
        let change = FileChange(
            path: "src/Legacy.swift",
            linesAdded: 5,
            linesDeleted: 95
        )
        let score = await engine.scoreFile(change)
        let deletionFactor = score.factors.first { $0.name == "deletion_heavy" }
        #expect(deletionFactor != nil)
    }

    @Test("Score is clamped between 0 and 1")
    func scoreClamped() async {
        let engine = await makeEngine()

        // Even extreme inputs should be clamped
        let change = FileChange(
            path: "src/Huge.swift",
            linesAdded: 10000,
            linesDeleted: 5000,
            hasTestCoverage: false
        )
        let score = await engine.scoreFile(change)
        #expect(score.score >= 0.0)
        #expect(score.score <= 1.0)
    }

    @Test("Deep nesting increases risk")
    func deepNesting() async {
        let engine = await makeEngine()
        let shallow = FileChange(
            path: "src/App.swift",
            linesAdded: 20,
            linesDeleted: 5,
            hasTestCoverage: true
        )
        let deep = FileChange(
            path: "src/a/b/c/d/e/f/g/Deep.swift",
            linesAdded: 20,
            linesDeleted: 5,
            hasTestCoverage: true
        )
        let shallowScore = await engine.scoreFile(shallow)
        let deepScore = await engine.scoreFile(deep)
        #expect(deepScore.score >= shallowScore.score)
    }

    // MARK: - PR Scoring

    @Test("Empty PR scores zero")
    func emptyPR() async {
        let engine = await makeEngine()
        let score = await engine.scorePR(files: [], prTitle: "empty")
        #expect(score.score == 0.0)
        #expect(score.level == .low)
    }

    @Test("PR score aggregates file risks")
    func prAggregation() async {
        let engine = await makeEngine()
        let files = [
            FileChange(path: "a.swift", linesAdded: 5, linesDeleted: 1, hasTestCoverage: true),
            FileChange(path: "b.swift", linesAdded: 200, linesDeleted: 100, hasTestCoverage: false),
        ]
        let score = await engine.scorePR(files: files, prTitle: "test PR")
        #expect(score.subject == "test PR")
        #expect(score.factors.contains { $0.name == "max_file_risk" })
        #expect(score.factors.contains { $0.name == "avg_file_risk" })
        #expect(score.factors.contains { $0.name == "pr_size" })
        #expect(score.factors.contains { $0.name == "file_count" })
        #expect(score.factors.contains { $0.name == "test_ratio" })
    }

    @Test("PR with no tests scores higher risk")
    func prNoTests() async {
        let engine = await makeEngine()
        let withTests = [
            FileChange(path: "src/a.swift", linesAdded: 30, linesDeleted: 5),
            FileChange(path: "Tests/aTests.swift", linesAdded: 20, linesDeleted: 2, isTestFile: true),
        ]
        let noTests = [
            FileChange(path: "src/a.swift", linesAdded: 30, linesDeleted: 5),
            FileChange(path: "src/b.swift", linesAdded: 20, linesDeleted: 2),
        ]
        let scoreWithTests = await engine.scorePR(files: withTests)
        let scoreNoTests = await engine.scorePR(files: noTests)
        // The no-tests PR should have a higher test_ratio factor
        let testRatioWith = scoreWithTests.factors.first { $0.name == "test_ratio" }?.value ?? 0
        let testRatioNo = scoreNoTests.factors.first { $0.name == "test_ratio" }?.value ?? 0
        #expect(testRatioNo >= testRatioWith)
    }

    // MARK: - RiskWeights

    @Test("Default risk weights sum to 1.0")
    func defaultWeightsSum() {
        let w = RiskWeights.default
        let sum = w.churnWeight + w.testCoverageWeight + w.fileTypeWeight
            + w.nestingDepthWeight + w.deletionHeavyWeight + w.newFileWeight
        #expect(abs(sum - 1.0) < 0.01)
    }

    @Test("RiskWeights JSON roundtrip")
    func weightsRoundTrip() throws {
        let weights = RiskWeights(churnWeight: 0.5, testCoverageWeight: 0.3)
        let data = try JSONEncoder().encode(weights)
        let decoded = try JSONDecoder().decode(RiskWeights.self, from: data)
        #expect(decoded == weights)
    }

    // MARK: - FileChange

    @Test("FileChange computes churn correctly")
    func fileChangeChurn() {
        let change = FileChange(path: "test.swift", linesAdded: 10, linesDeleted: 5)
        #expect(change.churn == 15)
    }

    @Test("FileChange extracts extension")
    func fileChangeExtension() {
        let swift = FileChange(path: "src/App.swift", linesAdded: 1, linesDeleted: 0)
        #expect(swift.fileExtension == "swift")
        let yml = FileChange(path: "config.yml", linesAdded: 1, linesDeleted: 0)
        #expect(yml.fileExtension == "yml")
    }

    @Test("FileChange computes directory depth")
    func fileChangeDepth() {
        let shallow = FileChange(path: "App.swift", linesAdded: 1, linesDeleted: 0)
        #expect(shallow.directoryDepth == 0)
        let deep = FileChange(path: "a/b/c/d.swift", linesAdded: 1, linesDeleted: 0)
        #expect(deep.directoryDepth == 3)
    }

    // MARK: - RiskScore

    @Test("RiskScore JSON roundtrip")
    func riskScoreRoundTrip() throws {
        // Use a whole-second date to avoid ISO8601 sub-second precision loss
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let score = RiskScore(
            subject: "test.swift",
            score: 0.42,
            factors: [
                RiskFactor(name: "churn", weight: 0.3, value: 0.5, description: "50 lines"),
            ],
            timestamp: fixedDate
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(score)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(RiskScore.self, from: data)
        #expect(decoded == score)
    }
}
