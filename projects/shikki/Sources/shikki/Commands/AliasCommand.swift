import ArgumentParser
import Foundation
import ShikkiKit

/// `shi alias` — Manage personal command aliases (shikkimoji).
struct AliasCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "alias",
        abstract: "Manage personal command aliases (shikkimoji)",
        subcommands: [
            AliasAddCommand.self,
            AliasListCommand.self,
            AliasRemoveCommand.self,
        ],
        defaultSubcommand: AliasListCommand.self
    )
}

// MARK: - Add

struct AliasAddCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Add or update a personal alias"
    )

    @Argument(help: "Emoji for the alias (e.g. \u{1F525})")
    var emoji: String

    @Option(name: .long, help: "Text equivalent (e.g. fire)")
    var text: String

    @Option(name: .long, help: "Command to execute (e.g. \"shi brainstorm --team --deep\")")
    var command: String

    func run() throws {
        let store = PersonalAliasStore()

        // Check if emoji already exists
        if let existing = try store.find(emoji: emoji) {
            print("\u{1B}[33mOverwriting existing alias: \(existing.emoji) /\(existing.text) \u{2192} \(existing.command)\u{1B}[0m")
        }

        let alias = PersonalAlias(emoji: emoji, text: text, command: command)
        try store.save(alias)
        print("\u{1B}[32mAlias saved: \(emoji)  /\(text) \u{2192} \(command)\u{1B}[0m")
    }
}

// MARK: - Remove

struct AliasRemoveCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove",
        abstract: "Remove a personal alias by emoji or text name"
    )

    @Argument(help: "Emoji to remove (e.g. \u{1F525})")
    var emoji: String?

    @Option(name: .long, help: "Text name to remove (e.g. fire)")
    var text: String?

    func validate() throws {
        guard emoji != nil || text != nil else {
            throw ValidationError("Provide an emoji argument or --text name to remove.")
        }
    }

    func run() throws {
        let store = PersonalAliasStore()

        if let emoji {
            if let existing = try store.find(emoji: emoji) {
                try store.remove(emoji: emoji)
                print("\u{1B}[32mRemoved alias: \(existing.emoji) /\(existing.text)\u{1B}[0m")
            } else {
                print("\u{1B}[33mNo alias found for emoji: \(emoji)\u{1B}[0m")
            }
        } else if let text {
            if let existing = try store.find(text: text) {
                try store.remove(text: text)
                print("\u{1B}[32mRemoved alias: \(existing.emoji) /\(existing.text)\u{1B}[0m")
            } else {
                print("\u{1B}[33mNo alias found for text: \(text)\u{1B}[0m")
            }
        }
    }
}

// MARK: - List

struct AliasListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "Show all personal and core aliases"
    )

    func run() throws {
        let store = PersonalAliasStore()
        let personalAliases = try store.listAll()

        if !personalAliases.isEmpty {
            print("\u{1B}[1m\u{1B}[36mPersonal Aliases:\u{1B}[0m")

            let maxEmoji = personalAliases.map(\.emoji.count).max() ?? 2
            let maxText = personalAliases.map { $0.text.count + 1 }.max() ?? 5

            for alias in personalAliases {
                let emojiPad = alias.emoji.padding(toLength: maxEmoji + 1, withPad: " ", startingAt: 0)
                let textPad = "/\(alias.text)".padding(toLength: maxText + 2, withPad: " ", startingAt: 0)
                print("  \(emojiPad) \(textPad) \u{2192} \(alias.command)")
            }
            print()
        } else {
            print("\u{1B}[2mNo personal aliases defined.\u{1B}[0m")
            print("  Add one: shi alias add \u{1F525} --text fire --command \"shi brainstorm --team --deep\"")
            print()
        }

        // Core shortcuts
        print("\u{1B}[1mCore Shortcuts (built-in):\u{1B}[0m")

        // Deduplicate core entries by command to show primary emoji only
        var seen = Set<String>()
        for entry in EmojiRegistry.all where !seen.contains(entry.command) {
            seen.insert(entry.command)
            print("  \(entry.emoji)  /\(entry.command.padding(toLength: 12, withPad: " ", startingAt: 0)) \u{2192} shi \(entry.command)")
        }
    }
}
