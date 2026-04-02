import Testing
@testable import ShikkiKit

@Suite("EmojiRouter — Emoji→Command Rewriting (BR-EM-01)")
struct EmojiRouterTests {

    // MARK: - Single Emoji Resolution

    @Test("Single emoji resolves to correct command — 🌟 → challenge")
    func singleEmojiChallenge() {
        let result = EmojiRouter.rewrite(["shi", "🌟"])
        #expect(result == ["shi", "challenge"])
    }

    @Test("Single emoji resolves — 🥕 → doctor")
    func singleEmojiDoctor() {
        let result = EmojiRouter.rewrite(["shi", "🥕"])
        #expect(result == ["shi", "doctor"])
    }

    @Test("Single emoji resolves — 🚀 → wave")
    func singleEmojiWave() {
        let result = EmojiRouter.rewrite(["shi", "🚀"])
        #expect(result == ["shi", "wave"])
    }

    @Test("Single emoji resolves — 🧠 → brain")
    func singleEmojiBrain() {
        let result = EmojiRouter.rewrite(["shi", "🧠"])
        #expect(result == ["shi", "brain"])
    }

    @Test("Single emoji resolves — 📊 → board")
    func singleEmojiBoard() {
        let result = EmojiRouter.rewrite(["shi", "📊"])
        #expect(result == ["shi", "board"])
    }

    // MARK: - Passthrough (Non-Emoji Input)

    @Test("Text command passes through unchanged")
    func textCommandPassthrough() {
        let result = EmojiRouter.rewrite(["shi", "doctor"])
        #expect(result == ["shi", "doctor"])
    }

    @Test("Unknown emoji passes through unchanged")
    func unknownEmojiPassthrough() {
        let result = EmojiRouter.rewrite(["shi", "💀"])
        #expect(result == ["shi", "💀"])
    }

    @Test("Empty args returns unchanged")
    func emptyArgsPassthrough() {
        let result = EmojiRouter.rewrite(["shi"])
        #expect(result == ["shi"])
    }

    @Test("No args returns unchanged")
    func noArgsPassthrough() {
        let result = EmojiRouter.rewrite([])
        #expect(result == [])
    }

    // MARK: - Args Preservation

    @Test("Emoji with trailing args preserves them")
    func emojiWithTrailingArgs() {
        let result = EmojiRouter.rewrite(["shi", "🔍", "CRDTs"])
        #expect(result == ["shi", "research", "CRDTs"])
    }

    @Test("Emoji with multiple trailing args preserves all")
    func emojiWithMultipleArgs() {
        let result = EmojiRouter.rewrite(["shi", "✏️", "new-feature", "--force"])
        #expect(result == ["shi", "spec", "new-feature", "--force"])
    }

    // MARK: - Mixed Emoji + Text

    @Test("Multi-character emoji string does not resolve (not single char)")
    func multiCharStringNoResolve() {
        // Compound emojis like 🐰🥕 in a single arg are multi-character
        // EmojiRouter only handles single-character emoji in args[1]
        let result = EmojiRouter.rewrite(["shi", "🐰🥕"])
        // 🐰🥕 is two characters, so candidate.count != 1, passes through
        #expect(result == ["shi", "🐰🥕"])
    }

    // MARK: - Registry Coverage

    @Test("Registry contains all expected categories")
    func registryCategories() {
        let categories = Set(EmojiRegistry.all.map { $0.category })
        #expect(categories.contains(.diagnostic))
        #expect(categories.contains(.workflow))
        #expect(categories.contains(.intelligence))
        #expect(categories.contains(.signals))
        #expect(categories.contains(.navigation))
        #expect(categories.contains(.meta))
    }

    @Test("Registry byEmoji lookup returns entry for registered emoji")
    func registryByEmojiLookup() {
        let entry = EmojiRegistry.byEmoji["🥕".precomposedStringWithCanonicalMapping]
        #expect(entry != nil)
        #expect(entry?.command == "doctor")
    }

    @Test("Registry byCommand returns primary emoji for command")
    func registryByCommandLookup() {
        let emoji = EmojiRegistry.byCommand["doctor"]
        #expect(emoji == "🥕")
    }

    @Test("Registry resolve handles VS16 normalization")
    func registryResolveVS16() {
        // ✏️ has VS16 (\u{FE0F})
        let command = EmojiRegistry.resolve("✏️")
        #expect(command == "spec")
    }

    @Test("Registry allEntries returns non-empty list")
    func registryAllEntries() {
        let entries = EmojiRegistry.allEntries()
        #expect(entries.count > 20)
    }

    @Test("Registry starterKit has exactly 5 items")
    func registryStarterKit() {
        #expect(EmojiRegistry.starterKit.count == 5)
        #expect(EmojiRegistry.starterKit[0].emoji == "🥕")
        #expect(EmojiRegistry.starterKit[0].command == "doctor")
    }

    @Test("Clock face emoji resolves to schedule")
    func clockFaceResolvesToSchedule() {
        let command = EmojiRegistry.resolve("🕐")
        #expect(command == "schedule")
    }

    @Test("Shell alias generation produces valid output")
    func shellAliasGeneration() {
        let aliases = EmojiRegistry.generateShellAliases()
        #expect(aliases.contains("alias sk-doctor='shi doctor'"))
        #expect(aliases.contains("sk-🥕"))
    }

    @Test("Destructive entries are marked correctly")
    func destructiveEntries() {
        let destructive = EmojiRegistry.all.filter { $0.isDestructive }
        #expect(destructive.count >= 2)
        let commands = destructive.map { $0.command }
        #expect(commands.contains("invalidate"))
        #expect(commands.contains("undo"))
    }
}
