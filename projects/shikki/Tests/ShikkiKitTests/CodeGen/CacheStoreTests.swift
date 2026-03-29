import Foundation
import Testing
@testable import ShikkiKit

@Suite("CacheStore")
struct CacheStoreTests {

    /// Create a temporary directory for test caches.
    private func makeTempStore() throws -> (CacheStore, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shikki-test-cache-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return (CacheStore(basePath: tempDir), tempDir)
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func sampleCache(projectId: String = "testproject", gitHash: String = "abc123") -> ArchitectureCache {
        ArchitectureCache(
            projectId: projectId,
            projectPath: "/tmp/test",
            gitHash: gitHash,
            builtAt: Date(),
            packageInfo: PackageInfo(name: "TestPackage", platforms: ["macOS 14"], targets: [
                TargetInfo(name: "App", type: .executable, path: "Sources/App", sourceFiles: 5),
            ], dependencies: []),
            protocols: [
                ProtocolDescriptor(name: "MyProtocol", file: "Proto.swift", methods: ["func run()"], module: "App"),
            ],
            types: [
                TypeDescriptor(name: "MyStruct", kind: .struct, file: "Model.swift", module: "App",
                               fields: ["id", "name"], conformances: ["Codable"], isPublic: true),
            ],
            dependencyGraph: ["App": ["Foundation"]],
            patterns: [
                CodePattern(name: "error_pattern", description: "Error enums", example: "enum E: Error {}", files: ["E.swift"]),
            ],
            testInfo: TestInfo(framework: "swift-testing", testFiles: 3, testCount: 15)
        )
    }

    // MARK: - Tests

    @Test("Save and load round-trip preserves data")
    func saveAndLoadRoundTrip() throws {
        let (store, dir) = try makeTempStore()
        defer { cleanup(dir) }

        let cache = sampleCache()
        try store.save(cache)

        let loaded = try store.load(projectId: "testproject")
        #expect(loaded != nil)
        #expect(loaded?.projectId == "testproject")
        #expect(loaded?.gitHash == "abc123")
        #expect(loaded?.packageInfo.name == "TestPackage")
        #expect(loaded?.protocols.count == 1)
        #expect(loaded?.protocols.first?.name == "MyProtocol")
        #expect(loaded?.types.count == 1)
        #expect(loaded?.types.first?.name == "MyStruct")
        #expect(loaded?.patterns.count == 1)
        #expect(loaded?.testInfo.testCount == 15)
    }

    @Test("Load returns nil for non-existent project")
    func loadNonExistent() throws {
        let (store, dir) = try makeTempStore()
        defer { cleanup(dir) }

        let result = try store.load(projectId: "nonexistent")
        #expect(result == nil)
    }

    @Test("isStale detects different git hash")
    func isStaleDetectsDifferentHash() throws {
        let (store, dir) = try makeTempStore()
        defer { cleanup(dir) }

        let cache = sampleCache(gitHash: "abc123")
        try store.save(cache)

        #expect(store.isStale(projectId: "testproject", currentGitHash: "def456") == true)
    }

    @Test("isStale returns false for matching hash")
    func isStaleMatchingHash() throws {
        let (store, dir) = try makeTempStore()
        defer { cleanup(dir) }

        let cache = sampleCache(gitHash: "abc123")
        try store.save(cache)

        #expect(store.isStale(projectId: "testproject", currentGitHash: "abc123") == false)
    }

    @Test("isStale returns true when no cache exists")
    func isStaleNoCache() throws {
        let (store, dir) = try makeTempStore()
        defer { cleanup(dir) }

        #expect(store.isStale(projectId: "nonexistent", currentGitHash: "abc") == true)
    }

    @Test("Invalidate removes cache file")
    func invalidateRemovesCache() throws {
        let (store, dir) = try makeTempStore()
        defer { cleanup(dir) }

        let cache = sampleCache()
        try store.save(cache)
        #expect(try store.load(projectId: "testproject") != nil)

        try store.invalidate(projectId: "testproject")
        #expect(try store.load(projectId: "testproject") == nil)
    }

    @Test("Invalidate does not throw for non-existent project")
    func invalidateNonExistent() throws {
        let (store, dir) = try makeTempStore()
        defer { cleanup(dir) }

        // Should not throw
        try store.invalidate(projectId: "nonexistent")
    }

    @Test("listCached returns all project IDs")
    func listCachedProjects() throws {
        let (store, dir) = try makeTempStore()
        defer { cleanup(dir) }

        try store.save(sampleCache(projectId: "alpha"))
        try store.save(sampleCache(projectId: "bravo"))
        try store.save(sampleCache(projectId: "charlie"))

        let cached = store.listCached()
        #expect(cached.count == 3)
        #expect(cached.contains("alpha"))
        #expect(cached.contains("bravo"))
        #expect(cached.contains("charlie"))
    }

    @Test("listCached returns empty for fresh store")
    func listCachedEmpty() throws {
        let (store, dir) = try makeTempStore()
        defer { cleanup(dir) }

        let cached = store.listCached()
        #expect(cached.isEmpty)
    }
}
