import Foundation
import Testing
@testable import ShikkiKit

@Suite("ProjectAnalyzer")
struct ProjectAnalyzerTests {

    let analyzer = ProjectAnalyzer()

    // MARK: - Package.swift Parsing

    @Test("Parse Package.swift extracts package name")
    func parsePackageName() {
        let content = """
        let package = Package(
            name: "MyApp",
            platforms: [.macOS(.v14)],
        """
        let name = analyzer.parsePackageName(content)
        #expect(name == "MyApp")
    }

    @Test("Parse Package.swift extracts platforms")
    func parsePlatforms() {
        let content = """
        platforms: [.macOS(.v14), .iOS(.v17)],
        """
        let platforms = analyzer.parsePlatforms(content)
        #expect(platforms.contains("macOS 14"))
        #expect(platforms.contains("iOS 17"))
    }

    @Test("Parse Package.swift extracts remote dependencies")
    func parseRemoteDependencies() {
        let content = """
        dependencies: [
            .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
            .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
        ],
        """
        let deps = analyzer.parseDependencies(content)
        #expect(deps.count == 2)
        #expect(deps[0].name == "swift-argument-parser")
        #expect(deps[0].isLocal == false)
        #expect(deps[0].url == "https://github.com/apple/swift-argument-parser.git")
        #expect(deps[1].name == "swift-log")
    }

    @Test("Parse Package.swift extracts local dependencies")
    func parseLocalDependencies() {
        let content = """
        dependencies: [
            .package(path: "../packages/CoreKit"),
        ],
        """
        let deps = analyzer.parseDependencies(content)
        #expect(deps.count == 1)
        #expect(deps[0].name == "CoreKit")
        #expect(deps[0].isLocal == true)
        #expect(deps[0].path == "../packages/CoreKit")
    }

    // MARK: - Protocol Discovery

    @Test("Discover protocols in Swift files")
    func discoverProtocols() {
        let content = """
        import Foundation

        public protocol BackendClientProtocol: Sendable {
            func healthCheck() async throws -> Bool
            func getStatus() async throws -> OrchestratorStatus
        }

        protocol InternalProtocol {
            func doWork() async
        }
        """
        let protocols = analyzer.parseProtocols(content, file: "Protocols/Test.swift", module: "ShikkiKit")
        #expect(protocols.count == 2)
        #expect(protocols[0].name == "BackendClientProtocol")
        #expect(protocols[0].methods.count == 2)
        #expect(protocols[0].module == "ShikkiKit")
        #expect(protocols[1].name == "InternalProtocol")
        #expect(protocols[1].methods.count == 1)
    }

    @Test("Protocol methods include async throws signatures")
    func protocolMethodSignatures() {
        let content = """
        public protocol MyService: Sendable {
            func fetch(id: String) async throws -> Data
            func save(item: Item) async throws
        }
        """
        let protocols = analyzer.parseProtocols(content, file: "test.swift", module: "App")
        #expect(protocols.count == 1)
        #expect(protocols[0].methods.count == 2)
        #expect(protocols[0].methods[0].contains("fetch"))
        #expect(protocols[0].methods[1].contains("save"))
    }

    // MARK: - Type Discovery

    @Test("Discover structs")
    func discoverStructs() {
        let content = """
        public struct Company: Codable, Sendable {
            public let id: String
            public let name: String
        }
        """
        let types = analyzer.parseTypes(content, file: "Models/Company.swift", module: "ShikkiKit")
        #expect(types.count == 1)
        #expect(types[0].name == "Company")
        #expect(types[0].kind == .struct)
        #expect(types[0].isPublic == true)
        #expect(types[0].conformances.contains("Codable"))
        #expect(types[0].conformances.contains("Sendable"))
    }

    @Test("Discover classes")
    func discoverClasses() {
        let content = """
        final class MockBackendClient: BackendClientProtocol, @unchecked Sendable {
            var shouldThrow: Error?
        }
        """
        let types = analyzer.parseTypes(content, file: "Mocks/Mock.swift", module: "Tests")
        #expect(types.count == 1)
        #expect(types[0].name == "MockBackendClient")
        #expect(types[0].kind == .class)
        #expect(types[0].isPublic == false)
    }

    @Test("Discover enums")
    func discoverEnums() {
        let content = """
        public enum TargetType: String, Sendable, Codable {
            case library
            case executable
            case test
        }
        """
        let types = analyzer.parseTypes(content, file: "Models/TargetType.swift", module: "ShikkiKit")
        #expect(types.count == 1)
        #expect(types[0].name == "TargetType")
        #expect(types[0].kind == .enum)
    }

    @Test("Discover actors")
    func discoverActors() {
        let content = """
        public actor SessionManager {
            var sessions: [String: Session] = [:]
        }
        """
        let types = analyzer.parseTypes(content, file: "Services/Session.swift", module: "ShikkiKit")
        #expect(types.count == 1)
        #expect(types[0].name == "SessionManager")
        #expect(types[0].kind == .actor)
    }

    // MARK: - Dependency Graph

    @Test("Build dependency graph from imports")
    func buildDependencyGraph() {
        let content = """
        import Foundation
        import ShikkiKit
        import Logging
        """
        let imports = analyzer.parseImports(content)
        #expect(imports.count == 3)
        #expect(imports.contains("Foundation"))
        #expect(imports.contains("ShikkiKit"))
        #expect(imports.contains("Logging"))
    }

    // MARK: - Pattern Detection

    @Test("Detect error pattern")
    func detectErrorPattern() {
        let content = """
        public enum CacheStoreError: Error, LocalizedError, Sendable {
            case encodingFailed
            case decodingFailed(String)

            public var errorDescription: String? {
                switch self {
                case .encodingFailed: return "Failed"
                case .decodingFailed(let d): return d
                }
            }
        }
        """
        let example = analyzer.extractErrorExample(content)
        #expect(example != nil)
        #expect(example?.contains("CacheStoreError") == true)
    }

    @Test("Detect mock pattern")
    func detectMockPattern() {
        let content = """
        final class MockBackendClient: BackendClientProtocol, @unchecked Sendable {
            var shouldThrow: Error?
            var healthCheckCallCount = 0
        }
        """
        let example = analyzer.extractMockExample(content)
        #expect(example != nil)
        #expect(example?.contains("MockBackendClient") == true)
    }

    // MARK: - Test Info

    @Test("Count Swift Testing @Test annotations")
    func countSwiftTestingTests() {
        let content = """
        @Suite("My Tests")
        struct MyTests {
            @Test("First test")
            func firstTest() { }

            @Test("Second test")
            func secondTest() { }
        }
        """
        let count = analyzer.countTests(content)
        #expect(count == 2)
    }

    @Test("Count XCTest test methods")
    func countXCTestMethods() {
        let content = """
        class MyTests: XCTestCase {
            func testFirst() { }
            func testSecond() { }
            func helperMethod() { }
        }
        """
        let count = analyzer.countTests(content)
        #expect(count == 2)
    }

    // MARK: - Edge Cases

    @Test("Handle missing Package.swift gracefully")
    func missingPackageSwift() {
        let info = analyzer.parsePackageSwift(at: "/nonexistent/path")
        #expect(info.name == "")
        #expect(info.targets.isEmpty)
        #expect(info.dependencies.isEmpty)
    }

    @Test("Relativize paths correctly")
    func relativizePaths() {
        let relative = analyzer.relativize("/Users/test/project/Sources/App.swift", from: "/Users/test/project")
        #expect(relative == "Sources/App.swift")
    }

    @Test("Infer module from path")
    func inferModule() {
        let targets = [
            TargetInfo(name: "ShikkiKit", type: .library, path: "Sources/ShikkiKit"),
            TargetInfo(name: "ShikkiKitTests", type: .test, path: "Tests/ShikkiKitTests"),
        ]
        let module = analyzer.inferModule(relativePath: "Sources/ShikkiKit/Models/Company.swift", targets: targets)
        #expect(module == "ShikkiKit")

        let testModule = analyzer.inferModule(relativePath: "Tests/ShikkiKitTests/SomeTest.swift", targets: targets)
        #expect(testModule == "ShikkiKitTests")
    }

    // MARK: - Fields Extraction

    @Test("Extract fields from struct")
    func extractFields() {
        let content = """
        public struct Company: Codable {
            public let id: String
            public let name: String
            public var status: Status
            private var internalFlag: Bool
        }
        """
        let fields = analyzer.extractFields(content, typeName: "Company")
        #expect(fields.contains("id"))
        #expect(fields.contains("name"))
        #expect(fields.contains("status"))
        #expect(fields.contains("internalFlag"))
    }
}
