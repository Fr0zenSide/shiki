import Foundation
import Testing
@testable import ShikkiKit

@Suite("MotoCacheBuilder")
struct MotoCacheBuilderTests {

    let builder = MotoCacheBuilder(builderId: "test@1.0")

    // MARK: - Build

    @Test("builds all cache files from ArchitectureCache")
    func buildComplete() throws {
        let cache = makeTestCache()
        let tmpDir = makeTmpDir("build-complete")
        defer { cleanup(tmpDir) }

        let manifest = try builder.build(from: cache, outputPath: tmpDir.path, branch: "main")

        // Verify all files exist
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: tmpDir.appendingPathComponent("manifest.json").path))
        #expect(fm.fileExists(atPath: tmpDir.appendingPathComponent("package.json").path))
        #expect(fm.fileExists(atPath: tmpDir.appendingPathComponent("protocols.json").path))
        #expect(fm.fileExists(atPath: tmpDir.appendingPathComponent("types.json").path))
        #expect(fm.fileExists(atPath: tmpDir.appendingPathComponent("dependencies.json").path))
        #expect(fm.fileExists(atPath: tmpDir.appendingPathComponent("patterns.json").path))
        #expect(fm.fileExists(atPath: tmpDir.appendingPathComponent("tests.json").path))
        #expect(fm.fileExists(atPath: tmpDir.appendingPathComponent("api-surface.json").path))

        // Verify manifest
        #expect(manifest.schemaVersion == 1)
        #expect(manifest.project == "TestProject")
        #expect(manifest.language == "swift")
        #expect(manifest.gitCommit == "abc123def456")
        #expect(manifest.gitBranch == "main")
        #expect(manifest.builder == "test@1.0")
    }

    @Test("manifest contains correct stats")
    func manifestStats() throws {
        let cache = makeTestCache()
        let tmpDir = makeTmpDir("manifest-stats")
        defer { cleanup(tmpDir) }

        let manifest = try builder.build(from: cache, outputPath: tmpDir.path)

        #expect(manifest.stats.protocols == 2)
        #expect(manifest.stats.types == 3)
        #expect(manifest.stats.testCount == 15)
        #expect(manifest.stats.sourceFiles == 8)
        #expect(manifest.stats.totalCacheTokens > 0)
    }

    @Test("manifest file references have non-empty SHA-256 hashes")
    func manifestChecksums() throws {
        let cache = makeTestCache()
        let tmpDir = makeTmpDir("checksums")
        defer { cleanup(tmpDir) }

        let manifest = try builder.build(from: cache, outputPath: tmpDir.path)

        #expect(manifest.files.package?.sha256.isEmpty == false)
        #expect(manifest.files.protocols?.sha256.isEmpty == false)
        #expect(manifest.files.types?.sha256.isEmpty == false)
        #expect(manifest.files.dependencies?.sha256.isEmpty == false)
        #expect(manifest.files.patterns?.sha256.isEmpty == false)
        #expect(manifest.files.tests?.sha256.isEmpty == false)
        #expect(manifest.files.apiSurface?.sha256.isEmpty == false)
    }

    @Test("checksums are valid SHA-256 hex strings (64 chars)")
    func checksumFormat() throws {
        let cache = makeTestCache()
        let tmpDir = makeTmpDir("checksum-format")
        defer { cleanup(tmpDir) }

        let manifest = try builder.build(from: cache, outputPath: tmpDir.path)

        let hexPattern = try Regex("^[0-9a-f]{64}$")
        #expect(manifest.files.package?.sha256.contains(hexPattern) == true)
        #expect(manifest.files.protocols?.sha256.contains(hexPattern) == true)
        #expect(manifest.files.types?.sha256.contains(hexPattern) == true)
    }

    @Test("git tag is included when provided")
    func gitTagIncluded() throws {
        let cache = makeTestCache()
        let tmpDir = makeTmpDir("git-tag")
        defer { cleanup(tmpDir) }

        let manifest = try builder.build(from: cache, outputPath: tmpDir.path, branch: "main", tag: "v1.0.0")
        #expect(manifest.gitTag == "v1.0.0")
    }

    @Test("git tag is nil when not provided")
    func gitTagOmitted() throws {
        let cache = makeTestCache()
        let tmpDir = makeTmpDir("no-tag")
        defer { cleanup(tmpDir) }

        let manifest = try builder.build(from: cache, outputPath: tmpDir.path)
        #expect(manifest.gitTag == nil)
    }

    @Test("creates output directory if it does not exist")
    func createsDirectory() throws {
        let cache = makeTestCache()
        let tmpDir = makeTmpDir("create-dir")
        let nested = tmpDir.appendingPathComponent("nested/deep")
        defer { cleanup(tmpDir) }

        let manifest = try builder.build(from: cache, outputPath: nested.path)
        #expect(manifest.project == "TestProject")
        #expect(FileManager.default.fileExists(atPath: nested.appendingPathComponent("manifest.json").path))
    }

    // MARK: - JSON Validity

    @Test("package.json is valid JSON matching PackageInfo")
    func packageJsonValid() throws {
        let cache = makeTestCache()
        let tmpDir = makeTmpDir("pkg-json")
        defer { cleanup(tmpDir) }

        try builder.build(from: cache, outputPath: tmpDir.path)

        let data = try Data(contentsOf: tmpDir.appendingPathComponent("package.json"))
        let decoded = try JSONDecoder().decode(PackageInfo.self, from: data)
        #expect(decoded.name == "TestPackage")
        #expect(decoded.targets.count == 2)
    }

    @Test("protocols.json is valid JSON matching [ProtocolDescriptor]")
    func protocolsJsonValid() throws {
        let cache = makeTestCache()
        let tmpDir = makeTmpDir("proto-json")
        defer { cleanup(tmpDir) }

        try builder.build(from: cache, outputPath: tmpDir.path)

        let data = try Data(contentsOf: tmpDir.appendingPathComponent("protocols.json"))
        let decoded = try JSONDecoder().decode([ProtocolDescriptor].self, from: data)
        #expect(decoded.count == 2)
        #expect(decoded[0].name == "Renderable")
    }

    @Test("types.json is valid JSON matching [TypeDescriptor]")
    func typesJsonValid() throws {
        let cache = makeTestCache()
        let tmpDir = makeTmpDir("types-json")
        defer { cleanup(tmpDir) }

        try builder.build(from: cache, outputPath: tmpDir.path)

        let data = try Data(contentsOf: tmpDir.appendingPathComponent("types.json"))
        let decoded = try JSONDecoder().decode([TypeDescriptor].self, from: data)
        #expect(decoded.count == 3)
    }

    @Test("dependencies.json is valid JSON matching [String: [String]]")
    func dependenciesJsonValid() throws {
        let cache = makeTestCache()
        let tmpDir = makeTmpDir("deps-json")
        defer { cleanup(tmpDir) }

        try builder.build(from: cache, outputPath: tmpDir.path)

        let data = try Data(contentsOf: tmpDir.appendingPathComponent("dependencies.json"))
        let decoded = try JSONDecoder().decode([String: [String]].self, from: data)
        #expect(decoded["AppModule"]?.contains("Foundation") == true)
    }

    @Test("manifest.json is valid JSON matching MotoCacheManifest")
    func manifestJsonValid() throws {
        let cache = makeTestCache()
        let tmpDir = makeTmpDir("manifest-json")
        defer { cleanup(tmpDir) }

        try builder.build(from: cache, outputPath: tmpDir.path)

        let data = try Data(contentsOf: tmpDir.appendingPathComponent("manifest.json"))
        let decoded = try JSONDecoder().decode(MotoCacheManifest.self, from: data)
        #expect(decoded.schemaVersion == 1)
        #expect(decoded.project == "TestProject")
    }

    // MARK: - API Surface Extraction

    @Test("extracts public types into API surface")
    func apiSurfaceExtraction() throws {
        let cache = makeTestCache()
        let tmpDir = makeTmpDir("api-surface")
        defer { cleanup(tmpDir) }

        try builder.build(from: cache, outputPath: tmpDir.path)

        let data = try Data(contentsOf: tmpDir.appendingPathComponent("api-surface.json"))
        let decoded = try JSONDecoder().decode(APISurface.self, from: data)
        #expect(!decoded.modules.isEmpty)
    }

    @Test("only public types appear in API surface")
    func apiSurfacePublicOnly() {
        let cache = ArchitectureCache(
            projectId: "test",
            projectPath: "/tmp/test",
            gitHash: "abc123",
            builtAt: Date(),
            packageInfo: PackageInfo(name: "test"),
            protocols: [],
            types: [
                TypeDescriptor(name: "PublicType", kind: .struct, module: "Mod", isPublic: true),
                TypeDescriptor(name: "PrivateType", kind: .struct, module: "Mod", isPublic: false),
            ],
            dependencyGraph: [:],
            patterns: [],
            testInfo: TestInfo()
        )

        let surface = builder.extractAPISurface(from: cache)
        let modTypes = surface.modules.first?.publicTypes ?? []
        #expect(modTypes.contains("PublicType"))
        #expect(!modTypes.contains("PrivateType"))
    }

    // MARK: - SHA-256

    @Test("sha256Hex produces consistent hashes")
    func sha256Consistency() {
        let data = "hello world".data(using: .utf8)!
        let hash1 = builder.sha256Hex(data)
        let hash2 = builder.sha256Hex(data)
        #expect(hash1 == hash2)
        #expect(hash1.count == 64)
    }

    @Test("sha256Hex produces different hashes for different data")
    func sha256Different() {
        let data1 = "hello".data(using: .utf8)!
        let data2 = "world".data(using: .utf8)!
        #expect(builder.sha256Hex(data1) != builder.sha256Hex(data2))
    }

    // MARK: - Helpers

    private func makeTestCache() -> ArchitectureCache {
        ArchitectureCache(
            projectId: "TestProject",
            projectPath: "/tmp/test-project",
            gitHash: "abc123def456",
            builtAt: Date(timeIntervalSince1970: 1_700_000_000),
            packageInfo: PackageInfo(
                name: "TestPackage",
                platforms: ["macOS 14"],
                targets: [
                    TargetInfo(name: "AppModule", type: .library, sourceFiles: 8),
                    TargetInfo(name: "AppModuleTests", type: .test, sourceFiles: 2),
                ],
                dependencies: [
                    DependencyInfo(name: "swift-log", isLocal: false, url: "https://github.com/apple/swift-log.git"),
                ]
            ),
            protocols: [
                ProtocolDescriptor(name: "Renderable", methods: ["func render()"], module: "AppModule"),
                ProtocolDescriptor(name: "DataSource", methods: ["func fetch() async throws"], module: "AppModule"),
            ],
            types: [
                TypeDescriptor(name: "AppConfig", kind: .struct, module: "AppModule", fields: ["apiKey", "baseURL"], isPublic: true),
                TypeDescriptor(name: "UserModel", kind: .struct, module: "AppModule", fields: ["id", "name"], conformances: ["Codable", "Sendable"], isPublic: true),
                TypeDescriptor(name: "InternalHelper", kind: .class, module: "AppModule", isPublic: false),
            ],
            dependencyGraph: [
                "AppModule": ["Foundation", "Logging"],
            ],
            patterns: [
                CodePattern(name: "error_pattern", description: "Typed error enums", example: "enum AppError: Error { ... }", files: ["Sources/AppModule/Errors.swift"]),
            ],
            testInfo: TestInfo(framework: "swift-testing", testFiles: 2, testCount: 15, mockPattern: "Mock* with shouldThrow")
        )
    }

    private func makeTmpDir(_ name: String) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("moto-test-\(name)-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }
}
