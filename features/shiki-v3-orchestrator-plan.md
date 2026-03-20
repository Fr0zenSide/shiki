# Shiki v3 — Orchestrator + Platform Plan

> **Status**: Spec (pending @Daimyo review)
> **Date**: 2026-03-17
> **Supersedes**: `project_orchestrator-v3-wave1-plan.md` (session foundation only)
> **Sources**: 9 IaC/agent research projects + 5 competitor deep-dives + event bus spec + PR review v2 spec
> **Branch target**: `feature/orchestrator-v3` from `develop`

---

## 0. Core Thesis

> **"The agent is NOT the product. The orchestration layer is the product."**
> — Confirmed by Augment ($472M), Composio, Overstory, Devin, GitHub Copilot independently.

Shiki v3 is not an upgrade. It's the transition from "CLI tool that manages tmux sessions" to **"observable orchestration platform with specs, personas, verification, and human oversight."**

Everything emits ShikiEvent. Everything is observable. The human decides, the system executes.

---

## 1. Architecture Layers

```
┌─────────────────────────────────────────────────────────────┐
│  Layer 5: Subscribers (TUI, Dashboard, Native App, DB)      │
├─────────────────────────────────────────────────────────────┤
│  Layer 4: Event Bus (ShikiEvent, EventBus, Transport)       │
├─────────────────────────────────────────────────────────────┤
│  Layer 3: Workflows (PR Review, Autofix, Dispatch, Wiki)    │
├─────────────────────────────────────────────────────────────┤
│  Layer 2: Orchestration (Registry, Lifecycle, Personas,     │
│           Specs, Verification, Budget, Recovery)            │
├─────────────────────────────────────────────────────────────┤
│  Layer 1: Foundation (Sessions, Journal, Watchdog, Hooks)   │
├─────────────────────────────────────────────────────────────┤
│  Layer 0: Runtime (AgentProvider protocol, tmux/process)    │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. Waves

### Wave 1: Session Foundation (~800 LOC, 3 new + 5 modified)
*Unchanged from original v3 plan — this is the base everything builds on.*

**Deliverables:**
- `SessionLifecycle.swift` — 11-state machine: `spawning → working → awaitingApproval → budgetPaused → pr_open → ci_failed → review_pending → changes_requested → approved → merged → done`. TransitionActor (system/user/agent/governance).
- `SessionRegistry.swift` — Discoverer protocol + 4-phase pipeline + `reapOrphans()` (5min staleness)
- `SessionJournal.swift` — Append-only JSONL checkpoints + coalesced writes + costThreshold reason
- Wire into: StatusCommand, RestartCommand, HeartbeatLoop, CompanyLauncher

**New from steal sheet:**
- Add `attentionZone` computed property to session (Composio pattern): `merge > respond > review > pending > working > idle`
- Add `ZFC health principle` (Overstory): observable state (tmux alive, pid) > recorded state (DB). When signals conflict, trust the kernel.
- Add session cost tracking from Claude Code JSONL transcripts (Overstory/Composio pattern)

**Tests:** ~32 new tests
**Depends on:** Nothing
**Blocks:** Everything

---

### Wave 2: Event Bus + Living Specs (~600 LOC, 6 new + 4 modified)

**2A: Event Bus (from event bus architecture spec)**
- `ShikiEvent` + `EventSource` + `EventType` + `EventScope` → `packages/ShikiKit/`
- `InProcessEventBus` (actor) → `ShikiCtlKit/Events/`
- `ShikiDBEventLogger` (persistent subscriber) → `ShikiCtlKit/Events/`
- `LocalPipeTransport` → `ShikiCtlKit/Events/`
- Migrate HeartbeatLoop to emit events instead of raw logs
- All session state transitions emit events

**2B: Living Specs (Augment Intent pattern)**
- `SpecDocument.swift` — structured markdown spec: overview, requirements (checkboxes), implementation plan (phased), decisions log, notes
- `.shiki/specs/{task-id}.md` — generated on dispatch, committed to branch
- Spec auto-updates as agents complete work (via PostToolUse hook)
- After context reset, spec is the recovery point — agent reads spec, resumes
- Spec is the verification surface (Wave 3)

**2C: PostToolUse Hooks (Composio pattern)**
- `.shiki/hooks/post-tool-use.sh` — intercept `gh pr create`, `git checkout -b`, `swift test` outputs
- Write PR URL, branch name, test results directly to session metadata
- Zero-latency metadata updates — no polling
- Self-review trigger: hook detects PR creation → auto-queue review pass

**Tests:** ~20 new tests (EventBus: pub/sub/filter, SpecDocument: parse/update, Hooks: event detection)
**Depends on:** Wave 1 (sessions)
**Blocks:** Wave 3 (personas + verification), Wave 4 (PR review v2)

---

### Wave 3: Agent Personas + Verification (~500 LOC, 4 new + 3 modified)

**3A: Agent Personas (Augment Intent pattern)**
```swift
enum AgentPersona: String, Codable, Sendable {
    case investigate  // read-only + codebase search. Cannot edit files.
    case implement    // full edit + build + test tools
    case verify       // read-only + test runner + diff checker (checks against spec)
    case critique     // read-only + spec access (reviews spec feasibility)
    case review       // read-only + PR context (code review with severity)
    case fix          // edit + test + specific file scope (PR fix agent)
}
```
- Each persona defines: allowed tools, system prompt overlay, scope constraints
- Tool removal IS prompt engineering: verify agent has no edit tools → structurally can't drift
- `AgentProvider` protocol (from feedback_ai-provider-agnostic.md) becomes real:
  ```swift
  protocol AgentProvider {
      func dispatch(task: Task, persona: AgentPersona, spec: SpecDocument?) -> AgentSession
  }
  ```
- First implementation: `ClaudeCodeProvider`

**3B: Spec-Driven Verification (Augment Intent pattern)**
- After implementation agents finish, auto-dispatch `verify` persona agent
- Verifier reads: the spec, the diff, the test results
- Produces: pass/fail report with citations (which spec requirements are met/unmet)
- Blocks PR creation until verification passes
- Self-review step (Copilot pattern): agent reviews own diff as part of verification

**3C: Progressive Watchdog (Overstory pattern)**
- 4 levels: warn → nudge → AI triage → terminate
- Configurable intervals per level
- Decision gate awareness: skip escalation if agent is intentionally paused (`awaitingApproval`)
- Named failure modes in agent prompts (Overstory pattern): HIERARCHY_BYPASS, SPEC_WRITING, PREMATURE_MERGE, SCOPE_EXPLOSION

**Tests:** ~25 new tests (Persona tool constraints, Verification logic, Watchdog escalation)
**Depends on:** Wave 2 (events + specs)
**Blocks:** Wave 5 (multi-agent coordination)

---

### Wave 4: PR Review v2 + External Tools (~600 LOC, from PR review spec)

**4A: PR Cache + Risk Triage** *(Phase 1 — DONE)*
- `PRCacheBuilder.swift` — parse git diff, generate cache files
- `PRRiskEngine.swift` — heuristic risk scoring per file
- `KeyMode.swift` — emacs/vim/arrows abstraction
- `PRConfig.swift` — YAML config loader

**4B: External Tools Integration**
- `ExternalTools.swift` — tool detection, shell-out, graceful degradation
- `QMDClient.swift` — qmd collection add, embed, query
- `d` → delta, `f` → fzf, `/` → qmd, `o` → $EDITOR, `g` → rg

**4C: AI Fix Agent**
- `PRFixAgent.swift` — worktree creation, context injection (review state + file + qmd results)
- Uses `AgentProvider` with `.fix` persona
- Emits ShikiEvents: `prFixSpawned`, `prFixCompleted`
- Course-correct via event bus injection

**4D: Review emits events**
- All PR review actions emit ShikiEvents
- `prCacheBuilt`, `prRiskAssessed`, `prSectionViewed`, `prVerdictSet`, `prSearchQuery`
- DB logger captures full review timeline

**Tests:** ~15 new tests (ExternalTools fallback, QMDClient parse, FixAgent context assembly)
**Depends on:** Wave 2 (events), Wave 3 (personas for fix agent)
**Blocks:** Nothing — can ship independently after Wave 2

---

### Wave 5: Multi-Agent Coordination (~700 LOC, 5 new + 4 modified)

**5A: Inter-Agent Messaging (Overstory SQLite mail → ShikiEvent)**
- NOT separate SQLite mail DB — use the EventBus with typed message events
- New event types: `agentQuestion`, `agentResult`, `agentHandoff`, `mergeReady`, `decisionGate`
- Broadcast groups via EventScope: `.agents("builders")`, `.agents("all")`
- Hook injection: incoming events → Claude Code UserPromptSubmit hook

**5B: Task Decomposer (Composio pattern)**
- LLM classifies tasks as atomic/composite
- Recursive decomposition (max depth 2 — NOT Overstory's 4-level hierarchy)
- Lineage context: "you are task 1.2, siblings are 1.1 and 1.3"
- Sibling awareness prevents duplicate work
- Requires approval before spawning (unlike Composio's fire-and-forget)

**5C: Merge Resolution (Overstory 4-tier pattern)**
- Tier 0: clean merge (git merge, no conflicts)
- Tier 1: auto-resolve (keep incoming for trivial conflicts)
- Tier 2: AI-resolve (Claude `--print` mode generates resolution)
- Tier 3: re-imagine (full rewrite of conflicting section from spec)
- Conflict pattern learning: record what worked/failed per file combination

**5D: Recovery Manager (Composio pattern)**
- Scan all sessions on startup and periodically
- Validate: runtime alive (tmux/pid), workspace exists, metadata consistent
- Auto-recover: restart crashed sessions with checkpoint context
- Escalate: unrecoverable sessions → notification + cleanup

**5E: Agent Handoffs (Copilot pattern)**
- Serialize context summary when agent completes
- Offer handoff to specialized next agent: implement → verify → review
- Context carries: spec, changes, test results, review comments

**Tests:** ~30 new tests (Message routing, Decomposer, Merge tiers, Recovery, Handoffs)
**Depends on:** Wave 1-3 (sessions, events, personas)
**Blocks:** Wave 6 (dashboard)

---

### Wave 6: Dashboard + Operational Tools (~500 LOC, 4 new + 2 modified)

**6A: `shiki dashboard` TUI (Composio attention-zone pattern)**
- Full-screen TUI showing all active sessions sorted by attention zone
- Columns: session, project, state, attention, elapsed, tokens, cost
- Real-time updates via EventBus subscription
- Drill into session: live output, PR status, review state
- Key mode support (emacs/vim/arrows)

**6B: `shiki doctor --fix` (Composio pattern)**
- 11-category diagnostic: PATH, binaries (tmux, delta, fzf, qmd), Docker/Colima, backend health, stale sessions, config validity, disk space, git status, worktree integrity, hook permissions, Shiki DB connection
- Auto-fix mode: repair stale sessions, clean orphaned worktrees, fix permissions

**6C: `shiki wiki` (Devin pattern)**
- Periodic repo indexing → architecture docs stored in Shiki DB
- Module-level summaries: purpose, dependencies, key types, public API
- Run on: `shiki wiki generate` (manual), git post-commit hook (auto), cron (nightly)
- Solves context-reset permanently — wiki is always current

**6D: `shiki autofix <PR#>` (Devin pattern)**
- Monitor CI via `gh run watch`
- On failure: extract logs, spawn fix agent with `.fix` persona
- Re-run CI after fix
- Max retries: configurable (default 2)
- Emit events: `autofixStarted`, `autofixSucceeded`, `autofixFailed`

**Tests:** ~20 new tests (Dashboard rendering, Doctor checks, Wiki generation, Autofix flow)
**Depends on:** Wave 1-4 (everything)
**Blocks:** Nothing — this is the polish wave

---

## 3. Scope Summary

| Wave | Focus | New Files | LOC (est.) | Tests |
|------|-------|-----------|-----------|-------|
| 1. Session Foundation | State machine, registry, journal | 3 | ~800 | ~32 |
| 2. Events + Specs + Hooks | Event bus, living specs, PostToolUse | 6 | ~600 | ~20 |
| 3. Personas + Verification | Agent types, spec checking, watchdog | 4 | ~500 | ~25 |
| 4. PR Review v2 | Cache, risk, tools, fix agent | 4 | ~600 | ~15 |
| 5. Multi-Agent Coordination | Messages, decomposer, merge, recovery | 5 | ~700 | ~30 |
| 6. Dashboard + Ops | TUI dashboard, doctor, wiki, autofix | 4 | ~500 | ~20 |
| **Total** | | **26 new, ~20 modified** | **~3,700** | **~142** |

---

## 4. Dependencies Graph

```
Wave 1 (Sessions)
  ├── Wave 2 (Events + Specs)
  │     ├── Wave 3 (Personas + Verification)
  │     │     └── Wave 5 (Multi-Agent)
  │     │           └── Wave 6D (Autofix)
  │     └── Wave 4 (PR Review v2)
  │           └── Wave 6A (Dashboard)
  └── Wave 6B (Doctor — can start early, only needs sessions)
```

Wave 4 (PR Review) and Wave 5 (Multi-Agent) are **parallel** after Wave 3.
Wave 6 components can start as soon as their dependencies land.

---

## 5. What We Steal vs. What We Invented

| Component | Source | Shiki's twist |
|-----------|--------|---------------|
| 11-state session machine | IaC research (Kestra/Paperclip) | + attention zones (Composio) |
| Event bus | Our design | ShikiEvent unifies all — replaces Overstory's SQLite mail AND Composio's flat files |
| Living Spec | Augment Intent | Local-first markdown, committed to branch, survives context resets |
| Agent Personas | Augment Intent | Tool removal as constraint (not just prompt instructions) |
| Verification loop | Augment Intent | Spec-driven, not vibes-driven |
| Progressive watchdog | Overstory | Simpler (no 4-level hierarchy), decision gate aware |
| PR risk triage | Original (no competitor has this) | AI heuristics + qmd semantic search |
| Attention zones | Composio | Applied to TUI, not web dashboard |
| PostToolUse hooks | Composio | For metadata + self-review trigger |
| Task decomposer | Composio | Max depth 2 (not 3), requires approval |
| Merge resolution | Overstory | 4-tier escalation + conflict learning |
| Recovery manager | Composio | DB-backed (not flat files) |
| Dashboard TUI | Copilot Mission Control | Terminal-native, not web |
| Auto-wiki | Devin | Local, Shiki DB stored, not cloud |
| Autofix loop | Devin | `gh run watch` + fix persona agent |
| Doctor command | Composio | 11-category + auto-fix |
| Budget control | Paperclip research | Per-project, auto-pause at threshold |
| Observable data stream | Our design | Nobody else has reactive event bus |

---

## 6. What We DON'T Build

| Rejected | Why | From |
|----------|-----|------|
| Cloud execution (Devbox VMs) | Local-first is the advantage | Devin |
| 4-level agent hierarchy | Too much overhead, Overstory admits it | Overstory |
| Web dashboard (now) | TUI first, web when team grows | Composio |
| Cloud Context Engine | LM Studio + Shiki DB + qmd instead | Augment |
| Separate SQLite mail DB | EventBus subsumes this | Overstory |
| Per-seat pricing | Usage-based, self-hosted | Copilot |
| Desktop GUI app (now) | CLI-first, native app via event bus later | Augment |

---

## 7. Success Criteria (v3 complete)

1. `shiki start` → agents dispatched with personas, specs generated, events flowing
2. `shiki dashboard` → attention-zone TUI, real-time session state, cost tracking
3. `shiki pr <N> --build` → risk triage + qmd search + delta diffs + fix agent
4. `shiki doctor --fix` → diagnose and repair environment in one command
5. `shiki wiki generate` → architecture docs in Shiki DB, survives context resets
6. `shiki autofix <PR#>` → CI failure auto-fixed, re-run, max 2 retries
7. Verify agent blocks PR until spec requirements met
8. Progressive watchdog catches stuck agents without false positives
9. Multi-agent merge resolution handles conflicts across worktrees
10. All actions recorded as ShikiEvents in Shiki DB
11. 99 existing + ~142 new = **~241 tests**, all green
12. Zero external deps for core (delta/fzf/qmd optional with degradation)

---

## 8. Open Decisions (for @Daimyo review)

All technical decisions are closed (see PR v2 spec section 10).

**Strategic decisions pending:**
- [x] License: **AGPL-3.0** + CLA before external contributors. Commercial license on enterprise demand only. (Decided 2026-03-17)
- [x] Domain: **shiki.sh** (primary) + **getshiki.dev** (redirect to .sh). (Decided 2026-03-17)
- [x] When to open-source: **After polish + shiki.sh live + PH launch prep.** Not before the product is ready to communicate. (Decided 2026-03-17)
- [x] Wave 1 start: **Now. Use Shiki to build Shiki (dog-fooding).** Split v3 into /md-feature files, run through Shiki process. (Decided 2026-03-17)
