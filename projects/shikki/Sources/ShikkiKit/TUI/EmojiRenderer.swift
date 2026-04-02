import Foundation

// MARK: - EmojiRenderer

/// Bidirectional emoji rendering for command output headers and help tables (BR-EM-08, BR-EM-09).
/// Uses `EmojiRegistry.byCommand` as the single source of truth.
public enum EmojiRenderer: Sendable {

    // MARK: - Reverse Lookup

    /// Return the primary emoji for a given command name, or nil if none is registered.
    public static func emojiForCommand(_ command: String) -> String? {
        EmojiRegistry.byCommand[command]
    }

    // MARK: - Decorated Command String

    /// Return "command (emoji)" for display — e.g. "doctor (🥕)".
    /// Falls back to plain command name when no emoji is registered.
    public static func renderCommandWithEmoji(_ command: String) -> String {
        guard let emoji = emojiForCommand(command) else { return command }
        return "\(command) (\(emoji))"
    }

    // MARK: - Help Table

    /// Render a formatted two-column help table of all emoji → command mappings,
    /// grouped by category. Suitable for `shi help` output (BR-EM-09).
    public static func renderHelpTable() -> String {
        var lines: [String] = []
        lines.append("\u{1B}[1mShikkimoji — Emoji Command Shortcuts\u{1B}[0m")
        lines.append("")

        for category in EmojiRegistry.Category.allCases {
            let entries = EmojiRegistry.all.filter { $0.category == category }
            guard !entries.isEmpty else { continue }

            // Category header (capitalised)
            let header = category.rawValue.prefix(1).uppercased() + category.rawValue.dropFirst()
            lines.append("\u{1B}[1m\u{1B}[4m\(header)\u{1B}[0m")

            for entry in entries {
                let emoji = pad(entry.emoji, 4)
                let cmd   = pad(entry.command, 12)
                lines.append("  \(emoji)  \(cmd)  \(entry.description)")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Private Helpers

    /// Pad a string to a minimum visible width (ignoring ANSI codes).
    private static func pad(_ string: String, _ width: Int) -> String {
        // Emoji are often rendered as double-width characters; use character count as best effort.
        let len = string.count
        if len >= width { return string }
        return string + String(repeating: " ", count: width - len)
    }
}
