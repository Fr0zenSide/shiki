import Testing
@testable import ShikiCtlKit

@Suite("PRRiskEngine")
struct PRRiskEngineTests {

    @Test("Large file with no test counterpart is HIGH risk")
    func largeUntested() {
        let file = PRFileEntry(
            path: "Sources/Services/NewService.swift",
            insertions: 200,
            deletions: 0,
            isNew: true,
            category: .source
        )
        let allFiles = [file]
        let risk = PRRiskEngine.assess(file: file, allFiles: allFiles)
        #expect(risk == .high)
    }

    @Test("Test file is always LOW risk")
    func testFileIsLow() {
        let file = PRFileEntry(
            path: "Tests/SomeTests.swift",
            insertions: 50,
            deletions: 10,
            isNew: false,
            category: .test
        )
        let risk = PRRiskEngine.assess(file: file, allFiles: [file])
        #expect(risk == .low)
    }

    @Test("Docs/config files are SKIP")
    func docsAreSkip() {
        let file = PRFileEntry(
            path: "README.md",
            insertions: 5,
            deletions: 3,
            isNew: false,
            category: .docs
        )
        let risk = PRRiskEngine.assess(file: file, allFiles: [file])
        #expect(risk == .skip)
    }

    @Test("Source file with matching test is MEDIUM not HIGH")
    func testedSourceIsMedium() {
        let source = PRFileEntry(
            path: "Sources/Services/ProcessCleanup.swift",
            insertions: 50,
            deletions: 10,
            isNew: false,
            category: .source
        )
        let test = PRFileEntry(
            path: "Tests/ProcessCleanupTests.swift",
            insertions: 30,
            deletions: 0,
            isNew: true,
            category: .test
        )
        let risk = PRRiskEngine.assess(file: source, allFiles: [source, test])
        #expect(risk == .medium || risk == .low)
    }

    @Test("Small change to existing file is LOW")
    func smallChangeIsLow() {
        let file = PRFileEntry(
            path: "Sources/Models/Company.swift",
            insertions: 3,
            deletions: 1,
            isNew: false,
            category: .source
        )
        let test = PRFileEntry(
            path: "Tests/CompanyTests.swift",
            insertions: 5,
            deletions: 0,
            isNew: false,
            category: .test
        )
        let risk = PRRiskEngine.assess(file: file, allFiles: [file, test])
        #expect(risk == .low)
    }

    @Test("Batch assessment returns sorted by risk descending")
    func batchSorted() {
        let files = [
            PRFileEntry(path: "README.md", insertions: 1, deletions: 1, isNew: false, category: .docs),
            PRFileEntry(path: "Sources/Big.swift", insertions: 300, deletions: 0, isNew: true, category: .source),
            PRFileEntry(path: "Sources/Small.swift", insertions: 5, deletions: 2, isNew: false, category: .source),
        ]
        let assessed = PRRiskEngine.assessAll(files: files)
        // High risk should come first
        #expect(assessed.first?.file.path == "Sources/Big.swift")
    }

    @Test("Config files are SKIP")
    func configIsSkip() {
        let file = PRFileEntry(
            path: "Package.swift",
            insertions: 2,
            deletions: 1,
            isNew: false,
            category: .config
        )
        let risk = PRRiskEngine.assess(file: file, allFiles: [file])
        #expect(risk == .skip)
    }
}
