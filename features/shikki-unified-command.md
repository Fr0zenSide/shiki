# Feature: Shikki — The Unified Command
> Created: 2026-03-22 | Status: Phase 5b — Execution Plan (PASS) | Owner: @Daimyo

## Context
The current `shiki` CLI has 19 subcommands including `start`, `stop`, `attach`, `session pause`, `session resume`. The vision is radical simplification: ONE command `shikki` that auto-detects what to do (start, resume, or attach), and `shikki stop` with a graceful countdown. No `session pause`. No `session resume`. No thinking. Like opening your laptop — it just knows.

### Current State
- `shiki start` — full startup (Docker bootstrap, tmux layout, heartbeat)
- `shiki stop` — confirmation prompt, cleanup, kill tmux
- `shiki attach` — execv to tmux attach
- `shiki session pause` — manual save checkpoint
- `shiki session resume` — load checkpoint, copy context, launch tmux
- `shiki session list` — list saved sessions

### Vision (from previous session)
```
shikki          # THE command. Start, resume, or attach. Auto-detects.
shikki stop     # Save + countdown 3→2→1 (Esc cancels) + close
```
- No `session pause`. No `session resume`. No thinking. Shikki just knows.
- Auto-save happens continuously. Stop is graceful with cancellable countdown.
- Like opening your laptop — you don't "resume macOS", it's just there.

### Dual Session System (to unify)
Currently two overlapping persistence systems:
- **PausedSessionManager** (`~/.shiki/sessions/*.json`) — user-facing context (branch, PRs, summary) for `session resume` clipboard paste
- **SessionJournal** (`~/.shiki/journal/*.jsonl`) — orchestrator crash recovery (FSM state, checkpoint reason, debounced)

The shikki vision unifies these: one continuous auto-checkpoint system that captures both FSM state AND rich context, read by the single `shikki` entry point.

## Inspiration
### Brainstorm Results

| # | Idea | Source | Feasibility | Impact | Fit | Verdict |
|---|------|--------|:-----------:|:------:|:---:|---------:|
| 1 | **Zero-Verb Entry Point** — `shikki` with no args resolves state and drops you in. No other dev session tool does stateful auto-resume as default zero-arg behavior. | @Shogun | High | High | Strong | BUILD |
| 2 | **3-2-1 Graceful Exit as Brand Signature** — visible countdown, Esc cancels. Steals from `kubectl drain` grace period but makes it visual. Anti-tmux positioning. | @Shogun | High | Medium | Strong | BUILD |
| 3 | **Implicit Session Lifecycle (Docker metaphor)** — `shikki` = `docker run` (create-or-reuse), `shikki stop` = `docker stop` (persist and exit). Eliminate pause/resume/list as user-facing verbs entirely. | @Shogun | Medium | High | Strong | BUILD |
| 4 | **"Welcome Back" Heartbeat** — single warm status line ("Resuming where you left off, 2h ago, feature/x") before workspace appears. The 3s is not loading — it's a breath of orientation. | @Hanami | High | High | Strong | BUILD |
| 5 | **Gentle Goodbye Ritual** — countdown shows what's being saved at each tick ("saving context... preserving 3 panes... done"). Esc says "Still here." Stopping = act of trust. | @Hanami | High | High | Strong | BUILD |
| 6 | **Typo-Forgiveness Layer** — any malformed invocation (`shikki resume session`, `shikki start`, even `shiki`) silently does the right thing with a soft hint. Two words in vocabulary, everything else = `shikki`. | @Hanami | Medium | High | Strong | BUILD |
| 7 | **Mu-Mind Principle** — stateless surface, stateful depth. CLI presents emptiness (one command, no flags) while context flows like groundwater. Tool removes itself from the conversation between craftsperson and craft. | @Kintsugi | High | High | Strong | BUILD |
| 8 | **Graceful Endings as Kintsugi Seams** — the countdown is not safety but micro-ritual of closure. A visible seam between sessions, like gold in kintsugi. Esc = "this ending was not yet true." | @Kintsugi | High | Medium | Strong | BUILD |
| 9 | **Three-State FSM (tmux as truth)** — `idle → running → stopping`. State derived from `tmux has-session` + `latestCheckpoint()`. No explicit state file. Delete SessionCommand, AttachCommand entirely — FSM subsumes them. | @Sensei | High | High | Strong | BUILD |
| 10 | **Dual-Symlink Binary Transition** — compile as `shikki`, keep `shiki` symlink with stderr deprecation. Old subcommands reachable via `shiki` only; `shikki` enforces reduced API by binary name. | @Sensei | High | Medium | Strong | BUILD |

### Selected Ideas
@Daimyo selected ALL 10 — every idea carries forward. No cutting.

1. **Zero-Verb Entry Point** (@Shogun) — `shikki` with no args auto-detects state
2. **3-2-1 Graceful Exit** (@Shogun) — brand signature countdown, Esc cancels
3. **Docker Metaphor** (@Shogun) — implicit lifecycle, eliminate pause/resume/list verbs
4. **"Welcome Back" Heartbeat** (@Hanami) — warm orientation line before workspace appears
5. **Gentle Goodbye Ritual** (@Hanami) — countdown shows what's being saved at each tick
6. **Typo-Forgiveness Layer** (@Hanami) — any malformed input silently does the right thing
7. **Mu-Mind Principle** (@Kintsugi) — stateless surface, stateful depth
8. **Kintsugi Seams** (@Kintsugi) — countdown as micro-ritual of closure between sessions
9. **Three-State FSM** (@Sensei) — tmux as single source of truth, delete SessionCommand/AttachCommand
10. **Dual-Symlink Transition** (@Sensei) — `shiki` → `shikki` deprecation via binary name check

## Synthesis

### Feature Brief

**Goal**: Replace the `shiki` CLI with `shikki` — a unified command that auto-detects workspace state and acts accordingly, with a graceful configurable countdown on stop.

**Scope**:
- Rename binary from `shiki-ctl`/`shiki` to `shikki`. Delete old names entirely.
- `shikki` (no args) = the magic entry point: start fresh, resume saved session, or attach to running tmux. Zero thinking.
- `shikki stop` = auto-save + configurable countdown (default 5s) with Esc cancel + cleanup + kill tmux
- `shikki <subcommand>` = all other commands (`pr`, `board`, `dashboard`, `doctor`, `search`, `ship`, etc.) remain accessible
- Delete `session` subcommand entirely (pause/resume/list) — the FSM handles this invisibly
- Delete `attach` subcommand — subsumed by `shikki` entry point
- Delete `start` subcommand — subsumed by `shikki` entry point
- Unify PausedSessionManager + SessionJournal into one checkpoint system
- Hybrid persistence: local BIOS file for cold start + DB as source of truth when available
- Typo-forgiveness: malformed inputs do the right thing with soft hint
- "Welcome back" orientation line on resume
- Countdown shows what's being saved at each tick

**Out of scope (deferred)**:
- Context trimming / progressive summarization (separate feature — important but distinct)
- MCP-first bootstrap architecture (depends on shiki-knowledge-mcp shipping)
- Agent-agnostic bootstrap (needs MCP-first to be meaningful)

**Success criteria**:
- `shikki` from any state drops you into your workspace in < 3 seconds
- `shikki stop` saves and exits with visible feedback, cancellable
- No user ever types `session pause/resume` again
- Old `shiki` binary no longer exists
- All existing subcommands work under `shikki <sub>`

**Dependencies**:
- Current `shiki` CLI codebase (Swift/ArgumentParser)
- tmux (state detection)
- Existing SessionJournal + PausedSessionManager (to merge)

**Open question (flagged by @Daimyo)**:
The countdown may feel irrelevant when executed via the AI agent (already finished by the time user sees it). Needs real-world testing to calibrate. The countdown is as much psychological reassurance as functional — "when you do shikki it re-runs the entire saved context, so it is normally the same session." The real safety net is the checkpoint quality, not the countdown duration.

**Related concern**: Context blowup on resume — saving/restoring full context may blast the AI agent's context window. Need to think about progressive trimming as a follow-up feature (not blocking v1 but tracked).

## Business Rules

### FSM States & Transitions
BR-01: The FSM defines exactly three states: IDLE, RUNNING, STOPPING. No other states exist.
BR-02: IDLE means no tmux session named "shikki" exists and no checkpoint file indicates a paused session.
BR-03: RUNNING means a tmux session named "shikki" exists and has at least one live pane.
BR-04: STOPPING means `shikki stop` has been invoked and the countdown has not yet completed or been cancelled.
BR-05: Valid transitions: IDLE→RUNNING (start), RUNNING→STOPPING (stop invoked), STOPPING→IDLE (countdown completes), STOPPING→RUNNING (Esc cancel), RUNNING→IDLE (crash/external kill detected on next invocation).
BR-06: No transition exists from IDLE→STOPPING or STOPPING→STOPPING. Attempting these is a no-op with diagnostic log.
BR-07: State detection runs in under 200ms. Checks in order: (1) `tmux has-session -t shikki`, (2) checkpoint file at `~/.shikki/checkpoint.json`.

### Entry Point (`shikki` no args)
BR-08: `shikki` with no arguments detects state and acts: IDLE → full startup. RUNNING → attach to existing session. STOPPING → block with "Stop in progress, wait or press Esc in the stop terminal."
BR-09: IDLE with checkpoint present → resume: restore checkpoint, start session, print "Welcome back" line, attach. This is the IDLE→RUNNING transition with checkpoint hydration.
BR-10: IDLE with no checkpoint → clean start, no restore step.
BR-11: `shikki` never prompts the user for which action to take. Detection is deterministic; the FSM decides.

### Stop Countdown (`shikki stop`)
BR-12: `shikki stop` initiates RUNNING→STOPPING. No-op with exit code 0 and message if IDLE.
BR-13: Countdown default is 3 seconds. Configurable via `--countdown N` (integer, 0–60, clamped).
BR-14: `--countdown 0` skips countdown entirely — immediate save + cleanup.
BR-15: Each tick (1/s) prints what's being saved: T-3 "Saving session context…", T-2 "Writing checkpoint…", T-1 "Closing session…". Longer countdowns (via `--countdown`) expand the sequence to include DB persist and pane cleanup as separate ticks. Save and checkpoint always run regardless of countdown length.
BR-16: Esc cancels the stop, transitions STOPPING→RUNNING, prints "Stop cancelled." Save operations are idempotent — a checkpoint written at T-4 becomes an available resume point.
BR-17: Non-TTY stdin disables Esc detection. Countdown runs to completion with warning: "Non-interactive terminal — Esc cancel unavailable."
BR-18: `shikki stop` while already STOPPING is a no-op: "Stop already in progress."

### Unified Checkpoint System
BR-19: PausedSessionManager and SessionJournal are deleted. Single `CheckpointManager` replaces both.
BR-20: Single file: `~/.shikki/checkpoint.json`. Atomic JSON overwrite (write-to-temp + rename), not append-only JSONL.
BR-21: Schema: `version` (Int), `timestamp` (ISO 8601), `fsmState` (String), `tmuxLayout` (pane dict), `sessionStats` (uptime, commands, agents), `contextSnippet` (String, max 4KB), `dbSynced` (Bool).
BR-22: Four methods: `save(state:) throws`, `load() -> Checkpoint?`, `exists() -> Bool`, `delete() throws`.
BR-23: On successful resume, checkpoint deleted after tmux session confirmed live. On failed resume, checkpoint preserved.
BR-24: Legacy migration: `~/.shiki/sessions/` and `~/.shiki/journal/` converted to new schema on first run, then deleted. Runs once.

### Hybrid Persistence (BIOS + DB)
BR-25: Save order: local disk first (hard error if fails), then DB (soft warning if fails, `dbSynced=false`).
BR-26: Resume reads local first. If no local file, queries DB for latest checkpoint (matched by hostname). DB result written to local disk.
BR-27: If both exist and differ, local wins. DB overwritten on next save.
BR-28: BIOS path: `~/.shikki/checkpoint.json`. Directory `~/.shikki/` created with mode 0700 on first run.
BR-29: Cold start with no DB and no BIOS = clean start. No error. Expected first-run path.

### Binary Rename
BR-30: Binary renamed from `shiki` to `shikki`. Symlink at `~/.local/bin/shikki`. Additional alias: `~/.local/bin/shi` → `shikki` (short form for CLI speed).
BR-31: Swift package executable target renamed from `shiki-ctl` to `shikki` in Package.swift.
BR-32: No backward-compatibility alias for `shiki`. `shiki` → "command not found." Clean break.
BR-33: tmux session named `shikki`. Humans read the session name — it must be recognizable at first sight.
BR-34: `StartupCommand.swift`, `StopCommand.swift`, `AttachCommand.swift`, `SessionCommand.swift` deleted. Logic refactored into FSM + CheckpointManager.
BR-35: `PausedSessionManager.swift` and `SessionJournal.swift` deleted. Consolidated into `CheckpointManager.swift`.

### Subcommand Routing
BR-36: Retained subcommands: `pr`, `board`, `dashboard`, `doctor`, `report`, `search`, `ship`, `menu`, `decide`, `heartbeat`, `history`, `wake`, `pause`, `restart`, `status`.
BR-37: Deleted subcommands: `start`, `attach`, `session` (all sub-commands). Subsumed by FSM.
BR-38: `shikki stop` remains as explicit subcommand.
BR-39: Subcommands requiring RUNNING state (`board`, `dashboard`) check FSM first. If not RUNNING: "No active session. Run `shikki` to start." exit 1.
BR-40: Subcommands not requiring RUNNING state (`pr`, `doctor`, `search`, `ship`) execute regardless.

### Typo Forgiveness
BR-41: Unknown subcommand → Levenshtein distance against known commands. Distance ≤ 2 → execute match + soft hint: "↪ Interpreted as `shikki <match>`. (You typed `<input>`.)"
BR-42: Distance > 2 → "Unknown command: `<input>`. Run `shikki --help`." exit 1.
BR-43: Typo correction NEVER applies to `stop`. `shikki sotp` prints suggestion but does NOT execute — safety. "Did you mean `shikki stop`? Re-run with the exact command."
BR-44: Typo correction is case-insensitive. `shikki PR` → `shikki pr`.

### Welcome Back Display
BR-45: On resume, "Welcome back" line appears first, before standard startup display.
BR-46: Format: "Welcome back — last session <relative time> (<duration>). Restoring <N> panes."
BR-47: Relative time: "<1m" / "Xm" / "Xh" / "Xd". Duration: "Xh Ym", omitting zero components.
BR-48: Checkpoint older than 7 days appends: "(checkpoint is <N>d old — layout may be outdated)".
BR-49: Clean start (no checkpoint) → no "Welcome back" line.

### Edge Cases
BR-50: tmux dies while RUNNING → FSM transitions to IDLE on next `shikki` invocation. Checkpoint preserved if it exists.
BR-51: DB unavailable during stop → local save only, `dbSynced=false`. No retry loop. Next invocation syncs if DB available.
BR-52: No checkpoint + no tmux = clean start. Must never error.
BR-53: PID lockfile at `~/.shikki/shikki.pid` prevents concurrent IDLE→RUNNING. Second instance polls for tmux (100ms, 30s timeout), then attaches. Stale PID → overwrite.
BR-54: Multiple RUNNING-state attaches are safe — tmux handles concurrent attach natively.
BR-55: `shikki stop` from inside shikki tmux → countdown runs, caller detached first, then session killed.
BR-56: Heartbeat failure sets internal flag but does NOT auto-clean. Cleanup on next explicit `shikki` or `shikki stop`.
BR-57: All file I/O uses POSIX atomic patterns: write to `.tmp`, then `rename(2)`. No partial writes visible.

## Test Plan

99 test signatures across 10 suites. Every BR has at least one covering test.

### Unit Tests

#### ShikkiFSMTests
```swift
// BR-01: 3 states
@Test func test_allStates_areIdleRunningAndStopping()
// BR-02: IDLE detection
@Test func test_detectIdle_whenNoTmuxAndNoCheckpoint()
// BR-03: RUNNING detection
@Test func test_detectRunning_whenTmuxSessionExists()
// BR-04/05: Valid transitions
@Test func test_transition_idleToRunning_succeeds()
@Test func test_transition_runningToStopping_succeeds()
@Test func test_transition_stoppingToIdle_succeeds()
@Test func test_transition_stoppingToRunning_succeeds()
@Test func test_transition_runningToIdle_onCrash_succeeds()
// BR-05/06: Invalid transitions
@Test func test_transition_idleToStopping_throws()
@Test func test_transition_stoppingToStopping_throws()
// BR-07: Performance
@Test func test_stateDetection_completesUnder200ms()
@Test func test_stateDetection_checksTmuxAndCheckpointFile()
```

#### ShikkiEntryPointTests
```swift
// BR-08: No-args behavior per state
@Test func test_noArgs_whenIdle_startsNewSession()
@Test func test_noArgs_whenRunning_attachesToSession()
@Test func test_noArgs_whenStopping_blocksWithMessage()
// BR-09/10: Resume vs clean start
@Test func test_noArgs_whenIdleWithCheckpoint_resumesSession()
@Test func test_noArgs_whenIdleWithoutCheckpoint_startsClean()
// BR-11: Deterministic
@Test func test_entryPoint_neverPromptsForInput()
```

#### StopCountdownTests
```swift
// BR-12: State transitions
@Test func test_stop_transitionsRunningToStopping()
@Test func test_stop_whenIdle_isNoOp()
// BR-13/14: Countdown config
@Test func test_stop_defaultCountdownIsThreeSeconds()
@Test func test_stop_countdownFlag_setsCustomDuration()
@Test func test_stop_countdownClampedToZeroMinimum()
@Test func test_stop_countdownClampedToSixtyMaximum()
@Test func test_stop_countdownZero_stopsImmediately()
// BR-15/16: Tick + cancel
@Test func test_stop_eachTickShowsSaveDescription()
@Test func test_stop_escKeyPress_cancelsAndReturnsToRunning()
// BR-17/18: Non-TTY + double stop
@Test func test_stop_nonTTY_disablesEscCancel()
@Test func test_stop_whileAlreadyStopping_isNoOp()
```

#### CheckpointManagerTests
```swift
// BR-19/20: Atomic writes
@Test func test_init_createsCheckpointManager()
@Test func test_save_writesAtomicJSON()
@Test func test_save_overwritesExistingCheckpoint()
// BR-21: Schema
@Test func test_checkpoint_containsVersion()
@Test func test_checkpoint_containsTimestamp()
@Test func test_checkpoint_containsFsmState()
@Test func test_checkpoint_containsTmuxLayout()
@Test func test_checkpoint_containsSessionStats()
@Test func test_checkpoint_containsContextSnippet()
@Test func test_checkpoint_containsDbSynced()
@Test func test_checkpoint_contextSnippetMaxFourKB()
// BR-22: API surface
@Test func test_save_writesToDisk()
@Test func test_load_readsFromDisk()
@Test func test_exists_returnsTrueWhenPresent()
@Test func test_exists_returnsFalseWhenAbsent()
@Test func test_delete_removesCheckpointFile()
// BR-23: Resume lifecycle
@Test func test_resume_deletesCheckpointAfterSuccess()
@Test func test_resume_preservesCheckpointOnFailure()
// BR-24: Legacy migration
@Test func test_migrate_convertsPausedSessionManagerData()
@Test func test_migrate_convertsSessionJournalData()
@Test func test_migrate_skipsWhenNoLegacyData()
```

#### HybridPersistenceTests
```swift
// BR-25: Save order
@Test func test_save_localFirst_throwsOnLocalFailure()
@Test func test_save_dbFailure_emitsWarningNotError()
// BR-26: Resume fallback
@Test func test_resume_loadsLocalCheckpointFirst()
@Test func test_resume_fallsBackToDbByHostname_whenNoLocal()
// BR-27: Conflict resolution
@Test func test_resume_localWins_whenBothExistAndDiffer()
// BR-28/29: Cold start
@Test func test_coldStart_noDbNoCheckpoint_startsClean()
```

#### SubcommandRoutingTests
```swift
// BR-36: Retained
@Test func test_subcommand_pr_isAvailable()
@Test func test_subcommand_board_isAvailable()
@Test func test_subcommand_dashboard_isAvailable()
@Test func test_subcommand_doctor_isAvailable()
// BR-37: Deleted
@Test func test_subcommand_start_isNotRecognized()
@Test func test_subcommand_attach_isNotRecognized()
@Test func test_subcommand_session_isNotRecognized()
// BR-38: Stop remains
@Test func test_subcommand_stop_isAvailable()
// BR-39/40: State requirements
@Test func test_runningRequired_whenIdle_throwsNotRunningError()
@Test func test_runningRequired_whenRunning_executes()
@Test func test_nonRunningSubcommand_executesInAnyState()
```

#### TypoForgivenessTests
```swift
// BR-41/42: Levenshtein matching
@Test func test_typo_distance1_executesWithHint()
@Test func test_typo_distance2_executesWithHint()
@Test func test_typo_distance3_showsError()
@Test func test_typo_completeGarbage_showsError()
// BR-43: Stop safety
@Test func test_typo_closerToStop_showsErrorInsteadOfExecuting()
@Test func test_typo_stpo_doesNotExecuteStop()
@Test func test_typo_sotp_doesNotExecuteStop()
// BR-44: Case-insensitive
@Test func test_typo_caseInsensitive_matchesUppercase()
@Test func test_typo_caseInsensitive_matchesMixedCase()
```

#### WelcomeBackTests
```swift
// BR-45/46: Message format
@Test func test_resume_showsWelcomeBackMessage()
@Test func test_resume_showsLastSessionTimeAgo()
@Test func test_resume_showsSessionDuration()
@Test func test_resume_showsPaneCount()
// BR-47: Relative time
@Test func test_relativeTime_underOneMinute_showsLessThanOneMinute()
@Test func test_relativeTime_minutes_showsXm()
@Test func test_relativeTime_hours_showsXh()
@Test func test_relativeTime_days_showsXd()
// BR-48: Staleness
@Test func test_resume_checkpointOlderThan7d_showsStalenessWarning()
@Test func test_resume_checkpointUnder7d_noStalenessWarning()
// BR-49: Clean start
@Test func test_cleanStart_showsNoWelcomeBackMessage()
```

### Integration Tests

#### ShikkiEdgeCaseTests
```swift
// BR-50: Crash recovery
@Test func test_afterTmuxCrash_stateIsIdle()
@Test func test_afterTmuxCrash_checkpointPreserved()
// BR-51: DB unavailable
@Test func test_save_dbUnavailable_savesLocally()
@Test func test_save_dbUnavailable_setsDbSyncedFalse()
// BR-52: Base case
@Test func test_noCheckpointNoTmux_startsClean()
// BR-53: Concurrency
@Test func test_concurrentStartup_secondInstanceBlocked()
@Test func test_lockfile_releasedOnExit()
@Test func test_lockfile_stalePid_isOverridden()
// BR-54: Multiple attach
@Test func test_multipleAttach_doesNotCorruptSession()
// BR-55: Stop from inside tmux
@Test func test_stopFromInsideTmux_detachesFirst()
// BR-57: Atomic I/O
@Test func test_save_interruptedWrite_doesNotCorruptCheckpoint()
```

## Architecture

### Files to Create

| Path | Purpose |
|------|---------|
| `Sources/ShikiCtlKit/Models/ShikkiState.swift` | FSM enum (idle, running, stopping) + transition rules |
| `Sources/ShikiCtlKit/Models/Checkpoint.swift` | Codable struct: version, timestamp, hostname, fsmState, tmuxLayout, sessionStats, contextSnippet (4KB), dbSynced |
| `Sources/ShikiCtlKit/Services/StateDetector.swift` | Detects FSM state from tmux has-session + checkpoint file (<200ms) |
| `Sources/ShikiCtlKit/Services/CheckpointManager.swift` | save/load/exists/delete with atomic I/O (.tmp+rename) + legacy migration |
| `Sources/ShikiCtlKit/Services/LockfileManager.swift` | PID lockfile at ~/.shikki/shikki.pid (acquire/release/stale check) |
| `Sources/ShikiCtlKit/Services/CountdownTimer.swift` | Configurable countdown with raw terminal Esc cancel |
| `Sources/ShikiCtlKit/Services/TypoCorrector.swift` | Levenshtein ≤ 2 → execute + hint. Never for `stop` |
| `Sources/ShikiCtlKit/Services/WelcomeRenderer.swift` | "Welcome back" message from checkpoint data |
| `Sources/ShikiCtlKit/Services/DBSyncClient.swift` | Soft-fail checkpoint POST to ShikiDB (3s timeout) |
| `Sources/shikki/Commands/ShikkiCommand.swift` | Root entry point — no-arg FSM dispatch + subcommand routing |
| `Sources/shikki/Commands/StopCommand.swift` | New stop with countdown + checkpoint save + cleanup |

### Files to Delete

| Path | Replaced by |
|------|-------------|
| `Sources/shiki-ctl/Commands/StartupCommand.swift` | ShikkiCommand (FSM idle→running path) |
| `Sources/shiki-ctl/Commands/StopCommand.swift` | New StopCommand with countdown |
| `Sources/shiki-ctl/Commands/AttachCommand.swift` | ShikkiCommand (FSM running→attach path) |
| `Sources/shiki-ctl/Commands/SessionCommand.swift` | CheckpointManager + FSM |
| `Sources/ShikiCtlKit/Services/SessionCheckpointManager.swift` | CheckpointManager |
| `Sources/ShikiCtlKit/Services/SessionJournal.swift` | CheckpointManager |

### Files Unchanged (dependencies)

SessionRegistry, SessionStats, ProcessCleanup, SplashRenderer, EnvironmentDetector — all existing services used by new code.

### Key Protocols

```swift
// FSM State
enum ShikkiState: String, Codable {
    case idle, running, stopping
    var allowedTransitions: Set<ShikkiState> { ... }
}

// State detection
protocol StateDetecting {
    func detect() async -> ShikkiState  // <200ms, no network
}

// Checkpoint persistence
protocol CheckpointManaging {
    func save(_ checkpoint: Checkpoint) throws
    func load() throws -> Checkpoint?
    func exists() -> Bool
    func delete() throws
    func migrateLegacy() throws
}

// PID lockfile
protocol Lockable {
    func acquire() throws
    func release() throws
    func isHeld() -> Bool
    func staleCheck() -> Bool
}
```

### Checkpoint Model

```swift
struct Checkpoint: Codable {
    static let currentVersion = 1
    static let maxContextBytes = 4096
    let version: Int
    let timestamp: Date
    let hostname: String
    let fsmState: ShikkiState
    let tmuxLayout: TmuxLayout?      // paneCount, layout string, pane labels
    let sessionStats: SessionSnapshot? // startedAt, branch, commits, lines
    let contextSnippet: String?       // ≤4KB
    let dbSynced: Bool
}
```

### Data Flow

```
shikki [subcommand?]
    │
    ├─ Has subcommand? → route (TypoCorrector if unknown)
    │
    └─ No args → StateDetector.detect()
        ├─ IDLE (fresh)    → splash + env detect + tmux new + attach
        ├─ IDLE (resumable)→ WelcomeRenderer + restore layout + attach + delete checkpoint
        ├─ RUNNING         → execv tmux attach
        └─ STOPPING        → "Stop in progress" + exit 1

shikki stop [--countdown N]
    │
    ├─ StateDetector must be RUNNING
    ├─ Build Checkpoint (registry + stats + layout)
    ├─ CheckpointManager.save()  → local (hard error)
    ├─ DBSyncClient.sync()       → remote (soft warning)
    ├─ CountdownTimer.run(N)     → tick display, Esc cancels
    ├─ ProcessCleanup.reap()
    ├─ tmux kill-session -t shikki
    └─ LockfileManager.release()
```

### DI Approach

No DI container. Constructor injection with protocol-typed parameters. Composition root in `ShikkiCommand.run()`:

```swift
let lockfile = LockfileManager(path: Paths.pidFile)
let checkpoint = CheckpointManager(directory: Paths.shikkiDir)
let registry = SessionRegistry()
let detector = StateDetector(registry: registry, checkpoint: checkpoint)
```

### Paths

```swift
enum Paths {
    static let shikkiDir = ~/.shikki/
    static let checkpointFile = ~/.shikki/checkpoint.json
    static let pidFile = ~/.shikki/shikki.pid
    static let legacySessionsDir = ~/.shiki/sessions/
    static let legacyJournalDir = ~/.shiki/journal/
}
```

### Package.swift Changes

```swift
// Old: .executableTarget(name: "shiki-ctl", ...)
// New: .executableTarget(name: "shikki", path: "Sources/shikki")
```

Source directory: `Sources/shiki-ctl/` → `Sources/shikki/`. Library `ShikiCtlKit` keeps its name.

Post-build: `scripts/install.sh` creates `shi → shikki` symlink in `~/.local/bin/`.

### Legacy Migration

In `CheckpointManager.migrateLegacy()` (called once before detect):
1. Read most recent `~/.shiki/sessions/*.json`
2. Convert to Checkpoint schema → write `~/.shikki/checkpoint.json`
3. Rename legacy dirs to `.migrated/` (don't delete)
4. Idempotent — skips if `.migrated/` exists

### Test Suite → Implementation Map

| Test Suite | Implementation File | Tests |
|------------|-------------------|-------|
| ShikkiStateTests | Models/ShikkiState.swift | ~5 |
| CheckpointTests | Models/Checkpoint.swift | ~8 |
| StateDetectorTests | Services/StateDetector.swift | ~6 |
| CheckpointManagerTests | Services/CheckpointManager.swift | ~10 |
| LockfileManagerTests | Services/LockfileManager.swift | ~5 |
| CountdownTimerTests | Services/CountdownTimer.swift | ~5 |
| TypoCorrectorTests | Services/TypoCorrector.swift | ~6 |
| WelcomeRendererTests | Services/WelcomeRenderer.swift | ~6 |
| DBSyncClientTests | Services/DBSyncClient.swift | ~4 |
| ShikkiCommandTests | Commands/ShikkiCommand.swift | ~5 |
| StopCommandTests | Commands/StopCommand.swift | ~5 |

**Total: ~65 tests across 11 suites.**

All testable via protocol injection — StateDetector gets mock Registry+Checkpoint, CountdownTimer gets mock InputStream, DBSyncClient gets mock URLSession, CheckpointManager uses temp directory.

## Execution Plan

18 tasks, 99 tests, ~110 min sequential / ~60 min with parallelism.

### Task 1: ShikkiState FSM enum (~5 min)
- **Files**: `Models/ShikkiState.swift` (new)
- **Test**: `ShikkiStateTests.swift` → 8 tests (transitions valid/invalid)
- **BRs**: BR-01 to BR-06
- **Depends on**: none

### Task 2: Checkpoint model (~5 min)
- **Files**: `Models/Checkpoint.swift` (new)
- **Test**: `CheckpointTests.swift` → 8 tests (schema, 4KB truncation)
- **BRs**: BR-20, BR-21
- **Depends on**: Task 1

### Task 3: CheckpointManager — save/load/exists/delete (~8 min)
- **Files**: `Services/CheckpointManager.swift` (new)
- **Test**: `CheckpointManagerTests.swift` → 10 tests (atomic I/O, CRUD)
- **BRs**: BR-19, BR-20, BR-22, BR-23, BR-28, BR-57
- **Depends on**: Task 2

### Task 4: CheckpointManager — legacy migration (~8 min)
- **Files**: `Services/CheckpointManager.swift` (modify)
- **Test**: `CheckpointManagerTests.swift` → +3 tests (migrate, skip, idempotent)
- **BRs**: BR-24, BR-35
- **Depends on**: Task 3

### Task 5: LockfileManager (~5 min)
- **Files**: `Services/LockfileManager.swift` (new)
- **Test**: `LockfileManagerTests.swift` → 8 tests (acquire, release, stale PID)
- **BRs**: BR-53
- **Depends on**: none

### Task 6: StateDetector (~5 min)
- **Files**: `Services/StateDetector.swift` (new)
- **Test**: `StateDetectorTests.swift` → 6 tests (idle/running/crash, <200ms)
- **BRs**: BR-02, BR-03, BR-07, BR-50
- **Depends on**: Task 1, Task 3

### Task 7: TypoCorrector (~5 min)
- **Files**: `Services/TypoCorrector.swift` (new)
- **Test**: `TypoCorrectorTests.swift` → 9 tests (Levenshtein, stop safety, case)
- **BRs**: BR-41 to BR-44
- **Depends on**: none

### Task 8: WelcomeRenderer (~5 min)
- **Files**: `Services/WelcomeRenderer.swift` (new)
- **Test**: `WelcomeRendererTests.swift` → 11 tests (format, relative time, staleness)
- **BRs**: BR-45 to BR-49
- **Depends on**: Task 2

### Task 9: CountdownTimer (~8 min)
- **Files**: `Services/CountdownTimer.swift` (new)
- **Test**: `CountdownTimerTests.swift` → 9 tests (ticks, Esc cancel, non-TTY, clamp)
- **BRs**: BR-13 to BR-18
- **Depends on**: none

### Task 10: DBSyncClient (~8 min)
- **Files**: `Services/DBSyncClient.swift` (new)
- **Test**: `DBSyncClientTests.swift` → 8 tests (soft-fail, hostname fallback, local wins)
- **BRs**: BR-25 to BR-29, BR-51
- **Depends on**: Task 2, Task 3

### Task 11: Package.swift rename shiki-ctl → shikki (~5 min)
- **Files**: `Package.swift` (modify), `Sources/shiki-ctl/` → `Sources/shikki/`
- **Test**: build verification only
- **BRs**: BR-30 to BR-33
- **Depends on**: none (but blocks Tasks 12+)

### Task 12: ShikkiCommand root entry point (~10 min)
- **Files**: `Commands/ShikkiCommand.swift` (new)
- **Test**: `ShikkiEntryPointTests.swift` → 6 tests (FSM dispatch per state)
- **BRs**: BR-08 to BR-11, BR-34, BR-36 to BR-40
- **Depends on**: Tasks 1, 3, 5, 6, 8, 11

### Task 13: ShikkiStopCommand with countdown (~10 min)
- **Files**: `Commands/ShikkiStopCommand.swift` (new)
- **Test**: `StopCountdownTests.swift` → 7 tests (state check, countdown, cancel)
- **BRs**: BR-12 to BR-18, BR-55
- **Depends on**: Tasks 1, 3, 5, 6, 9, 10, 11

### Task 14: Subcommand routing + state guards (~5 min)
- **Files**: `Commands/ShikkiCommand.swift` (modify)
- **Test**: `SubcommandRoutingTests.swift` → 11 tests (retained/deleted/guards)
- **BRs**: BR-36 to BR-40
- **Depends on**: Task 12

### Task 15: Typo correction integration (~5 min)
- **Files**: `Commands/ShikkiCommand.swift` (modify)
- **BRs**: BR-41 to BR-44
- **Depends on**: Tasks 7, 12

### Task 16: Edge case integration tests (~8 min)
- **Files**: `ShikkiEdgeCaseTests.swift` (new)
- **Test**: 11 tests (crash recovery, concurrent startup, atomic I/O)
- **BRs**: BR-50 to BR-57
- **Depends on**: Tasks 3, 5, 6, 10, 13

### Task 17: Wire @main + remove old ShikiCtl.swift (~5 min)
- **Files**: `ShikiCtl.swift` (modify/replace)
- **BRs**: BR-30 to BR-34
- **Depends on**: Tasks 11, 12, 13, 14

### Task 18: Delete legacy files (~10 min)
- **Files**: DELETE 6 files (StartupCommand, old StopCommand, AttachCommand, SessionCommand, PausedSessionManager, SessionJournal)
- **Test**: full suite must pass
- **BRs**: BR-34, BR-35
- **Depends on**: ALL previous tasks

### Parallelism Map
```
Wave 1 (parallel): T1, T5, T7, T9, T11
Wave 2 (parallel): T2, T8 (need T1)
Wave 3 (parallel): T3, T6 (need T2)
Wave 4 (parallel): T4, T10 (need T3)
Wave 5: T12 (needs T1,3,5,6,8,11)
Wave 6 (parallel): T13, T14, T15 (need T12)
Wave 7: T16 (needs T3,5,6,10,13)
Wave 8: T17 (needs T11,12,13,14)
Wave 9: T18 (needs ALL)
```

### Implementation Readiness Gate

| Check | Status | Detail |
|-------|--------|--------|
| BR Coverage | PASS | 57/57 BRs mapped |
| Test Coverage | PASS | 99/99 signatures mapped |
| File Alignment | PASS | 11/11 new files + 6 deletions covered |
| Task Dependencies | PASS | DAG, no cycles, max parallelism 5 |
| Task Granularity | PASS | All ≤ 10 min |
| Testability | PASS | All tasks have verify step |

**Verdict: PASS** — ready for Phase 6 (Implementation).

## Implementation Log
<!-- Decisions, progress notes, SDD progress table -->

## Review History
| Date | Phase | Reviewer | Decision | Notes |
|------|-------|----------|----------|-------|
