import Foundation
import Testing
@testable import ShikkiKit

@Suite("Moto Ingest Integration")
struct MotoIngestTests {

    // MARK: - Pointer Creation

    @Test("pointer creation from manifest and dotfile has correct stats")
    func pointerCreationCorrectStats() {
        let manifest = makeTestManifest()
        let dotfile = makeTestDotfile()

        let pointer = MotoCacheIngestAdapter.createPointer(
            manifest: manifest,
            dotfile: dotfile
        )

        #expect(pointer.projectName == "Brainy")
        #expect(pointer.motoVersion == "1.2.0")
        #expect(pointer.cacheEndpoint == "https://cache.originate.dev/brainy")
        #expect(pointer.stats.protocolCount == 5)
        #expect(pointer.stats.typeCount == 12)
        #expect(pointer.stats.testCount == 42)
    }

    @Test("pointer creation uses dotfile project name over manifest project")
    func pointerUsesProjectName() {
        var manifest = makeTestManifest()
        manifest.project = "brainy-internal"
        let dotfile = makeTestDotfile()

        let pointer = MotoCacheIngestAdapter.createPointer(
            manifest: manifest,
            dotfile: dotfile
        )

        #expect(pointer.projectName == "Brainy")
    }

    @Test("pointer creation with nil endpoint uses local path fallback")
    func pointerNilEndpointFallback() {
        let manifest = makeTestManifest()
        var dotfile = makeTestDotfile()
        dotfile.cache.endpoint = nil

        let pointer = MotoCacheIngestAdapter.createPointer(
            manifest: manifest,
            dotfile: dotfile
        )

        #expect(pointer.cacheEndpoint == "moto-local://.moto-cache/")
    }

    @Test("pointer creation computes manifest checksum from file checksums")
    func pointerManifestChecksum() {
        let manifest = makeTestManifest()
        let dotfile = makeTestDotfile()

        let pointer = MotoCacheIngestAdapter.createPointer(
            manifest: manifest,
            dotfile: dotfile
        )

        #expect(!pointer.manifestChecksum.isEmpty)
        // The checksum should be deterministic
        let pointer2 = MotoCacheIngestAdapter.createPointer(
            manifest: manifest,
            dotfile: dotfile
        )
        #expect(pointer.manifestChecksum == pointer2.manifestChecksum)
    }

    // MARK: - Pointer to Chunks

    @Test("pointer to chunks produces 1-2 IngestChunks with moto_cache category")
    func pointerToChunksCategory() {
        let pointer = makeTestPointer()

        let chunks = MotoCacheIngestAdapter.toIngestChunks(pointer: pointer)

        #expect(chunks.count >= 1)
        #expect(chunks.count <= 2)
        for chunk in chunks {
            #expect(chunk.category == "moto_cache")
            #expect(chunk.sourceType == "moto_cache")
        }
    }

    @Test("first chunk contains project name, version, endpoint, stats summary")
    func firstChunkContent() {
        let pointer = makeTestPointer()

        let chunks = MotoCacheIngestAdapter.toIngestChunks(pointer: pointer)

        let firstContent = chunks[0].content
        #expect(firstContent.contains("Brainy"))
        #expect(firstContent.contains("1.2.0"))
        #expect(firstContent.contains("https://cache.originate.dev/brainy"))
        #expect(firstContent.contains("5"))   // protocolCount
        #expect(firstContent.contains("12"))  // typeCount
    }

    @Test("chunks have correct source URI from pointer endpoint")
    func chunksSourceUri() {
        let pointer = makeTestPointer()

        let chunks = MotoCacheIngestAdapter.toIngestChunks(pointer: pointer)

        for chunk in chunks {
            #expect(chunk.sourceUri == "https://cache.originate.dev/brainy")
        }
    }

    // MARK: - Round-trip

    @Test("round-trip: create pointer -> to chunks -> chunks contain parseable JSON reference")
    func roundTripParseableJSON() throws {
        let manifest = makeTestManifest()
        let dotfile = makeTestDotfile()

        let pointer = MotoCacheIngestAdapter.createPointer(
            manifest: manifest,
            dotfile: dotfile
        )
        let chunks = MotoCacheIngestAdapter.toIngestChunks(pointer: pointer)

        // The second chunk (cache reference) should contain valid JSON
        let refChunk = chunks.last!
        #expect(refChunk.content.contains("manifestChecksum"))
        #expect(refChunk.content.contains("motoVersion"))

        // Verify the JSON is parseable
        let data = refChunk.content.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(MotoIngestPointer.self, from: data)
        #expect(decoded.projectName == pointer.projectName)
        #expect(decoded.manifestChecksum == pointer.manifestChecksum)
    }

    // MARK: - IngestChunk Codable

    @Test("IngestChunk is Codable and round-trips correctly")
    func ingestChunkCodable() throws {
        let chunk = IngestChunk(
            content: "test content",
            category: "moto_cache",
            sourceType: "moto_cache",
            sourceUri: "https://example.com"
        )

        let data = try JSONEncoder().encode(chunk)
        let decoded = try JSONDecoder().decode(IngestChunk.self, from: data)

        #expect(decoded.content == chunk.content)
        #expect(decoded.category == chunk.category)
        #expect(decoded.sourceType == chunk.sourceType)
        #expect(decoded.sourceUri == chunk.sourceUri)
    }

    // MARK: - Source Registry

    @Test("source registry hasMotoCache returns true when .moto file exists")
    func registryHasMotoCacheTrue() async throws {
        let tmpDir = makeTmpDir("registry-has")
        defer { cleanup(tmpDir) }

        // Create a .moto file
        let motoPath = tmpDir.appendingPathComponent(".moto")
        try makeTestDotfileContent().write(to: motoPath, atomically: true, encoding: .utf8)

        let registry = MotoSourceRegistry()
        let result = await registry.hasMotoCache(at: tmpDir.path)

        #expect(result == true)
    }

    @Test("source registry hasMotoCache returns false when no .moto file")
    func registryHasMotoCacheFalse() async {
        let tmpDir = makeTmpDir("registry-no")
        defer { cleanup(tmpDir) }

        let registry = MotoSourceRegistry()
        let result = await registry.hasMotoCache(at: tmpDir.path)

        #expect(result == false)
    }

    @Test("source registry loadDotfile parses .moto from project path")
    func registryLoadDotfile() async throws {
        let tmpDir = makeTmpDir("registry-load")
        defer { cleanup(tmpDir) }

        let motoPath = tmpDir.appendingPathComponent(".moto")
        try makeTestDotfileContent().write(to: motoPath, atomically: true, encoding: .utf8)

        let registry = MotoSourceRegistry()
        let dotfile = try await registry.loadDotfile(at: tmpDir.path)

        #expect(dotfile.project.name == "TestProject")
        #expect(dotfile.cache.endpoint == "https://cache.example.com/test")
    }

    @Test("source registry register and list sources")
    func registryRegisterAndList() async {
        let registry = MotoSourceRegistry()
        let dotfile = makeTestDotfile()

        await registry.register(projectPath: "/projects/brainy", dotfile: dotfile)

        let sources = await registry.listSources()
        #expect(sources.count == 1)
        #expect(sources[0].path == "/projects/brainy")
        #expect(sources[0].dotfile.project.name == "Brainy")
    }

    @Test("source registry register multiple sources")
    func registryMultipleSources() async {
        let registry = MotoSourceRegistry()
        let dotfile1 = makeTestDotfile()
        var dotfile2 = makeTestDotfile()
        dotfile2.project.name = "WabiSabi"

        await registry.register(projectPath: "/projects/brainy", dotfile: dotfile1)
        await registry.register(projectPath: "/projects/wabisabi", dotfile: dotfile2)

        let sources = await registry.listSources()
        #expect(sources.count == 2)
    }

    // MARK: - MotoIngestStats

    @Test("MotoIngestStats includes duplicate count from manifest")
    func ingestStatsIncludeDuplicateCount() {
        let manifest = makeTestManifest()
        let dotfile = makeTestDotfile()

        let pointer = MotoCacheIngestAdapter.createPointer(
            manifest: manifest,
            dotfile: dotfile
        )

        // Default manifest has 0 duplicates (no method index to detect from)
        #expect(pointer.stats.duplicateCount == 0)
    }

    @Test("createPointer with method count from stats")
    func pointerMethodCount() {
        let manifest = makeTestManifest()
        let dotfile = makeTestDotfile()

        let pointer = MotoCacheIngestAdapter.createPointer(
            manifest: manifest,
            dotfile: dotfile
        )

        // methodCount defaults to 0 when no method index is provided
        #expect(pointer.stats.methodCount == 0)
    }

    // MARK: - Helpers

    private func makeTestManifest() -> MotoCacheManifest {
        MotoCacheManifest(
            schemaVersion: 1,
            project: "Brainy",
            language: "swift",
            gitCommit: "abc123def456",
            gitBranch: "main",
            builtAt: "2026-04-01T00:00:00Z",
            builder: "shikki@0.3.0",
            files: MotoCacheManifest.FileReferences(
                package: MotoCacheManifest.FileEntry(path: "package.json", sha256: "aaa111"),
                protocols: MotoCacheManifest.FileEntry(path: "protocols.json", sha256: "bbb222"),
                types: MotoCacheManifest.FileEntry(path: "types.json", sha256: "ccc333"),
                dependencies: MotoCacheManifest.FileEntry(path: "dependencies.json", sha256: "ddd444"),
                patterns: MotoCacheManifest.FileEntry(path: "patterns.json", sha256: "eee555"),
                tests: MotoCacheManifest.FileEntry(path: "tests.json", sha256: "fff666"),
                apiSurface: MotoCacheManifest.FileEntry(path: "api-surface.json", sha256: "ggg777")
            ),
            stats: MotoCacheManifest.CacheStats(
                sourceFiles: 30,
                protocols: 5,
                types: 12,
                testCount: 42,
                totalCacheTokens: 8000
            )
        )
    }

    private func makeTestDotfile() -> MotoDotfile {
        MotoDotfile(
            project: MotoDotfile.ProjectSection(
                name: "Brainy",
                description: "RSS reader with AI analysis",
                language: "swift"
            ),
            cache: MotoDotfile.CacheSection(
                endpoint: "https://cache.originate.dev/brainy",
                version: "1.2.0",
                commit: "abc123def456",
                schema: "1",
                branches: ["main"],
                localPath: ".moto-cache/"
            ),
            attribution: MotoDotfile.AttributionSection(
                authors: ["Alice <alice@example.com>"],
                organization: "OBYW"
            )
        )
    }

    private func makeTestPointer() -> MotoIngestPointer {
        MotoIngestPointer(
            projectName: "Brainy",
            motoVersion: "1.2.0",
            cacheEndpoint: "https://cache.originate.dev/brainy",
            manifestChecksum: "abc123checksum",
            stats: MotoIngestStats(
                protocolCount: 5,
                typeCount: 12,
                methodCount: 30,
                testCount: 42,
                duplicateCount: 2
            ),
            indexedAt: Date(timeIntervalSince1970: 1_712_000_000)
        )
    }

    private func makeTestDotfileContent() -> String {
        """
        [project]
        name = "TestProject"
        description = "A test project"
        language = "swift"

        [cache]
        endpoint = "https://cache.example.com/test"
        version = "1.0.0"
        schema = "1"

        [attribution]
        authors = ["Test <test@example.com>"]
        """
    }

    private func makeTmpDir(_ name: String) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("moto-ingest-\(name)-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }
}
