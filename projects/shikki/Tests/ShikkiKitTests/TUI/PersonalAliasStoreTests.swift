import Foundation
import Testing
@testable import ShikkiKit

@Suite("PersonalAliasStore — Personal Alias System (Wave 4)")
struct PersonalAliasStoreTests {

    // MARK: - Helpers

    /// Creates a temp directory and returns the path for aliases.json inside it.
    private func makeTempAliasPath() throws -> String {
        let tmp = NSTemporaryDirectory()
        let dir = (tmp as NSString).appendingPathComponent("shikki-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return (dir as NSString).appendingPathComponent("aliases.json")
    }

    /// Cleans up a temp alias path and its parent directory.
    private func cleanup(_ path: String) {
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.removeItem(atPath: dir)
    }

    // MARK: - save()

    @Test("save() creates aliases.json if missing")
    func saveCreatesFile() throws {
        let path = try makeTempAliasPath()
        defer { cleanup(path) }

        let store = PersonalAliasStore(path: path)
        let alias = PersonalAlias(emoji: "\u{1F525}", text: "fire", command: "shi brainstorm --team --deep")

        try store.save(alias)

        #expect(FileManager.default.fileExists(atPath: path))
    }

    @Test("save() writes valid JSON")
    func saveWritesValidJSON() throws {
        let path = try makeTempAliasPath()
        defer { cleanup(path) }

        let store = PersonalAliasStore(path: path)
        let alias = PersonalAlias(emoji: "\u{1F525}", text: "fire", command: "shi brainstorm --team --deep")

        try store.save(alias)

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let aliases = try decoder.decode([PersonalAlias].self, from: data)
        #expect(aliases.count == 1)
        #expect(aliases[0].emoji == "\u{1F525}")
        #expect(aliases[0].text == "fire")
        #expect(aliases[0].command == "shi brainstorm --team --deep")
    }

    // MARK: - listAll()

    @Test("listAll() returns all aliases")
    func listAllReturnsAll() throws {
        let path = try makeTempAliasPath()
        defer { cleanup(path) }

        let store = PersonalAliasStore(path: path)
        try store.save(PersonalAlias(emoji: "\u{1F525}", text: "fire", command: "shi brainstorm"))
        try store.save(PersonalAlias(emoji: "\u{26A1}", text: "quick", command: "shi quick"))

        let all = try store.listAll()
        #expect(all.count == 2)
    }

    // MARK: - find()

    @Test("find(emoji:) returns correct alias")
    func findByEmoji() throws {
        let path = try makeTempAliasPath()
        defer { cleanup(path) }

        let store = PersonalAliasStore(path: path)
        try store.save(PersonalAlias(emoji: "\u{1F525}", text: "fire", command: "shi brainstorm"))
        try store.save(PersonalAlias(emoji: "\u{26A1}", text: "quick", command: "shi quick"))

        let found = try store.find(emoji: "\u{1F525}")
        #expect(found?.text == "fire")
        #expect(found?.command == "shi brainstorm")
    }

    @Test("find(text:) returns correct alias")
    func findByText() throws {
        let path = try makeTempAliasPath()
        defer { cleanup(path) }

        let store = PersonalAliasStore(path: path)
        try store.save(PersonalAlias(emoji: "\u{1F525}", text: "fire", command: "shi brainstorm"))

        let found = try store.find(text: "fire")
        #expect(found?.emoji == "\u{1F525}")
        #expect(found?.command == "shi brainstorm")
    }

    // MARK: - remove()

    @Test("remove(emoji:) removes the alias")
    func removeByEmoji() throws {
        let path = try makeTempAliasPath()
        defer { cleanup(path) }

        let store = PersonalAliasStore(path: path)
        try store.save(PersonalAlias(emoji: "\u{1F525}", text: "fire", command: "shi brainstorm"))
        try store.save(PersonalAlias(emoji: "\u{26A1}", text: "quick", command: "shi quick"))

        try store.remove(emoji: "\u{1F525}")
        let all = try store.listAll()
        #expect(all.count == 1)
        #expect(all[0].emoji == "\u{26A1}")
    }

    @Test("remove(text:) removes the alias")
    func removeByText() throws {
        let path = try makeTempAliasPath()
        defer { cleanup(path) }

        let store = PersonalAliasStore(path: path)
        try store.save(PersonalAlias(emoji: "\u{1F525}", text: "fire", command: "shi brainstorm"))
        try store.save(PersonalAlias(emoji: "\u{26A1}", text: "quick", command: "shi quick"))

        try store.remove(text: "fire")
        let all = try store.listAll()
        #expect(all.count == 1)
        #expect(all[0].text == "quick")
    }

    // MARK: - Overwrite

    @Test("save() overwrites existing alias with same emoji")
    func saveOverwritesSameEmoji() throws {
        let path = try makeTempAliasPath()
        defer { cleanup(path) }

        let store = PersonalAliasStore(path: path)
        try store.save(PersonalAlias(emoji: "\u{1F525}", text: "fire", command: "shi brainstorm"))
        try store.save(PersonalAlias(emoji: "\u{1F525}", text: "fire", command: "shi quick --fast"))

        let all = try store.listAll()
        #expect(all.count == 1)
        #expect(all[0].command == "shi quick --fast")
    }

    // MARK: - resolve()

    @Test("resolve() checks personal first, then core EmojiRegistry")
    func resolvePersonalFirst() throws {
        let path = try makeTempAliasPath()
        defer { cleanup(path) }

        let store = PersonalAliasStore(path: path)
        // Override a core emoji (doctor carrot)
        try store.save(PersonalAlias(emoji: "\u{1F955}", text: "carrot", command: "shi custom-doctor"))

        let result = store.resolve("\u{1F955}")
        #expect(result == "shi custom-doctor")
    }

    @Test("resolve() falls back to core EmojiRegistry for unknown personal aliases")
    func resolveFallsBackToCore() throws {
        let path = try makeTempAliasPath()
        defer { cleanup(path) }

        let store = PersonalAliasStore(path: path)
        // No personal aliases — should fall back to core
        let result = store.resolve("\u{1F680}")
        #expect(result == "wave")
    }

    @Test("resolve() returns nil for unknown input")
    func resolveReturnsNilForUnknown() throws {
        let path = try makeTempAliasPath()
        defer { cleanup(path) }

        let store = PersonalAliasStore(path: path)
        let result = store.resolve("nonexistent")
        #expect(result == nil)
    }

    @Test("resolve() matches text with / prefix")
    func resolveMatchesTextWithSlash() throws {
        let path = try makeTempAliasPath()
        defer { cleanup(path) }

        let store = PersonalAliasStore(path: path)
        try store.save(PersonalAlias(emoji: "\u{1F525}", text: "fire", command: "shi brainstorm"))

        let result = store.resolve("/fire")
        #expect(result == "shi brainstorm")
    }

    @Test("resolve() matches text without / prefix")
    func resolveMatchesTextWithoutSlash() throws {
        let path = try makeTempAliasPath()
        defer { cleanup(path) }

        let store = PersonalAliasStore(path: path)
        try store.save(PersonalAlias(emoji: "\u{1F525}", text: "fire", command: "shi brainstorm"))

        let result = store.resolve("fire")
        #expect(result == "shi brainstorm")
    }

    // MARK: - Edge Cases

    @Test("Empty file returns empty list (not crash)")
    func emptyFileReturnsEmptyList() throws {
        let path = try makeTempAliasPath()
        defer { cleanup(path) }

        // Create empty file
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: path, contents: Data())

        let store = PersonalAliasStore(path: path)
        let all = try store.listAll()
        #expect(all.isEmpty)
    }

    @Test("Missing file returns empty list")
    func missingFileReturnsEmptyList() throws {
        let path = try makeTempAliasPath()
        defer { cleanup(path) }
        // Don't create the file — just use a path that doesn't exist
        try? FileManager.default.removeItem(atPath: path)

        let store = PersonalAliasStore(path: path)
        let all = try store.listAll()
        #expect(all.isEmpty)
    }

    @Test("Concurrent save/list does not corrupt file")
    func concurrentSaveListNoCrash() async throws {
        let path = try makeTempAliasPath()
        defer { cleanup(path) }

        let store = PersonalAliasStore(path: path)
        // Seed initial data
        try store.save(PersonalAlias(emoji: "\u{1F525}", text: "fire", command: "shi brainstorm"))

        // Run concurrent operations — the goal is no crash, not specific ordering
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    let alias = PersonalAlias(
                        emoji: "E\(i)",
                        text: "text\(i)",
                        command: "shi cmd\(i)"
                    )
                    try? store.save(alias)
                }
                group.addTask {
                    _ = try? store.listAll()
                }
            }
        }

        // Verify file is still valid JSON after concurrent access
        let all = try store.listAll()
        #expect(!all.isEmpty)
    }
}
