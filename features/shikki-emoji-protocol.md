# Feature: Shikkimoji — The Emoji Language for Shikki

> Emoji-first command interface — faster to type, more expressive, alive.
>
> Status: **SPEC**
> Author: @Daimyo + @t team
> Date: 2026-03-26
> Priority: P1

---

## Brand Family

Shikkimoji lives within the Shikki brand family:

| Product | Role |
|---------|------|
| **Shikki** | BUILD — the CLI orchestrator |
| **Kintsugi** | DESIGN — the design system |
| **WabiSabi** | PRESENT — the iOS app |
| **Moto** | AUTHENTICATE — auth layer |
| **Shikkimoji** | COMMUNICATE — the emoji language |

---

## Phase 1: Team Brainstorm

### @Hanami (UX) — 3 Ideas

**1. Emoji as Muscle Memory, Not Novelty**
Emoji commands must feel like keyboard shortcuts, not gimmicks. The mapping should be *associative* — the emoji instantly evokes the action. A carrot (🥕) for doctor works because of the classic Bugs Bunny "What's up, doc?" — playful, questioning, and instantly memorable. If a user has to think "wait, what was the thermometer one again?", the protocol fails. Every emoji must pass the **3-second recall test**: can you remember what it does after seeing it once?

**2. Text Always Works**
Emoji are an *acceleration layer*, never a gate. Every emoji command MUST have a text equivalent that works identically. The help output (`shikki help` or 📃) should show both side by side. Tab-completion in the shell should suggest emoji after the text command, and vice versa. Non-emoji users lose nothing. Emoji users gain speed and joy.

**3. Discoverability via the Splash Screen**
On startup, Shikki's splash/welcome screen should show the 5 most-used emoji commands for the current user (learned from signal history). New users see the "starter kit" (🥕 🌡️ 📊 🚀 📃). The `shikki menu` TUI should have an emoji cheat sheet panel toggled with `?`. Emoji should also appear in tmux status bar segments — clicking the thermometer segment runs `shikki status`.

---

### @Sensei (Architecture) — 2 Ideas

**1. EmojiRouter as Pre-Parser — Dual Strategy**
Swift ArgumentParser does not natively support emoji as subcommand names (they work in `commandName` strings but are fragile across terminals). The strategy is two-pronged:

**Now: EmojiRouter SPM package** — implement `EmojiRouter` as a standalone SPM package that intercepts `CommandLine.arguments` in `ShikkiCommand.main()` *before* `parseAsRoot()`. The router maps emoji to their text equivalents, rewrites argv, and lets ArgumentParser handle the rest. This keeps ArgumentParser clean and makes emoji a zero-cost layer. Ship this immediately.

**Later: Fork ArgumentParser** — nobody has submitted native emoji subcommand support to Apple's `swift-argument-parser` yet. This is an opportunity. After `EmojiRouter` proves the concept in production, contribute a PR to apple/swift-argument-parser adding first-class emoji command support. We'd be the first to do this.

```swift
// In ShikkiCommand.main(), before parseAsRoot():
let rewritten = EmojiRouter.rewrite(CommandLine.arguments)
// Then parse using rewritten args
```

The `EmojiRouter` is a simple `[String: String]` dictionary with one twist: some emoji carry arguments (e.g., `🧠 "design a caching layer"`), so the router must handle `emoji + rest-of-args` patterns. Emoji that map to commands with arguments pass the remainder through.

**2. Bidirectional Rendering**
Commands that produce output should render emoji in their output too. `shikki status` shows `🌡️ Status` as header. `shikki doctor` shows `🥕 Diagnostics`. This creates visual consistency — the emoji you type is the emoji you see. The `EmojiRegistry` should be the single source of truth for both parsing and rendering, stored in ShikkiKit so both CLI and TUI can use it.

---

### @Shogun (Market) — 2 Ideas

**1. First-Mover in Emoji CLI**
No mainstream CLI tool uses emoji as first-class commands. GitHub CLI (`gh`), Homebrew, npm, cargo — all text-only. Some tools use emoji in *output* (Homebrew's beer mug, cargo's crab), but none accept emoji as *input commands*. Shikki would be the first production CLI where `🚀` actually does something. This is a genuine differentiator. It's the kind of thing that goes viral on dev Twitter/Bluesky — "wait, you can just type a rocket emoji and it deploys?"

**2. Shareability and Word-of-Mouth**
Emoji commands are inherently shareable. A screenshot of `shikki 🚀` deploying code is more memorable than `shikki wave --resume`. This feeds organic discovery. The emoji protocol should be mentioned prominently in the README, with a GIF showing the flow. For conference talks: "Here's our entire deploy workflow" *types rocket emoji* — crowd goes wild.

---

### @Enso (Brand) — 2 Ideas

**1. Emoji as Shikki's Emotional Vocabulary**
Shikki is not a cold tool — it's a professional companion. The emoji protocol makes that tangible. Each emoji is a *word* in Shikki's language. The carrot says "let me check on you" (Bugs Bunny style — "What's up, doc?"). The brain says "let's think together." The rocket says "let's go." This isn't decoration — it's the product's personality expressed through interaction design. The protocol should feel like a conversation shorthand between you and your tool.

**2. The Soul Emojis**
Every brand has core symbols. Shikki's soul emojis are:
- 🥕 — Health (the diagnostic carrot, Bugs Bunny energy — playful and distinctive)
- 🧠 — Intelligence (the team brain, collective thinking)
- 🚀 — Momentum (shipping, executing, moving forward)
- 🌟 — Excellence (the challenge star, pushing quality higher)

These four should appear in the logo, documentation, and splash screen. They ARE Shikki.

---

## Phase 2: Complete Emoji Registry

### Core Registry (@Daimyo's Map)

| Emoji | Command | Args | Description |
|-------|---------|------|-------------|
| 🥕 | `doctor` | — | Diagnostic health check ("What's up, doc?") |
| 🐰 | `doctor` | — | Doctor alias (Bugs Bunny) |
| 🐰🥕 | `doctor` | — | Doctor alias (Bugs Bunny with carrot) |
| 🥕🐰 | `doctor` | — | Doctor alias (carrot + rabbit variant) |
| 🧠 | `brain` | `<prompt>` | Brainstorm with @t team |
| 🌟 | `challenge` | `<prompt>` | Challenge session with @t team (Easter egg!) |
| ⭐ | `challenge` | `<prompt>` | Star alternative for challenge |
| 🌠 | `challenge` | `<prompt>` | Shooting star alternative |
| ✨ | `challenge` | `<prompt>` | Sparkles alternative |
| 💫 | `challenge` | `<prompt>` | Dizzy star alternative |
| 🚀 | `wave` | `[--resume]` | Run next waves/tasks |
| 🤠 | `ingest` | `<prompt>` | Ingest or remember with @Indy |
| 🤔 | `explain` | `<UUID\|prompt>` | Tell me more about that |
| ✅ | `validate` | `<UUID\|prompt>` | Validate this (positive quality signal) |
| ❌ | `invalidate` | `<UUID\|prompt>` | Invalidate this (negative quality signal) |
| 👍 | `like` | `<UUID\|prompt>` | Positive signal (learning feedback) |
| 👎 | `dislike` | `<UUID\|prompt>` | Negative signal (learning feedback) |
| 🌡️ | `status` | — | Orchestrator status overview |
| 📊 | `board` | — | Kanban board |
| ⚡️ | `inbox` | — | Inbox (pending items) |
| 📨 | `inbox` | — | Inbox (alias) |
| 🧙‍♂️ | `wizard` | `<prompt>` | Documentation/wizard helper |
| 🕸️ | `nodes` | — | Network/nodes list |
| 📃 | `help` | — | Show help / emoji cheat sheet |
| 🔍 | `research` | `<links,keyword,prompt>` | Research (mixed: ingest + radar + challenge) |
| ⏰ | `schedule` | — | Schedule (any clock emoji variant) |
| 🕐🕑🕒🕓🕔🕕🕖🕗🕘🕙🕚🕛 | `schedule` | — | Clock emoji variants (all map to schedule) |

### Additional Commands (Team Proposals)

These are daily actions missing from the original map:

| Emoji | Command | Args | Description | Rationale |
|-------|---------|------|-------------|-----------|
| 📦 | `ship` | `[--why "reason"]` | Quality-gated release pipeline | Shipping is a daily action. Package = ready to deliver. |
| ✏️ | `spec` | `<input>` | Generate feature specification | The pencil writes the spec — first stone of Shikki Flow. |
| ⏸️ | `pause` | `<slug>` | Pause a company/session | Universal pause symbol. |
| ▶️ | `restart` | — | Restart/resume session | Universal play symbol. |
| 💾 | `context save` | — | Save context/checkpoint | Floppy disk = save. Universal across generations. |
| 📂 | `context load` | `[id]` | Load/restore context | Folder open = load. |
| 🔄 | `history` | — | Show session/command history | Circular arrows = look back. |
| 🗡️ | `review` | `<PR#>` | @Ronin adversarial review | Katana/sword = @Ronin's weapon. Slices through bad code. |
| 🏗️ | `decide` | `<prompt>` | @Sensei architecture decision | Construction = structural decisions. |
| 🔇 | `focus` | `[duration]` | Focus mode — suppress notifications, queue inbox | Mute = deep work. No interruptions. |
| ⏪ | `undo` | `[UUID]` | Rollback last action/checkpoint | Rewind = undo. |
| 📋 | `backlog` | — | Show backlog | Clipboard = task list. |
| 🔔 | `wake` | — | Wake/ping agents | Bell = wake up. |
| 📝 | `log` | `<message>` | Quick log entry | Notepad = write it down. |
| 🎯 | `codir` | `<prompt>` | Co-direction session | Target = focused direction. |

---

## Phase 3: Feature Brief

### What
An emoji-first command interface for Shikki that maps single emoji (or emoji + arguments) to full CLI commands. Emoji are parsed before ArgumentParser sees them, rewritten to text equivalents, and executed normally. The system is bidirectional: emoji appear in command output too. Named **Shikkimoji** (漆器文字) — the emoji language of Shikki.

### Why
1. **Speed** — One emoji is faster than typing a multi-character command
2. **Expressiveness** — Emoji convey intent and emotion that text commands cannot
3. **Personality** — Makes Shikki feel alive, not like another cold CLI tool
4. **Shareability** — Screenshots of emoji commands are inherently viral
5. **Competitive moat** — No other CLI tool does this. First-mover advantage.

### Who
- Primary: @Daimyo (power user who types 100+ commands/day)
- Secondary: Any Shikki user who wants faster interaction
- Tertiary: People who see Shikki demos and think "I want that"

### Where
- `ShikkiKit/Services/EmojiRouter.swift` — emoji-to-command mapping + argv rewriting
- `ShikkiKit/Services/EmojiRegistry.swift` — single source of truth for all emoji mappings
- `ShikkiCommand.main()` — integration point (before parseAsRoot)
- `TypoCorrector.swift` — extend to handle near-miss emoji (e.g., wrong clock variant)

---

## Phase 4: Business Rules

### BR-EM-01: EmojiRouter Pre-Parser
The `EmojiRouter` intercepts `CommandLine.arguments` before ArgumentParser parsing. It rewrites the first argument if it matches a registered emoji. Remaining arguments pass through unchanged.

### BR-EM-02: EmojiRegistry as Single Source of Truth
All emoji-to-command mappings live in `EmojiRegistry`, a static dictionary in ShikkiKit. Both the CLI (for parsing) and renderers (for output decoration) use this registry. No hardcoded emoji strings anywhere else.

### BR-EM-03: Text Commands Always Work
Every command that has an emoji shortcut MUST continue to work with its text name. Emoji are additive, never a replacement. `shikki doctor` and `shikki 🥕` are identical.

### BR-EM-04: Emoji with Arguments
Some emoji commands accept arguments. The router extracts the emoji from argv[1], maps it to the text command, and passes argv[2...] as arguments to the resolved command.

```
shikki 🧠 "design a caching layer"
→ shikki brain "design a caching layer"

shikki 🤔 abc123-def456
→ shikki explain abc123-def456
```

### BR-EM-05: Clock Emoji Normalization
All Unicode clock face emoji (🕐 through 🕛, plus ⏰ ⏱️ ⏲️) map to `schedule`. The router normalizes any clock-like emoji to the same command.

### BR-EM-06: Validation and Invalidation Signals
✅ and ❌ are quality signals stored in ShikiDB. When invoked with a UUID, they update the `reactions` table for that entity. When invoked with free text, they create a new signal entry. These feed the learning loop and confidence scoring.

**Generic Reaction System Architecture:**
- Every reaction (✅❌👍👎) is linked to a UUID that points to a context entity (task, spec, event, decision, memory, agent output)
- `reactions` table: `id`, `entity_id` (UUID), `entity_type` (task|spec|event|decision|memory|output), `reaction` (emoji), `user_id`, `created_at`, `updated_at`
- Bidirectional: user adds reactions on any entity, system presents entities WITH their reactions
- Reactions are mutable: updating a reaction on the same entity replaces the previous one (one state per user per entity)
- Full chain: entity → reactions → context. Query any entity and get all reactions. Query reactions and get the full entity context.
- Future UI: Slack/iMessage-style reaction display on tasks, agent outputs, specs, decisions
- Reactions update in-place in DB (not append-only — one active reaction per user per entity)
- Feeds: confidence scoring, learning loop, quality metrics, @Metsuke audits

```sql
INSERT INTO quality_signals (entity_id, signal_type, context, created_at)
VALUES ($1, 'validated', $2, NOW());
```

### BR-EM-07: Like/Dislike Signals
👍 and 👎 are lightweight feedback signals (distinct from validation). They record user sentiment without the formal quality gate semantics. Stored in the same `quality_signals` table with `signal_type = 'liked' | 'disliked'`.

### BR-EM-08: Bidirectional Rendering
Commands that produce headers or titles should include their emoji. `shikki status` renders `🌡️ Status`. `shikki doctor` renders `🥕 Diagnostics`. The renderer looks up the emoji from `EmojiRegistry` by command name.

### BR-EM-09: Help Output
`shikki help` (or `shikki 📃`) shows a two-column table: emoji on the left, text command + description on the right. Grouped by category (diagnostics, workflow, signals, navigation).

### BR-EM-10: Splash Screen Integration
The Shikki splash/welcome screen shows the user's top 5 most-used emoji commands. New users see the starter kit: 🥕 🌡️ 📊 🚀 📃. Usage frequency is tracked per-user in ShikiDB.

### BR-EM-11: Typo Tolerance for Emoji
If a user types an unrecognized emoji, the `TypoCorrector` checks if it's visually similar to a registered emoji (e.g., same Unicode category). If close, suggest the correct one. If no match, fall through to standard text typo correction.

### BR-EM-12: Multi-Byte Safety
Emoji are multi-byte Unicode. The router must compare using `String` equality (not byte-level), handle variation selectors (VS16 / `\uFE0F`), and handle ZWJ sequences (🧙‍♂️ is `🧙 + ZWJ + ♂️`). Normalize both the input and registry keys using `.precomposedStringWithCanonicalMapping` before comparison.

### BR-EM-13: Terminal Compatibility
Some terminals render emoji as double-width, some as single. The protocol does not attempt to fix terminal rendering — it works at the argument level. Emoji in output headers use the ANSI-aware padding already in StatusRenderer/ShipRenderer.

### BR-EM-14: Focus Mode
🔇 enters focus mode with explicit duration support:
- `shikki 🔇 20m` — focus for 20 minutes
- `shikki 🔇` (no duration) — show elapsed time since focus mode was enabled
- At timer expiry: popup "Want more? Y/N". Y extends by the same duration, N exits focus mode and suggests a ☕ break
- Focus mode suppresses ntfy notifications, queues inbox items instead of interrupting, and sets a tmux status indicator
- Manual toggle: `shikki 🔇` again exits focus mode early (same behavior as before)

### BR-EM-15: Undo via Checkpoint
⏪ triggers checkpoint-based undo. Without arguments, it shows the last 5 checkpoints. With a UUID, it restores that specific checkpoint. Delegates to `CheckpointManager.restore()`.

### BR-EM-16: Never Auto-Execute Destructive Emoji
Following BR-43 (never auto-correct to "stop"), the emoji router must NEVER auto-correct a mistyped emoji to a destructive command. Destructive commands: `stop`, `invalidate`, `undo`. If fuzzy match points to these, require exact match.

### BR-EM-17: Shell Alias Generation
`shikki doctor --emit-aliases` (or a dedicated setup command) can generate shell aliases for users who prefer typing `:carrot:` instead of pasting emoji. Optional convenience, not required for core protocol.

### BR-EM-18: Carrot/Rabbit Aliases
🥕, 🐰, 🐰🥕, and 🥕🐰 all map to `doctor`. The Bugs Bunny "What's up, doc?" reference is the soul of this command — the rabbit and carrot variants are easter eggs for users who know the joke. All four are registered in `EmojiRegistry` and treated as first-class aliases.

### BR-EM-19: Reaction System
Slack/iMessage-style reactions on tasks, agent outputs, and decisions. A reaction (using any signal emoji) can target a specific sub-task UUID:

```
shikki ✅ <task-uuid>   # validate a specific task
shikki 👍 <output-uuid> # like a specific agent output
```

Reactions are stored in `quality_signals` and feed the learning loop. Sub-task targeting means reactions are granular — reacting to a sub-task does not automatically react to its parent.

---

## Phase 5: Architecture

### EmojiRegistry (ShikkiKit)

```swift
public enum EmojiRegistry {
    public struct Entry: Sendable {
        public let emoji: String
        public let command: String
        public let category: Category
        public let acceptsArgs: Bool
        public let description: String
    }

    public enum Category: String, Sendable, CaseIterable {
        case diagnostic   // 🥕 🐰 🌡️ 🕸️
        case workflow      // 🚀 📦 ✏️ ⏸️ ▶️ 🔇
        case intelligence  // 🧠 🌟 🤔 🤠 🧙‍♂️ 🔍 🎯 🏗️
        case signals       // ✅ ❌ 👍 👎
        case navigation    // 📊 ⚡️ 📨 📋 🔄 📝 🔔
        case meta          // 📃 ⏰ 💾 📂 ⏪
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
              description: "Focus mode (e.g. 🔇 20m)"),

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
              description: "Invalidate"),
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
              description: "Undo/rollback"),
    ]

    /// Fast lookup: emoji string → Entry
    public static let byEmoji: [String: Entry] = {
        var map: [String: Entry] = [:]
        for entry in all {
            map[entry.emoji] = entry
        }
        // Clock variants all → schedule
        let clockFaces = "🕐🕑🕒🕓🕔🕕🕖🕗🕘🕙🕚🕛⏱️⏲️"
        let scheduleEntry = Entry(emoji: "⏰", command: "schedule",
                                   category: .meta, acceptsArgs: false,
                                   description: "Schedule")
        for scalar in clockFaces.unicodeScalars {
            let char = String(scalar)
            if char.count > 0 { map[char] = scheduleEntry }
        }
        return map
    }()

    /// Reverse lookup: command name → emoji (first match)
    public static let byCommand: [String: String] = {
        var map: [String: String] = [:]
        for entry in all {
            if map[entry.command] == nil {
                map[entry.command] = entry.emoji
            }
        }
        return map
    }()
}
```

### EmojiRouter (ShikkiKit)

```swift
public enum EmojiRouter {
    /// Rewrite argv if the first argument (after binary name) is a registered emoji.
    /// Returns the original args if no emoji match.
    public static func rewrite(_ args: [String]) -> [String] {
        guard args.count >= 2 else { return args }

        let candidate = args[1]
            .precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespaces)

        // Strip variation selector (VS16) for comparison
        let normalized = candidate.replacingOccurrences(of: "\u{FE0F}", with: "")

        // Try exact match first, then normalized
        let entry = EmojiRegistry.byEmoji[candidate]
            ?? EmojiRegistry.byEmoji[normalized]

        guard let entry else { return args }

        // Rewrite: [binary, emoji, ...rest] → [binary, command, ...rest]
        var rewritten = args
        rewritten[1] = entry.command
        return rewritten
    }
}
```

### Integration Point (ShikkiCommand.swift)

```swift
// In ShikkiCommand.main(), first line:
static func main() async {
    // BR-EM-01: Emoji pre-parser
    let args = EmojiRouter.rewrite(CommandLine.arguments)
    // ... use rewritten args for parsing
}
```

### Signal Storage Schema (ShikiDB)

```sql
-- quality_signals table (extends existing schema)
CREATE TABLE IF NOT EXISTS quality_signals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entity_id TEXT,           -- UUID of the target entity, or NULL for free-text
    signal_type TEXT NOT NULL, -- 'validated' | 'invalidated' | 'liked' | 'disliked'
    context TEXT,             -- free text / prompt that accompanied the signal
    source TEXT DEFAULT 'cli', -- 'cli' | 'tui' | 'push' | 'ios'
    created_by TEXT DEFAULT 'daimyo',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_quality_signals_entity ON quality_signals(entity_id);
CREATE INDEX idx_quality_signals_type ON quality_signals(signal_type);
```

---

## Phase 6: Test Plan

### Unit Tests (EmojiRouterTests.swift)

| # | Test | Validates |
|---|------|-----------|
| 1 | `testRewriteKnownEmoji` — 🥕 → doctor | BR-EM-01 basic routing |
| 2 | `testRewriteEmojiWithArgs` — 🧠 "prompt" → brain "prompt" | BR-EM-04 arg passthrough |
| 3 | `testRewriteUnknownEmoji` — 🦄 → unchanged | BR-EM-01 no-match passthrough |
| 4 | `testRewriteTextCommand` — "doctor" → unchanged | BR-EM-03 text commands unaffected |
| 5 | `testRewriteEmptyArgs` — [] → [] | Edge case |
| 6 | `testRewriteBinaryOnly` — ["shikki"] → ["shikki"] | Edge case |
| 7 | `testClockVariants` — 🕐🕑🕒...🕛 all → schedule | BR-EM-05 clock normalization |
| 8 | `testVariationSelectorStripping` — ⏰ with/without VS16 | BR-EM-12 multi-byte safety |
| 9 | `testZWJSequence` — 🧙‍♂️ (with ZWJ) → wizard | BR-EM-12 ZWJ handling |
| 10 | `testMultipleEmojiAliases` — ⚡️ and 📨 both → inbox | BR-EM-02 alias support |
| 11 | `testRabbitAlias` — 🐰 → doctor | BR-EM-18 Bugs Bunny alias |
| 12 | `testRabbitCarrotAlias` — 🐰🥕 → doctor | BR-EM-18 compound alias |
| 13 | `testCarrotRabbitAlias` — 🥕🐰 → doctor | BR-EM-18 compound alias variant |

### Unit Tests (EmojiRegistryTests.swift)

| # | Test | Validates |
|---|------|-----------|
| 14 | `testAllEntriesHaveUniqueEmoji` — no duplicate emoji keys (excluding intentional aliases) | BR-EM-02 registry integrity |
| 15 | `testByCommandReverseLookup` — every command maps back to an emoji | BR-EM-08 bidirectional |
| 16 | `testCategoryCoverage` — every category has at least one entry | BR-EM-02 completeness |
| 17 | `testAllCommandsExistInShikki` — registry commands match known subcommands | BR-EM-03 sync check |

### Unit Tests (Signal Storage)

| # | Test | Validates |
|---|------|-----------|
| 18 | `testValidateSignalCreatesEntry` — ✅ + UUID → DB insert | BR-EM-06 |
| 19 | `testInvalidateSignalCreatesEntry` — ❌ + UUID → DB insert | BR-EM-06 |
| 20 | `testLikeSignalCreatesEntry` — 👍 + text → DB insert | BR-EM-07 |
| 21 | `testDislikeSignalCreatesEntry` — 👎 + text → DB insert | BR-EM-07 |

### Integration Tests

| # | Test | Validates |
|---|------|-----------|
| 22 | `testEndToEndEmojiDoctor` — full `shikki 🥕` invocation | Full pipeline |
| 23 | `testEndToEndEmojiWithPrompt` — `shikki 🧠 "test"` invocation | Args passthrough |
| 24 | `testEmojiInOutputHeaders` — status output contains 🌡️ | BR-EM-08 bidirectional rendering |
| 25 | `testHelpShowsEmojiTable` — help output contains emoji column | BR-EM-09 |
| 26 | `testFocusModeWithDuration` — 🔇 10s starts timer, expires with popup (use 10s for test speed) | BR-EM-14 |
| 27 | `testFocusModeNoArgShowsElapsed` — 🔇 with no args shows elapsed | BR-EM-14 |
| 28 | `testFocusModeToggle` — 🔇 then 🔇 again disables | BR-EM-14 |
| 29 | `testDestructiveEmojiNoAutoCorrect` — near-miss to ❌ rejected | BR-EM-16 safety |
| 30 | `testReactionTargetsSubTask` — ✅ <subtask-uuid> stored with sub-task reference | BR-EM-19 |

### Snapshot Tests

| # | Test | Validates |
|---|------|-----------|
| 31 | `testHelpEmojiCheatSheet` — golden snapshot of help output | BR-EM-09 visual regression |
| 32 | `testSplashStarterKit` — splash shows 🥕 🌡️ 📊 🚀 📃 | BR-EM-10 |

---

## Implementation Waves

### Wave 1: Core Router (~200 LOC, ~17 tests)
- `EmojiRegistry.swift` — full registry with all entries including 🐰 aliases
- `EmojiRouter.swift` — argv rewriter with VS16/ZWJ normalization
- Integration in `ShikkiCommand.main()` — 3 lines
- Tests: #1-17

### Wave 2: Signal Commands (~150 LOC, ~4 tests)
- `ValidateCommand.swift`, `InvalidateCommand.swift`, `LikeCommand.swift`, `DislikeCommand.swift`
- `QualitySignalService.swift` — DB persistence with sub-task targeting (BR-EM-19)
- `quality_signals` migration
- Tests: #18-21

### Wave 3: Bidirectional Rendering + Help (~100 LOC, ~4 tests)
- Update renderers to use `EmojiRegistry.byCommand` for headers
- Emoji cheat sheet in help output
- Splash screen starter kit
- Tests: #24-25, #31-32

### Wave 4: New Commands (~250 LOC, ~7 tests)
- `FocusCommand.swift` (🔇) with duration + expiry popup + ☕ suggestion
- `UndoCommand.swift` (⏪)
- `BrainCommand.swift` (🧠), `ChallengeCommand.swift` (🌟)
- Tests: #22-23, #26-30

### Wave 5: Polish (~50 LOC)
- Shell alias generation (BR-EM-17)
- Splash screen personalization (top 5 used)
- TypoCorrector emoji extension (BR-EM-11)
- Fork ArgumentParser — submit PR to apple/swift-argument-parser for native emoji subcommand support

---

## Appendix: Emoji Quick Reference Card

```
DIAGNOSTICS          WORKFLOW             INTELLIGENCE
🥕  doctor           🚀  wave/run         🧠  brainstorm
🐰  doctor (alias)   📦  ship             🌟  challenge
🌡️  status           ✏️  spec             🤔  explain
🕸️  nodes            ⏸️  pause            🤠  ingest
                     ▶️  restart          🧙‍♂️  wizard
SIGNALS              🔇  focus [dur]      🔍  research
✅  validate                              🎯  co-direct
❌  invalidate       NAVIGATION            🏗️  decide
👍  like             📊  board             🗡️  review
👎  dislike          ⚡️  inbox
                     📋  backlog
META                 🔄  history
📃  help             📝  log
⏰  schedule         🔔  wake
💾  save context
📂  load context
⏪  undo
```

> "The best interface is the one that feels like a conversation."
> — Shikkimoji (漆器文字), v1
