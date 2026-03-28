# Shikki Commands Architecture — Unified Swift + Skills Boundary

> Status: DRAFT — @Daimyo review pending
> Date: 2026-03-28
> Branch: integration/shikki-v0.3.0-pre
> Saved to ShikiDB: yes

---

## Phase 1 — Brainstorm Table

### @Sensei (CTO) — Architecture Boundaries

**The core question**: Which commands should be compiled Swift vs interpreted skills (markdown)?

Decision criteria, in priority order:

1. **LLM dependency**: If the command can complete without calling an LLM, it MUST be Swift. Status, doctor, schedule, heartbeat — these are pure data + syscall operations. Invoking Claude to check if tmux is running is waste.

2. **Testability gate**: Can it have a `XCTestCase`? If yes and it carries business logic, it MUST be Swift. Skills cannot have test files. Skills have never had test files. This is the original sin.

3. **Pipeline position**: Is it a gate in a release or spec pipeline? If it's a gate, it MUST be compiled — gates that drift kill the whole pipeline silently. A markdown file drifting its prompt definition is undetectable. A `ShipGate` protocol conformance failing to compile is caught at build time.

4. **Frequency + latency**: Commands run >10x per day and require <200ms response should be Swift. LLM cold-start is 2-5 seconds minimum.

5. **Composability**: Does other Swift code need to call it programmatically? If yes, it must be Swift (a struct conforming to a protocol), not a string in a markdown file.

**Decision matrix**:

| Criterion | Swift (compiled) | Skill (markdown) |
|-----------|-----------------|-----------------|
| No LLM needed | Required | Disqualifying |
| Needs test coverage | Required | Not possible |
| Is a pipeline gate | Required | Fragile |
| High frequency, low latency | Required | Costly |
| Pure text generation / reasoning | Overkill | Natural fit |
| Needs agent orchestration (multi-step LLM) | Wrapper only | Body of logic |
| User-facing documentation / onboarding | Overkill | Natural fit |

**Bottom line from @Sensei**: The current architecture is already correct in intent but muddy in execution. `SpecCommand.swift` calls `ClaudeAgentProvider()` — the Swift layer is the contract, the LLM is the worker. The mistake is that some skills (`/pre-pr`, `/orchestrate`, `/autopilot`, `/feature-pipeline`) own business logic that belongs in Swift. They should be Swift state machines that invoke LLMs as a tool, not markdown prompts that describe a state machine they'll never enforce.

---

### @Ronin (Adversarial) — What Actually Breaks

**Attack surface 1 — Prompt drift**
`/pre-pr` has 9 gates described in markdown. Gate 3 is "tests must pass". What enforces that? Nothing. The next time someone edits `pre-pr-pipeline.md`, they can silently downgrade "must pass" to "should pass" — and no build, no CI, no test, no linter catches it. The first you learn about it is a broken production deploy.

**Attack surface 2 — No regression testing**
There are currently 0 tests for any skill. `ShipCommand.swift` has `ShipServiceTests.swift`. `pre-pr-pipeline.md` has nothing. The asymmetry is not acceptable for P0 pipeline components.

**Attack surface 3 — Versioning fiction**
Skills are `.md` files tracked by git. The git history is there. But there is no semantic version, no changelog, no backward-compat guarantee. When `ShikkiCommand.swift` is at v0.3.0, what version is `pre-pr-pipeline.md`? Unknown. Can you `shikki upgrade` skills independently? No. They're coupled to the repo without being coupled to the Swift version.

**Attack surface 4 — Invocation ambiguity**
The user types `shikki spec "add login"`. This calls the compiled `SpecCommand.swift`, which invokes `ClaudeAgentProvider`, which reads a system prompt. But the user could ALSO type `/spec add login` to Claude Code directly, which reads `feature-pipeline.md`. These are two different code paths producing output that should be identical — but neither enforces that the other exists or that they agree.

**Attack surface 5 — Skills are not composable**
`/pre-pr` calls `/review` in gate 1a. It does this by telling Claude to "run the /review skill now". This is string-based dispatch — indirection with no type safety, no error contract, no timeout, no retry. When `/review` fails mid-`/pre-pr`, recovery is undefined.

**Ronin's verdict**: At least 3 skills are ticking time bombs: `/pre-pr`, `/orchestrate`, and `/autopilot`. They contain the most critical business logic in the entire system — shipping, multi-company orchestration, autonomous execution — and they have zero compile-time safety, zero tests, and zero version lock.

---

### @Hanami (UX) — Seamless Single Entry Point

**The user's mental model**:
The user doesn't think "should I use the Swift binary or invoke a skill?" They think: "I want to ship this feature." They want to type one thing and trust the system.

The problem is that today there are at least three places to look for commands:
- `shikki --help` (compiled)
- Claude Code `/help` (built-ins)
- `.claude/skills/` (discovered only if you know to look)

This is three different discoverability surfaces with no crosslinks.

**@Hanami's vision — One canonical surface**:

```
shikki help                    # shows ALL commands — Swift + skills + CC built-ins
shikki spec "feature idea"     # Swift entry, delegates to LLM as needed
shikki review pr24             # Swift entry, delegates to LLM as needed
shikki ship --why "reason"     # Swift entry, pure gate pipeline
```

The user always types `shikki <verb>`. The binary routes:
- To a compiled implementation if one exists (fast path)
- To a skill invocation via `ClaudeAgentProvider` if the verb requires LLM
- The routing table is declared in Swift (`ShikkiCommand.swift`) — not discovered at runtime

Skills that are user-facing commands get a `shikki <verb>` entry point in the compiled binary. The `.md` file becomes the prompt/logic body, but the contract (input types, output shape, error handling) lives in Swift.

**What @Hanami wants killed**: The concept of "skills the user types directly". Users should never need to know about `.claude/skills/`. That's an implementation detail. The public API is `shikki <verb>`.

---

### @Shogun (Market) — Competitive Landscape

**How competitors split compiled vs interpreted**:

| Tool | Compiled layer | Interpreted layer | Boundary |
|------|---------------|-------------------|----------|
| Claude Code | Built-in slash commands (Go/Rust binary) | `/skills/*.md` prompt files | Hard: built-ins are code, skills are prompts |
| Cursor | Rules (`.cursorrules`, project rules) | AI action system | Rules are config (enforced), actions are freeform |
| Aider | Python CLI — all compiled | None — no skill concept | All code, all the time |
| Devin | Agent planner (TypeScript) | Action executor (Python agents) | Compiled planner, interpreted execution |
| GitHub Copilot Workspace | Compiled session manager | LLM-generated step plans | Session infra compiled, task plans interpreted |

**Market insight**: The pattern across winning tools is consistent — the **orchestration layer is compiled** (fast, testable, version-locked), the **generation/reasoning layer is interpreted** (flexible, prompt-tunable, LLM-routed). No successful tool puts gate logic in markdown files.

**Shogun's positioning note**: Shikki's differentiation is that it's the only tool that has both a compiled gate pipeline (`ShipCommand`, `WaveCommand`) AND an agent skills layer. That's a genuine moat — but only if the boundary is clearly enforced. Right now the moat leaks: users can bypass compiled gates by invoking skills directly, and compiled commands sometimes do less than their skill equivalents.

**Parity gap to fix**: `shikki ship` (compiled, 9 gates) vs `/pre-pr` (skill, also ~9 gates) — these two should be the same command. The skill should call the binary or the binary should absorb the skill. Currently they're parallel implementations that can drift independently.

---

### @Metsuke (Quality Inspector) — Can We Test and Version Skills?

**Current state audit**:

| Item | Swift commands | Skills |
|------|---------------|--------|
| Unit tests | Yes (ShikkiKitTests/) | No |
| Integration tests | Yes (ShikkiEntryPointIntegrationTests) | No |
| Type safety | Yes (Swift compiler) | No |
| Version tracking | Yes (semver in ShikkiCommand.swift) | No (git hash only) |
| CI enforcement | Yes (swift test) | No |
| Slop detection | Yes (@Metsuke checklist runs on code) | No (skills are the slop detectors, not subject to them) |
| Lint | Yes (SwiftLint) | No |
| Snapshot tests | Yes (__Snapshots__/) | No |

**Can we test skills at all?**

Technically yes — by writing a test that invokes Claude Code with the skill and asserts properties of the output. This is what `ShikkiEntryPointIntegrationTests` does for the binary. But:
- It requires a live LLM — non-deterministic, slow, expensive
- It's E2E only — no unit-level isolation
- Prompt changes don't break tests until you run the full E2E suite

**@Metsuke's recommendation**: Classify skills into two tiers:

**Tier A — Logic Skills** (must migrate to Swift or become Swift-wrapped):
- `/pre-pr` — gate pipeline with business rules
- `/orchestrate` — company lifecycle management
- `/autopilot` — autonomous loop
- `/feature-pipeline` (`/md-feature`) — spec-to-code pipeline
- `/parallel-dispatch` — worktree dispatch logic

**Tier B — Reasoning Skills** (fine as markdown, prompt-tunable, no migration needed):
- `/elicitation` — structured questioning prompts
- `/ai-slop-scan` — LLM review prompt
- `/sdd-protocol` — subagent instructions
- `/verification-protocol` — checklist prompts
- All agent persona files (`agents.md`, checklists)

Tier A skills should be audited every release cycle by checking for gate logic, state transitions, and conditional branches — those are red flags that belong in Swift.

---

## Phase 2 — Feature Brief: Unified Command Architecture

### Problem Statement

Shikki has three command surfaces with no enforced boundary:

1. **Compiled Swift** (`shikki <verb>`) — 27 subcommands, fully typed, tested, version-locked
2. **Skill markdown** (`.claude/skills/shikki-process/*.md`) — ~20 skills, LLM-interpreted, untested, versions loosely tracked by git
3. **Claude Code built-ins** (`/help`, `/clear`, `/compact`) — 11 commands, external, not Shikki's concern

The core tension: skills can encode business logic (gate rules, pipeline stages, state machines) that should be in compiled code. When they do, that logic is invisible to tests, invisible to the type system, and vulnerable to silent drift.

### Vision

**One entry point. One mental model.**

```
shikki <verb>           # always the answer, regardless of what runs underneath
```

The `ShikkiCommand` binary is the **public API**. Skills are **implementation details** — prompt bodies that feed into `ClaudeAgentProvider`, not standalone commands users invoke directly. Claude Code built-ins remain their own concern.

The architecture:

```
User types: shikki spec "add OAuth login"
              │
              ▼
        ShikkiCommand.swift  ←─ compiled, typed, tested
              │
         SpecCommand.swift   ←─ validates input, resolves context
              │
        SpecPipeline.swift   ←─ orchestrates: prompt → agent → validate → persist
              │
     ClaudeAgentProvider     ←─ calls LLM with structured prompt
              │
    [prompt template]        ←─ skill body (prompt logic, persona, format)
              │
          ShikiDB            ←─ persists result
```

The skill is the prompt template — not the orchestrator. Swift is the orchestrator.

### Unified Command Architecture — Target State

**Three tiers, three roles**:

| Tier | What | Role | Owned by |
|------|------|------|----------|
| **Execution tier** | Swift commands (`shikki *`) | Contract, routing, gate enforcement, state, events | `ShikkiKit`, `ShikkiCommand` |
| **Reasoning tier** | Skill prompt templates (`.claude/skills/`) | LLM instructions, persona, output format | Skills repo (shikki-process) |
| **Extension tier** | Claude Code built-ins (`/help`, `/compact`) | Claude Code session management | Claude Code (external) |

**Key rule**: Logic that has a right answer belongs in Swift. Logic that requires reasoning or synthesis belongs in skills. Nothing belongs in both.

---

## Phase 3 — Key Business Rules

### BR-CA-01: LLM-free commands MUST be compiled Swift

Any command that can complete without invoking an LLM must be a Swift `ParsableCommand`. Invoking Claude for a `shikki doctor` run (environment check) or `shikki status` (tmux session state) is architecturally wrong.

**In scope**: `doctor`, `status`, `heartbeat`, `log`, `board`, `history`, `report` (metrics only), `stop`, `pause`, `wake`, `restart`, `codir`.

### BR-CA-02: Pipeline gates MUST be compiled Swift

Any command or step that acts as a binary gate (pass/fail with downstream consequences) must be a Swift `ShipGate` (or equivalent protocol). Gate logic in markdown is unenforceable.

**In scope**: All gates in `ShipCommand`, all stages in `WaveCommand`, the readiness check in `SpecCommand`.

### BR-CA-03: Skills own prompts, not pipelines

A skill file (`.md`) may contain:
- LLM persona instructions
- Output format templates
- Reasoning frameworks (brainstorm tables, checklists)
- Agent targeting (`@Sensei`, `@Ronin`, etc.)

A skill file must NOT contain:
- Gate conditions ("if tests fail, stop here")
- State transition logic ("advance to phase 3 after user confirms")
- Routing logic ("dispatch to worktree A, B, C based on feature")
- Error recovery logic ("on failure, retry with --autofix")

These belong in Swift.

### BR-CA-04: Every user-facing skill gets a Swift entry point

If a skill is intended to be invoked by the user as a command (not just as an LLM system prompt), it must have a corresponding `ShikkiCommand` subcommand. The subcommand handles: argument parsing, validation, context resolution, error display. The skill handles: what Claude does once invoked.

**Migration target**: `/pre-pr` → `shikki pre-pr` (or `shikki review --pre`), `/orchestrate` → absorbed into heartbeat loop, `/autopilot` → `shikki wave` (already exists).

### BR-CA-05: Skills are versioned with the binary

When `shikki` ships at v0.3.0, all skills in `.claude/skills/shikki-process/` are implicitly v0.3.0. The `shikki doctor` command should validate that the skills directory is present and that the skill manifest matches the expected version hash. Skill drift without binary upgrade is a warning, not an error — but it must be visible.

### BR-CA-06: Shikki emoji commands (`shikki 📦`, `shikki 🚀`) are syntactic sugar

Emoji commands are short aliases resolved in Swift (e.g., `📦` → `ship`, `🚀` → `wave --yolo`). They are not a separate command tier. They resolve to standard subcommand invocations before any routing occurs. No skill handles an emoji directly.

### BR-CA-07: `shikki help` is the single discovery surface

`shikki help` (or `shikki --help`) outputs ALL commands: compiled subcommands, skill-backed subcommands (labeled `[skill]`), and pointers to CC built-ins. Users never need to read `.claude/skills/README.md` to discover commands.

### BR-CA-08: Critical path skills are compiled-first, prompt-second

For `/spec`, `/wave`, `/ship`, `/review` — the Swift code is the authoritative definition of "what this does". The skill file is the LLM instruction that gets invoked inside the Swift pipeline. The skill body can change without changing the Swift contract. The Swift contract can add new gates without the skill knowing (the skill just responds to whatever the pipeline asks).

---

## Phase 4 — Migration Plan

### Current skill-to-command mapping

| Skill | Current state | Target state | Priority |
|-------|--------------|--------------|----------|
| `/pre-pr` (`pre-pr-pipeline.md`) | Standalone skill, 9 gates in markdown | Absorb into `ShipCommand.swift` as pre-ship review gates OR create `ReviewCommand.swift` (already TODOed in `ShikkiCommand.swift`) | P0 |
| `/md-feature` (`feature-pipeline.md`) | Standalone skill, 8 phases in markdown | Already partially absorbed by `SpecCommand.swift` + `WaveCommand.swift`. Remaining: phase 2 (synthesis Q&A) into `SpecCommand --interactive` | P0 |
| `/orchestrate` (`orchestrator.md`) | Standalone skill, full company lifecycle FSM | Absorb into `HeartbeatCommand.swift` (already the loop entry) + `ShikkiCore CompanyManager` | P1 |
| `/autopilot` (`autopilot.md`) | Standalone skill, autonomous loop | Already superceded by `WaveCommand.swift`. Skill becomes prompt template only | P1 |
| `/parallel-dispatch` (`parallel-dispatch.md`) | Standalone skill, worktree routing | Absorb into `WaveCommand.swift` (already does worktree dispatch via `ArchitectureCache`) | P1 |
| `/quick-flow` (`quick-flow.md`) | Standalone skill, lightweight pipeline | Create `shikki quick` Swift command (maps to `WaveCommand` with lightweight preset) | P1 |
| `/elicitation` | Reasoning skill, pure prompts | Keep as skill — no logic, pure LLM craft | Keep |
| `/ai-slop-scan` | Review prompt skill | Keep as skill — pure LLM review | Keep |
| `/sdd-protocol` | Agent instructions | Keep as skill — pure LLM instructions | Keep |
| `/verification-protocol` | Checklist prompts | Keep as skill — pure LLM checklist | Keep |
| `/tdd` | Fix loop skill | Keep as skill body — logic is minimal, mostly prompting | Keep |
| `/course-correct` | Mid-feature correction | Keep as skill — pure reasoning | Keep |
| `agents.md` | Agent persona definitions | Keep as skill — persona config | Keep |
| `bootstrap.md` | Active rules | Keep as skill — session context | Keep |
| All checklists | Review criteria | Keep as skills — pure LLM | Keep |

### Migration waves

**Wave 1 — Eliminate the dual-ship problem (P0)**

The most critical gap: `shikki ship` (Swift) and `/pre-pr` (skill) are parallel implementations of "quality gate before shipping". This must converge.

Option A: `shikki ship` absorbs `/pre-pr` gates. The review gates (CTO review, slop scan, test validation) become `ShipGate` implementations in Swift that invoke the skill prompts as their LLM step.

Option B: Create `shikki review --pre-pr` as the pre-ship gate command, and `shikki ship` requires passing `shikki review --pre-pr` first (checked via lockfile or ShikiDB record).

Recommendation: **Option A**. One command, one pipeline. Gates call LLM prompts (skills) for the reasoning steps. Gate pass/fail is determined by Swift, not by Claude saying "this looks good".

**Wave 2 — `ReviewCommand.swift` (P0, already TODOed)**

`ShikkiCommand.swift` line 28 has `// TODO: rebase on top of PR #29 cleanup`. This is the `ReviewCommand` that was removed. Restore it — it should be the compiled entry point for PR review, with `pr-review.md` as its system prompt body.

**Wave 3 — `shikki quick` Swift command (P1)**

Create a lightweight `QuickCommand.swift` that maps to `WaveCommand` with a quick-flow preset (no spec required, single-agent, no gate review). The `/quick-flow` skill becomes its prompt body.

**Wave 4 — Skill version manifest (P2)**

Add a `shikki-process/MANIFEST.json` (or Swift-readable format) declaring each skill's name, version, and `min-shikki-version`. `shikki doctor` reads it and warns on mismatch.

**Wave 5 — `shikki help` unified surface (P2)**

Extend `ShikkiCommand.swift` to output a rich help screen that shows compiled commands and skill-backed commands with distinct labels. Consider a `shikki commands` subcommand for machine-readable output (useful for TUI command palette).

---

## Phase 5 — Architectural Constraints (Non-Negotiables)

1. **No LLM invocation in status/health commands.** `shikki status`, `shikki doctor`, `shikki heartbeat` are pure Swift. Always sub-200ms.

2. **ShipGate protocol is the gate boundary.** Any release gate must conform to `ShipGate`. No gate logic lives outside a conforming type.

3. **Skills are prompt bodies, not command definitions.** Removing a skill file must not break any compiled command. The compiled command must gracefully degrade if its skill prompt is missing (use a fallback minimal prompt, log a warning).

4. **`shikki` is the only user-facing entry point.** Claude Code skills are implementation tools. Users are never instructed to type `/pre-pr` or `/orchestrate` — they type `shikki review --pre-pr` or `shikki` (which routes to the orchestrator).

5. **Skill logic migrations are accompanied by tests.** Before any skill logic moves to Swift, the target behavior must be captured in a test. No migration without a failing test first (TDD migration).

---

## Appendix — Full Current Inventory

### Compiled Swift Commands (27 total)

| Command | LLM? | Gate? | Notes |
|---------|------|-------|-------|
| `shikki` (default) | No | No | State detector — start/resume/attach |
| `stop` | No | No | Countdown TUI |
| `status` | No | No | Pure data display |
| `doctor` | No | No | Environment check |
| `heartbeat` | No | No | Orchestrator loop (internal) |
| `log` | No | No | Event stream reader |
| `board` | No | No | Data display |
| `history` | No | No | Session transcript |
| `report` | No | No | Metrics aggregation |
| `backlog` | Partial | No | LLM for enrichment only |
| `inbox` | No | No | List display |
| `decide` | Yes | No | LLM-powered Q&A |
| `spec` | Yes | No | LLM pipeline, Swift contract |
| `wave` | Yes | Yes | LLM dispatch, Swift gates |
| `ship` | No | Yes | Pure Swift gates |
| `search` | No | No | fzf shell-out |
| `menu` | No | No | TUI grid |
| `pr` | No | No | Git/gh shell-out |
| `ingest` | Yes | No | Architecture analysis |
| `context` | No | No | Cache query |
| `codir` | No | No | Board summary |
| `dashboard` | No | No | Live TUI |
| `pause` | No | No | State write |
| `wake` | No | No | Session launch |
| `restart` | No | No | Process restart |
| `startup` | No | No | Layout bootstrap (legacy) |

### Skill Files — Tier Classification

| Skill | Tier | Disposition |
|-------|------|-------------|
| `pre-pr-pipeline.md` | A (Logic) | Migrate gates to `ShipCommand.swift` / `ReviewCommand.swift` |
| `feature-pipeline.md` | A (Logic) | Gates already in `SpecCommand` + `WaveCommand`. Complete migration. |
| `orchestrator.md` | A (Logic) | Absorb into `HeartbeatCommand` + ShikiCore `CompanyManager` |
| `autopilot.md` | A (Logic) | Superseded by `WaveCommand`. Demote to prompt body. |
| `parallel-dispatch.md` | A (Logic) | Absorb into `WaveCommand` dispatch logic |
| `quick-flow.md` | A (Logic) | Create `QuickCommand.swift` |
| `decision-queue.md` | A (Logic) | Absorbed by `DecideCommand.swift` — confirm parity |
| `elicitation.md` | B (Reasoning) | Keep as skill — pure LLM craft |
| `ai-slop-scan.md` | B (Reasoning) | Keep as skill — pure LLM review |
| `sdd-protocol.md` | B (Reasoning) | Keep as skill — agent instructions |
| `verification-protocol.md` | B (Reasoning) | Keep as skill — checklist |
| `tdd.md` | B (Reasoning) | Keep as skill — minimal logic |
| `course-correct.md` | B (Reasoning) | Keep as skill — pure reasoning |
| `company-management.md` | B (Reasoning) | Keep — persona/context only |
| `feature-tracking.md` | B (Reasoning) | Keep — output format guide |
| `pr-review.md` | B (Reasoning) | Keep — review prompt body |
| `pr-checklist-validation.md` | B (Reasoning) | Keep — checklist |
| `agents.md` | B (Reasoning) | Keep — persona config |
| `bootstrap.md` | B (Reasoning) | Keep — session rules |
| `process-overview.md` | B (Reasoning) | Keep — documentation |
| All checklists | B (Reasoning) | Keep — LLM criteria |

---

*Spec authored: 2026-03-28. Brainstorm: @Sensei, @Ronin, @Hanami, @Shogun, @Metsuke. Awaiting @Daimyo one-shot validation.*
