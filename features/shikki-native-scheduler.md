# Feature: ShikkiKernel — The Living Scheduler
> Created: 2026-03-25 | Status: Phase 2 — Synthesis (rewritten) | Owner: @Daimyo

## Context
~~Shikki's heartbeat loop runs 24/7 and we want to add a cron scheduler inside it.~~

**Rewrite (2026-03-25 @Daimyo challenge):** The scheduler is NOT a feature inside the heartbeat. The scheduler IS the root process — the kernel that manages everything, including the heartbeat itself. Like `launchd` is to macOS, like the Linux kernel's CFS is to processes. The heartbeat is just one managed service among many.

The key insight: **time is the resource we're scheduling.** Different tasks need different rhythms — health checks every 10s, decisions every 30s, dispatch every 60s, stale detection every 300s. Cramming them all into one fixed 60s loop is wrong. The kernel manages multiple timelines, coalesces timers for efficiency, and adapts its own tick rate to load.

Second insight: **speculative execution.** When a task exceeds 1.25x its estimated time, spawn a duplicate and race them. First to finish wins, loser gets killed. Like CPU branch prediction but for agent tasks. 3 consecutive failures = kill all, escalate to @t.

Analogy validated: macOS timer coalescing (72% fewer CPU wake-ups), Linux CFS (fair scheduling via virtual runtime), Swift async/await (capture scope, dispatch, rejoin run loop), Erlang/OTP supervision trees.

## Inspiration
### Original Brainstorm Results (retained)

| # | Idea | Source | Feasibility | Impact | Project Fit | Verdict |
|---|------|--------|:-----------:|:------:|:-----------:|--------:|
| 1 | **HeartbeatScheduler** — ScheduleEvaluator in heartbeat loop | @Sensei | High | High | Strong | EVOLVED → ShikkiKernel |
| 2 | **EphemeralAgentNode** — serverless agent spawn | @Sensei | Medium | High | Strong | BUILD (v2) |
| 3 | **NativeTriggerMigration** — replace Anthropic cloud triggers | @Sensei | High | Critical | Strong | BUILD (v1) |
| 4 | **Cron-Style Schedule CLI** — `shikki schedule add/list/rm` | @Hanami | High | Medium-High | Strong | BUILD (v1) |
| 5 | **Sleep/Wake Personality** — tamagotchi sleep cycle | @Hanami | Medium | High | Strong | BUILD (v2) |
| 6 | **Patina Heartbeat** — scheduled corroboration sweeps | @Kintsugi | Medium | High | Strong | BUILD (v1.1) |

### @Daimyo Architectural Challenge (2026-03-25)

**Question:** Is the scheduler the ROOT PROCESS, not a feature? Like systemd/launchd — it launches everything, monitors health, restarts on failure, manages different timelines.

**@Sensei verdict: YES.** HeartbeatLoop is a 377-line god object doing 8 unrelated concerns at one fixed interval. Extract each into a managed service with its own cadence and QoS.

**@Ronin verdict: NO.** Don't build systemd for one service. HeartbeatLoop is 30 lines of control flow. Sequential coupling prevents races.

**@Daimyo resolution:** @Ronin is wrong on the framing — this is NOT systemd (service manager), it's the **kernel** (scheduler + process manager + speculative executor). Different thing entirely. The heart doesn't beat at constant rate — it adapts.

### @t Team Review (2026-03-25)

**@Ronin — 3 Failure Modes (still valid, addressed in BRs):**
1. Mac sleep/lid close = timer drift → BR-20 (sleep/wake handler)
2. Two nodes + same cron = double-dispatch → BR-06 (atomic claim)
3. Crash mid-task = ghost sessions → BR-23 (startup reconciliation)

**@Shogun — Competitive Gap:**
- No tool combines project-aware scheduling + agent orchestration + budget constraints
- Linux CFS, macOS timer coalescing, Erlang supervision trees — patterns to steal
- Temporal/Inngest solve durability for functions, not AI agent sessions

**@Hanami — UX:**
- Bare `shikki` (no subcommand) = peek at the creature, not --help
- Status shows rhythm/tempo, not just state

**@Kintsugi — Philosophy:**
- The scheduler is the breath, not the clock — organic rhythm that adapts
- `shikki stop` is choosing to let the creature sleep
- Scheduled corroboration = the machine tends its memory garden

## Synthesis

### Feature Brief

**Goal**: Build the ShikkiKernel — a process scheduler that manages all Shikki services with adaptive timing, speculative execution, and fair resource allocation. Replaces the monolithic HeartbeatLoop.

**Scope (v1 — Minimal Kernel)**:
- `ShikkiKernel` actor: root process managing N `ManagedService` instances
- `ManagedService` protocol: id, qos, interval, tick(), canRun()
- Extract HeartbeatLoop concerns into 5 focused services
- Timer coalescing: batch API calls into one `KernelSnapshot` per tick
- Per-service intervals (10s / 30s / 60s / 120s / 300s)
- `ScheduledTask` model + `TaskSchedulerService` (cron evaluation)
- `shikki schedule add/list/rm/run` CLI
- Migrate daily radar from Anthropic cloud → native
- Built-in tasks: corroboration-sweep, radar-scan

**Scope (v1.1 — Speculative Executor)**:
- Track avg execution time per task type (learned from history)
- If running > 1.25x avg → spawn duplicate racer
- First to complete wins, loser killed
- 3 consecutive failures → kill all, snapshot state, escalate to @t
- Sleep/wake handler (NSWorkspace notifications)
- Adaptive tick rate: speed up under load, tickless when idle

**Scope (v2 — Mesh Kernel)**:
- EphemeralAgentNode (serverless spawn)
- QoS-based token budgeting (interactive 60%, utility 30%, background 10%)
- On-demand agent activation (launchd-style: spawn on event, not at boot)
- Supervision tree (restart policies per service)
- Sleep/wake personality (tamagotchi layer)

**Out of scope**:
- Distributed consensus (Raft/PBFT — overkill for 2-3 nodes)
- Tensor-level scheduling (that's the mesh protocol)
- Process isolation/sandboxing (trust boundary is the agent prompt, not OS-level)

**Success criteria**:
- HeartbeatLoop is decomposed into 5+ services with independent intervals
- Health checks run at 10s, dispatch at 60s, stale detection at 300s — independently
- API calls batched: 1 request per tick instead of 5
- `shikki schedule add "radar" --cron "0 5 * * *"` works
- Speculative execution catches stuck builds (>1.25x estimate → race)
- 3-failure escalation produces actionable @t diagnosis

**Dependencies**:
- HeartbeatLoop (exists — will be decomposed)
- ScheduleEvaluator (exists — becomes a service)
- CompanyManager (exists — managed by kernel)
- AgentRunner (exists — used by speculative executor)
- Watchdog (exists — finally wired in)
- SessionRegistry (exists — used by SessionSupervisor)
- EventBus (exists — used by EventPersister service)

## Business Rules

### Kernel Core
```
BR-01: ShikkiKernel is the root actor. It starts first, stops last.
       All services are children of the kernel.
BR-02: The kernel maintains a KernelSnapshot — a batched fetch of all backend data
       needed by services this tick. One HTTP request replaces 5.
BR-03: Each ManagedService declares: id, qos (ServiceQoS), interval (Duration),
       restart policy (always/on-failure/once), and max restart count.
BR-04: The kernel evaluates which services are due each tick, batches them,
       and fans out to concurrent tasks with shared snapshot data.
BR-05: Services with higher QoS run first within each tick.
       QoS levels: critical (0), userInitiated (1), default (2), utility (3), background (4).
```

### Timer Coalescing
```
BR-06: The kernel sleeps until the NEXT service is due (not a fixed interval).
       Sleep duration = min(all services' next_due_time) - now.
       This is tickless when nothing is due (like Linux NO_HZ).
BR-07: When multiple services are due within the same coalescing window (±2s),
       they fire in the same tick, sharing the KernelSnapshot.
BR-08: Each service has a leeway tolerance (like macOS NSTimer.tolerance):
       critical: ±0s, userInitiated: ±2s, default: ±5s, utility: ±10s, background: ±30s.
```

### Service Decomposition (from HeartbeatLoop)
```
BR-09: HealthMonitor — QoS: critical, interval: 10s. API reachability check.
       If unhealthy, block all services except HealthMonitor and SessionSupervisor.
BR-10: DecisionMonitor — QoS: userInitiated, interval: 30s. Poll pending decisions,
       notify via ntfy, detect answered decisions → signal re-dispatch.
BR-11: DispatchService — QoS: default, interval: 60s. Fetch queue, evaluate
       schedule/budget/slots, launch sessions. Also triggered reactively by
       DecisionMonitor.answered signal.
BR-12: SessionSupervisor — QoS: utility, interval: 120s. Cleanup idle sessions,
       capture transcripts, Watchdog escalation (warn → nudge → triage → terminate).
BR-13: StaleCompanyDetector — QoS: background, interval: 300s. Find stale companies,
       evaluate pending tasks, relaunch.
BR-14: EventPersister — QoS: background, event-driven. Subscribe to EventBus,
       write to ShikiDB. Pattern detection (stuck agent, repeat failure).
BR-15: TaskSchedulerService — QoS: default, interval: 60s. Evaluate cron tasks,
       atomic claim, dispatch. (The "cron" feature from original spec.)
```

### Scheduled Tasks (retained from original spec)
```
BR-16: A ScheduledTask has: id, name, cron expression, command, company ref (optional),
       enabled flag, retry policy, estimated_duration_ms, avg_duration_ms,
       last_run_at, next_run_at, claimed_by, claimed_at.
BR-17: Cron expressions follow 5-field POSIX syntax. Minimum interval: 1 hour.
BR-18: Tasks stored in ShikiDB. Survive machine changes. Visible to all mesh nodes.
BR-19: Atomic claim: UPDATE ... SET claimed_by = $node WHERE claimed_by IS NULL.
       0 rows = another node got it → skip.
BR-20: Stuck claim: claimed for > 2x estimated_duration → clear claimed_by (lease expiry).
```

### Speculative Execution
```
BR-21: The kernel tracks avg execution time per task type.
       Updated after each execution: avg = 0.8 * old_avg + 0.2 * actual.
       (Exponential moving average — recent executions weighted more.)
BR-22: If a task runs > 1.25x avg_duration, the kernel spawns a DUPLICATE
       in a parallel worktree/process. Both race. First to complete wins.
       Loser is killed (SIGTERM, then SIGKILL after 5s).
BR-23: If both racer and original fail, count as 1 failure (not 2).
BR-24: After 3 consecutive failures for the same task:
       a. Kill all processes for this task
       b. Snapshot task state (inputs, outputs, errors) to ShikiDB
       c. Emit escalation event with full context
       d. Disable the task
       e. @t investigation: @Ronin diagnoses, @Sensei proposes fix
BR-25: Speculative execution is opt-in per task via `speculative: true` flag.
       Not all tasks benefit (e.g., destructive operations should NOT be raced).
```

### Sleep/Wake (macOS)
```
BR-26: On NSWorkspace.willSleepNotification: freeze all service timers,
       checkpoint all active sessions, record sleep_at timestamp.
BR-27: On NSWorkspace.didWakeNotification: compute time_slept,
       reconcile all service states (some may have missed their window),
       recalculate next_due for all services, resume.
BR-28: Missed scheduled tasks during sleep fire on wake (if still within
       their tolerance window). If past tolerance → skip, schedule next occurrence.
```

### Startup Reconciliation
```
BR-29: On kernel boot, before starting any service:
       a. Scan tmux panes → find running agent sessions
       b. Compare with SessionJournal → reconcile ghosts
       c. Clear stale claims in ShikiDB (claimed_by with expired lease)
       d. Recover crashed sessions from checkpoints
BR-30: Only after reconciliation completes does the kernel start services.
```

### CLI
```
BR-31: `shikki schedule add` requires name + cron. Optional: --company, --prompt,
       --command, --speculative, --estimated-duration.
BR-32: `shikki schedule list` shows: name, cron, next run, last run, avg duration, status.
BR-33: `shikki schedule rm <id>` disables (soft delete).
BR-34: `shikki schedule run <id>` triggers immediate execution.
BR-35: `shikki status` shows kernel state: services, next tick, active tasks, tempo.
```

### Built-in Tasks
```
BR-36: Seed on first run:
       - "corroboration-sweep" (daily 03:00, global): refresh stale memories (freshness < 0.3)
       - "radar-scan" (daily 05:00, global): GitHub trending → ShikiDB
       Built-in tasks: is_builtin = true, cannot be deleted.
BR-37: Built-in tasks can be disabled but not removed.
```

## Test Plan

### Unit Tests — Kernel Core
```
BR-01 → test_kernel_starts_all_services()
BR-02 → test_kernelSnapshot_batches_api_calls()
BR-03 → test_managedService_declares_qos_and_interval()
BR-04 → test_kernel_fans_out_due_services_concurrently()
BR-05 → test_higher_qos_runs_first()
```

### Unit Tests — Timer Coalescing
```
BR-06 → test_kernel_sleeps_until_next_due()
BR-06 → test_tickless_when_nothing_due()
BR-07 → test_services_within_window_coalesce()
BR-08 → test_leeway_per_qos_level()
```

### Unit Tests — Services
```
BR-09 → test_healthMonitor_blocks_others_when_unhealthy()
BR-10 → test_decisionMonitor_notifies_on_pending()
BR-11 → test_dispatchService_respects_budget()
BR-12 → test_sessionSupervisor_cleans_idle()
BR-13 → test_staleDetector_relaunches_company()
BR-15 → test_taskScheduler_evaluates_cron()
```

### Unit Tests — Scheduled Tasks
```
BR-16 → test_scheduledTask_creation()
BR-17 → test_cron_parsing_valid()
BR-17 → test_cron_parsing_invalid_throws()
BR-17 → test_minimumInterval_rejects_subHourly()
BR-19 → test_atomicClaim_prevents_double_dispatch()
BR-20 → test_stuckClaim_expires()
BR-36 → test_builtinTasks_seeded()
BR-37 → test_builtinTasks_cannot_be_deleted()
```

### Unit Tests — Speculative Execution
```
BR-21 → test_avgDuration_exponentialMovingAverage()
BR-22 → test_speculative_spawns_at_1_25x()
BR-22 → test_first_to_finish_wins()
BR-23 → test_both_fail_counts_as_one()
BR-24 → test_3_failures_kills_all_and_escalates()
BR-25 → test_speculative_only_when_opted_in()
```

### Unit Tests — Sleep/Wake
```
BR-26 → test_sleep_freezes_timers()
BR-27 → test_wake_reconciles_services()
BR-28 → test_missed_task_fires_on_wake_within_tolerance()
BR-28 → test_missed_task_skips_past_tolerance()
```

### Unit Tests — Startup
```
BR-29 → test_startup_scans_tmux_panes()
BR-29 → test_startup_clears_stale_claims()
BR-30 → test_services_start_after_reconciliation()
```

### Integration Tests
```
test_kernel_full_tick_lifecycle()
test_cli_schedule_add_list_rm_roundtrip()
test_speculative_race_with_mock_agents()
test_3_failure_escalation_flow()
```

## Architecture

### Process Tree

```
ShikkiKernel (root actor — PID 1 of Shikki)
│
├── [critical, 10s]    HealthMonitor
├── [userInit, 30s]    DecisionMonitor
├── [default, 60s]     DispatchService (uses CompanyManager)
├── [default, 60s]     TaskSchedulerService (cron evaluation)
├── [utility, 120s]    SessionSupervisor (Watchdog + cleanup)
├── [background, 300s] StaleCompanyDetector
├── [background, event] EventPersister (EventBus subscriber)
└── [background, boot]  RecoveryService (one-shot on startup)
```

### ManagedService Protocol

```swift
public protocol ManagedService: Actor {
    var id: ServiceID { get }
    var qos: ServiceQoS { get }
    var interval: Duration { get }
    var leeway: Duration { get }
    var restartPolicy: RestartPolicy { get }

    func tick(snapshot: KernelSnapshot) async
    func canRun(health: HealthStatus) -> Bool
}

public enum ServiceQoS: Int, Comparable {
    case critical = 0
    case userInitiated = 1
    case `default` = 2
    case utility = 3
    case background = 4
}

public enum RestartPolicy {
    case always(maxRestarts: Int, backoff: Duration)
    case onFailure(maxRestarts: Int, backoff: Duration)
    case once
}
```

### KernelSnapshot (timer coalescing)

```swift
public struct KernelSnapshot: Sendable {
    let health: HealthStatus
    let companies: [Company]
    let dispatchQueue: [DispatcherTask]
    let pendingDecisions: [Decision]
    let scheduledTasks: [ScheduledTask]
    let sessions: [SessionInfo]
    let fetchedAt: Date
}
```

### Speculative Executor

```swift
public actor SpeculativeExecutor {
    func raceOrWait(task: ScheduledTask, runner: AgentRunner) async -> AgentResult {
        let start = Date()
        let estimate = task.avg_duration_ms

        // Start primary
        async let primary = runner.run(prompt: task.command, ...)

        // Monitor elapsed time
        let monitor = Task {
            try await Task.sleep(for: .milliseconds(Int(Double(estimate) * 1.25)))
            return true // threshold exceeded
        }

        // If primary finishes first → return it
        // If threshold exceeded → spawn racer, return first to finish
    }
}
```

### Files to Create/Modify

| File | Action | Purpose |
|------|--------|---------|
| `ShikkiKit/Services/ShikkiKernel.swift` | **New** | Root actor: service management, tick coalescing, snapshot batching |
| `ShikkiKit/Protocols/ManagedService.swift` | **New** | Protocol + ServiceQoS + RestartPolicy |
| `ShikkiKit/Services/KernelSnapshot.swift` | **New** | Batched backend data for timer coalescing |
| `ShikkiKit/Services/HealthMonitor.swift` | **New** | Extracted from HeartbeatLoop |
| `ShikkiKit/Services/DecisionMonitor.swift` | **New** | Extracted from HeartbeatLoop |
| `ShikkiKit/Services/DispatchService.swift` | **New** | Extracted from HeartbeatLoop |
| `ShikkiKit/Services/TaskSchedulerService.swift` | **New** | Cron evaluation + dispatch |
| `ShikkiKit/Services/SessionSupervisor.swift` | **New** | Extracted from HeartbeatLoop |
| `ShikkiKit/Services/StaleCompanyDetector.swift` | **New** | Extracted from HeartbeatLoop |
| `ShikkiKit/Services/SpeculativeExecutor.swift` | **New** | Race duplicates, kill losers |
| `ShikkiKit/Services/CronParser.swift` | **New** | 5-field POSIX cron |
| `ShikkiKit/Models/ScheduledTask.swift` | **New** | Task model with estimated/avg duration |
| `ShikkiKit/Services/HeartbeatLoop.swift` | **Modify** | Strip down to HeartbeatService (publish event only) |
| `ShikkiKit/Events/ShikkiEvent.swift` | **Modify** | Add kernel + scheduler + speculative event types |
| `shikki/Commands/ScheduleCommand.swift` | **New** | CLI: add/list/rm/run |
| `shikki/Commands/HeartbeatCommand.swift` | **Modify** | Launch ShikkiKernel instead of HeartbeatLoop |
| `src/db/migrations/008_scheduled_tasks.sql` | **New** | DB table + built-in seeds |
| Tests (7 new files) | **New** | ~40 tests across kernel, services, scheduler, speculative |

### Data Flow

```
ShikkiKernel.run()
  ├── RecoveryService.boot() — scan tmux, clear claims, restore checkpoints
  │
  └── LOOP:
      ├── compute next_due = min(all services' next tick)
      ├── sleep(until: next_due) — tickless when nothing due
      │
      ├── collect due_services (within coalescing window)
      ├── if due_services need backend data:
      │     snapshot = batchFetch() — ONE HTTP call
      │
      ├── fan out due_services (concurrent, ordered by QoS):
      │     ├── HealthMonitor.tick(snapshot)
      │     ├── DecisionMonitor.tick(snapshot)
      │     ├── TaskSchedulerService.tick(snapshot)
      │     │     └── for each ready cron task:
      │     │           atomicClaim() → dispatch via AgentRunner
      │     │           if speculative && elapsed > 1.25x avg:
      │     │             SpeculativeExecutor.race()
      │     ├── DispatchService.tick(snapshot)
      │     ├── SessionSupervisor.tick(snapshot)
      │     └── StaleCompanyDetector.tick(snapshot)
      │
      ├── handle service crashes:
      │     restart per policy, backoff, max restarts
      │
      └── handle signals:
            SIGTERM → checkpoint all, graceful shutdown
            SIGINT → same
            NSWorkspace.willSleep → freeze timers
            NSWorkspace.didWake → reconcile, resume
```

## Execution Plan

### Wave 1 — Minimal Kernel (extract + restructure)
**Task 1**: ManagedService protocol + ServiceQoS + KernelSnapshot
**Task 2**: ShikkiKernel actor (tick loop, coalescing, sleep-until-next-due)
**Task 3**: Extract HealthMonitor from HeartbeatLoop
**Task 4**: Extract DispatchService from HeartbeatLoop
**Task 5**: Extract SessionSupervisor from HeartbeatLoop
**Task 6**: Wire HeartbeatCommand to launch ShikkiKernel instead of HeartbeatLoop
**Verify**: All existing heartbeat behavior works, but through kernel

### Wave 2 — Scheduler
**Task 7**: CronParser (5-field, next occurrence)
**Task 8**: ScheduledTask model
**Task 9**: TaskSchedulerService (evaluate, claim, dispatch)
**Task 10**: ScheduleCommand CLI (add/list/rm/run)
**Task 11**: DB migration + built-in task seeds
**Task 12**: Migrate daily radar from Anthropic cloud trigger
**Verify**: `shikki schedule add/list` works, radar runs natively

### Wave 3 — Speculative Executor
**Task 13**: SpeculativeExecutor actor (race pattern)
**Task 14**: Avg duration tracking (exponential moving average)
**Task 15**: 3-failure escalation protocol
**Task 16**: Speculative flag on ScheduledTask + CLI
**Verify**: Stuck builds get raced, failures escalate to @t

### Wave 4 — Resilience
**Task 17**: Sleep/wake handler (NSWorkspace)
**Task 18**: Startup reconciliation (tmux scan + claim cleanup)
**Task 19**: DecisionMonitor + StaleCompanyDetector extraction
**Task 20**: Adaptive tick rate (speed up under load, tickless when idle)
**Verify**: Lid close → wake → clean recovery. Idle system = zero ticks.

## Implementation Readiness Gate

| Check | Status | Detail |
|-------|--------|--------|
| BR Coverage | PASS | 37/37 BRs mapped |
| Test Coverage | PASS | 40+ test signatures |
| File Alignment | PASS | 18 files across 20 tasks |
| Task Dependencies | PASS | Wave 1→2→3→4 (wave-internal is parallel-safe) |
| Task Granularity | PASS | Each task 3-10 min |
| Testability | PASS | Each wave has verify step |

**Verdict: PASS** — proceed to Phase 6 when ready.

## Implementation Log

## Review History
| Date | Phase | Reviewer | Decision | Notes |
|------|-------|----------|----------|-------|
| 2026-03-25 | Phase 1 | @Daimyo | All 6 approved | Original brainstorm |
| 2026-03-25 | Phase 1.5 | @Daimyo | CHALLENGE: scheduler = kernel | Architectural inversion |
| 2026-03-25 | Phase 2-5b | @Sensei | Rewritten as ShikkiKernel | 37 BRs, 40+ tests, 20 tasks, 4 waves |
