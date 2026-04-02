import Foundation
import Testing
@testable import ShikkiKit

// MARK: - ReviewVerdict Tests

@Suite("ReviewVerdict.from(findings:)")
struct ReviewVerdictTests {

    @Test("No findings returns approve")
    func noFindingsApprove() {
        let verdict = ReviewVerdict.from(findings: [])
        #expect(verdict == .approve)
    }

    @Test("Only minor findings returns approve")
    func onlyMinorApprove() {
        let findings = [
            PRReviewFinding(severity: .minor, reviewer: "@tech", message: "Spacing"),
            PRReviewFinding(severity: .minor, reviewer: "@tech", message: "Naming"),
        ]
        let verdict = ReviewVerdict.from(findings: findings)
        #expect(verdict == .approve)
    }

    @Test("Single critical returns changesRequested")
    func singleCriticalChangesRequested() {
        let findings = [
            PRReviewFinding(severity: .critical, reviewer: "@Sensei", message: "Race condition"),
        ]
        let verdict = ReviewVerdict.from(findings: findings)
        #expect(verdict == .changesRequested)
    }

    @Test("Multiple criticals returns changesRequested")
    func multipleCriticalsChangesRequested() {
        let findings = [
            PRReviewFinding(severity: .critical, reviewer: "@Sensei", message: "Race condition"),
            PRReviewFinding(severity: .critical, reviewer: "@Katana", message: "SQL injection"),
            PRReviewFinding(severity: .minor, reviewer: "@tech", message: "Typo"),
        ]
        let verdict = ReviewVerdict.from(findings: findings)
        #expect(verdict == .changesRequested)
    }

    @Test("Three or more important findings returns changesRequested")
    func threeImportantChangesRequested() {
        let findings = [
            PRReviewFinding(severity: .important, reviewer: "@Sensei", message: "Missing tests"),
            PRReviewFinding(severity: .important, reviewer: "@tech", message: "Error handling"),
            PRReviewFinding(severity: .important, reviewer: "@tech", message: "Missing docs"),
        ]
        let verdict = ReviewVerdict.from(findings: findings)
        #expect(verdict == .changesRequested)
    }

    @Test("Single important returns needsDiscussion")
    func singleImportantNeedsDiscussion() {
        let findings = [
            PRReviewFinding(severity: .important, reviewer: "@Sensei", message: "Architecture concern"),
        ]
        let verdict = ReviewVerdict.from(findings: findings)
        #expect(verdict == .needsDiscussion)
    }

    @Test("Two important returns needsDiscussion")
    func twoImportantNeedsDiscussion() {
        let findings = [
            PRReviewFinding(severity: .important, reviewer: "@Sensei", message: "Architecture concern"),
            PRReviewFinding(severity: .important, reviewer: "@tech", message: "Performance issue"),
        ]
        let verdict = ReviewVerdict.from(findings: findings)
        #expect(verdict == .needsDiscussion)
    }

    @Test("Critical takes precedence over important count")
    func criticalPrecedence() {
        let findings = [
            PRReviewFinding(severity: .critical, reviewer: "@Sensei", message: "Security hole"),
            PRReviewFinding(severity: .important, reviewer: "@tech", message: "Missing tests"),
        ]
        let verdict = ReviewVerdict.from(findings: findings)
        #expect(verdict == .changesRequested)
    }
}

// MARK: - PRReviewFinding Tests

@Suite("PRReviewFinding")
struct PRReviewFindingTests {

    @Test("Finding with all fields")
    func findingWithAllFields() {
        let finding = PRReviewFinding(
            severity: .critical, reviewer: "@Sensei",
            file: "Foo.swift", line: 42, message: "Race condition"
        )
        #expect(finding.severity == .critical)
        #expect(finding.reviewer == "@Sensei")
        #expect(finding.file == "Foo.swift")
        #expect(finding.line == 42)
        #expect(finding.message == "Race condition")
    }

    @Test("Finding with optional fields nil")
    func findingOptionalNil() {
        let finding = PRReviewFinding(severity: .minor, reviewer: "@tech", message: "Spacing")
        #expect(finding.file == nil)
        #expect(finding.line == nil)
    }

    @Test("Severity raw values")
    func severityRawValues() {
        #expect(PRReviewFinding.Severity.critical.rawValue == "critical")
        #expect(PRReviewFinding.Severity.important.rawValue == "important")
        #expect(PRReviewFinding.Severity.minor.rawValue == "minor")
    }

    @Test("Finding is Equatable")
    func findingEquatable() {
        let a = PRReviewFinding(severity: .critical, reviewer: "@Sensei", message: "Bug")
        let b = PRReviewFinding(severity: .critical, reviewer: "@Sensei", message: "Bug")
        #expect(a == b)
    }
}

// MARK: - PRMetadata Tests

@Suite("PRMetadata")
struct PRMetadataTests {

    @Test("totalLines sums additions and deletions")
    func totalLines() {
        let meta = PRMetadata(
            number: 1, title: "Test", author: "user",
            branch: "feature/x", baseBranch: "develop",
            additions: 100, deletions: 50, changedFiles: 5, isDraft: false
        )
        #expect(meta.totalLines == 150)
    }

    @Test("sizeLabel format")
    func sizeLabel() {
        let meta = PRMetadata(
            number: 1, title: "Test", author: "user",
            branch: "feature/x", baseBranch: "develop",
            additions: 200, deletions: 30, changedFiles: 8, isDraft: false
        )
        #expect(meta.sizeLabel == "+200/-30 (8 files)")
    }

    @Test("Metadata is Equatable")
    func metadataEquatable() {
        let a = PRMetadata(
            number: 42, title: "Fix bug", author: "dev",
            branch: "fix/bug", baseBranch: "develop",
            additions: 10, deletions: 5, changedFiles: 2, isDraft: false
        )
        let b = PRMetadata(
            number: 42, title: "Fix bug", author: "dev",
            branch: "fix/bug", baseBranch: "develop",
            additions: 10, deletions: 5, changedFiles: 2, isDraft: false
        )
        #expect(a == b)
    }
}

// MARK: - ReviewPromptBuilder Tests

@Suite("ReviewPromptBuilder")
struct ReviewPromptBuilderTests {

    @Test("Build includes PR number and title")
    func includesPRNumberAndTitle() {
        let meta = PRMetadata(
            number: 42, title: "Add feature X", author: "dev",
            branch: "feature/x", baseBranch: "develop",
            additions: 100, deletions: 10, changedFiles: 3, isDraft: false
        )
        let prompt = ReviewPromptBuilder.build(metadata: meta)
        #expect(prompt.contains("PR #42"))
        #expect(prompt.contains("Add feature X"))
    }

    @Test("Build includes author")
    func includesAuthor() {
        let meta = PRMetadata(
            number: 1, title: "Test", author: "jeoffrey",
            branch: "fix/x", baseBranch: "develop",
            additions: 5, deletions: 2, changedFiles: 1, isDraft: false
        )
        let prompt = ReviewPromptBuilder.build(metadata: meta)
        #expect(prompt.contains("@jeoffrey"))
    }

    @Test("Build includes branch info")
    func includesBranchInfo() {
        let meta = PRMetadata(
            number: 1, title: "Test", author: "dev",
            branch: "feature/widgets", baseBranch: "develop",
            additions: 5, deletions: 2, changedFiles: 1, isDraft: false
        )
        let prompt = ReviewPromptBuilder.build(metadata: meta)
        #expect(prompt.contains("feature/widgets"))
        #expect(prompt.contains("develop"))
    }

    @Test("Build includes size label")
    func includesSizeLabel() {
        let meta = PRMetadata(
            number: 1, title: "Test", author: "dev",
            branch: "fix/x", baseBranch: "develop",
            additions: 200, deletions: 30, changedFiles: 8, isDraft: false
        )
        let prompt = ReviewPromptBuilder.build(metadata: meta)
        #expect(prompt.contains("+200/-30 (8 files)"))
    }

    @Test("Build includes DRAFT status when draft")
    func includesDraftStatus() {
        let meta = PRMetadata(
            number: 1, title: "WIP", author: "dev",
            branch: "feature/wip", baseBranch: "develop",
            additions: 5, deletions: 0, changedFiles: 1, isDraft: true
        )
        let prompt = ReviewPromptBuilder.build(metadata: meta)
        #expect(prompt.contains("DRAFT"))
    }

    @Test("Build excludes DRAFT when not draft")
    func excludesDraftWhenNot() {
        let meta = PRMetadata(
            number: 1, title: "Ready", author: "dev",
            branch: "feature/ready", baseBranch: "develop",
            additions: 5, deletions: 0, changedFiles: 1, isDraft: false
        )
        let prompt = ReviewPromptBuilder.build(metadata: meta)
        #expect(!prompt.contains("DRAFT"))
    }

    @Test("Build includes review instructions")
    func includesInstructions() {
        let meta = PRMetadata(
            number: 1, title: "Test", author: "dev",
            branch: "fix/x", baseBranch: "develop",
            additions: 5, deletions: 2, changedFiles: 1, isDraft: false
        )
        let prompt = ReviewPromptBuilder.build(metadata: meta)
        #expect(prompt.contains("Architecture compliance"))
        #expect(prompt.contains("Security concerns"))
        #expect(prompt.contains("CRITICAL"))
        #expect(prompt.contains("IMPORTANT"))
        #expect(prompt.contains("MINOR"))
    }
}

// MARK: - ReviewFindingsParser Tests

@Suite("ReviewFindingsParser")
struct ReviewFindingsParserTests {

    @Test("Parse critical finding with file and line")
    func parseCriticalWithFileLine() {
        let output = "[CRITICAL] [@Sensei] [Foo.swift:42] Race condition in async call"
        let findings = ReviewFindingsParser.parse(output)
        #expect(findings.count == 1)
        #expect(findings[0].severity == .critical)
        #expect(findings[0].reviewer == "@Sensei")
        #expect(findings[0].file == "Foo.swift")
        #expect(findings[0].line == 42)
        #expect(findings[0].message == "Race condition in async call")
    }

    @Test("Parse important finding without line number")
    func parseImportantWithoutLine() {
        // Note: regex uses \w+ for reviewer, so hyphenated names like @tech-expert
        // won't match. Only @word_chars are accepted.
        let output = "[IMPORTANT] [@tech_expert] [Bar.swift] Missing error handling"
        let findings = ReviewFindingsParser.parse(output)
        #expect(findings.count == 1)
        #expect(findings[0].severity == .important)
        #expect(findings[0].reviewer == "@tech_expert")
        #expect(findings[0].file == "Bar.swift")
        #expect(findings[0].line == nil)
    }

    @Test("Parse minor finding")
    func parseMinorFinding() {
        let output = "[MINOR] [@tech] [Utils.swift:10] Consider renaming variable"
        let findings = ReviewFindingsParser.parse(output)
        #expect(findings.count == 1)
        #expect(findings[0].severity == .minor)
    }

    @Test("Parse multiple findings from multiline output")
    func parseMultipleFindings() {
        let output = """
        Some preamble text
        [CRITICAL] [@Sensei] [A.swift:1] Issue one
        Some noise
        [IMPORTANT] [@tech] [B.swift:20] Issue two
        [MINOR] [@tech] [C.swift:30] Issue three
        Trailing text
        """
        let findings = ReviewFindingsParser.parse(output)
        #expect(findings.count == 3)
        #expect(findings[0].severity == .critical)
        #expect(findings[1].severity == .important)
        #expect(findings[2].severity == .minor)
    }

    @Test("Parse empty output returns no findings")
    func parseEmptyOutput() {
        let findings = ReviewFindingsParser.parse("")
        #expect(findings.isEmpty)
    }

    @Test("Parse output with no matching lines returns no findings")
    func parseNoMatchingLines() {
        let output = """
        This is just regular text.
        No findings here.
        All good!
        """
        let findings = ReviewFindingsParser.parse(output)
        #expect(findings.isEmpty)
    }

    @Test("Parse finding without file reference")
    func parseFindingWithoutFileRef() {
        let output = "[CRITICAL] [@Sensei] General architecture concern"
        let findings = ReviewFindingsParser.parse(output)
        #expect(findings.count == 1)
        #expect(findings[0].file == nil)
        #expect(findings[0].line == nil)
    }
}

// MARK: - PRRangeParser Tests

@Suite("PRRangeParser")
struct PRRangeParserTests {

    @Test("Parse simple range")
    func parseSimpleRange() throws {
        let result = try PRRangeParser.parse("14..18")
        #expect(result == [14, 15, 16, 17, 18])
    }

    @Test("Parse range with pr prefix")
    func parseWithPRPrefix() throws {
        let result = try PRRangeParser.parse("pr14..pr18")
        #expect(result == [14, 15, 16, 17, 18])
    }

    @Test("Parse range with PR prefix uppercase")
    func parseWithPRPrefixUppercase() throws {
        let result = try PRRangeParser.parse("PR14..PR18")
        #expect(result == [14, 15, 16, 17, 18])
    }

    @Test("Parse range with hash prefix")
    func parseWithHashPrefix() throws {
        let result = try PRRangeParser.parse("#14..#18")
        #expect(result == [14, 15, 16, 17, 18])
    }

    @Test("Parse single PR range")
    func parseSinglePRRange() throws {
        let result = try PRRangeParser.parse("42..42")
        #expect(result == [42])
    }

    @Test("Reversed range throws")
    func reversedRangeThrows() {
        #expect(throws: ReviewError.self) {
            try PRRangeParser.parse("18..14")
        }
    }

    @Test("Non-numeric range throws")
    func nonNumericThrows() {
        #expect(throws: ReviewError.self) {
            try PRRangeParser.parse("abc..def")
        }
    }

    @Test("Missing dots throws")
    func missingDotsThrows() {
        #expect(throws: ReviewError.self) {
            try PRRangeParser.parse("14-18")
        }
    }

    @Test("Negative PR numbers throw")
    func negativePRNumbersThrow() {
        #expect(throws: ReviewError.self) {
            try PRRangeParser.parse("-1..5")
        }
    }
}

// MARK: - ReviewProgress Tests

@Suite("ReviewProgress")
struct ReviewProgressTests {

    @Test("Initial progress is zero")
    func initialProgressZero() {
        let progress = ReviewProgress(prNumber: 42, totalFiles: 10)
        #expect(progress.progress == 0.0)
        #expect(!progress.isComplete)
        #expect(progress.filesReviewed.isEmpty)
    }

    @Test("Progress fraction calculates correctly")
    func progressFraction() {
        var progress = ReviewProgress(prNumber: 42, totalFiles: 4)
        progress.filesReviewed = ["A.swift", "B.swift"]
        #expect(progress.progress == 0.5)
        #expect(!progress.isComplete)
    }

    @Test("All files reviewed marks complete")
    func allFilesComplete() {
        var progress = ReviewProgress(prNumber: 42, totalFiles: 2)
        progress.filesReviewed = ["A.swift", "B.swift"]
        #expect(progress.isComplete)
        #expect(progress.progress == 1.0)
    }

    @Test("Zero total files returns zero progress")
    func zeroTotalFiles() {
        let progress = ReviewProgress(prNumber: 1, totalFiles: 0)
        #expect(progress.progress == 0.0)
    }

    @Test("More reviewed than total still marks complete")
    func moreReviewedThanTotal() {
        var progress = ReviewProgress(prNumber: 1, totalFiles: 2)
        progress.filesReviewed = ["A.swift", "B.swift", "C.swift"]
        #expect(progress.isComplete)
    }
}

// MARK: - ReviewPersistence Tests

@Suite("ReviewPersistence")
struct ReviewPersistenceTests {

    @Test("Save and load progress round-trips")
    func saveAndLoadProgress() throws {
        let tempDir = NSTemporaryDirectory() + "review-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let persistence = ReviewPersistence(baseDirectory: tempDir)
        var progress = ReviewProgress(prNumber: 42, totalFiles: 5)
        progress.filesReviewed = ["A.swift", "B.swift"]
        progress.findings = [
            PRReviewFinding(severity: .critical, reviewer: "@Sensei", message: "Bug"),
        ]

        try persistence.save(progress)
        let loaded = persistence.load(prNumber: 42)

        #expect(loaded != nil)
        #expect(loaded?.prNumber == 42)
        #expect(loaded?.totalFiles == 5)
        #expect(loaded?.filesReviewed.count == 2)
        #expect(loaded?.findings.count == 1)
    }

    @Test("Load returns nil for missing PR")
    func loadMissingReturnsNil() {
        let tempDir = NSTemporaryDirectory() + "review-test-\(UUID().uuidString)"
        let persistence = ReviewPersistence(baseDirectory: tempDir)
        let loaded = persistence.load(prNumber: 999)
        #expect(loaded == nil)
    }

    @Test("Save result creates result file")
    func saveResult() throws {
        let tempDir = NSTemporaryDirectory() + "review-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let persistence = ReviewPersistence(baseDirectory: tempDir)
        let result = PRReviewResult(
            prNumber: 42,
            findings: [
                PRReviewFinding(severity: .minor, reviewer: "@tech", message: "Style"),
            ],
            verdict: .approve,
            filesReviewed: 5,
            totalFiles: 5
        )

        try persistence.saveResult(result)

        let resultPath = "\(tempDir)/pr42/result.json"
        #expect(FileManager.default.fileExists(atPath: resultPath))

        // Verify the file is valid JSON
        let data = try Data(contentsOf: URL(fileURLWithPath: resultPath))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PRReviewResult.self, from: data)
        #expect(decoded.prNumber == 42)
        #expect(decoded.verdict == .approve)
        #expect(decoded.findings.count == 1)
    }

    @Test("Review directory path format")
    func reviewDirectoryPath() {
        let persistence = ReviewPersistence(baseDirectory: "/tmp/reviews")
        #expect(persistence.reviewDirectory(for: 42) == "/tmp/reviews/pr42")
        #expect(persistence.reviewDirectory(for: 1) == "/tmp/reviews/pr1")
    }

    @Test("Multiple PRs saved independently")
    func multiplePRsIndependent() throws {
        let tempDir = NSTemporaryDirectory() + "review-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let persistence = ReviewPersistence(baseDirectory: tempDir)

        let p1 = ReviewProgress(prNumber: 10, totalFiles: 3)
        let p2 = ReviewProgress(prNumber: 20, totalFiles: 7)
        try persistence.save(p1)
        try persistence.save(p2)

        let loaded1 = persistence.load(prNumber: 10)
        let loaded2 = persistence.load(prNumber: 20)
        #expect(loaded1?.prNumber == 10)
        #expect(loaded1?.totalFiles == 3)
        #expect(loaded2?.prNumber == 20)
        #expect(loaded2?.totalFiles == 7)
    }
}

// MARK: - ReviewError Tests

@Suite("ReviewError")
struct ReviewErrorTests {

    @Test("ReviewError cases are Equatable")
    func errorEquatable() {
        #expect(ReviewError.invalidPRNumber(0) == ReviewError.invalidPRNumber(0))
        #expect(ReviewError.ghNotAvailable == ReviewError.ghNotAvailable)
        #expect(ReviewError.prNotFound(42) == ReviewError.prNotFound(42))
    }
}

// MARK: - ReviewTarget Tests

@Suite("ReviewTarget")
struct ReviewTargetTests {

    @Test("Single target equality")
    func singleEquality() {
        #expect(ReviewTarget.single(42) == ReviewTarget.single(42))
        #expect(ReviewTarget.single(1) != ReviewTarget.single(2))
    }

    @Test("Batch target equality")
    func batchEquality() {
        #expect(ReviewTarget.batch([1, 2, 3]) == ReviewTarget.batch([1, 2, 3]))
    }

    @Test("PrePR target equality")
    func prePREquality() {
        #expect(ReviewTarget.prePR == ReviewTarget.prePR)
    }
}

// MARK: - ReviewVerdict Codable Tests

@Suite("ReviewVerdict Codable")
struct ReviewVerdictCodableTests {

    @Test("Verdict raw values are correct")
    func verdictRawValues() {
        #expect(ReviewVerdict.approve.rawValue == "APPROVE")
        #expect(ReviewVerdict.changesRequested.rawValue == "CHANGES_REQUESTED")
        #expect(ReviewVerdict.needsDiscussion.rawValue == "NEEDS_DISCUSSION")
    }

    @Test("Verdict round-trips through JSON")
    func verdictRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for verdict in [ReviewVerdict.approve, .changesRequested, .needsDiscussion] {
            let data = try encoder.encode(verdict)
            let decoded = try decoder.decode(ReviewVerdict.self, from: data)
            #expect(decoded == verdict)
        }
    }
}
