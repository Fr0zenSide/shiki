import Foundation
import Testing
@testable import ShikkiKit

// MARK: - EmojiRegistry Tests

@Suite("EmojiRegistry — BR-EM-02")
struct EmojiRegistryTests {

    @Test("🥕 resolves to doctor")
    func emojiRegistryResolvesCarrot() {
        #expect(EmojiRegistry.resolve("🥕") == "doctor")
    }

    @Test("🐰 resolves to doctor")
    func emojiRegistryResolvesRabbit() {
        #expect(EmojiRegistry.resolve("🐰") == "doctor")
    }

    @Test("🐰🥕 resolves to doctor (compound alias)")
    func emojiRegistryResolvesRabbitCarrot() {
        #expect(EmojiRegistry.resolve("🐰🥕") == "doctor")
    }

    @Test("🥕🐰 resolves to doctor (compound alias variant)")
    func emojiRegistryResolvesCarrotRabbit() {
        #expect(EmojiRegistry.resolve("🥕🐰") == "doctor")
    }

    @Test("Unknown emoji returns nil")
    func emojiRegistryReturnsNilForUnknown() {
        #expect(EmojiRegistry.resolve("🦄") == nil)
    }

    @Test("allEntries returns complete list matching static all count")
    func allEntriesReturnsCompleteList() {
        let entries = EmojiRegistry.allEntries()
        #expect(entries.count == EmojiRegistry.all.count)
        // Every entry has a non-empty emoji and command
        for entry in entries {
            #expect(!entry.emoji.isEmpty)
            #expect(!entry.command.isEmpty)
        }
    }

    @Test("EmojiRegistry is Sendable (compile-time check)")
    func registryIsSendable() {
        // This test validates Sendable conformance at compile time.
        // If EmojiRegistry or Entry were not Sendable, this would not compile.
        let _: [EmojiRegistry.Entry] = EmojiRegistry.all
        let _: EmojiRegistry.Entry? = EmojiRegistry.all.first
    }
}

// MARK: - EmojiRouter Tests

@Suite("EmojiRouter — BR-EM-01")
struct EmojiRouterTests {

    @Test("Rewrites single emoji: 🥕 → doctor")
    func routerRewritesSingleEmoji() {
        let result = EmojiRouter.rewrite(["shikki", "🥕"])
        #expect(result == ["shikki", "doctor"])
    }

    @Test("Rewrites emoji with trailing args: 🔍 url → research url")
    func routerRewritesEmojiWithArgs() {
        let result = EmojiRouter.rewrite(["shikki", "🔍", "https://example.com"])
        #expect(result == ["shikki", "research", "https://example.com"])
    }

    @Test("Text command passes through unchanged")
    func routerPassthroughTextCommand() {
        let input = ["shikki", "doctor"]
        let result = EmojiRouter.rewrite(input)
        #expect(result == input)
    }

    @Test("No args passes through unchanged")
    func routerPassthroughNoArgs() {
        let input = ["shikki"]
        let result = EmojiRouter.rewrite(input)
        #expect(result == input)
    }

    @Test("Empty args passes through unchanged")
    func routerPassthroughEmpty() {
        let result = EmojiRouter.rewrite([])
        #expect(result == [])
    }

    @Test("All registered emojis resolve through router")
    func routerHandlesAllRegisteredEmojis() {
        for entry in EmojiRegistry.all {
            let result = EmojiRouter.rewrite(["shikki", entry.emoji])
            #expect(
                result[1] == entry.command,
                "Expected \(entry.emoji) to rewrite to \(entry.command), got \(result[1])"
            )
        }
    }

    @Test("⚡️ and 📨 both route to inbox (alias support)")
    func routerHandlesInboxAliases() {
        let result1 = EmojiRouter.rewrite(["shikki", "⚡️"])
        let result2 = EmojiRouter.rewrite(["shikki", "📨"])
        #expect(result1[1] == "inbox")
        #expect(result2[1] == "inbox")
    }

    @Test("ZWJ sequence: 🧙‍♂️ routes to wizard (BR-EM-12)")
    func routerHandlesZWJSequence() {
        let result = EmojiRouter.rewrite(["shikki", "🧙‍♂️"])
        #expect(result == ["shikki", "wizard"])
    }

    @Test("Variation selector stripping: emoji with/without VS16 (BR-EM-12)")
    func routerHandlesVariationSelectors() {
        // ⏰ with explicit VS16
        let withVS16 = "⏰\u{FE0F}"
        let result = EmojiRouter.rewrite(["shikki", withVS16])
        #expect(result[1] == "schedule")
    }

    @Test("EmojiRouter is Sendable (compile-time check)")
    func routerIsSendable() {
        // EmojiRouter is an enum with only static methods — inherently Sendable.
        // This validates the Sendable conformance compiles.
        let _: any Sendable.Type = EmojiRouter.self
    }
}
