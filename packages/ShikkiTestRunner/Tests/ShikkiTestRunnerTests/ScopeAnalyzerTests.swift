import Foundation
import Testing

@testable import ShikkiTestRunner

@Suite("ScopeAnalyzer")
struct ScopeAnalyzerTests {

    // MARK: - Helpers

    private static let testManifest = ScopeManifest(
        scopes: [
            ScopeDefinition(
                name: "nats",
                modulePatterns: ["NATSClient", "NATSProtocol"],
                typePatterns: ["NATSConnection", "EventBus", "EventRouter"],
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
                typePatterns: ["TerminalOutput", "ANSIRenderer"],
                testFilePatterns: []
            ),
        ],
        source: .defaultFallback
    )

    private var analyzer: ScopeAnalyzer {
        ScopeAnalyzer(manifest: Self.testManifest)
    }

    // MARK: - Import Parsing

    @Test("Parse simple import statement")
    func parseSimpleImport() {
        let content = """
            import Foundation
            import NATSClient
            """
        let imports = analyzer.parseImports(from: content)
        #expect(imports == ["Foundation", "NATSClient"])
    }

    @Test("Parse @testable import")
    func parseTestableImport() {
        let content = """
            @testable import ShikkiKit
            import Foundation
            """
        let imports = analyzer.parseImports(from: content)
        #expect(imports == ["Foundation", "ShikkiKit"])
    }

    @Test("Parse import with submodule syntax")
    func parseSubmoduleImport() {
        let content = """
            import struct NATSClient.Connection
            import class Foundation.JSONDecoder
            """
        let imports = analyzer.parseImports(from: content)
        #expect(imports == ["Foundation", "NATSClient"])
    }

    @Test("Ignore non-import lines")
    func ignoreNonImportLines() {
        let content = """
            // import FakeModule
            let x = "import NotReal"
            import RealModule
            """
        let imports = analyzer.parseImports(from: content)
        #expect(imports == ["RealModule"])
    }

    @Test("Empty file produces no imports")
    func emptyFileNoImports() {
        let imports = analyzer.parseImports(from: "")
        #expect(imports.isEmpty)
    }

    @Test("Deduplicate repeated imports")
    func deduplicateImports() {
        let content = """
            import Foundation
            import Foundation
            """
        let imports = analyzer.parseImports(from: content)
        #expect(imports == ["Foundation"])
    }

    // MARK: - Type Reference Parsing

    @Test("Parse PascalCase type references")
    func parsePascalCaseTypes() {
        let content = """
            let bus = EventBus()
            let kernel = ShikkiKernel.shared
            """
        let types = analyzer.parseTypeReferences(from: content)
        #expect(types.contains("EventBus"))
        #expect(types.contains("ShikkiKernel"))
    }

    @Test("Exclude well-known Swift types")
    func excludeStandardTypes() {
        let content = """
            let s: String = ""
            let i: Int = 0
            let d: Data = Data()
            let custom = EventBus()
            """
        let types = analyzer.parseTypeReferences(from: content)
        #expect(!types.contains("String"))
        #expect(!types.contains("Int"))
        #expect(!types.contains("Data"))
        #expect(types.contains("EventBus"))
    }

    @Test("Exclude XCTest types")
    func excludeTestTypes() {
        let content = """
            class MyTests: XCTestCase {
                func testSomething() {
                    XCTAssertEqual(1, 1)
                    let router = EventRouter()
                }
            }
            """
        let types = analyzer.parseTypeReferences(from: content)
        #expect(!types.contains("XCTestCase"))
        #expect(!types.contains("XCTAssertEqual"))
        #expect(types.contains("EventRouter"))
        #expect(types.contains("MyTests"))
    }

    // MARK: - Scope Assignment

    @Test("Assign by file pattern match")
    func assignByFilePattern() {
        let result = analyzer.analyze(
            filePath: "Tests/ShikkiKitTests/NATSConnectionTests.swift",
            content: "import Foundation\nclass NATSConnectionTests {}"
        )

        #expect(result.scopeName == "nats")
        if case .filePatternMatch = result.matchReason {
            // Expected
        } else {
            Issue.record("Expected filePatternMatch, got \(result.matchReason)")
        }
    }

    @Test("Assign by import match")
    func assignByImportMatch() {
        let result = analyzer.analyze(
            filePath: "Tests/SomeTests/CustomEventTests.swift",
            content: """
                @testable import NATSClient
                import Testing

                struct CustomEventTests {}
                """
        )

        #expect(result.scopeName == "nats")
        if case .importMatch(let module) = result.matchReason {
            #expect(module == "NATSClient")
        } else {
            Issue.record("Expected importMatch, got \(result.matchReason)")
        }
    }

    @Test("Assign by type reference match")
    func assignByTypeMatch() {
        let result = analyzer.analyze(
            filePath: "Tests/SomeTests/RandomTests.swift",
            content: """
                import Testing

                struct RandomTests {
                    func testBus() {
                        let bus = EventBus()
                    }
                }
                """
        )

        #expect(result.scopeName == "nats")
        if case .typeMatch(let type) = result.matchReason {
            #expect(type == "EventBus")
        } else {
            Issue.record("Expected typeMatch, got \(result.matchReason)")
        }
    }

    @Test("Unscoped when no match found")
    func unscopedWhenNoMatch() {
        let result = analyzer.analyze(
            filePath: "Tests/SomeTests/UtilityTests.swift",
            content: """
                import Testing

                struct UtilityTests {
                    func testHelper() {
                        let x = 42
                    }
                }
                """
        )

        #expect(result.scopeName == nil)
        #expect(result.matchReason == .unscoped)
    }

    @Test("File pattern takes priority over import match")
    func filePatternPriorityOverImport() {
        // File matches "kernel" by pattern but imports NATSClient
        let result = analyzer.analyze(
            filePath: "Tests/ShikkiKitTests/KernelNATSTests.swift",
            content: """
                @testable import NATSClient
                import Testing

                struct KernelNATSTests {}
                """
        )

        // File pattern for kernel matches **/Kernel*Tests.swift
        #expect(result.scopeName == "kernel")
        if case .filePatternMatch = result.matchReason {
            // Expected: file pattern wins over import
        } else {
            Issue.record("Expected filePatternMatch, got \(result.matchReason)")
        }
    }

    @Test("Analyze multiple files returns one assignment per file")
    func analyzeMultipleFiles() {
        let files: [(path: String, content: String)] = [
            ("Tests/NATSTests.swift", "import NATSClient"),
            ("Tests/KernelTests.swift", "import ShikkiKit"),
            ("Tests/RandomTests.swift", "import Testing"),
        ]

        let assignments = analyzer.analyzeAll(files: files)
        #expect(assignments.count == 3)
        #expect(assignments[0].scopeName == "nats")
        #expect(assignments[1].scopeName == "kernel")
        #expect(assignments[2].scopeName == nil)
    }

    @Test("Matched types populated in assignment")
    func matchedTypesPopulated() {
        let result = analyzer.analyze(
            filePath: "Tests/EventTests.swift",
            content: """
                import NATSClient
                let bus = EventBus()
                let router = EventRouter()
                let conn = NATSConnection()
                """
        )

        #expect(result.scopeName == "nats")
        #expect(result.matchedTypes.contains("EventBus"))
        #expect(result.matchedTypes.contains("EventRouter"))
        #expect(result.matchedTypes.contains("NATSConnection"))
    }
}
