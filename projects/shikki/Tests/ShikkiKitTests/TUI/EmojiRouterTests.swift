import Testing
@testable import ShikkiKit

@Suite("EmojiRouter+Registry — Extended TUI Routing (BR-EM-01/02)")
struct EmojiRouterExtendedTests {

    // MARK: - Router: Single Emoji Resolution

    @Test("🌟 rewrites to challenge")
    func singleEmojiChallenge() {
        let result = EmojiRouter.rewrite(["shi", "🌟"])
        #expect(result == ["shi", "challenge"])
    }

    @Test("🚀 rewrites to wave")
    func singleEmojiWave() {
        let result = EmojiRouter.rewrite(["shi", "🚀"])
        #expect(result == ["shi", "wave"])
    }

    @Test("🧠 rewrites to brain")
    func singleEmojiBrain() {
        let result = EmojiRouter.rewrite(["shi", "🧠"])
        #expect(result == ["shi", "brain"])
    }

    @Test("📊 rewrites to board")
    func singleEmojiBoard() {
        let result = EmojiRouter.rewrite(["shi", "📊"])
        #expect(result == ["shi", "board"])
    }

    // MARK: - Router: Passthrough (Non-Emoji Input)

    @Test("Unknown emoji passes through unchanged")
    func unknownEmojiPassthrough() {
        let result = EmojiRouter.rewrite(["shi", "💀"])
        #expect(result == ["shi", "💀"])
    }

    @Test("Multi-character emoji string does not resolve (not single char)")
    func multiCharStringNoResolve() {
        // Compound emojis like 🐰🥕 in a single arg are two characters
        // EmojiRouter only handles single-character emoji in args[1]
        let result = EmojiRouter.rewrite(["shi", "🐰🥕"])
        #expect(result == ["shi", "🐰🥕"])
    }

    // MARK: - Router: Args Preservation

    @Test("Emoji with multiple trailing args preserves all")
    func emojiWithMultipleArgs() {
        let result = EmojiRouter.rewrite(["shi", "✏️", "new-feature", "--force"])
        #expect(result == ["shi", "spec", "new-feature", "--force"])
    }

    // MARK: - Registry: Category Coverage

    @Test("Registry contains all six expected categories")
    func registryCategories() {
        let categories = Set(EmojiRegistry.all.map { $0.category })
        #expect(categories.contains(.diagnostic))
        #expect(categories.contains(.workflow))
        #expect(categories.contains(.intelligence))
        #expect(categories.contains(.signals))
        #expect(categories.contains(.navigation))
        #expect(categories.contains(.meta))
        #expect(categories.count == 6)
    }

    // MARK: - Registry: Lookup Methods

    @Test("byEmoji lookup returns entry for registered emoji")
    func registryByEmojiLookup() {
        let entry = EmojiRegistry.byEmoji["🥕".precomposedStringWithCanonicalMapping]
        #expect(entry != nil)
        #expect(entry?.command == "doctor")
    }

    @Test("byCommand returns primary emoji for command")
    func registryByCommandLookup() {
        let emoji = EmojiRegistry.byCommand["doctor"]
        #expect(emoji == "🥕")
    }

    @Test("resolve handles VS16 normalization (✏️ → spec)")
    func registryResolveVS16() {
        let command = EmojiRegistry.resolve("✏️")
        #expect(command == "spec")
    }

    @Test("resolve returns nil for unregistered emoji")
    func registryResolveUnknown() {
        #expect(EmojiRegistry.resolve("🦄") == nil)
    }

    @Test("lookup by Character finds registered entry")
    func registryLookupCharacter() {
        let entry = EmojiRegistry.lookup("🚀" as Character)
        #expect(entry != nil)
        #expect(entry?.command == "wave")
    }

    @Test("lookup by Character returns nil for unregistered")
    func registryLookupCharacterUnknown() {
        let entry = EmojiRegistry.lookup("💀" as Character)
        #expect(entry == nil)
    }

    // MARK: - Registry: Clock Face Variants

    @Test("All 12 clock face emojis resolve to schedule")
    func clockFacesResolveToSchedule() {
        let clocks = ["🕐", "🕑", "🕒", "🕓", "🕔", "🕕",
                      "🕖", "🕗", "🕘", "🕙", "🕚", "🕛"]
        for clock in clocks {
            #expect(
                EmojiRegistry.resolve(clock) == "schedule",
                "\(clock) should resolve to schedule"
            )
        }
    }

    @Test("Timer emojis resolve to schedule")
    func timerEmojisResolveToSchedule() {
        #expect(EmojiRegistry.resolve("⏱️") == "schedule")
        #expect(EmojiRegistry.resolve("⏲️") == "schedule")
    }

    // MARK: - Registry: Starter Kit

    @Test("Starter kit has exactly 5 items in correct order")
    func registryStarterKit() {
        #expect(EmojiRegistry.starterKit.count == 5)
        #expect(EmojiRegistry.starterKit[0] == (emoji: "🥕", command: "doctor"))
        #expect(EmojiRegistry.starterKit[1] == (emoji: "🌡️", command: "status"))
        #expect(EmojiRegistry.starterKit[2] == (emoji: "📊", command: "board"))
        #expect(EmojiRegistry.starterKit[3] == (emoji: "🚀", command: "wave"))
        #expect(EmojiRegistry.starterKit[4] == (emoji: "📃", command: "help"))
    }

    // MARK: - Registry: Shell Aliases

    @Test("Shell alias generation produces valid output")
    func shellAliasGeneration() {
        let aliases = EmojiRegistry.generateShellAliases()
        #expect(aliases.contains("alias sk-doctor='shi doctor'"))
        #expect(aliases.contains("alias sk-wave='shi wave'"))
        #expect(aliases.contains("sk-🥕"))
    }

    @Test("Shell alias generation deduplicates text aliases")
    func shellAliasDeduplicate() {
        let aliases = EmojiRegistry.generateShellAliases()
        // "doctor" appears multiple times in registry (🥕, 🐰, 🐰🥕, 🥕🐰)
        // but sk-doctor alias should appear only once
        let lines = aliases.components(separatedBy: "\n")
        let doctorAliases = lines.filter { $0 == "alias sk-doctor='shi doctor'" }
        #expect(doctorAliases.count == 1)
    }

    // MARK: - Registry: Destructive Entries

    @Test("Destructive entries are flagged correctly")
    func destructiveEntries() {
        let destructive = EmojiRegistry.all.filter { $0.isDestructive }
        #expect(destructive.count >= 2)
        let commands = Set(destructive.map { $0.command })
        #expect(commands.contains("invalidate"))
        #expect(commands.contains("undo"))
    }

    @Test("Non-destructive entries are the majority")
    func nonDestructiveEntries() {
        let nonDestructive = EmojiRegistry.all.filter { !$0.isDestructive }
        let destructive = EmojiRegistry.all.filter { $0.isDestructive }
        #expect(nonDestructive.count > destructive.count)
    }
}
