# PR #5 Review — feat(shiki-ctl): v0.2.0 CLI migration + orchestrator fixes

> **Branch**: `feature/cli-core-architecture` → `develop`
> **Files**: 28 changed, +3,010 / -767
> **Tests**: 52/52 green, 13 suites
> **Pre-PR**: All gates passed (1 fix iteration on Gate 1b)

---

## Review Sections

Navigate with your editor's heading jumps (e.g., `gj`/`gk` in vim, `Ctrl+Shift+O` in VS Code).

### Section 1: Architecture Overview

| Layer | Role | Files |
|-------|------|-------|
| **Commands** (`shiki-ctl/Commands/`) | CLI entry points, user-facing | 7 files (Startup, Stop, Restart, Attach, Heartbeat, Decide, Status) |
| **Services** (`ShikiCtlKit/Services/`) | Business logic, reusable | 8 files (ProcessCleanup, HeartbeatLoop, BackendClient, CompanyLauncher, etc.) |
| **Protocols** (`ShikiCtlKit/Protocols/`) | Abstractions for testability | ProcessLauncher, EnvironmentChecking, NotificationSender |
| **Tests** (`Tests/`) | 52 tests, 13 suites | 7 test files |
| **Scripts** (`scripts/`) | Bash wrapper + zsh completions | 2 files |
| **Docs** (`docs/`) | Vision spec | 1 file |

**Key design decision**: Commands are thin (parse args → call services). All logic lives in `ShikiCtlKit` so it's testable without CLI parsing.

---

### Section 2: Critical Path — Ghost Process Cleanup

**The bug**: `shiki stop` killed the tmux session but orphaned Claude/xcodebuild/Simulator processes survived.

**The fix** (2 files):

**`ProcessCleanup.swift`** (NEW, 182 lines)
- `collectSessionPIDs(session:)` — enumerates all pane PIDs from non-reserved tmux windows
- `killProcessTree(pid:)` — SIGTERM children first, wait 500ms, SIGKILL survivors
- `cleanupSession(session:)` — orchestrates: collect PIDs → kill task windows → kill orphans → return stats
- `findOrphanedClaudeProcesses()` — `pgrep -x claude` (exact binary match, not `-f` which is too broad)
- Single source of truth for `reservedWindows: Set<String> = ["orchestrator", "board", "research"]`

**`StopCommand.swift`** (REWRITTEN, 106 lines)
- Before: `tmux kill-session -t shiki` (one line, everything dies)
- After: `ProcessCleanup.cleanupSession()` → kill tmux session last
- Reports: "Killed N task window(s)", "Killed N orphaned process(es)"

**Review questions**:
- [ ] Is `usleep(500_000)` acceptable for SIGTERM→SIGKILL wait? (CLI context, blocking is OK)
- [ ] Should `findOrphanedClaudeProcesses` also look for `xcodebuild`, `swift-test`, `swift-build`?
- [ ] Is the self-PID filter (`myPID` + `getppid()`) sufficient to avoid self-kill?

---

### Section 3: Orchestrator — Smart Stale Relaunch

**The bug**: `checkStaleCompanies()` was disabled — it relaunched ALL stale companies every 60s cycle.

**The fix** (`HeartbeatLoop.swift`, new method `checkStaleCompaniesSmart`):
```
For each stale company:
  Skip if → no pending tasks in dispatcher queue
  Skip if → already has a running tmux session
  Skip if → budget exhausted (spentToday >= dailyUsd)
  Otherwise → relaunch with launchTaskSession
```

**Review questions**:
- [ ] Is the budget check correct? (compares `task.spentToday` vs `task.budget.dailyUsd`)
- [ ] Should there be a cooldown to prevent rapid relaunch cycles?

---

### Section 4: Orchestrator — Decision Unblock

**The bug**: After `shiki decide` answers a question, the company session that asked it may be dead. Nobody re-dispatches.

**The fix** (`HeartbeatLoop.swift`, new method `checkAnsweredDecisions`):
```
Track previousPendingDecisionIds across cycles
Diff: answered = previous - current
If any answered → check if company has a running session
If dead → log "unblocked, checkAndDispatch runs next"
checkAndDispatch() handles actual re-launch (same cycle)
```

**Optimization**: `checkDecisions()` now returns `[Decision]`, reused by `checkAnsweredDecisions(currentPending:)` — no redundant API call.

**Review questions**:
- [ ] Is tracking only decision IDs sufficient, or should we track the company slug too?
- [ ] Should we explicitly trigger dispatch for unblocked companies instead of relying on checkAndDispatch order?

---

### Section 5: BackendClient Migration

**The change**: `AsyncHTTPClient` → curl subprocess.

**Why**: Connection pools go stale with Docker networking. After Docker restart or Colima hiccup, all subsequent requests hang until connect timeout (5s). curl doesn't maintain a pool — each request is independent.

**Key methods**: `get<T>`, `post<T>`, `patch<T>` all delegate to `curlRequest(method:path:body:)`.

**Review questions**:
- [ ] Is curl subprocess per request acceptable performance-wise? (60s heartbeat interval → at most ~5 curl calls per cycle)
- [ ] Should we add a retry on curl timeout?

---

### Section 6: Smart Startup

**`StartupCommand.swift`** (NEW, 502 lines — largest file)

6-step flow:
1. **Environment** — detect Docker, Colima, LM Studio, backend health
2. **Docker bootstrap** — `docker compose up -d` if containers not running
3. **Orchestrator data** — count companies via API
4. **Binary** — detect if running from compiled binary or `swift run`
5. **Status** — render dashboard (box-drawing, session stats, git line counts)
6. **Tmux** — create session with 3 tabs (orchestrator, board, research), auto-attach

**Review questions**:
- [ ] Is 502 lines too large for one command? Should env detection be extracted?
- [ ] The `EnvironmentDetector` protocol is good — but StartupCommand also does its own Process calls. Consolidate?

---

### Section 7: Other Commands

| Command | Lines | What it does |
|---------|-------|-------------|
| **RestartCommand** | 115 | Sends Ctrl-C to orchestrator pane, waits 1s, relaunches heartbeat. Session preserved. |
| **AttachCommand** | 40 | `execv` to replace process with `tmux attach-session`. Clean handoff. |
| **HeartbeatCommand** | 57 | Internal — launched by StartupCommand inside tmux. Wires up BackendClient + TmuxProcessLauncher + notifier → HeartbeatLoop.run() |
| **DecideCommand** | 116 | Multiline input fix: `readMultilineInput()` collects lines until empty line (double-enter). |
| **StatusCommand** | 158 | Added workspace path detection + multi-session awareness. |

**Review questions**:
- [ ] RestartCommand duplicates `tmuxSessionExists` / `shellExec` / workspace resolution from other commands. Extract to shared helper?
- [ ] AttachCommand uses `execv` — is this safe with Swift's runtime?

---

### Section 8: Tests

| Suite | Tests | Coverage |
|-------|-------|----------|
| Process cleanup on stop | 5 | ProcessCleanup: nonexistent session, PID killing, reserved windows, orphan detection |
| Smart stale company relaunch | 2 | Skip if session exists, budget exhaustion |
| Decision unblock re-dispatch | 2 | Answered detection via set diff, dead session re-dispatch |
| Session health monitoring | 3 | Stale (3min+), fresh (<3min), unknown session |
| Window naming | 2 | Format, short title |
| HeartbeatLoop unit logic | 3 | Notification, launcher tracking, session listing |
| EnvironmentDetector | 4 | Mock environment checks |
| SessionStats | 1 | Non-git directory returns empty |
| StartupRenderer | 2 | Empty data, full data |
| BackendClient response parsing | 4 | Status, company, decision, overview |
| BackendClient connection resilience | 1 | Unreachable backend |
| CLI command parsing | 2 | Subcommands registered, version |
| ScheduleEvaluator | 4 | Window checks |

**Known limitation** (flagged in /pre-pr): Tests are shallow — they test "doesn't crash" paths, not behavior with mocked subprocesses. Acceptable for v0.2.0 velocity, needs `ProcessRunner` protocol for proper testability post-release.

---

### Section 9: Docs & Scripts

| File | What |
|------|------|
| `README.md` | Rewritten: 496→~150 lines, reflects v0.2.0 reality |
| `docs/session-2026-03-16-vision-and-architecture.md` | Full session reconstruction: vision, debates, decisions, bugs, phasing |
| `scripts/shiki` | Added `restart` subcommand, improved `stop` |
| `scripts/install-completions.sh` | Zsh autocompletion for all 12 subcommands |

---

### Section 10: Pre-PR Gate Results

| Gate | Status | Notes |
|------|--------|-------|
| Spec review (1a) | SKIPPED | Bug-fix/infra PR, no feature file |
| @Sensei review (1b) | **PASS** | After fix: `pgrep -x` (exact), removed dead `sessionLastSeen`, deduplicated constants |
| @tech-expert review (1b) | **PASS** | After fix: cached API call, fixed misleading comment |
| @Hanami review (1b) | N/A | No UI changes |
| Tests (3) | **52/52** | 13 suites, all green |
| Visual QC (5) | SKIPPED | CLI project |
| AI Slop Scan (8) | **CLEAN** | 2 hits in autopilot prompt (functional) |

---

## Reviewer Checklist

Mark as you go:

- [ ] **Section 2**: ProcessCleanup logic is correct and safe
- [ ] **Section 3**: Smart stale relaunch conditions are complete
- [ ] **Section 4**: Decision unblock flow handles edge cases
- [ ] **Section 5**: curl migration is acceptable trade-off
- [ ] **Section 6**: StartupCommand complexity is manageable
- [ ] **Section 7**: Command duplication is acceptable for now
- [ ] **Section 8**: Test coverage is sufficient for v0.2.0
- [ ] **Section 9**: README and docs are accurate
- [ ] **Overall**: Ready to merge to develop
