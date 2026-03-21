# Feature: Wave 1 — Session Foundation

> **Type**: /md-feature
> **Priority**: P0 — blocks all v3 work
> **Branch**: `feature/v3-wave1-sessions` from `develop`
> **Parent plan**: `features/shiki-v3-orchestrator-plan.md`
> **Estimated**: ~800 LOC, 3 new files, 5 modified, ~32 tests

---

## 1. Problem

The orchestrator has no session state model. Sessions are tmux panes with no lifecycle, no state machine, no health tracking, no cost awareness. The heartbeat loop queries tmux directly and makes ad-hoc decisions. There's no way to know: "what needs my attention right now?"

## 2. Solution

A proper session foundation with:
- 11-state lifecycle machine with enforced transitions
- Session registry with discovery, reconciliation, and orphan reaping
- Append-only journal for crash recovery
- Attention-zone sorting (gradient, never filter)
- Cost tracking from Claude Code JSONL transcripts
- Simplified tmux layout (1 window + sidebar, not 3 windows)

## 3. Deliverables

### 3A. `ShikiCtlKit/Services/SessionLifecycle.swift` (~300 LOC)

**SessionState** enum — 11 states:
`spawning → working → awaitingApproval → budgetPaused → prOpen → ciFailed → reviewPending → changesRequested → approved → merged → done`

**AttentionZone** enum — 6 levels (always visible, intensity gradient):
`merge(0) > respond(1) > review(2) > pending(3) > working(4) > idle(5)`

**TransitionActor** enum: `system | user(String) | agent(String) | governance`

**SessionTransition** struct: from, to, actor, reason, timestamp

**TaskContext** struct: taskId, companySlug, projectPath, parentSessionId, wakeReason, budgetDailyUsd, spentTodayUsd

**SessionLifecycle** actor:
- `transition(to:actor:reason:)` — enforced valid transitions (invalid throws)
- `attentionZone` computed property
- `reconcile(tmuxAlive:pidAlive:)` — ZFC principle: observable state > recorded state

### 3B. `ShikiCtlKit/Services/SessionRegistry.swift` (~300 LOC)

**SessionDiscoverer** protocol: `discover() async -> [DiscoveredSession]`

**TmuxDiscoverer** implementation: parses `tmux list-panes` for the shiki session only

**SessionRegistry** actor:
- `refresh()` — 4-phase pipeline: discover → reconcile → transition → reap
- `register(_:)` / `deregister(_:)` — session lifecycle
- `reapOrphans(stalenessThreshold: 300)` — 5-minute staleness, safety rules:
  - NEVER touch external tmux sessions (not named `shiki`)
  - NEVER touch reserved windows (orchestrator, research)
  - NEVER touch sessions in `awaitingApproval` or `budgetPaused`
  - NEVER touch the currently active pane
  - PID matching confirms Shiki ownership
- `sessionsByAttention()` — sorted by attention zone
- `updateCosts()` — parse Claude Code JSONL transcripts for token usage

### 3C. `ShikiCtlKit/Services/SessionJournal.swift` (~200 LOC)

**SessionCheckpoint** struct: sessionId, state, timestamp, reason, metadata

**CheckpointReason** enum: `stateTransition | periodic | costThreshold | userAction | recovery`

**SessionJournal** actor:
- `checkpoint(_:)` — append to `.shiki/journal/{session-id}.jsonl`
- `coalescedCheckpoint(_:debounce:)` — buffer rapid transitions, flush on 2s debounce
- `loadCheckpoints(sessionId:)` — read for recovery
- `prune(olderThan: 14 * 24 * 3600)` — 14-day retention (safe for holidays)

### 3D. Modified files

**StartupCommand.swift** — Replace 3-window layout with 1-window sidebar layout:
```
┌─────────────────────┬──────────┐
│   main (Claude)     │ session  │ ← 20% sidebar
│                     │ stream   │
├─────────────────────┤ (attn    │
│   heartbeat (20%)   │  sorted) │
└─────────────────────┴──────────┘
```
- Remove board window creation (panes created on-demand by dispatcher)
- Remove research window creation (moved to `shiki research` in Wave 6)
- Keep pane border titles with session numbers

**HeartbeatLoop.swift** — Use `SessionRegistry.refresh()` instead of raw tmux queries. Register sessions on dispatch. Emit transitions on state changes.

**StatusCommand.swift** — Sort by `attentionZone`. Show cost per session. ANSI gradient: bold+bright for top zones, dim for idle.

**CompanyLauncher.swift** — Register sessions in registry on launch. Set TaskContext with company/project/budget.

**StopCommand.swift** — Graceful shutdown: journal final checkpoint for all sessions, then cleanup. Keep research window alive if it has active work.

## 4. Tests (~32)

### SessionLifecycleTests (8)
- Valid transition: spawning → working
- Invalid transition: done → working (throws)
- Attention zone: prOpen → .review
- Attention zone: approved + CI green → .merge
- Budget pause: spentToday >= budgetDaily → .budgetPaused
- ZFC reconcile: tmux dead + state working → transition to done
- ZFC reconcile: tmux alive + state done → no change (trust recorded)
- Transition history recorded with actor + reason

### SessionRegistryTests (8)
- Discover finds tmux panes in shiki session
- Discover ignores external tmux sessions
- Reconcile: new pane → register
- Reconcile: missing pane + 5min stale → reap
- Reconcile: missing pane + 2min → keep (not stale yet)
- Never reap reserved windows
- Never reap awaitingApproval sessions
- sessionsByAttention returns merge first, idle last

### SessionJournalTests (6)
- Append writes JSONL line
- Coalesced debounce: 3 rapid checkpoints → 1 write
- Load checkpoints returns ordered list
- Prune removes files older than 14 days
- Prune keeps recent files
- Empty journal returns empty checkpoints

### TmuxDiscovererTests (4)
- Parse tmux list-panes output
- Handle empty output (no session)
- Handle dead panes (no PID)
- Only discover panes in shiki session

### IntegrationTests (6)
- Full pipeline: register → transition → checkpoint → reap
- Cost update from mock JSONL
- Attention sort with mixed states
- Graceful shutdown journals all sessions
- Sidebar layout creation (tmux mock)
- Session number assignment and 4h retention

## 5. Verification

1. `swift build` — clean, zero warnings
2. `swift test` — 99 existing + ~32 new = ~131 all green
3. `shiki start` — creates 1-window layout with sidebar
4. `shiki status` — shows sessions sorted by attention zone with gradient
5. Orphan sessions reaped after 5 minutes (verified no false positives)
6. Journal files at `.shiki/journal/` with JSONL checkpoints
7. Budget pause triggers at 100% threshold
8. `shiki restart` — restarts heartbeat, all other panes survive
9. `shiki stop` — journals final state, cleans up

## 6. Out of Scope (later waves)

- Event bus (Wave 2)
- Living specs (Wave 2)
- Agent personas (Wave 3)
- PR review improvements (Wave 4)
- Multi-agent coordination (Wave 5)
- Dashboard TUI, shiki research, shiki doctor (Wave 6)

## 7. Critical References

- State machine research: `memory/project_orchestrator-v3-wave1-plan.md` (Kestra 17-state, Paperclip patterns)
- Attention zones: Composio agent-orchestrator pattern (steal sheet #2)
- ZFC health: Overstory STEELMAN.md principle (steal sheet)
- Cost tracking: Overstory/Composio JSONL parsing pattern
- Orphan safety: `memory/feedback_orphan-reaping-safety.md`
- Layout: `memory/feedback_tmux-layout-simplification.md`
- Gradient UX: `memory/feedback_attention-zones-gradient.md`
