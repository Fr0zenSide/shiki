# Feature: Shikki Native Scheduler
> Created: 2026-03-25 | Status: Phase 1 — Inspiration | Owner: @Daimyo

## Context
Shikki's heartbeat loop runs 24/7. It already evaluates company schedules (active hours, timezone, days). But there's no way for the user to schedule arbitrary recurring tasks — radar scans, corroboration sweeps, report generation, backlog triage. Currently these depend on external Anthropic cloud triggers (vendor lock-in, can't reach local ShikiDB, no project awareness). The native scheduler turns the heartbeat into a full crontab that understands companies, budgets, agents, and the mesh. If no main node is running, a temporary agent node spawns to handle the task, then exits — serverless for agents.

## Inspiration
### Brainstorm Results

| # | Idea | Source | Feasibility | Impact | Project Fit | Verdict |
|---|------|--------|:-----------:|:------:|:-----------:|--------:|
| 1 | **HeartbeatScheduler** — `ScheduleEvaluator` injected into existing heartbeat loop. `scheduled_tasks` DB table. Each tick evaluates all tasks against `Date.now`, fires matching ones through CompanyManager dispatch. No new loop, no new timer — just a new evaluator in the existing tick. ~200 LOC. | @Sensei | High | High | Strong | BUILD |
| 2 | **EphemeralAgentNode** — When a scheduled task fires and no orchestrator is running, spawn a minimal agent process via `AgentRunner.run()`. Temporary CapabilityManifest, execute, persist results, exit. First node to claim the task row (optimistic SQL lock: `claimed_by + claimed_at`) wins, others skip. Zero residual footprint. | @Sensei | Medium | High | Strong | BUILD |
| 3 | **NativeTriggerMigration** — Replace ALL Anthropic cloud triggers with `ScheduledTask` rows. Daily radar → `0 5 * * * radar-scan`. Cloud triggers become fallback-only (wake-up ping via ntfy if all nodes offline >2x interval). Eliminates vendor lock-in for scheduling. | @Sensei | High | Critical | Strong | BUILD |
| 4 | **Cron-Style Schedule CLI** — `shikki schedule add "backup wabisabi" --at 03:00 --days mon,wed,fri --company wabisabi` / `shikki schedule list` / `shikki schedule rm <id>`. In `shikki status`: "Next: backup-wabisabi in 2h14m". Extends existing ScheduleEvaluator from company-level gating to per-task triggers. | @Hanami | High | Medium-High | Strong | BUILD |
| 5 | **Sleep/Wake Personality Layer** — Tamagotchi sleep cycle: `zzz wabisabi (wakes 08:00)`. Wake-up sequence: sleeping → stretching → active (3 ASCII frames). After task: yawn → sleep. MiniStatusFormatter gets `.sleeping` icon (dim moon). The user opens terminal and sees the machine has been working and resting on its own. | @Hanami | Medium | High | Strong | BUILD |
| 6 | **Patina Heartbeat — Scheduled Corroboration Sweeps** — When a scheduled task touches a project, emit `corroboration_sweep` event refreshing all memories in that scope. Nightly task queries memories with freshness < 0.3 and dispatches lightweight agent to verify/update/archive. The machine wakes, tends its memory garden, sleeps. In `shikki status`: `patina: 12 memories fading`. | @Kintsugi | Medium | High | Strong | BUILD |

### @t Team Review (2026-03-25)

**@Ronin — 3 Critical Failure Modes:**
1. **Mac sleep/lid close** — `Task.sleep` drifts during macOS suspend. No `NSWorkspace.willSleepNotification` / `didWakeNotification` handler. Post-wake heartbeat may fire stale tasks or false-positive Watchdog kills. NEED: sleep/wake event handler to freeze timers and reconcile.
2. **Two nodes + same cron** — `LockfileManager` is single-machine PID-based. No distributed lock. Both nodes dispatch same task = double-spend, conflicting git ops. NEED: atomic `claimTask` endpoint with TTL lease (or DB advisory lock).
3. **Crash mid-task** — Signal handler only catches SIGINT/SIGTERM. SIGKILL/OOM = ghost tmux sessions. `SessionRegistry` is in-memory only, doesn't reconcile with running panes on restart. NEED: scan tmux panes on startup before first dispatch.

**@Shogun — Competitive Analysis:**
- GitHub Actions cron: unreliable (15-60min delays), no overlap prevention, fire-and-forget
- Temporal/Inngest: durable execution via event replay, but not agent-native (functions, not AI sessions)
- Linear: cloud-hosted SaaS triggers, no local execution
- n8n: cron + Redis queue + workers, but stateless DAGs not agent sessions
- **Gap**: No tool combines project-aware scheduling + agent orchestration + budget constraints. Shikki sits at the intersection.

**@Katana — Security Note:**
- Scheduled task prompts stored in DB = prompt injection vector if DB is compromised
- NEED: validate task commands against allowlist, don't execute arbitrary strings

**@Metsuke — Scope Check:**
- 6 ideas is fine — they compose linearly: #1 (engine) → #4 (CLI) → #3 (migration) → #6 (corroboration) → #2 (ephemeral) → #5 (personality)
- #1 and #4 are v1. #3 and #6 are v1.1. #2 is v2 (needs mesh). #5 is polish.

### Selected Ideas

**@Daimyo approved all 6.** Build order per @Metsuke:

**v1 (ship now):**
1. HeartbeatScheduler (#1) — the engine
2. Cron-Style CLI (#4) — the user surface
3. NativeTriggerMigration (#3) — prove it works

**v1.1 (fast-follow):**
4. Patina Heartbeat (#6) — scheduled corroboration
5. @Ronin fixes — sleep/wake handler, claim protocol, startup reconciliation

**v2 (after mesh):**
6. EphemeralAgentNode (#2) — serverless spawn
7. Sleep/Wake Personality (#5) — tamagotchi layer

## Synthesis

### Feature Brief

**Goal**: Turn Shikki's heartbeat into a native crontab that understands companies, budgets, agents, and the mesh — replacing external scheduling dependencies.

**Scope (v1)**:
- `ScheduledTask` model: cron expression, command/prompt, company ref, retry policy, last/next run
- `ScheduleEvaluator` extension: evaluate per-task crons on each heartbeat tick
- `shikki schedule add/list/rm` CLI commands
- `shikki status` shows next scheduled task
- Migrate daily radar trigger from Anthropic cloud → native ScheduledTask
- Task execution through existing CompanyManager dispatch or direct AgentRunner

**Scope (v1.1)**:
- `corroboration_sweep` ShikkiEvent type
- Nightly memory freshness review task (built-in, always active)
- Sleep/wake handler (NSWorkspace notifications)
- Atomic task claim protocol (optimistic SQL lock)
- Startup tmux pane reconciliation

**Out of scope (v2)**:
- EphemeralAgentNode (needs mesh CapabilityManifest)
- Sleep/wake tamagotchi animations
- Natural language schedule parsing
- Distributed multi-node task claiming (beyond optimistic lock)

**Success criteria**:
- `shikki schedule add "radar scan" --cron "0 5 * * *"` creates a recurring task
- `shikki schedule list` shows all tasks with next run time
- Heartbeat fires the task at the right time
- Daily radar runs natively, no Anthropic cloud trigger needed
- `shikki status` shows "Next: radar-scan in 3h42m"

**Dependencies**:
- HeartbeatLoop (exists)
- ScheduleEvaluator (exists — extend)
- CompanyManager (exists)
- AgentRunner protocol (exists)
- ShikiDB (scheduled_tasks table — new)

## Business Rules

### Task Model
```
BR-01: A ScheduledTask has: id, name, cron expression, command (shikki subcommand or prompt),
       company ref (optional), enabled flag, retry policy, last_run_at, next_run_at, claimed_by, claimed_at.
BR-02: Cron expressions follow standard 5-field POSIX syntax. Minimum interval: 1 hour.
BR-03: Tasks are stored in ShikiDB scheduled_tasks table. Not in local config files —
       tasks survive machine changes and are visible to all mesh nodes.
BR-04: A task's next_run_at is computed on creation and after each execution.
```

### Evaluation & Dispatch
```
BR-05: On each heartbeat tick, ScheduleEvaluator checks all enabled tasks where
       next_run_at <= NOW() and claimed_by IS NULL.
BR-06: Before dispatching, the evaluator atomically claims the task:
       UPDATE scheduled_tasks SET claimed_by = $node_id, claimed_at = NOW()
       WHERE id = $task_id AND claimed_by IS NULL.
       If UPDATE returns 0 rows, another node already claimed it — skip.
BR-07: After successful execution, update last_run_at, compute next_run_at, clear claimed_by.
BR-08: After failed execution, increment retry_count. If retry_count >= max_retries (default 3),
       disable the task and emit alert event.
BR-09: A task claimed for longer than 2x its expected duration is considered stuck.
       The evaluator clears claimed_by on the next tick (lease expiry).
```

### Schedule Awareness
```
BR-10: If a company ref is set, the task only fires within that company's active schedule
       (respects Company.Schedule.activeHours, timezone, days).
BR-11: If budget ref is set, the task only fires if the company's daily budget has headroom.
BR-12: Tasks without company ref fire unconditionally (global tasks like radar, corroboration).
```

### CLI
```
BR-13: `shikki schedule add` requires name + cron. Optional: --company, --prompt, --command.
BR-14: `shikki schedule list` shows: name, cron (human-readable), next run, last run, status.
BR-15: `shikki schedule rm <id>` disables (soft delete), does not hard delete.
BR-16: `shikki schedule run <id>` triggers immediate execution (bypasses cron, respects claim).
```

### Built-in Tasks
```
BR-17: On first run, seed two built-in scheduled tasks:
       - "corroboration-sweep" (daily, 03:00, global): refresh stale memories
       - "radar-scan" (daily, 05:00, global): fetch GitHub trending, diff, save to DB
       Built-in tasks are created with is_builtin = true, cannot be deleted via CLI.
BR-18: Built-in tasks can be disabled but not removed. `shikki schedule list` marks them [built-in].
```

## Test Plan

### Unit Tests
```
BR-01 → test_scheduledTask_cron_parsing_valid()
BR-01 → test_scheduledTask_cron_parsing_invalid_throws()
BR-02 → test_minimumInterval_rejects_subHourly()
BR-04 → test_nextRunAt_computed_on_creation()
BR-04 → test_nextRunAt_updated_after_execution()
BR-05 → test_evaluator_finds_ready_tasks()
BR-05 → test_evaluator_skips_future_tasks()
BR-05 → test_evaluator_skips_disabled_tasks()
BR-06 → test_atomicClaim_prevents_double_dispatch()
BR-07 → test_execution_clears_claim_updates_nextRun()
BR-08 → test_failedExecution_increments_retryCount()
BR-08 → test_maxRetries_disables_task()
BR-09 → test_stuckClaim_expires_after_2x_duration()
BR-10 → test_companySchedule_respected()
BR-11 → test_budgetHeadroom_checked()
BR-12 → test_globalTask_fires_unconditionally()
BR-17 → test_builtinTasks_seeded_on_firstRun()
BR-18 → test_builtinTasks_cannot_be_deleted()
```

### Integration Tests
```
BR-05+06 → test_heartbeatTick_dispatches_ready_task()
BR-03 → test_tasks_persist_across_restart()
BR-13+14+15 → test_cli_add_list_rm_roundtrip()
BR-16 → test_schedule_run_immediate()
```

## Architecture

### Files to Create/Modify

| File | Action | Purpose |
|------|--------|---------|
| `Sources/ShikkiKit/Models/ScheduledTask.swift` | New | Data model: id, name, cron, command, company, claim, retry |
| `Sources/ShikkiKit/Services/TaskScheduler.swift` | New | Core evaluator: find ready tasks, claim, dispatch, update |
| `Sources/ShikkiKit/Services/CronParser.swift` | New | 5-field POSIX cron parsing + next occurrence calculation |
| `Sources/ShikkiKit/Services/HeartbeatLoop.swift` | Modify | Inject TaskScheduler, call `evaluateAndDispatch()` per tick |
| `Sources/ShikkiKit/Events/ShikkiEvent.swift` | Modify | Add `scheduledTaskFired`, `scheduledTaskCompleted`, `scheduledTaskFailed`, `corroborationSweep` |
| `Sources/shikki/Commands/ScheduleCommand.swift` | New | CLI: add/list/rm/run subcommands |
| `Sources/shikki/Commands/ShikkiCommand.swift` | Modify | Register ScheduleCommand |
| `Tests/ShikkiKitTests/TaskSchedulerTests.swift` | New | Unit + integration tests |
| `Tests/ShikkiKitTests/CronParserTests.swift` | New | Cron parsing tests |
| `src/db/migrations/008_scheduled_tasks.sql` | New | DB table + built-in task seed |

### Data Flow

```
HeartbeatLoop tick (every 60s)
  → TaskScheduler.evaluateAndDispatch()
    → CronParser.nextOccurrence(cron, after: lastRun) <= NOW?
      → YES: atomicClaim(taskId, nodeId)
        → claimed? dispatch via AgentRunner or CompanyManager
          → success: update lastRun, compute nextRun, clear claim
          → failure: increment retryCount, emit alert if maxed
        → not claimed (another node got it): skip
      → NO: skip
```

## Execution Plan

### Task 1: CronParser
- **Files**: `Sources/ShikkiKit/Services/CronParser.swift` (new)
- **Test**: `Tests/ShikkiKitTests/CronParserTests.swift` → `test_parsesStandardCron()`
- **Implement**: Parse 5-field cron, compute next occurrence from a given date
- **Verify**: `swift test --filter CronParser` → 8+ tests passing
- **BRs**: BR-01, BR-02, BR-04
- **Time**: ~5 min

### Task 2: ScheduledTask model
- **Files**: `Sources/ShikkiKit/Models/ScheduledTask.swift` (new)
- **Test**: `Tests/ShikkiKitTests/TaskSchedulerTests.swift` → `test_scheduledTask_creation()`
- **Implement**: Struct with all BR-01 fields, Codable, Sendable
- **Verify**: `swift test --filter TaskScheduler` → 2+ tests passing
- **BRs**: BR-01, BR-03
- **Time**: ~3 min

### Task 3: TaskScheduler core
- **Files**: `Sources/ShikkiKit/Services/TaskScheduler.swift` (new)
- **Test**: `Tests/ShikkiKitTests/TaskSchedulerTests.swift` → `test_evaluator_finds_ready_tasks()`
- **Implement**: evaluateAndDispatch(), atomicClaim(), updateAfterExecution()
- **Verify**: `swift test --filter TaskScheduler` → 10+ tests passing
- **BRs**: BR-05, BR-06, BR-07, BR-08, BR-09, BR-10, BR-11, BR-12
- **Time**: ~8 min

### Task 4: Wire into HeartbeatLoop
- **Files**: `Sources/ShikkiKit/Services/HeartbeatLoop.swift` (modify)
- **Test**: `Tests/ShikkiKitTests/TaskSchedulerTests.swift` → `test_heartbeatTick_dispatches_ready_task()`
- **Implement**: Inject TaskScheduler, call on each tick
- **Verify**: `swift test --filter TaskScheduler` → integration test passing
- **BRs**: BR-05
- **Time**: ~3 min

### Task 5: Event types + DB migration
- **Files**: `Sources/ShikkiKit/Events/ShikkiEvent.swift` (modify), `src/db/migrations/008_scheduled_tasks.sql` (new)
- **Test**: n/a (compile check + migration)
- **Implement**: Add 4 event types, create scheduled_tasks table, seed built-in tasks
- **BRs**: BR-03, BR-17, BR-18
- **Time**: ~5 min

### Task 6: ScheduleCommand CLI
- **Files**: `Sources/shikki/Commands/ScheduleCommand.swift` (new), `ShikkiCommand.swift` (modify)
- **Test**: `Tests/ShikkiTests/CommandParsingTests.swift` → `test_schedule_add_parses()`
- **Implement**: add/list/rm/run subcommands via ArgumentParser
- **BRs**: BR-13, BR-14, BR-15, BR-16
- **Time**: ~8 min

## Implementation Readiness Gate

| Check | Status | Detail |
|-------|--------|--------|
| BR Coverage | PASS | 18/18 BRs mapped to tasks |
| Test Coverage | PASS | 18 test signatures mapped |
| File Alignment | PASS | 10 files covered across 6 tasks |
| Task Dependencies | PASS | Linear: 1→2→3→4→5→6 |
| Task Granularity | PASS | All tasks 3-8 min |
| Testability | PASS | All tasks have verify step |

**Verdict: PASS** — proceed to Phase 6 when ready.

## Implementation Log

## Review History
| Date | Phase | Reviewer | Decision | Notes |
|------|-------|----------|----------|-------|
| 2026-03-25 | Phase 1 | @Daimyo | All 6 approved | @t brainstorm: @Sensei @Ronin @Shogun @Hanami @Kintsugi |
| 2026-03-25 | Phase 2-5b | @Sensei | Spec complete | 18 BRs, 18 tests, 6 tasks, readiness gate PASS |
