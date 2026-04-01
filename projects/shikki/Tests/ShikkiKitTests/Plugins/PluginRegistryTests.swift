import Foundation
import Testing
@testable import ShikkiKit

@Suite("PluginRegistry — register, unregister, command resolution, discovery")
struct PluginRegistryTests {

    // MARK: - Test Fixtures

    private static func makeManifest(
        id: String = "shikki/creative-studio",
        commands: [PluginCommand] = [PluginCommand(name: "creative")],
        minimumShikkiVersion: SemanticVersion = SemanticVersion(major: 0, minor: 3, patch: 0),
        checksum: String = "sha256-test"
    ) -> PluginManifest {
        PluginManifest(
            id: PluginID(id),
            displayName: "Test Plugin",
            version: SemanticVersion(major: 0, minor: 1, patch: 0),
            source: .builtin,
            commands: commands,
            capabilities: ["test"],
            dependencies: PluginDependencies(),
            minimumShikkiVersion: minimumShikkiVersion,
            entryPoint: "TestPlugin",
            author: "test",
            license: "MIT",
            description: "A test plugin",
            checksum: checksum
        )
    }

    // MARK: - Registration

    @Test("Register a plugin successfully")
    func register_validPlugin_succeeds() async throws {
        let registry = PluginRegistry()
        let manifest = Self.makeManifest()
        let result = try await registry.register(manifest: manifest)
        #expect(result.id == manifest.id)

        let count = await registry.count
        #expect(count == 1)
    }

    @Test("Register multiple plugins")
    func register_multiplePlugins_succeeds() async throws {
        let registry = PluginRegistry()
        try await registry.register(manifest: Self.makeManifest(
            id: "shikki/plugin-a",
            commands: [PluginCommand(name: "alpha")]
        ))
        try await registry.register(manifest: Self.makeManifest(
            id: "shikki/plugin-b",
            commands: [PluginCommand(name: "beta")]
        ))

        let count = await registry.count
        #expect(count == 2)
    }

    @Test("Registering duplicate plugin ID throws")
    func register_duplicate_throws() async throws {
        let registry = PluginRegistry()
        try await registry.register(manifest: Self.makeManifest())

        await #expect(throws: PluginRegistryError.self) {
            try await registry.register(manifest: Self.makeManifest())
        }
    }

    @Test("Registering duplicate command throws")
    func register_duplicateCommand_throws() async throws {
        let registry = PluginRegistry()
        try await registry.register(manifest: Self.makeManifest(
            id: "shikki/plugin-a",
            commands: [PluginCommand(name: "shared")]
        ))

        await #expect(throws: PluginRegistryError.self) {
            try await registry.register(manifest: Self.makeManifest(
                id: "shikki/plugin-b",
                commands: [PluginCommand(name: "shared")]
            ))
        }
    }

    @Test("Registering incompatible version throws")
    func register_incompatibleVersion_throws() async {
        let registry = PluginRegistry(
            shikkiVersion: SemanticVersion(major: 0, minor: 2, patch: 0)
        )

        await #expect(throws: PluginRegistryError.self) {
            try await registry.register(manifest: Self.makeManifest(
                minimumShikkiVersion: SemanticVersion(major: 1, minor: 0, patch: 0)
            ))
        }
    }

    // MARK: - Unregistration

    @Test("Unregister an installed plugin")
    func unregister_existingPlugin_succeeds() async throws {
        let registry = PluginRegistry()
        try await registry.register(manifest: Self.makeManifest())

        try await registry.unregister(id: PluginID("shikki/creative-studio"))

        let count = await registry.count
        #expect(count == 0)
    }

    @Test("Unregister removes command index entries")
    func unregister_removesCommandIndex() async throws {
        let registry = PluginRegistry()
        try await registry.register(manifest: Self.makeManifest(
            commands: [PluginCommand(name: "creative"), PluginCommand(name: "create")]
        ))

        try await registry.unregister(id: PluginID("shikki/creative-studio"))

        let result1 = await registry.resolve(command: "creative")
        let result2 = await registry.resolve(command: "create")
        #expect(result1 == nil)
        #expect(result2 == nil)
    }

    @Test("Unregistering non-existent plugin throws")
    func unregister_nonExistent_throws() async {
        let registry = PluginRegistry()

        await #expect(throws: PluginRegistryError.self) {
            try await registry.unregister(id: PluginID("shikki/nonexistent"))
        }
    }

    // MARK: - Command Resolution

    @Test("Resolve command to its owning plugin")
    func resolve_existingCommand_returnsPlugin() async throws {
        let registry = PluginRegistry()
        try await registry.register(manifest: Self.makeManifest(
            id: "shikki/creative-studio",
            commands: [PluginCommand(name: "creative")]
        ))

        let result = await registry.resolve(command: "creative")
        #expect(result != nil)
        #expect(result?.id == PluginID("shikki/creative-studio"))
    }

    @Test("Resolve unknown command returns nil")
    func resolve_unknownCommand_returnsNil() async {
        let registry = PluginRegistry()
        let result = await registry.resolve(command: "nonexistent")
        #expect(result == nil)
    }

    @Test("Resolve disambiguates between multiple plugins")
    func resolve_multiplePlugins_returnsCorrectOne() async throws {
        let registry = PluginRegistry()
        try await registry.register(manifest: Self.makeManifest(
            id: "shikki/creative-studio",
            commands: [PluginCommand(name: "creative")]
        ))
        try await registry.register(manifest: Self.makeManifest(
            id: "shikki/research",
            commands: [PluginCommand(name: "research")]
        ))

        let creative = await registry.resolve(command: "creative")
        let research = await registry.resolve(command: "research")
        #expect(creative?.id == PluginID("shikki/creative-studio"))
        #expect(research?.id == PluginID("shikki/research"))
    }

    // MARK: - Listing

    @Test("Installed returns all plugins sorted by display name")
    func installed_returnsSorted() async throws {
        let registry = PluginRegistry()
        try await registry.register(manifest: PluginManifest(
            id: "shikki/zebra",
            displayName: "Zebra Plugin",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            source: .builtin,
            commands: [PluginCommand(name: "zebra")],
            capabilities: [],
            dependencies: PluginDependencies(),
            minimumShikkiVersion: SemanticVersion(major: 0, minor: 1, patch: 0),
            entryPoint: "Zebra",
            author: "test",
            license: "MIT",
            description: "Z",
            checksum: "z"
        ))
        try await registry.register(manifest: PluginManifest(
            id: "shikki/alpha",
            displayName: "Alpha Plugin",
            version: SemanticVersion(major: 1, minor: 0, patch: 0),
            source: .builtin,
            commands: [PluginCommand(name: "alpha")],
            capabilities: [],
            dependencies: PluginDependencies(),
            minimumShikkiVersion: SemanticVersion(major: 0, minor: 1, patch: 0),
            entryPoint: "Alpha",
            author: "test",
            license: "MIT",
            description: "A",
            checksum: "a"
        ))

        let list = await registry.installed()
        #expect(list.count == 2)
        #expect(list[0].displayName == "Alpha Plugin")
        #expect(list[1].displayName == "Zebra Plugin")
    }

    // MARK: - Checksum Verification

    @Test("Verify checksum of installed plugin — matching")
    func verify_matchingChecksum_returnsTrue() async throws {
        let registry = PluginRegistry()
        try await registry.register(manifest: Self.makeManifest(checksum: "sha256-abc"))

        let result = try await registry.verify(
            id: PluginID("shikki/creative-studio"),
            expectedChecksum: "sha256-abc"
        )
        #expect(result == true)
    }

    @Test("Verify checksum of installed plugin — mismatched")
    func verify_mismatchedChecksum_returnsFalse() async throws {
        let registry = PluginRegistry()
        try await registry.register(manifest: Self.makeManifest(checksum: "sha256-abc"))

        let result = try await registry.verify(
            id: PluginID("shikki/creative-studio"),
            expectedChecksum: "sha256-WRONG"
        )
        #expect(result == false)
    }

    @Test("Verify checksum of non-existent plugin throws")
    func verify_nonExistent_throws() async {
        let registry = PluginRegistry()

        await #expect(throws: PluginRegistryError.self) {
            try await registry.verify(
                id: PluginID("shikki/nonexistent"),
                expectedChecksum: "any"
            )
        }
    }

    // MARK: - Discovery from Disk

    @Test("Load from directory with manifest.json files")
    func loadFromDirectory_withManifests_loadsPlugins() async throws {
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory.appendingPathComponent("shikki-test-plugins-\(UUID().uuidString)").path

        defer { try? fm.removeItem(atPath: tmpDir) }

        // Create a plugin directory with manifest.json
        let pluginDir = (tmpDir as NSString).appendingPathComponent("test-plugin")
        try fm.createDirectory(atPath: pluginDir, withIntermediateDirectories: true)

        let manifest = Self.makeManifest(id: "shikki/test-plugin")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(manifest)

        let manifestPath = (pluginDir as NSString).appendingPathComponent("manifest.json")
        fm.createFile(atPath: manifestPath, contents: data)

        let registry = PluginRegistry()
        let results = await registry.loadFromDirectory(tmpDir)

        let loaded = results.compactMap { result -> PluginManifest? in
            if case .loaded(let m) = result { return m }
            return nil
        }
        #expect(loaded.count == 1)
        #expect(loaded.first?.id == PluginID("shikki/test-plugin"))

        let count = await registry.count
        #expect(count == 1)
    }

    @Test("Load from non-existent directory returns empty")
    func loadFromDirectory_nonExistent_returnsEmpty() async {
        let registry = PluginRegistry()
        let results = await registry.loadFromDirectory("/tmp/shikki-nonexistent-\(UUID().uuidString)")
        #expect(results.isEmpty)
    }

    @Test("Load skips directories without manifest.json")
    func loadFromDirectory_noManifest_skips() async throws {
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory.appendingPathComponent("shikki-test-skip-\(UUID().uuidString)").path

        defer { try? fm.removeItem(atPath: tmpDir) }

        let pluginDir = (tmpDir as NSString).appendingPathComponent("empty-plugin")
        try fm.createDirectory(atPath: pluginDir, withIntermediateDirectories: true)

        let registry = PluginRegistry()
        let results = await registry.loadFromDirectory(tmpDir)

        let skipped = results.compactMap { result -> String? in
            if case .skipped(let dir, _) = result { return dir }
            return nil
        }
        #expect(skipped.count == 1)
        #expect(skipped.first == "empty-plugin")

        let count = await registry.count
        #expect(count == 0)
    }
}
