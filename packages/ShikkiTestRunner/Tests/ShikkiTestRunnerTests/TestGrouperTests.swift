import Foundation
import Testing

@testable import ShikkiTestRunner

@Suite("TestGrouper")
struct TestGrouperTests {

    // MARK: - Helpers

    private static let testManifest = ScopeManifest(
        scopes: [
            ScopeDefinition(
                name: "nats",
                modulePatterns: ["NATSClient"],
                typePatterns: ["EventBus", "NATSConnection"],
                testFilePatterns: ["**/NATS*Tests.swift"]
            ),
            ScopeDefinition(
                name: "kernel",
                modulePatterns: ["ShikkiKit"],
                typePatterns: ["ShikkiKernel", "ManagedService"],
                testFilePatterns: ["**/Kernel*Tests.swift"]
            ),
            ScopeDefinition(
                name: "tui",
                modulePatterns: ["TUI"],
                typePatterns: ["TerminalOutput"],
                testFilePatterns: []
            ),
        ],
        source: .defaultFallback
    )

    private var grouper: TestGrouper {
        TestGrouper(manifest: Self.testManifest)
    }

    // MARK: - Grouping

    @Test("Group files into correct scopes")
    func groupFilesIntoScopes() {
        let files: [(path: String, content: String)] = [
            ("Tests/NATSConnectionTests.swift", "import NATSClient\nclass Tests {}"),
            ("Tests/NATSEventTests.swift", "@testable import NATSClient\nclass Tests {}"),
            ("Tests/KernelBootTests.swift", "import ShikkiKit\nclass Tests {}"),
            ("Tests/TUIRenderTests.swift", "import TUI\nclass Tests {}"),
        ]

        let groups = grouper.group(files: files)

        let nats = groups.first { $0.scopeName == "nats" }
        let kernel = groups.first { $0.scopeName == "kernel" }
        let tui = groups.first { $0.scopeName == "tui" }

        #expect(nats != nil)
        #expect(nats?.files.count == 2)
        #expect(kernel != nil)
        #expect(kernel?.files.count == 1)
        #expect(tui != nil)
        #expect(tui?.files.count == 1)
    }

    @Test("Unscoped files collected in safety net group")
    func unscopedSafetyNet() {
        let files: [(path: String, content: String)] = [
            ("Tests/NATSTests.swift", "import NATSClient"),
            ("Tests/UtilityTests.swift", "import Foundation"),
            ("Tests/HelperTests.swift", "import Testing\nlet x = 1"),
        ]

        let groups = grouper.group(files: files)
        let unscoped = groups.first { $0.scopeName == "unscoped" }

        #expect(unscoped != nil)
        #expect(unscoped?.files.count == 2)
        #expect(unscoped?.files.contains("Tests/UtilityTests.swift") == true)
        #expect(unscoped?.files.contains("Tests/HelperTests.swift") == true)
    }

    @Test("No unscoped group when all files are covered")
    func noUnscopedWhenFullCoverage() {
        let files: [(path: String, content: String)] = [
            ("Tests/NATSTests.swift", "import NATSClient"),
            ("Tests/KernelTests.swift", "import ShikkiKit"),
        ]

        let groups = grouper.group(files: files)
        let unscoped = groups.first { $0.scopeName == "unscoped" }

        #expect(unscoped == nil)
    }

    @Test("Empty file list produces no groups")
    func emptyFileListNoGroups() {
        let groups = grouper.group(files: [])
        #expect(groups.isEmpty)
    }

    @Test("Groups preserve manifest scope order")
    func groupsPreserveOrder() {
        let files: [(path: String, content: String)] = [
            ("Tests/TUITests.swift", "import TUI"),
            ("Tests/NATSTests.swift", "import NATSClient"),
            ("Tests/KernelTests.swift", "import ShikkiKit"),
        ]

        let groups = grouper.group(files: files)
        // Manifest order: nats, kernel, tui
        #expect(groups[0].scopeName == "nats")
        #expect(groups[1].scopeName == "kernel")
        #expect(groups[2].scopeName == "tui")
    }

    @Test("Dependencies populated from manifest patterns")
    func dependenciesPopulated() {
        let files: [(path: String, content: String)] = [
            ("Tests/NATSTests.swift", "import NATSClient\nlet bus = EventBus()"),
        ]

        let groups = grouper.group(files: files)
        let nats = groups.first { $0.scopeName == "nats" }

        #expect(nats != nil)
        #expect(nats!.dependencies.contains("NATSClient"))
        #expect(nats!.dependencies.contains("EventBus"))
    }

    // MARK: - Verification

    @Test("Verification passes when all files scoped")
    func verificationPassesAllScoped() {
        let files: [(path: String, content: String)] = [
            ("Tests/NATSTests.swift", "import NATSClient"),
            ("Tests/KernelTests.swift", "import ShikkiKit"),
        ]

        let result = grouper.verify(files: files)

        #expect(result.isComplete)
        #expect(result.unscopedFiles.isEmpty)
        #expect(result.duplicateFiles.isEmpty)
        #expect(result.totalFiles == 2)
        #expect(result.activeScopeCount == 2)
    }

    @Test("Verification detects unscoped files")
    func verificationDetectsUnscoped() {
        let files: [(path: String, content: String)] = [
            ("Tests/NATSTests.swift", "import NATSClient"),
            ("Tests/RandomTests.swift", "import Foundation"),
        ]

        let result = grouper.verify(files: files)

        #expect(!result.isComplete)
        #expect(result.unscopedFiles == ["Tests/RandomTests.swift"])
        #expect(result.totalFiles == 2)
        #expect(result.activeScopeCount == 1)
    }

    // MARK: - Scope Listing

    @Test("List scopes from manifest only (no files)")
    func listScopesManifestOnly() {
        let listings = grouper.listScopes()

        #expect(listings.count == 3)
        #expect(listings[0].scopeName == "nats")
        #expect(listings[1].scopeName == "kernel")
        #expect(listings[2].scopeName == "tui")
        // No file analysis, so counts are zero
        #expect(listings[0].fileCount == 0)
    }

    @Test("List scopes with file analysis")
    func listScopesWithFiles() {
        let files: [(path: String, content: String)] = [
            ("Tests/NATSTests.swift", "import NATSClient"),
            ("Tests/NATSEventTests.swift", "import NATSClient"),
            ("Tests/KernelTests.swift", "import ShikkiKit"),
        ]

        let listings = grouper.listScopes(files: files)
        let nats = listings.first { $0.scopeName == "nats" }
        let kernel = listings.first { $0.scopeName == "kernel" }

        #expect(nats?.fileCount == 2)
        #expect(kernel?.fileCount == 1)
    }

    // MARK: - Scope Filtering

    @Test("Filter groups to specific scopes")
    func filterToSpecificScopes() {
        let files: [(path: String, content: String)] = [
            ("Tests/NATSTests.swift", "import NATSClient"),
            ("Tests/KernelTests.swift", "import ShikkiKit"),
            ("Tests/TUITests.swift", "import TUI"),
        ]

        let allGroups = grouper.group(files: files)
        let filtered = grouper.filterScopes(
            groups: allGroups,
            scopeNames: ["nats", "tui"]
        )

        #expect(filtered.count == 2)
        #expect(filtered.map(\.scopeName).contains("nats"))
        #expect(filtered.map(\.scopeName).contains("tui"))
        #expect(!filtered.map(\.scopeName).contains("kernel"))
    }

    @Test("Filter with empty scope names returns nothing")
    func filterEmptyReturnsNothing() {
        let groups = [
            TestGroup(scopeName: "nats", files: ["a.swift"], dependencies: [])
        ]
        let filtered = grouper.filterScopes(groups: groups, scopeNames: [])
        #expect(filtered.isEmpty)
    }

    // MARK: - Test Count Estimation

    @Test("Count XCTest functions")
    func countXCTestFunctions() {
        let content = """
            class MyTests: XCTestCase {
                func testFirst() { }
                func testSecond() { }
                func testThird() { }
                func helperMethod() { }
            }
            """
        let count = TestGrouper.countTestFunctions(in: content)
        #expect(count == 3)
    }

    @Test("Count Swift Testing @Test functions")
    func countSwiftTestingFunctions() {
        let content = """
            @Suite struct MyTests {
                @Test func someBehavior() { }
                @Test "named test" { }
                func helper() { }
            }
            """
        let count = TestGrouper.countTestFunctions(in: content)
        #expect(count == 2)
    }

    @Test("Count mixed XCTest and Swift Testing functions")
    func countMixedTestFunctions() {
        let content = """
            class Legacy: XCTestCase {
                func testOldStyle() { }
            }
            @Suite struct Modern {
                @Test func newStyle() { }
            }
            """
        let count = TestGrouper.countTestFunctions(in: content)
        #expect(count == 2)
    }

    @Test("Empty file has zero test functions")
    func emptyFileZeroTests() {
        #expect(TestGrouper.countTestFunctions(in: "") == 0)
    }
}
