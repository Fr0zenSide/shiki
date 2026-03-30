import Foundation

// MARK: - EmojiRegistry

/// Single source of truth for all emoji→command mappings (BR-EM-02).
public enum EmojiRegistry: Sendable {

    public struct Entry: Sendable, Equatable {
        public let emoji: String
        public let command: String
        public let category: Category
        public let acceptsArgs: Bool
        public let isDestructive: Bool
        public let description: String

        public init(
            emoji: String,
            command: String,
            category: Category,
            acceptsArgs: Bool,
            isDestructive: Bool = false,
            description: String
        ) {
            self.emoji = emoji
            self.command = command
            self.category = category
            self.acceptsArgs = acceptsArgs
            self.isDestructive = isDestructive
            self.description = description
        }
    }

    public enum Category: String, Sendable, CaseIterable {
        case diagnostic
        case workflow
        case intelligence
        case signals
        case navigation
        case meta
    }

    /// All registered emoji commands.
    public static let all: [Entry] = [
        // Diagnostic
        Entry(emoji: "🥕", command: "doctor", category: .diagnostic, acceptsArgs: false,
              description: "Health check (\"What's up, doc?\")"),
        Entry(emoji: "🐰", command: "doctor", category: .diagnostic, acceptsArgs: false,
              description: "Doctor alias (Bugs Bunny)"),
        Entry(emoji: "🐰🥕", command: "doctor", category: .diagnostic, acceptsArgs: false,
              description: "Doctor alias (Bugs Bunny with carrot)"),
        Entry(emoji: "🥕🐰", command: "doctor", category: .diagnostic, acceptsArgs: false,
              description: "Doctor alias (carrot + rabbit variant)"),
        Entry(emoji: "🌡️", command: "status", category: .diagnostic, acceptsArgs: false,
              description: "Status overview"),
        Entry(emoji: "🕸️", command: "nodes", category: .diagnostic, acceptsArgs: false,
              description: "Network nodes"),

        // Workflow
        Entry(emoji: "🚀", command: "wave", category: .workflow, acceptsArgs: true,
              description: "Run next waves"),
        Entry(emoji: "📦", command: "ship", category: .workflow, acceptsArgs: true,
              description: "Ship release"),
        Entry(emoji: "✏️", command: "spec", category: .workflow, acceptsArgs: true,
              description: "Write spec"),
        Entry(emoji: "⏸️", command: "pause", category: .workflow, acceptsArgs: true,
              description: "Pause"),
        Entry(emoji: "▶️", command: "restart", category: .workflow, acceptsArgs: false,
              description: "Restart/resume"),
        Entry(emoji: "🔇", command: "focus", category: .workflow, acceptsArgs: true,
              description: "Focus mode"),

        // Intelligence
        Entry(emoji: "🧠", command: "brain", category: .intelligence, acceptsArgs: true,
              description: "Brainstorm with @t"),
        Entry(emoji: "🌟", command: "challenge", category: .intelligence, acceptsArgs: true,
              description: "Challenge with @t"),
        Entry(emoji: "🤔", command: "explain", category: .intelligence, acceptsArgs: true,
              description: "Tell me more"),
        Entry(emoji: "🤠", command: "ingest", category: .intelligence, acceptsArgs: true,
              description: "Ingest/remember"),
        Entry(emoji: "🧙‍♂️", command: "wizard", category: .intelligence, acceptsArgs: true,
              description: "Documentation helper"),
        Entry(emoji: "🔍", command: "research", category: .intelligence, acceptsArgs: true,
              description: "Research"),
        Entry(emoji: "🎯", command: "codir", category: .intelligence, acceptsArgs: true,
              description: "Co-direction"),
        Entry(emoji: "🏗️", command: "decide", category: .intelligence, acceptsArgs: true,
              description: "Architecture decision"),
        Entry(emoji: "🗡️", command: "review", category: .intelligence, acceptsArgs: true,
              description: "@Ronin review"),

        // Signals
        Entry(emoji: "✅", command: "validate", category: .signals, acceptsArgs: true,
              description: "Validate"),
        Entry(emoji: "❌", command: "invalidate", category: .signals, acceptsArgs: true,
              isDestructive: true, description: "Invalidate"),
        Entry(emoji: "👍", command: "like", category: .signals, acceptsArgs: true,
              description: "Like"),
        Entry(emoji: "👎", command: "dislike", category: .signals, acceptsArgs: true,
              description: "Dislike"),

        // Navigation
        Entry(emoji: "📊", command: "board", category: .navigation, acceptsArgs: false,
              description: "Kanban board"),
        Entry(emoji: "⚡️", command: "inbox", category: .navigation, acceptsArgs: false,
              description: "Inbox"),
        Entry(emoji: "📨", command: "inbox", category: .navigation, acceptsArgs: false,
              description: "Inbox (alias)"),
        Entry(emoji: "📋", command: "backlog", category: .navigation, acceptsArgs: false,
              description: "Backlog"),
        Entry(emoji: "🔄", command: "history", category: .navigation, acceptsArgs: false,
              description: "History"),
        Entry(emoji: "📝", command: "log", category: .navigation, acceptsArgs: true,
              description: "Quick log"),
        Entry(emoji: "🔔", command: "wake", category: .navigation, acceptsArgs: false,
              description: "Wake agents"),

        // Meta
        Entry(emoji: "📃", command: "help", category: .meta, acceptsArgs: false,
              description: "Help / cheat sheet"),
        Entry(emoji: "⏰", command: "schedule", category: .meta, acceptsArgs: false,
              description: "Schedule"),
        Entry(emoji: "💾", command: "context", category: .meta, acceptsArgs: true,
              description: "Save context"),
        Entry(emoji: "📂", command: "context", category: .meta, acceptsArgs: true,
              description: "Load context"),
        Entry(emoji: "⏪", command: "undo", category: .meta, acceptsArgs: true,
              isDestructive: true, description: "Undo/rollback"),
    ]

    /// Fast lookup: emoji string → Entry
    public static let byEmoji: [String: Entry] = {
        var map: [String: Entry] = [:]
        for entry in all {
            let key = entry.emoji.precomposedStringWithCanonicalMapping
            map[key] = entry
        }
        // Clock face variants all → schedule
        let clockFaces: [String] = [
            "🕐", "🕑", "🕒", "🕓", "🕔", "🕕",
            "🕖", "🕗", "🕘", "🕙", "🕚", "🕛",
            "⏱️", "⏲️",
        ]
        let scheduleEntry = Entry(
            emoji: "⏰", command: "schedule",
            category: .meta, acceptsArgs: false,
            description: "Schedule"
        )
        for clock in clockFaces {
            map[clock.precomposedStringWithCanonicalMapping] = scheduleEntry
        }
        return map
    }()

    /// Reverse lookup: command name → primary emoji
    public static let byCommand: [String: String] = {
        var map: [String: String] = [:]
        for entry in all {
            if map[entry.command] == nil {
                map[entry.command] = entry.emoji
            }
        }
        return map
    }()

    /// Look up an emoji Character in the registry.
    /// Handles VS16 normalization.
    public static func lookup(_ char: Character) -> Entry? {
        let str = String(char).precomposedStringWithCanonicalMapping
        if let entry = byEmoji[str] { return entry }
        // Try stripping VS16
        let stripped = str.replacingOccurrences(of: "\u{FE0F}", with: "")
        return byEmoji[stripped]
    }

    // MARK: - Convenience API (compatibility)

    /// Resolve an emoji string to its command name. Supports single emoji and compound aliases (🐰🥕).
    public static func resolve(_ emoji: String) -> String? {
        let normalized = emoji.precomposedStringWithCanonicalMapping
        // Try direct lookup by string
        if let entry = byEmoji[normalized] { return entry.command }
        // Try stripping VS16
        let stripped = normalized.replacingOccurrences(of: "\u{FE0F}", with: "")
        if let entry = byEmoji[stripped] { return entry.command }
        // Try single character
        if normalized.count == 1, let char = normalized.first, let entry = lookup(char) {
            return entry.command
        }
        return nil
    }

    /// All entries as (emoji, command) pairs.
    public static func allEntries() -> [(emoji: String, command: String)] {
        all.map { (emoji: $0.emoji, command: $0.command) }
    }

    // MARK: - Starter Kit (BR-EM-10)

    /// Default top-5 emoji shown to new users on the splash screen.
    public static let starterKit: [(emoji: String, command: String)] = [
        ("🥕", "doctor"),
        ("🌡️", "status"),
        ("📊", "board"),
        ("🚀", "wave"),
        ("📃", "help"),
    ]

    // MARK: - Shell Alias Generation (BR-EM-17)

    /// Generates bash/zsh shell aliases for all registered emoji commands.
    /// Produces `sk-<command>` text aliases and `sk-<emoji>` emoji aliases.
    /// Usage: eval "$(shikki doctor --emit-aliases)"
    public static func generateShellAliases() -> String {
        var lines: [String] = [
            "# Shikkimoji shell aliases — generated by shikki",
            "# Add to ~/.zshrc or ~/.bashrc: eval \"$(shikki doctor --emit-aliases)\"",
            "",
        ]

        // Text aliases (sk-<command>) — deduplicated by command
        var seenCommands = Set<String>()
        for entry in all where !seenCommands.contains(entry.command) {
            seenCommands.insert(entry.command)
            lines.append("alias sk-\(entry.command)='shikki \(entry.command)'")
        }

        lines.append("")

        // Emoji aliases — one per unique entry
        for entry in all {
            lines.append("alias 'sk-\(entry.emoji)'='shikki \(entry.command)'")
        }

        return lines.joined(separator: "\n")
    }
}
