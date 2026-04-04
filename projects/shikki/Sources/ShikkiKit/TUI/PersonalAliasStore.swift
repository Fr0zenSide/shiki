import Foundation

// MARK: - PersonalAlias

/// A user-defined emoji and text shortcut that maps to a shikki command.
public struct PersonalAlias: Codable, Sendable, Equatable {
    public let emoji: String
    public let text: String
    public let command: String
    public let createdAt: Date

    public init(emoji: String, text: String, command: String, createdAt: Date = Date()) {
        self.emoji = emoji
        self.text = text
        self.command = command
        self.createdAt = createdAt
    }
}

// MARK: - PersonalAliasStore

/// Manages user-defined aliases stored in `~/.shikki/aliases.json`.
/// Personal aliases override core EmojiRegistry entries when the same emoji is used.
public struct PersonalAliasStore: Sendable {
    private let path: String

    public init(path: String? = nil) {
        if let path {
            self.path = path
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            self.path = (home as NSString).appendingPathComponent(".shikki/aliases.json")
        }
    }

    // MARK: - CRUD

    /// Add or update an alias. Creates `aliases.json` (and parent directory) if missing.
    public func save(_ alias: PersonalAlias) throws {
        var aliases = try loadAliases()
        aliases.removeAll { $0.emoji == alias.emoji }
        aliases.append(alias)
        try writeAliases(aliases)
    }

    /// Remove an alias by emoji.
    public func remove(emoji: String) throws {
        var aliases = try loadAliases()
        aliases.removeAll { $0.emoji == emoji }
        try writeAliases(aliases)
    }

    /// Remove an alias by text name.
    public func remove(text: String) throws {
        var aliases = try loadAliases()
        aliases.removeAll { $0.text == text }
        try writeAliases(aliases)
    }

    /// List all personal aliases.
    public func listAll() throws -> [PersonalAlias] {
        try loadAliases()
    }

    /// Find alias by emoji.
    public func find(emoji: String) throws -> PersonalAlias? {
        try loadAliases().first { $0.emoji == emoji }
    }

    /// Find alias by text name.
    public func find(text: String) throws -> PersonalAlias? {
        try loadAliases().first { $0.text == text }
    }

    // MARK: - Resolution

    /// Resolve any input (emoji or text) to a command.
    /// Checks personal aliases first, then falls back to core EmojiRegistry.
    public func resolve(_ input: String) -> String? {
        if let aliases = try? loadAliases() {
            // Check emoji match
            if let match = aliases.first(where: { $0.emoji == input }) {
                return match.command
            }
            // Check text match (with or without leading /)
            let textInput = input.hasPrefix("/") ? String(input.dropFirst()) : input
            if let match = aliases.first(where: { $0.text == textInput }) {
                return match.command
            }
        }
        // Fall back to core EmojiRegistry
        return EmojiRegistry.resolve(input)
    }

    // MARK: - Internal

    private func loadAliases() throws -> [PersonalAlias] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return [] }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        if data.isEmpty { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([PersonalAlias].self, from: data)
    }

    private func writeAliases(_ aliases: [PersonalAlias]) throws {
        let fm = FileManager.default
        let dir = (path as NSString).deletingLastPathComponent
        if !fm.fileExists(atPath: dir) {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(aliases)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
