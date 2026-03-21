# Shiki — Full PR Review Queue

> Generated: 2026-03-18
> PRs: #2, #3, #5, #6 (all open)

---

## 1. Executive Summary

| Metric | Value |
|--------|-------|
| **Total PRs** | 4 |
| **Total additions** | +26,135 |
| **Total deletions** | -800 |
| **Total files changed** | 261 (with 7 overlapping between PR #5 and #6) |
| **Total tests** | ~262 (39 MediaKit + 0 backend + 52 CLI v0.2 + 171 Wave 1) |

### Risk Heatmap

| PR | Risk | Reason |
|----|------|--------|
| **#3** | **CRITICAL** | Targets `main` (violates git flow), zero backend tests for 778-line orchestrator, destructive DDL migrations |
| **#6** | **HIGH** | 4,657 lines of new platform code, pipe deadlock pattern in 8 legacy files, session state machine complexity |
| **#5** | **MEDIUM-HIGH** | 4 known unfixed bugs documented, untested command layer (502-line StartupCommand), force-unwrap |
| **#2** | **MEDIUM** | Hardcoded secrets in garage.toml, stub uploader ships as default, disconnected retry queue |

### Dependency Chain

```
PR #5 (CLI foundation) ──> PR #6 (Wave 1, based on PR #5 branch)
PR #2 (MediaKit) ─────────> independent
PR #3 (orchestrator) ─────> BROKEN TARGET (main instead of develop)
```

---

## 2. Review by Topic

---

### CRITICAL PATH (review first)

#### Session Foundation — PR #6

**Files:** `SessionLifecycle.swift`, `SessionJournal.swift`, `SessionRegistry.swift`
**Tests:** 31 (SessionLifecycleTests, SessionJournalTests, SessionRegistryTests, SessionIntegrationTests)

The core state machine for session management. `SessionLifecycle` defines the `.idle -> .starting -> .running -> .stopping -> .stopped` state machine. `SessionJournal` writes JSONL to `~/.shiki/journal/`. `SessionRegistry` tracks active sessions with attention-zone sorted output.

**Review focus:**
- State machine transition safety — verify no invalid transitions are silently allowed
- Journal file I/O error handling — what happens when disk is full or path is unwritable?
- Registry cleanup on crash — does an unclean shutdown leave stale entries?

#### Event Bus + Router — PR #6

**Files:** `EventBus.swift`, `ShikiEvent.swift`, `PRReviewEvents.swift`, `ShikiDBEventLogger.swift`
**Tests:** 14 (EventBusTests, ShikiDBEventLoggerTests)

In-process event bus implementing the `ShikiEvent` protocol from `features/shiki-event-bus-architecture.md`. The DB logger posts events to the Shiki backend for observability.

**Review focus:**
- Event delivery guarantees — fire-and-forget vs. at-least-once?
- DB logger failure mode — does a backend outage block event delivery or silently drop?
- Thread safety of the in-process bus under concurrent publishers

#### HeartbeatLoop Changes — PR #5 + PR #6 (OVERLAPPING)

**PR #5:** +104/-20 — adds `checkStaleCompanies()` (documented as disabled) and decision re-dispatch logic
**PR #6:** further modifications to HeartbeatLoop

**Review focus:**
- `checkStaleCompanies()` is dead code in PR #5 — is it activated in PR #6?
- Merge conflict risk: both PRs modify this file
- Decision re-dispatch logic is unverified in integration tests

---

### ARCHITECTURE

#### Agent Personas + Watchdog — PR #6

**Files:** `AgentPersona.swift`, `Watchdog.swift`, `AgentMessages.swift`
**Tests:** 20 (AgentPersonaTests, WatchdogTests, AgentCoordinationTests)

Defines the agent persona system (@Sensei, @Hanami, etc.) and a progressive watchdog for session health monitoring.

**Review focus:**
- Watchdog escalation thresholds — are they configurable or hardcoded?
- Persona message routing — does it integrate with the event bus?
- Orphan reaping safety — per `feedback_orphan-reaping-safety.md`, must only reap Shiki-created panes

#### Observatory + Dashboard — PR #6

**Files:** `DashboardSnapshot.swift`, `DashboardCommand.swift`, `TerminalSnapshot.swift`
**Tests:** 7 (TerminalSnapshotTests + snapshots: `attention-zones.snapshot`, `dashboard-sessions.snapshot`)

Dashboard model with attention-zone gradient rendering (bright top, dim bottom per `feedback_attention-zones-gradient.md`).

**Review focus:**
- Snapshot rendering correctness — verify against snapshot files
- Terminal width handling — does it degrade gracefully on narrow terminals?

#### Living Specs (SpecDocument) — PR #6

**Files:** `SpecDocument.swift`
**Tests:** 8 (SpecDocumentTests)

Living specification documents that track deliverables and their implementation status.

#### S3 Parser + External Tools — PR #6

**Files:** `ExternalTools.swift`
**Tests:** 11 (ExternalToolsTests)

External tool integration (qmd, fzf, etc.) following `feedback_external-tools-philosophy.md` — use now (shell-out), build later.

#### Multi-Agent Coordination — PR #6

**Files:** `HandoffChain.swift`, `RecoveryManager.swift`, `PRFixAgent.swift`, `PRQueue.swift`
**Tests:** 10 (PRQueueTests + UserFlowTests)

Agent-to-agent handoff chains, crash recovery, and PR fix automation.

**Review focus:**
- Recovery manager — what state is preserved across crashes?
- Handoff chain — is there a timeout for unresponsive agents?

---

### CLI COMMANDS

#### StartupCommand (smart startup) — PR #5

**File:** `Commands/StartupCommand.swift` (+502 lines)
**Tests:** **NONE** (only `StartupRendererTests` covers the renderer, not the orchestration)

**Known issues:**
- Force-unwrap on line 130 (`completionDate!`)
- Hardcoded paths (`~/Documents/Workspaces/shiki`)
- Monolithic: mixes Docker bootstrap, tmux layout, health polling in one file
- Uses `execv`, `Process`, `fflush(stdout)`, raw ANSI codes

**Verdict:** Highest-risk untested code in the entire queue. Extract orchestration into a testable service.

#### StopCommand + ProcessCleanup — PR #5 + PR #6 (OVERLAPPING)

**PR #5:** `StopCommand.swift` (+106), `ProcessCleanup.swift` (+182)
**PR #6:** further `StopCommand.swift` modifications
**Tests:** `ProcessCleanupTests` (158 lines, mock-only)

**Known issues:**
- Self-kill risk when run from inside tmux (documented bug #3 in session doc)
- `ProcessCleanup` may not be wired into `StopCommand` — verify call chain
- Real `pkill`/`pgrep` behavior untested

#### DoctorCommand — PR #6

**File:** `Commands/DoctorCommand.swift`
**Tests:** DoctorTests + `doctor-diagnostics.snapshot`

System health diagnostics: binary detection, disk space, configuration validation.

#### StatusCommand — PR #5 + PR #6 (OVERLAPPING)

**PR #5:** +66/-1 — adds workspace + session detection
**PR #6:** further modifications for attention-zone output

Both PRs touch this file — merge conflict likely.

#### Other Commands — PR #5

| Command | Lines | Tests | Risk |
|---------|-------|-------|------|
| `RestartCommand` | +115 | **NONE** | HIGH — sends `C-c` to tmux panes by index |
| `AttachCommand` | +40 | **NONE** | LOW — thin tmux wrapper |
| `HeartbeatCommand` | +9/-4 | Existing | LOW — rename only |
| `DecideCommand` | +25/-3 | Existing | LOW — multiline fix |

---

### BACKEND

#### Orchestrator Routes + Dispatcher — PR #3

**Files:** `orchestrator.ts` (778 lines), `routes.ts` (+308 lines), `schemas.ts` (+121 lines)
**Tests:** **ZERO** in diff (82 E2E assertions claimed in PR body but absent from diff)

22 new REST endpoints. Atomic task claim with `FOR UPDATE SKIP LOCKED`. Budget tracking. Decision queue with auto-unblock.

**Known issues:**
- **Route fragility:** `path.split("/")[3]` for ID extraction, no param middleware
- **Route ordering dependency:** `/api/decision-queue/pending` must precede `/api/decision-queue/:id`
- **Dual budget source:** `companies.budget` JSONB vs. `company_budget_log` SUM — which is truth?

#### DB Migrations — PR #3

**Files:** `004_orchestrator.sql` (186 lines), `005_dispatcher_model.sql` (100 lines), `006_session_transcripts.sql`

**Known issues:**
- Requires TimescaleDB extension — fails silently if missing
- Migration 005 drops index from 004 and replaces its view — implicit ordering
- FK references to `projects` and `pipeline_runs` — migration fails if those tables don't exist

#### Budget System — PR #3

Cumulative budget computed atomically via `INSERT ... SELECT SUM()` in `company_budget_log`. But `companies.budget` JSONB also stores `spent_today_usd`. Two sources of truth.

---

### PACKAGES

#### MediaKit SPM + Garage S3 — PR #2

**Files:** 48 files (26 source, 13 test, 9 infra)
**Tests:** 39 (all passing)

GPS-authenticated activity photo pipeline: metadata extraction, corridor matching, compression, actor-based retry queue, DI assembly.

**Known issues:**
- **Hardcoded secrets** in `deploy/garage.toml` (`rpc_secret`, `admin_token`)
- **StubMediaUploader as default** in `MediaKitAssembly` — no guard against shipping to prod
- **Disconnected retry queue** — `BackgroundRetryQueue` and `FailedUploadManager` are not wired together; exhausted items silently dropped
- **Non-Codable corridor config** — tuple array blocks serialization
- **Duplicate commit** — `setup-garage-local.sh` appears twice (rebase artifact)

#### Shared SPM Packages — PR #3 (bundled)

CoreKit, NetworkKit, SecurityKit, DesignKit, ShikiKit — all included in PR #3.

**Issue:** DesignKit is deprecated (replaced by DSKintsugi per MEMORY.md) but ships in this PR (+11 files, ~1,000 lines of dead code).

---

### KNOWN ISSUES (consolidated from precomputed reviews)

| PR | Issue | Severity | Status |
|----|-------|----------|--------|
| **#3** | Targets `main` instead of `develop` | **BLOCKER** | Must retarget or close/redo |
| **#3** | Zero backend tests (778-line orchestrator) | **HIGH** | No E2E tests in diff |
| **#3** | Dual budget source (JSONB vs. log table) | **MEDIUM** | Needs single source of truth |
| **#3** | DesignKit included but deprecated | **LOW** | Remove from PR |
| **#2** | Hardcoded secrets in garage.toml | **BLOCKER** | Move to .env |
| **#2** | StubMediaUploader as default | **MEDIUM** | Make uploader required param |
| **#2** | BackgroundRetryQueue drops items silently | **MEDIUM** | Wire FailedUploadManager |
| **#2** | Duplicate commit | **LOW** | Squash |
| **#5** | StartupCommand untested (502 lines) | **HIGH** | Extract into testable service |
| **#5** | Force-unwrap line 130 | **MEDIUM** | Use `if let` |
| **#5** | 4 known unfixed bugs (ghost, stale, self-kill, curl) | **HIGH** | Documented in session doc |
| **#5** | StopCommand/RestartCommand untested | **MEDIUM** | Add tests |
| **#6** | Pipe deadlock pattern in 8 legacy files | **HIGH** | Needs audit |
| **#6** | 7 files overlap with PR #5 | **MEDIUM** | Merge #5 first to avoid conflicts |

---

## 3. Merge Order

```
Step 1: PR #5 → develop     (CLI foundation — merge FIRST)
        Branch: feature/cli-core-architecture → develop
        Prerequisites: fix force-unwrap, verify ProcessCleanup wiring
        Command: gh pr merge 5 --squash

Step 2: PR #6 → PR #5 branch → develop  (Wave 1 — merge SECOND)
        Branch: feature/v3-wave1-sessions → feature/cli-core-architecture
        Prerequisites: PR #5 merged, rebase onto develop
        After PR #5 merges, retarget PR #6 base to develop:
          gh pr edit 6 --base develop
        Then: gh pr merge 6 --squash

Step 3: PR #2 → develop     (MediaKit — INDEPENDENT, merge anytime)
        Branch: story/media-strategy → develop
        Prerequisites: remove hardcoded secrets, squash duplicate commit
        Command: gh pr merge 2 --squash

Step 4: PR #3 → CLOSE       (targets main — violates git flow)
        Branch: develop → main
        Action: Close PR, cherry-pick backend changes into a new
                feature/orchestrator-backend branch, open new PR → develop
        Command: gh pr close 3 --comment "Retargeting to develop per git flow"
```

---

## 4. Per-PR Quick Reference

| | PR #5 | PR #6 | PR #2 | PR #3 |
|---|---|---|---|---|
| **Title** | feat(shiki-ctl): v0.2.0 CLI migration + orchestrator fixes | feat(shiki-ctl): Wave 1 — Session Foundation | story: Media Strategy — MediaKit SPM + Garage S3 infra | feat(orchestrator): multi-company autonomous agency |
| **Branch** | `feature/cli-core-architecture` | `feature/v3-wave1-sessions` | `story/media-strategy` | `develop` |
| **Base** | `develop` | `feature/cli-core-architecture` | `develop` | `main` |
| **Additions** | +3,010 | +4,657 | +2,022 | +16,446 |
| **Deletions** | -767 | -33 | -0 | -0 |
| **Files** | 28 | 50 | 48 | 135 |
| **Commits** | 1 | 15 | 34 | 19 |
| **Tests** | 52 (13 suites) | 171 (31 suites) | 39 (14 suites) | ~124 (Swift only, 0 backend) |
| **Risk** | **MEDIUM-HIGH** | **HIGH** | **MEDIUM** | **CRITICAL** |
| **Blockers** | Force-unwrap, untested commands | Depends on PR #5 merge | Hardcoded secrets | Targets main (git flow violation) |
| **Review time est.** | ~45 min | ~60 min | ~30 min | ~20 min (close + plan redo) |

---

## Review Session Plan (30-minute speed run)

1. **[5 min] PR #3 — Triage only.** Confirm it targets `main`. Close it. Note backend changes to cherry-pick later.
2. **[10 min] PR #5 — CLI foundation.** Focus on: force-unwrap fix, ProcessCleanup wiring into StopCommand, HeartbeatLoop dead code. Skip README changes and docs.
3. **[10 min] PR #6 — Wave 1 architecture.** Focus on: SessionLifecycle state transitions, EventBus thread safety, Watchdog orphan reaping rules, overlapping files with PR #5.
4. **[5 min] PR #2 — MediaKit.** Focus on: secrets in garage.toml (blocker), StubMediaUploader default registration. Rest is clean.

---

*Generated by shiki-ctl review-queue | 2026-03-18*
