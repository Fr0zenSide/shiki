import Testing
@testable import ShikkiKit

// MARK: - EmojiRendererTests

@Suite("EmojiRenderer — bidirectional rendering and help table")
struct EmojiRendererTests {

    // MARK: Reverse Lookup

    @Test("Reverse lookup: doctor returns 🥕")
    func testReverseLookup_doctor_returns_carrot() {
        let emoji = EmojiRenderer.emojiForCommand("doctor")
        #expect(emoji == "🥕")
    }

    @Test("Reverse lookup: unknown command returns nil")
    func testUnknownCommand_returns_nil() {
        let emoji = EmojiRenderer.emojiForCommand("nonexistent-xyz-command")
        #expect(emoji == nil)
    }

    // MARK: renderCommandWithEmoji

    @Test("renderCommandWithEmoji formats known command as 'command (emoji)'")
    func testRenderCommandWithEmoji_formats_correctly() {
        let result = EmojiRenderer.renderCommandWithEmoji("doctor")
        #expect(result == "doctor (🥕)")
    }

    @Test("renderCommandWithEmoji returns plain name for unknown command")
    func testRenderCommandWithEmoji_unknown_returns_plain() {
        let result = EmojiRenderer.renderCommandWithEmoji("unknown-cmd")
        #expect(result == "unknown-cmd")
    }

    // MARK: renderHelpTable

    @Test("renderHelpTable contains all commands from registry")
    func testRenderHelpTable_containsAllCommands() {
        let table = EmojiRenderer.renderHelpTable()

        // Collect unique commands in the registry
        let uniqueCommands = Set(EmojiRegistry.all.map(\.command))
        for command in uniqueCommands {
            #expect(table.contains(command), "Help table missing command: \(command)")
        }
    }

    @Test("renderHelpTable contains all category headers")
    func testRenderHelpTable_containsAllCategories() {
        let table = EmojiRenderer.renderHelpTable()
        for category in EmojiRegistry.Category.allCases {
            let header = category.rawValue.prefix(1).uppercased() + category.rawValue.dropFirst()
            #expect(table.contains(header), "Help table missing category header: \(header)")
        }
    }
}
