# Shikkimoji Chaining + @Agent Actions

> Addendum to [Shikkimoji](shikki-emoji-protocol.md) — multi-command chains with agent targeting.
>
> Status: **ANALYSIS** (pre-spec brainstorm synthesis)
> Author: @t team (full brainstorm)
> Date: 2026-03-26
> Parent: `features/shikki-emoji-protocol.md`

---

## The Idea

Chain multiple emoji in a single invocation, with optional `@agent` targeting:

```
shikki 🌟🧠@t "is this a good idea?"     # challenge + brainstorm with team
shikki 🔍🌟@t https://github.com/foo/bar  # research + challenge + brainstorm
shikki ✅🚀                                # validate + run next waves
shikki 🧠@Sensei "should we use CRDTs?"    # brainstorm with Sensei only
shikki 🗡️@Ronin                            # adversarial review by Ronin
shikki 🌟🧠📦@t "new payment system"       # challenge + brainstorm + ship (triple)
```

---

## @t Team Analysis

### @Sensei (Architecture) — 2 Ideas

**1. Left-to-Right EmojiChainParser**

The `EmojiRouter` currently handles single-emoji rewriting. Chaining requires a new layer: `EmojiChainParser`. It consumes a string left-to-right, greedily matching the longest registered emoji at each position (greedy-longest-match, same principle as lexer tokenization). This handles ZWJ sequences correctly — `🧙‍♂️` is longer than `🧙` so it matches first.

```swift
public struct EmojiChain {
    public let steps: [ChainStep]
    public let target: AgentTarget?    // @t, @Sensei, etc.
    public let args: String?           // trailing text/URLs
}

public struct ChainStep {
    public let entry: EmojiRegistry.Entry
}

public enum AgentTarget: Sendable {
    case team                          // @t, @shi, @team
    case agent(String)                 // @Sensei, @Ronin, etc.
}
```

The parser splits the first argv token into: `[emoji...][@target] [args...]`. The `@` symbol is the boundary between emoji chain and agent target. Everything after the emoji+target token is args.

**2. Sequential vs Parallel Execution: Pipeline Model**

Chains execute **left-to-right, sequentially**, with output piping. Each step receives the previous step's result as context:

- Step 1 (`🔍 research`) runs, produces a research summary
- Step 2 (`🌟 challenge`) receives research summary as input context
- Step 3 (`🧠@t brainstorm`) receives challenge output as input context

This is a **pipeline**, not parallel execution. Parallel would be chaotic — you can't brainstorm about research you haven't done yet. The pipeline model means each `ChainStep` has an `input: StepOutput?` and produces an `output: StepOutput`.

Exception: signal emoji (✅❌👍👎) at the start of a chain apply to the **final** output, not as a step. `✅🚀` means "validate then run" — the validate applies to current context, not to the rocket's output.

---

### @Hanami (UX) — 2 Ideas

**1. Chain Progress Visualization**

During a chain, the user sees a Claude Code wave-style progress display:

```
● Wave 1/3  🔍 research ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ done
▸ Wave 2/3  🌟 challenge ─────────────────────────────────────────
○ Wave 3/3  🧠@t brainstorm

Challenging https://github.com/foo/bar...
```

Each step shows: `✓` (done), `▸` (active), `○` (pending), `✗` (failed). The active step's output streams below the pipeline bar. When a step completes, its summary collapses to one line, and the next step begins.

**Auto-refresh is adaptive**: short chains (2 steps, fast commands) refresh every 10 seconds; complex chains (3+ steps, agent calls) refresh every 30 seconds to avoid terminal noise. In TUI mode, the pipeline bar stays pinned at top. In raw terminal mode, it reprints at each refresh interval.

**2. Error Handling: Fail-Forward with Escape**

If step 2 of 3 fails:
- Show the error inline under that step's position in the pipeline bar
- Ask: "Step 2 failed. [S]kip to step 3 / [R]etry / [A]bort?" (single keypress)
- Default: **skip** (fail-forward). The next step receives a `StepOutput.skipped(reason:)` instead of real output
- In non-interactive mode (piped/CI): always skip forward, log the failure

This prevents a chain from being all-or-nothing. A failed research step shouldn't block the brainstorm — it just means the brainstorm has less context.

---

### @Ronin (Adversarial) — 2 Concerns

**1. Emoji Boundary Detection Is Hard**

Unicode emoji are not single codepoints. Problems:
- `🌟🧠` — two emoji, easy to split (each is one scalar + optional VS16)
- `👨‍👩‍👧‍👦` — one emoji, four people joined by ZWJ. If any sub-emoji is registered, greedy parsing could consume the wrong thing
- `🌟🌟🌟` — three stars. Is this "challenge, challenge, challenge" (triple retry?) or an error? Or "challenge with emphasis"?
- Skin tone modifiers: `👍🏽` — is this `👍` + `🏽` or one emoji?

**Mitigation**: The greedy-longest-match parser must use Unicode's emoji segmentation rules (UAX #29 extended grapheme clusters). In Swift, iterating by `Character` (which IS grapheme clusters) handles this correctly. `"🌟🧠".forEach { ... }` yields two Characters. `"👨‍👩‍👧‍👦"` yields one Character. Swift's String type is our ally here.

For repeated emoji (`🌟🌟🌟`): treat as N repetitions of the same command. Three stars = three sequential challenge rounds. This is actually useful — "challenge this three times from different angles." Maximum **3 repetitions** (BR-EM-CHAIN-REPEAT-CAP). More than 3 is rejected.

**2. Conflicting Targets**

What if the chain mixes agent-specific commands?
- `🗡️@Ronin🧠@Sensei` — review by Ronin, then brainstorm by Sensei?
- Current syntax puts `@target` at the END of the emoji chain, applying to ALL steps

**Decision**: One target per chain. `@target` applies to the entire chain. If you need different agents for different steps, use `&&` or `;` as bash separators for distinct commands. Rationale: the chain is one thought, one intent. Splitting agents across steps adds complexity for a rare use case. If someone truly needs Ronin-then-Sensei, two commands is clearer:

```
shikki 🗡️@Ronin PR#42 && shikki 🧠@Sensei "review Ronin's findings"
shikki 🗡️@Ronin PR#42 ; shikki 🌡️   # review then check status regardless of exit code
```

The `&&` form stops on failure. The `;` form always continues.

---

### @Enso (Brand) — 1 Idea

**Shikkimoji Chaining as Language Grammar**

The chain syntax creates a natural grammar:

| Part | Linguistic Role | Example |
|------|----------------|---------|
| Emoji chain | **Verbs** (actions) | `🔍🌟🧠` = research, challenge, discuss |
| `@target` | **Subject** (who) | `@t` = the team, `@Sensei` = the architect |
| Trailing text | **Object** (what) | `"payment system"`, URL, UUID |

So `🔍🌟@t https://github.com/foo/bar` reads as: "research and challenge, team, this repo."

This is Shikkimoji's **sentence structure**: `[verbs]@[subject] [object]`. It's the inverse of English (SVO) — it's VSO (Verb-Subject-Object), like Welsh, Arabic, and classical Irish. This feels right for a command language: the action comes first, because that's what matters most.

Lean into this. Documentation should frame chains as "sentences." The help text for chaining could say: *"Write what you want to do, who should do it, and what it's about."*

---

## Team Aliases

Agent targets support team aliases with defined membership:

| Alias | Members |
|-------|---------|
| `@tech` | @Sensei, @Ronin, @Katana, @Kenshi, @Metsuke |
| `@creative` | @Sensei, @Hanami, @Enso, @Tsubaki |
| `@marketing` | @Shogun, @Enso, @Tsubaki, @Kintsugi |

**@Sensei is a member of every team** — architecture context is always relevant. Team aliases are shorthand: `shikki 🧠@tech "CRDT tradeoffs"` dispatches to all tech team members in parallel and synthesizes their outputs.

Custom team aliases can be defined in `~/.config/shikki/teams.toml`:

```toml
[teams.infra]
members = ["Sensei", "Katana", "Kenshi"]
```

---

## Pipe Syntax and --format: Analysis

Two options were proposed:

### Option A: Pure Concatenation
```
shikki 🔍🌟🧠@t https://foo
```

### Option B: Explicit Pipes
```
shikki 🔍 https://foo | 🌟 | 🧠@t
```

### Verdict: Concatenation wins, pipes reserved for bash

**Concatenation** is the primary syntax because:
1. Shorter — the whole point of emoji is speed
2. Visually cohesive — one "word" of intent
3. Matches the linguistic metaphor (one sentence, not three piped commands)
4. Shell `|` is reserved for bash piping — do NOT overload it

**`|` is strictly bash piping**: `shikki 🌡️ | jq '.sessions'` works as expected — Shikki outputs JSON, jq processes it. We do not repurpose `|` for internal chain syntax. This avoids confusion and preserves composability with the Unix ecosystem.

**Future `--format` flag** for structured output (reserves the design space):
```
shikki 🌡️ --format json    # machine-readable, for piping
shikki 📊 --format html    # export board as HTML
shikki 📊 --format md      # export as Markdown
```

`--format` is output formatting only — not a chain separator. Implementation deferred post-v0.3.0.

Implementation: the shell `|` creates separate processes, so pipe syntax is actually separate `shikki` invocations with stdin/stdout piping. Each invocation reads the previous step's JSON output from stdin. This means pipeline composition works for free — single-emoji commands gain pipeline support by checking stdin.

---

## Proposed Business Rules

### BR-EM-CHAIN-01: Chain Parsing
The `EmojiChainParser` splits a single argument string into a sequence of `ChainStep` values by iterating Swift `Character` boundaries (grapheme clusters). Each Character is looked up in `EmojiRegistry.byEmoji`. Unrecognized characters terminate the emoji sequence — everything after is `@target` or args.

### BR-EM-CHAIN-02: Agent Targeting
`@target` appears immediately after the emoji chain, before any space. Recognized targets: `@t` / `@team` / `@shi` (full team), named team aliases (`@tech`, `@creative`, `@marketing`), or any agent name from `agents.md` (e.g., `@Sensei`, `@Ronin`, `@Hanami`). If no `@target`, the command uses its default agent routing.

### BR-EM-CHAIN-03: Sequential Pipeline Execution
Chain steps execute left-to-right. Each step receives the prior step's `StepOutput` as context. Steps do not run in parallel. The chain halts on abort; skips on non-interactive failure.

### BR-EM-CHAIN-04: Single Target per Chain
One `@target` applies to the entire chain. Mixed per-step targeting is not supported. Use `&&` or `;` bash separators for multi-agent workflows across separate commands.

### BR-EM-CHAIN-05: Repetition Cap
The same emoji repeated N times (e.g., `🌟🌟🌟`) runs that command N times sequentially, each receiving the previous iteration's output. **Maximum 3 repetitions.** More than 3 is an error: "Chain repetition limit is 3. Use a loop or separate commands."

### BR-EM-CHAIN-06: Destructive Emoji in Chains
Destructive emoji (❌, ⏪) cannot appear in chains. They must be standalone commands. `❌🚀` is rejected with: "Destructive commands cannot be chained. Run `shikki ❌` separately." This extends BR-EM-16.

### BR-EM-CHAIN-07: Bash Pipe Passthrough
Shell pipe (`|`) between `shikki` invocations is bash piping — Shikki does not intercept it. Each invocation reads `StepOutput` JSON from stdin if present. No special chain handling needed — single-emoji commands gain pipeline support by checking stdin.

### BR-EM-CHAIN-08: Args Apply to Chain
In concatenated syntax, trailing text/args apply to the chain as a whole (passed to the first step, then context-forwarded). Per-step args require separate commands with `&&` or `;`.

### BR-EM-CHAIN-09: Ambiguous Chain Confirmation
For chains of 3+ emoji where the intent is not obvious (detected by LLM intent classifier), Shikki may prompt: "You're about to run [challenge → brainstorm → ship]. Is that right? Y/n". Default is Y (confirm with Enter). In non-interactive mode, always proceed without prompt. The LLM intent classifier runs locally and only fires when confidence is below threshold.

### BR-EM-CHAIN-10: `--format` Flag (Future)
`--format json|html|md` controls output serialization format. Reserved design space — not implemented in v0.3.0. Do not repurpose `|` for format switching.

### BR-EM-CHAIN-11: Team Aliases
Named team aliases (`@tech`, `@creative`, `@marketing`) dispatch to all members in parallel and synthesize outputs. Custom aliases defined in `~/.config/shikki/teams.toml`. @Sensei is present in every built-in team.

---

## Architecture Impact

### New Types

```swift
// ShikkiKit/Services/EmojiChainParser.swift

public struct EmojiChain: Sendable {
    public let steps: [ChainStep]
    public let target: AgentTarget?
    public let args: String?
}

public struct ChainStep: Sendable {
    public let entry: EmojiRegistry.Entry
    public let repetition: Int  // 1 for normal, 2-3 for repeats (max 3)
}

public enum AgentTarget: Sendable, Equatable {
    case team
    case namedTeam(String)   // @tech, @creative, @marketing
    case agent(String)

    public init?(string: String) {
        switch string.lowercased() {
        case "t", "team", "shi": self = .team
        case "tech", "creative", "marketing": self = .namedTeam(string.lowercased())
        default: self = .agent(string)
        }
    }
}

public struct StepOutput: Sendable, Codable {
    public let command: String
    public let summary: String
    public let data: [String: String]?  // structured output for next step
    public let status: StepStatus

    public enum StepStatus: String, Sendable, Codable {
        case completed, skipped, failed
    }
}
```

### Modified Types

`EmojiRouter.rewrite()` gains a new path: if the first arg contains multiple emoji Characters, delegate to `EmojiChainParser` instead of single-emoji lookup. The single-emoji path remains unchanged (backward compatible).

### Pipeline Executor

```swift
// ShikkiKit/Services/ChainExecutor.swift

public struct ChainExecutor {
    public func execute(_ chain: EmojiChain) async throws -> StepOutput {
        var previousOutput: StepOutput? = nil
        for step in chain.steps {
            let command = resolveCommand(step, target: chain.target)
            previousOutput = try await command.run(
                args: chain.args,
                input: previousOutput
            )
        }
        return previousOutput!
    }
}
```

---

## Test Plan (Addendum to Phase 6)

| # | Test | Validates |
|---|------|-----------|
| 27 | `testChainParserTwoEmoji` — "🌟🧠" → [challenge, brain] | BR-EM-CHAIN-01 |
| 28 | `testChainParserTripleEmoji` — "🌟🧠📦" → [challenge, brain, ship] | BR-EM-CHAIN-01 |
| 29 | `testChainParserWithTarget` — "🌟🧠@t" → chain + .team | BR-EM-CHAIN-02 |
| 30 | `testChainParserAgentTarget` — "🧠@Sensei" → chain + .agent("Sensei") | BR-EM-CHAIN-02 |
| 31 | `testChainParserWithArgs` — "🔍🌟@t https://foo" → chain + args | BR-EM-CHAIN-08 |
| 32 | `testRepetition` — "🌟🌟🌟" → 3x challenge | BR-EM-CHAIN-05 |
| 33 | `testRepetitionCap` — "🌟🌟🌟🌟" → error (max 3) | BR-EM-CHAIN-05 |
| 34 | `testDestructiveInChainRejected` — "❌🚀" → error | BR-EM-CHAIN-06 |
| 35 | `testSingleEmojiUnchanged` — "🥕" → same as before (no chain) | Backward compat |
| 36 | `testZWJNotSplitInChain` — "🧙‍♂️🌟" → [wizard, challenge] not [wizard-broken, star] | BR-EM-CHAIN-01 + BR-EM-12 |
| 37 | `testStdinPipelineInput` — StepOutput JSON on stdin → consumed as input | BR-EM-CHAIN-07 |
| 38 | `testChainProgressRendering` — Claude Code wave-style progress bar snapshot | BR-EM-CHAIN-09 + @Hanami UX |
| 39 | `testAdaptiveRefreshShortChain` — 2-step chain refresh interval = 10s | BR-EM-CHAIN-09 |
| 40 | `testAdaptiveRefreshComplexChain` — 3+ step agent chain refresh interval = 30s | BR-EM-CHAIN-09 |
| 41 | `testTeamAliasExpansion` — @tech → [Sensei, Ronin, Katana, Kenshi, Metsuke] | BR-EM-CHAIN-11 |
| 42 | `testSenseiInAllTeams` — @creative and @marketing both include Sensei | BR-EM-CHAIN-11 |
| 43 | `testAmbiguousChainPrompt` — long chain below confidence threshold → Y/n prompt | BR-EM-CHAIN-09 |

---

## Open Questions

1. **Should signals compose?** `✅🚀` feels like "approve then execute." But `✅` as a signal is different from `✅` as a pipeline step. Current decision: signals at chain start apply to current context (like a pre-condition), not as a pipeline step. Needs user validation.

2. **Max chain length?** Proposed: 5 steps. Longer chains are likely mistakes or abuse. But 3 might be more practical. Needs real usage data.

3. **Chain history storage.** Should the EventBus log the chain as one event or N events? Proposal: one `chain_executed` event with steps array, plus individual step events for granular tracking.

4. **Autocomplete.** How does shell tab-completion work for chains? It can't — emoji are pasted or typed via OS emoji picker, not tab-completed. This is fine. Chains are for power users who know the emoji.

5. **LLM intent detection threshold.** What confidence score triggers the "Is that right?" prompt for ambiguous chains? Proposed: < 0.7. Needs calibration against real usage.

---

> "Emoji + @ + text. Verb + subject + object. The command line as a language."
> — @Enso
