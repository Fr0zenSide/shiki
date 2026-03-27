import Foundation

// MARK: - EmojiRegistry (BR-EM-02)
// Single source of truth for all emoji→command mappings.
// Used by EmojiRouter (parsing) and renderers (output decoration).

public enum EmojiRegistry: Sendable {

    public struct Entry: Sendable, Equatable {
        public let emoji: String
        public let command: String
    }

    // MARK: - Static Registry

    /// All registered emoji→command mappings, including aliases.
    /// Order: diagnostic, workflow, intelligence, signals, navigation, meta.
    public static let all: [Entry] = [
        // Diagnostic
        Entry(emoji: "🥕", command: "doctor"),
        Entry(emoji: "🐰", command: "doctor"),
        Entry(emoji: "🐰🥕", command: "doctor"),
        Entry(emoji: "🥕🐰", command: "doctor"),

        // Intelligence
        Entry(emoji: "🧠", command: "brainstorm"),
        Entry(emoji: "🌟", command: "challenge"),
        Entry(emoji: "🤔", command: "explain"),
        Entry(emoji: "🤠", command: "ingest"),
        Entry(emoji: "🧙‍♂️", command: "wizard"),
        Entry(emoji: "🔍", command: "research"),
        Entry(emoji: "🎯", command: "codir"),
        Entry(emoji: "🏗️", command: "decide"),
        Entry(emoji: "🗡️", command: "review"),

        // Workflow
        Entry(emoji: "🚀", command: "next"),
        Entry(emoji: "📦", command: "ship"),
        Entry(emoji: "✏️", command: "spec"),
        Entry(emoji: "⏸️", command: "pause"),
        Entry(emoji: "▶️", command: "restart"),

        // Signals
        Entry(emoji: "✅", command: "validate"),
        Entry(emoji: "❌", command: "invalidate"),
        Entry(emoji: "👍", command: "like"),
        Entry(emoji: "👎", command: "dislike"),

        // Navigation
        Entry(emoji: "🌡️", command: "status"),
        Entry(emoji: "📊", command: "board"),
        Entry(emoji: "⚡️", command: "inbox"),
        Entry(emoji: "📨", command: "inbox"),
        Entry(emoji: "📋", command: "backlog"),
        Entry(emoji: "🔄", command: "history"),
        Entry(emoji: "📝", command: "log"),
        Entry(emoji: "🔔", command: "wake"),

        // Meta
        Entry(emoji: "📃", command: "help"),
        Entry(emoji: "⏰", command: "schedule"),
        Entry(emoji: "💾", command: "save"),
        Entry(emoji: "📂", command: "load"),
        Entry(emoji: "⏪", command: "undo"),
        Entry(emoji: "🕸️", command: "network"),
        Entry(emoji: "🔇", command: "focus"),
    ]

    // MARK: - Lookup

    /// Fast emoji→command lookup dictionary.
    /// Keys are normalized (precomposedStringWithCanonicalMapping).
    private static let _lookup: [String: String] = {
        var map: [String: String] = [:]
        for entry in all {
            let key = entry.emoji.precomposedStringWithCanonicalMapping
            map[key] = entry.command
        }
        return map
    }()

    /// Resolve a single emoji (or multi-emoji like 🐰🥕) to its command name.
    /// Returns nil if the emoji is not registered.
    public static func resolve(_ emoji: String) -> String? {
        let normalized = emoji.precomposedStringWithCanonicalMapping
        if let command = _lookup[normalized] {
            return command
        }
        // Try stripping VS16 variation selectors
        let stripped = normalized.replacingOccurrences(of: "\u{FE0F}", with: "")
        return _lookup[stripped]
    }

    /// All entries for help display.
    public static func allEntries() -> [(emoji: String, command: String)] {
        all.map { (emoji: $0.emoji, command: $0.command) }
    }
}
