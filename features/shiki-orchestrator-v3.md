# Shiki Orchestrator v3 — "The Agency That Ships"

> **Created**: 2026-03-16
> **Status**: Phase 5b — Execution Plan (ready for implementation)
> **Owner**: @Daimyo
> **Branch**: `feature/orchestrator-v3` from `develop`
> **Research**: 9 projects analyzed (Terraform, Kestra, Pulumi, Salt, Trivy, Terraformer, AWS CDK, Motion AI, Paperclip)
> **Vision**: `docs/session-2026-03-16-vision-and-architecture.md`
> **Evolution Plan**: `projects/research/plan-shiki-evolution-v4.md`

---

## Phase 1 — Inspiration

### Problem Statement

Shiki v0.2.0 migrated from bash to Swift (12 subcommands, 38 tests), but the orchestration layer has critical gaps:

1. **Ghost processes survive `shiki stop`** — Claude sub-agents, xcodebuild, Simulator orphaned after tmux kill
2. **Companies can't resume after `shiki decide`** — no mechanism to detect answered decisions and re-dispatch
3. **Binary session lifecycle** — only running/done, no pause/retry/queue/budget states
4. **No session registry** — can't discover what's running, can't reconstruct after crash
5. **No execution graph** — waves are flat sequential batches, can't express dependencies
6. **No plan artifact** — intent goes straight to execution, nothing survives context resets
7. **No cost control** — agents run unbounded, no budget awareness
8. **No autonomous reactions** — everything is user-dispatched, system can't self-heal

### Brainstorm Sources

| Source | Key Insight | Agent |
|--------|------------|-------|
| Terraform (48k★) | DAG walker + plan/apply lifecycle = audit + parallelism | @Sensei |
| Kestra (26.5k★) | 17-state machine with full history = real session lifecycle | @Sensei |
| Pulumi (24.9k★) | Chain/antichain + Automation API + snapshot journaling | @Sensei |
| Salt (15.3k★) | Reactor system (event→action) + grains/pillar (agent self-description) | @Sensei |
| Trivy (33k★) | Self-registering analyzers + 3-tier hook lifecycle | @Sensei |
| Terraformer (14.5k★) | ServiceGenerator + 4-phase state reconstruction pipeline | @Sensei |
| AWS CDK (12.7k★) | L1/L2/L3 construct abstraction + aspect system (visitors) | @Sensei |
| Motion AI | Cross-project priority, SOP→workflow, bottleneck dashboards, at-risk alerts | @Shogun |
| Paperclip | Orphan reaping, atomic checkout, cost control, governance gates, goal hierarchy, adapter system, wakeup coalescing | @Sensei |
| Vision session c914f0eb | DAG not tree, concentric circles, progressive disclosure, master/slave, knowledge commons | @Kintsugi |
| Evolution Plan v4 | 3 horizons (Ship→Visibility→Orchestrate), Motion feature mapping, anti-scope | @Shogun |
| Session bugs (4 critical) | Ghost processes, stale companies, self-kill, curl exit 28 | @Ronin |

---

## Phase 2 — Synthesis

### Feature Brief

**Goal**: Transform Shiki from a CLI that launches tmux sessions into a proper orchestration engine with session lifecycle management, dependency-aware dispatch, cost control, and crash recovery — while fixing the 4 critical bugs from the vision session.

**Scope**: 5 waves, each a self-contained deliverable that unlocks the next.

**Out of scope** (anti-scope from Evolution Plan v4 + vision session):
- No calendar integration (Motion's core, not ours)
- No meeting transcription (solo dev, session debrief replaces this)
- No AI Sheets/Dashboards UI (DB + CLI is enough)
- No Agent Teams yet (tmux first, Agent Teams Phase 5 when Anthropic stabilizes — radar check 2026-03-28)
- No always-on orchestrator (demand-driven, idle = no cost)
- No multi-workspace yet (architecture supports it, code implements solo first)
- No auth/collaboration yet (ZITADEL chosen, deferred to Phase 5+ of vision roadmap)
- No HCL/DSL for workflows (domain too fluid for agent orchestration, use Swift structs)

**Success Criteria**:
- [ ] `shiki stop` kills ALL child processes (zero ghosts)
- [ ] `shiki status` shows live session states with history
- [ ] Crashed sessions recoverable from journal within 5 seconds
- [ ] Orphan sessions auto-detected and reported after 5 minutes
- [ ] Agent dispatch respects dependency graph (parallel where safe, sequential where needed)
- [ ] Execution plan reviewable as artifact before dispatch
- [ ] Cost budget per company/agent with auto-pause at limit
- [ ] Governance gates block high-impact operations pending approval
- [ ] All new code has tests (target: 80+ new tests across 5 waves)
- [ ] Zero regressions on existing 38 tests
- [ ] Zero breaking changes to existing CLI interface

**Dependencies**:
- shiki-ctl v0.2.0 code on `feature/cli-core-architecture` branch (uncommitted — must commit first)
- Shiki backend running at localhost:3900
- Existing FIXMEs: session registry, prompt templates, NetKit migration

---

## Phase 3 — Business Rules

### Critical Bugs (from vision session — fix FIRST)

| ID | Rule | Type |
|----|------|------|
| BR-01 | `shiki stop` MUST capture all pane PIDs and process trees, send SIGTERM → wait 3s → SIGKILL, then kill tmux session LAST | Bug fix |
| BR-02 | `shiki stop` MUST handle self-kill scenario (running from inside the session being killed) by forking cleanup to background | Bug fix |
| BR-03 | After `shiki decide` answers a decision, orchestrator MUST detect newly-unblocked tasks and re-dispatch within one heartbeat cycle (60s) | Bug fix |
| BR-04 | `checkStaleCompanies()` MUST be re-enabled with smart logic: only relaunch if task was in-progress, not if company was idle | Bug fix |

### Session Lifecycle (from Kestra + Paperclip)

| ID | Rule | Type |
|----|------|------|
| BR-05 | Every session MUST have exactly one of 11 states: `queued`, `awaitingApproval`, `dispatched`, `running`, `paused`, `retrying`, `succeeded`, `failed`, `killed`, `budgetPaused`, `unknown` | Constraint |
| BR-06 | Every state transition MUST be recorded with timestamp, reason, and actor (system/user/agent/governance) | Constraint |
| BR-07 | Only valid transitions are allowed (defined in state machine). Invalid transitions MUST throw | Constraint |
| BR-08 | Terminal states (`succeeded`, `failed`, `killed`) are immutable — no transitions out | Constraint |
| BR-09 | `unknown` state is ONLY for crash recovery (discovered session with unclear state) | Constraint |

### Session Registry (from Terraformer + Trivy + Paperclip)

| ID | Rule | Type |
|----|------|------|
| BR-10 | Each agent type (company, agent, heartbeat, worktree) MUST register a discoverer with the registry at startup | Constraint |
| BR-11 | Registry MUST support 4-phase reconstruction: discover → hydrate → normalize → persist | Constraint |
| BR-12 | Orphan reaping MUST detect sessions with no heartbeat for >5 minutes and transition them to `unknown` | Constraint |
| BR-13 | Registry queries MUST be filterable by SessionKind | Constraint |

### Snapshot Journaling (from Pulumi + Paperclip)

| ID | Rule | Type |
|----|------|------|
| BR-14 | Every state transition MUST trigger a journal checkpoint | Constraint |
| BR-15 | Journal storage is append-only JSONL at `~/.config/shiki/journal/{sessionId}.jsonl` | Constraint |
| BR-16 | Journal MUST support coalesced writes (5s debounce) during burst activity to prevent I/O thrashing | Constraint |
| BR-17 | `recoverAll()` MUST return the latest snapshot per session, not all entries | Constraint |
| BR-18 | Journal entries older than 7 days MUST be prunable via `prune()` | Constraint |
| BR-19 | Corrupt journal lines MUST be skipped, not crash recovery | Constraint |

### Process Cleanup (from vision session Bug #1)

| ID | Rule | Type |
|----|------|------|
| BR-20 | `ProcessCleanup` MUST walk the full process tree from tmux pane PIDs | Constraint |
| BR-21 | Kill order: task windows first (SIGTERM → 3s → SIGKILL), then tmux session | Constraint |
| BR-22 | Self-kill detection: if caller PID is inside the session, fork cleanup to background process | Constraint |
| BR-23 | After cleanup, verify zero orphaned Claude/xcodebuild/Simulator processes | Constraint |

### Execution Graph (from Terraform + Kestra + Salt)

| ID | Rule | Type |
|----|------|------|
| BR-24 | Agent tasks MUST declare dependencies via `dependsOn` | Constraint |
| BR-25 | Independent tasks MUST execute in parallel, bounded by configurable concurrency (default: 4) | Constraint |
| BR-26 | Upstream failure MUST skip downstream dependent tasks (no cascade execution on bad data) | Constraint |
| BR-27 | Graph MUST support typed edges: `require` (must succeed), `onFailure` (run if failed), `watch` (re-run on change) | Design |
| BR-28 | Graph cycles MUST be detected and rejected at plan time, not execution time | Constraint |

### Plan/Apply Lifecycle (from Terraform + Pulumi + AWS CDK)

| ID | Rule | Type |
|----|------|------|
| BR-29 | Every dispatch MUST produce a serializable plan artifact before execution | Constraint |
| BR-30 | Plans MUST show: agent assignments, dependency graph, estimated cost, quality gates | Constraint |
| BR-31 | Plans MUST be diffable (two plans for the same intent can be compared) | Design |
| BR-32 | Apply MUST refuse to execute a stale plan (inputs changed since plan was generated) | Constraint |
| BR-33 | Plan artifact MUST survive context resets (stored on disk, not in memory) | Constraint |

### Cost Control (from Paperclip + Motion)

| ID | Rule | Type |
|----|------|------|
| BR-34 | Budgets are three-layer: company monthly → agent monthly → project | Constraint |
| BR-35 | 80% budget = soft alert (ntfy notification) | Constraint |
| BR-36 | 100% budget = hard limit → auto-transition to `budgetPaused` state | Constraint |
| BR-37 | Budget resets monthly (UTC) | Constraint |
| BR-38 | Cost events MUST be logged for attribution reporting | Constraint |

### Governance (from Paperclip)

| ID | Rule | Type |
|----|------|------|
| BR-39 | High-impact operations (defined per company) MUST enter `awaitingApproval` state | Constraint |
| BR-40 | Approval gates route through `shiki decide` + ntfy notification | Constraint |
| BR-41 | All mutations MUST be logged to audit trail | Constraint |

### Cross-Cutting Aspects (from AWS CDK)

| ID | Rule | Type |
|----|------|------|
| BR-42 | Aspects are visitor-pattern policies applied to all sessions in scope | Design |
| BR-43 | Built-in aspects: CostAspect (budget enforcement), QualityAspect (require tests on code agents), SLAAspect (max duration) | Design |
| BR-44 | Aspects run during plan synthesis, BEFORE execution | Constraint |

### Agent Self-Registration (from Trivy + Salt)

| ID | Rule | Type |
|----|------|------|
| BR-45 | Agents MUST register capabilities and a `canHandle(task)` filter | Design |
| BR-46 | Dispatcher routes by capability match, not hardcoded agent mapping | Design |
| BR-47 | Agents self-describe via "grains" (bottom-up capabilities). Per-agent config via "pillar" (top-down secrets/settings) | Design |

### Task Context (from Paperclip goal hierarchy)

| ID | Rule | Type |
|----|------|------|
| BR-48 | Every session MUST carry a `TaskContext` with companyId, projectId, taskDescription, parentSessionId, wakeReason | Constraint |
| BR-49 | Full ancestor chain available so agents understand "why" they are running | Design |

---

## Phase 4 — Test Plan

### Wave 1: Session Foundation (~32 tests)

**SessionLifecycleTests** (14 tests):
```
test_validTransition_queuedToDispatched
test_validTransition_runningToSucceeded
test_validTransition_runningToFailed
test_validTransition_runningToKilled
test_validTransition_runningToPaused
test_validTransition_runningToRetrying
test_validTransition_runningToBudgetPaused
test_validTransition_queuedToAwaitingApproval
test_validTransition_awaitingApprovalToDispatched
test_invalidTransition_succeededToRunning_throws
test_invalidTransition_failedToRunning_throws
test_historyAccumulates_multipleTransitions
test_transitionActorRecorded_systemUserAgentGovernance
test_codableRoundTrip_sessionStateWithHistory
test_taskContextRoundTrip
test_validTransitionsMap_noOrphanStates
```

**SessionRegistryTests** (10 tests):
```
test_registerDiscoverer_canQueryByKind
test_unregisterDiscoverer_removesFromRegistry
test_reconstruct_4PhasesPipeline_withMockDiscoverers
test_reconstruct_emptyState_returnsEmptyArray
test_activeSessions_filtersByKind
test_activeSessions_returnsAllWhenNoFilter
test_concurrentDiscovery_multipleDiscoverersInParallel
test_reapOrphans_detectsStaleSessionsOver5Minutes
test_reapOrphans_skipsHealthySessions
test_reapOrphans_transitionsToUnknownState
```

**SessionJournalTests** (8 tests):
```
test_checkpoint_writeAndReadRoundTrip
test_checkpoint_multipleEntriesPerSession_appends
test_recoverAll_returnsLatestPerSession
test_prune_removesEntriesOlderThan7Days
test_prune_keepsRecentEntries
test_corruptLine_skippedGracefully
test_coalescedCheckpoint_debounces5Seconds
test_costThresholdCheckpoint_includesBudgetMetadata
```

### Wave 2: Process Cleanup (~12 tests)

**ProcessCleanupTests** (12 tests):
```
test_captureProcessTree_fromPanePID
test_captureProcessTree_includesChildProcesses
test_killSequence_sigterm_then_sigkill
test_killSequence_respectsTimeout
test_killOrder_taskWindowsFirst_thenTmux
test_selfKillDetection_callerInsideSession
test_selfKillDetection_callerOutsideSession
test_verifyCleanup_noOrphanedProcesses
test_stopCommand_integration_killsAllChildren
test_stopForce_skipsConfirmation
test_restartCommand_preservesSession
test_staleCompanyRelaunch_onlyInProgress
```

### Wave 3: Execution Graph (~16 tests)

**ExecutionGraphTests** (16 tests):
```
test_addTask_noDependencies_runsImmediately
test_addTask_withDependency_waitsForUpstream
test_parallelExecution_independentTasks
test_parallelExecution_boundedBySemaphore
test_upstreamFailure_skipsDownstream
test_upstreamFailure_onFailureEdge_runsHandler
test_watchEdge_rerunsOnChange
test_cycleDetection_throwsAtPlanTime
test_graphVisualization_asciiOutput
test_concurrencyLimit_configurable
test_dynamicExpansion_subgraphFromVertex
test_emptyGraph_noOp
test_singleTask_noEdges_succeeds
test_chainExecution_ABC_sequential
test_diamondExecution_ABCD_parallel
test_typedEdge_require_vs_onFailure_vs_watch
```

### Wave 4: Plan/Apply + Cost Control (~16 tests)

**PlanApplyTests** (10 tests):
```
test_synthesizePlan_fromTaskList
test_synthesizePlan_includesAgentAssignments
test_synthesizePlan_includesDependencyGraph
test_synthesizePlan_includesCostEstimate
test_planSerialization_toDiskAndBack
test_planDiff_twoPlansComparable
test_applyPlan_executesInGraphOrder
test_applyPlan_rejectsStalePlan
test_applyPlan_aspectValidation_beforeExecution
test_planArtifact_survivesContextReset
```

**CostControlTests** (6 tests):
```
test_budgetCheck_underLimit_allows
test_budgetCheck_80Percent_softAlert
test_budgetCheck_100Percent_autoPause
test_budgetReset_monthly
test_threeLayerBudget_companyAgentProject
test_costEventLogging_attribution
```

### Wave 5: Reactor + Aspects (~10 tests)

**ReactorTests** (6 tests):
```
test_eventMatch_globPattern
test_eventMatch_exactTag
test_reactor_triggersAction_onMatch
test_reactor_ignoresNonMatch
test_addReactor_atRuntime
test_removeReactor_atRuntime
```

**AspectTests** (4 tests):
```
test_costAspect_rejectOverBudgetPlan
test_qualityAspect_requireTestsOnCodeAgent
test_slaAspect_rejectExceedingMaxDuration
test_aspectPropagation_parentToChildren
```

**Total: ~86 new tests across 5 waves**

---

## Phase 5 — Architecture

### Package Structure

All new files in `tools/shiki-ctl/`:

```
Sources/ShikiCtlKit/
├── Models/
│   ├── SessionLifecycle.swift          # NEW — 11-state machine, TransitionActor, TaskContext
│   ├── ExecutionGraph.swift            # NEW — DAG with typed edges, walker, cycle detection
│   └── ExecutionPlan.swift             # NEW — Plan artifact, serialization, diff
├── Services/
│   ├── SessionRegistry.swift           # NEW — Discoverer protocol, 4-phase pipeline, orphan reaping
│   ├── SessionJournal.swift            # NEW — Append-only JSONL, coalescing, recovery
│   ├── ProcessCleanup.swift            # EXISTS (new file) — Process tree kill, self-kill detection
│   ├── Reactor.swift                   # NEW — Event-glob→action mapping
│   ├── CostController.swift            # NEW — 3-layer budget, soft/hard limits
│   ├── AspectRunner.swift              # NEW — Visitor pattern for cross-cutting policies
│   ├── BackendClient.swift             # MODIFY — Add cost event logging
│   ├── CompanyLauncher.swift           # MODIFY — Register discoverer, state transitions, TaskContext
│   ├── HeartbeatLoop.swift             # MODIFY — Re-enable checkStaleCompanies, orphan detection, periodic checkpoints
│   ├── EnvironmentDetector.swift       # EXISTS — No changes
│   ├── SessionStats.swift              # EXISTS — No changes
│   ├── StartupRenderer.swift           # EXISTS — No changes
│   └── NotificationService.swift       # MODIFY — Cost alerts, governance notifications
├── Aspects/
│   ├── CostAspect.swift                # NEW — Budget validation at plan time
│   ├── QualityAspect.swift             # NEW — Require tests on code-producing agents
│   └── SLAAspect.swift                 # NEW — Max duration enforcement
└── Protocols/
    ├── SessionDiscoverer.swift         # NEW — Protocol extracted for clarity
    └── Aspect.swift                    # NEW — IAspect visitor protocol

Sources/shiki-ctl/Commands/
├── StatusCommand.swift                 # MODIFY — Show states, history, TaskContext, graph
├── StopCommand.swift                   # MODIFY — Use ProcessCleanup, handle self-kill
├── RestartCommand.swift                # MODIFY — Use journal recovery
├── StartupCommand.swift                # MODIFY — Initialize registry + journal
├── DecideCommand.swift                 # MODIFY — Trigger re-dispatch after decision
└── DispatchCommand.swift               # NEW — Plan/apply workflow (`shiki dispatch`)

Tests/ShikiCtlKitTests/
├── SessionLifecycleTests.swift         # NEW — 14 tests
├── SessionRegistryTests.swift          # NEW — 10 tests
├── SessionJournalTests.swift           # NEW — 8 tests
├── ProcessCleanupTests.swift           # EXISTS — Extend to 12 tests
├── ExecutionGraphTests.swift           # NEW — 16 tests
├── PlanApplyTests.swift                # NEW — 10 tests
├── CostControlTests.swift              # NEW — 6 tests
├── ReactorTests.swift                  # NEW — 6 tests
└── AspectTests.swift                   # NEW — 4 tests
```

### Key Protocols

```swift
// --- Session Discovery (from Terraformer + Trivy) ---
protocol SessionDiscoverer {
    var kind: SessionKind { get }
    func discover() async throws -> [DiscoveredSession]
    func hydrate(_ session: DiscoveredSession) async throws -> SessionState
    func canHandle(_ session: DiscoveredSession) -> Bool  // from Trivy Required()
}

// --- Aspect System (from AWS CDK) ---
protocol Aspect {
    var name: String { get }
    func visit(_ session: SessionState, in plan: ExecutionPlan) throws
}

// --- Reactor (from Salt) ---
protocol ReactionHandler {
    func handle(event: ShikiEvent) async throws
}

struct ReactorRule {
    let tagPattern: String          // fnmatch glob
    let handler: ReactionHandler
}

// --- Execution Graph (from Terraform) ---
enum EdgeKind { case require, onFailure, watch }

struct TaskVertex {
    let id: String
    let agent: String
    let task: TaskContext
    var dependsOn: [(id: String, edge: EdgeKind)]
}
```

### Data Flow

```
User Intent ("review PR #42 for security")
        │
        ▼
┌─────────────────────┐
│   Plan Synthesis     │ ← Aspects validate (cost, quality, SLA)
│   (graph builder)    │ ← Agent capabilities matched to tasks
│                      │ ← Dependencies inferred + explicit
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│   Execution Plan     │ ← Serializable artifact (JSON on disk)
│   (DAG + metadata)   │ ← @Daimyo reviews once
└──────────┬──────────┘
           │ approved
           ▼
┌─────────────────────┐
│   DAG Walker         │ ← Semaphore-bounded parallelism
│   (graph executor)   │ ← Upstream failure → skip downstream
│                      │ ← Each vertex: queued→dispatched→running→done
└──────────┬──────────┘
           │ events
           ▼
┌─────────────────────┐
│   Event Bus          │ ← Tagged events (shiki/agent/*/task/*)
│   + Reactor          │ ← Glob-matched reactions (auto-heal, alert)
│   + Journal          │ ← Incremental state persistence
│   + Cost Controller  │ ← Budget tracking per event
└─────────────────────┘
```

### State Machine Diagram

```
                    ┌──────────────────┐
                    │     queued       │
                    └────────┬─────────┘
                             │
                    ┌────────▼─────────┐
              ┌─────│ awaitingApproval │ (governance gate)
              │     └────────┬─────────┘
              │              │ approved
              │     ┌────────▼─────────┐
              │     │   dispatched     │
              │     └────────┬─────────┘
              │              │
              │     ┌────────▼─────────┐
              │  ┌──│    running       │──┐
              │  │  └──┬──────┬──┬─────┘  │
              │  │     │      │  │        │
              │  │  ┌──▼──┐ ┌▼──▼───┐ ┌──▼──────────┐
              │  │  │pause│ │retry  │ │budgetPaused  │
              │  │  │  d  │ │  ing  │ │(cost limit)  │
              │  │  └──┬──┘ └──┬────┘ └──┬───────────┘
              │  │     └───────┘─────────┘
              │  │         (resume)
              │  │
         ┌────▼──▼───┐  ┌──────────┐  ┌──────────┐
         │  killed    │  │succeeded │  │  failed  │
         └────────────┘  └──────────┘  └──────────┘
              (terminal states — no transitions out)

         ┌──────────┐
         │ unknown  │ ← crash recovery only
         └────┬─────┘
              │ (→ running, failed, or killed after hydration)
```

---

## Phase 5b — Execution Plan

### Prerequisites (before any wave)

| # | Task | Est. | Verify |
|---|------|------|--------|
| P-1 | Commit all uncommitted work on `feature/cli-core-architecture` (36 files from vision session) | 5 min | `git status` clean |
| P-2 | Merge pending PRs on shiki-ctl, rebase `develop` | 10 min | CI green |
| P-3 | Create `feature/orchestrator-v3` branch from `develop` | 1 min | Branch exists |

### Wave 1: Session Foundation (BR-05 → BR-19, BR-48 → BR-49)

**Delivers**: Session lifecycle, registry, journal. The foundation everything else builds on.

| # | Task | File | Tests | Deps | Est. |
|---|------|------|-------|------|------|
| 1.1 | Create `SessionLifecycle.swift` — 11 states, `StateTransition`, `TransitionActor`, `TaskContext`, valid transitions map | `Models/SessionLifecycle.swift` | 14 | None | 15 min |
| 1.2 | Create `SessionLifecycleTests.swift` — all 14 test signatures from Phase 4 | `Tests/.../SessionLifecycleTests.swift` | — | 1.1 | 10 min |
| 1.3 | Create `SessionDiscoverer.swift` protocol + `SessionKind` enum + `DiscoveredSession` struct | `Protocols/SessionDiscoverer.swift` | — | 1.1 | 5 min |
| 1.4 | Create `SessionRegistry.swift` — discoverer map, `reconstruct()` 4-phase pipeline, `reapOrphans()` | `Services/SessionRegistry.swift` | 10 | 1.1, 1.3 | 15 min |
| 1.5 | Create `SessionRegistryTests.swift` — mock discoverers, orphan reaping | `Tests/.../SessionRegistryTests.swift` | — | 1.4 | 10 min |
| 1.6 | Create `SessionJournal.swift` — JSONL append, `checkpoint()`, `coalescedCheckpoint()`, `recoverAll()`, `prune()` | `Services/SessionJournal.swift` | 8 | 1.1 | 15 min |
| 1.7 | Create `SessionJournalTests.swift` — round-trip, coalescing, corrupt line handling | `Tests/.../SessionJournalTests.swift` | — | 1.6 | 10 min |
| 1.8 | Wire registry + journal into `ShikiCtl.swift` startup | `ShikiCtl.swift` | — | 1.4, 1.6 | 5 min |
| 1.9 | Update `StatusCommand.swift` — query registry, show states + history | `Commands/StatusCommand.swift` | — | 1.8 | 10 min |
| 1.10 | Update `HeartbeatLoop.swift` — register as discoverer, periodic checkpoints | `Services/HeartbeatLoop.swift` | — | 1.8 | 10 min |
| 1.11 | Update `CompanyLauncher.swift` — register as discoverer, state transitions, TaskContext | `Services/CompanyLauncher.swift` | — | 1.8 | 10 min |
| 1.12 | Run full test suite — verify 38 existing + 32 new all green | — | — | 1.1–1.11 | 5 min |

**Wave 1 PR**: `feat(shiki): session lifecycle, registry, and journal (orchestrator v3 wave 1)`

---

### Wave 2: Process Cleanup + Bug Fixes (BR-01 → BR-04, BR-20 → BR-23)

**Delivers**: Ghost process fix, stale company re-dispatch, self-kill handling. Fixes all 4 critical bugs from vision session.

| # | Task | File | Tests | Deps | Est. |
|---|------|------|-------|------|------|
| 2.1 | Enhance `ProcessCleanup.swift` — process tree walker, SIGTERM→SIGKILL sequence, self-kill fork | `Services/ProcessCleanup.swift` | 12 | Wave 1 | 20 min |
| 2.2 | Create/extend `ProcessCleanupTests.swift` — tree walk, kill sequence, self-kill detection | `Tests/.../ProcessCleanupTests.swift` | — | 2.1 | 15 min |
| 2.3 | Update `StopCommand.swift` — use ProcessCleanup, verify zero orphans post-stop | `Commands/StopCommand.swift` | — | 2.1 | 10 min |
| 2.4 | Update `RestartCommand.swift` — use journal `recoverAll()` for state reconstruction | `Commands/RestartCommand.swift` | — | Wave 1 | 10 min |
| 2.5 | Re-enable `checkStaleCompanies()` in `HeartbeatLoop.swift` with smart logic (only in-progress) | `Services/HeartbeatLoop.swift` | — | Wave 1 | 10 min |
| 2.6 | Add decision-unblock detection in `HeartbeatLoop.swift` — after `checkDecisions()`, detect answered → re-dispatch | `Services/HeartbeatLoop.swift` | — | 2.5 | 10 min |
| 2.7 | Update `DecideCommand.swift` — signal orchestrator after decision answered | `Commands/DecideCommand.swift` | — | 2.6 | 5 min |
| 2.8 | Run full test suite — verify all green including new cleanup tests | — | — | 2.1–2.7 | 5 min |

**Wave 2 PR**: `fix(shiki): ghost process cleanup, stale company re-dispatch, self-kill handling`

---

### Wave 3: Execution Graph (BR-24 → BR-28)

**Delivers**: DAG-based dispatch replacing wave-based sequential dispatch.

| # | Task | File | Tests | Deps | Est. |
|---|------|------|-------|------|------|
| 3.1 | Create `ExecutionGraph.swift` — `TaskVertex`, `EdgeKind`, `AcyclicGraph`, `Walker` with semaphore-bounded parallelism | `Models/ExecutionGraph.swift` | 16 | Wave 1 | 25 min |
| 3.2 | Implement cycle detection (DFS-based) — reject at build time | `Models/ExecutionGraph.swift` | — | 3.1 | 10 min |
| 3.3 | Implement upstream failure propagation — skip downstream on `require` edge, run on `onFailure` edge | `Models/ExecutionGraph.swift` | — | 3.1 | 10 min |
| 3.4 | Implement `watch` edge — re-run vertex when dependency output changes | `Models/ExecutionGraph.swift` | — | 3.1 | 10 min |
| 3.5 | ASCII graph visualization for `shiki status --graph` | `Models/ExecutionGraph.swift` | — | 3.1 | 10 min |
| 3.6 | Create `ExecutionGraphTests.swift` — all 16 test signatures | `Tests/.../ExecutionGraphTests.swift` | — | 3.1–3.5 | 15 min |
| 3.7 | Integrate graph into `CompanyLauncher.swift` — tasks dispatched via walker instead of flat loop | `Services/CompanyLauncher.swift` | — | 3.1 | 15 min |
| 3.8 | Run full test suite | — | — | 3.1–3.7 | 5 min |

**Wave 3 PR**: `feat(shiki): DAG-based execution graph with typed edges`

---

### Wave 4: Plan/Apply + Cost Control (BR-29 → BR-38)

**Delivers**: Reviewable execution plans, `shiki dispatch` command, budget enforcement.

| # | Task | File | Tests | Deps | Est. |
|---|------|------|-------|------|------|
| 4.1 | Create `ExecutionPlan.swift` — plan synthesis from task list, serialization to JSON, diff support | `Models/ExecutionPlan.swift` | 10 | Wave 3 | 20 min |
| 4.2 | Create `CostController.swift` — 3-layer budget (company/agent/project), soft/hard limits, monthly reset, event logging | `Services/CostController.swift` | 6 | Wave 1 | 15 min |
| 4.3 | Create `DispatchCommand.swift` — `shiki dispatch` with plan preview + approval + apply | `Commands/DispatchCommand.swift` | — | 4.1, Wave 3 | 15 min |
| 4.4 | Create `PlanApplyTests.swift` + `CostControlTests.swift` | Tests | — | 4.1, 4.2 | 15 min |
| 4.5 | Integrate cost events into `HeartbeatLoop.swift` — budget check per cycle, auto-pause at limit | `Services/HeartbeatLoop.swift` | — | 4.2 | 10 min |
| 4.6 | Update `NotificationService.swift` — cost alerts via ntfy | `Services/NotificationService.swift` | — | 4.2 | 5 min |
| 4.7 | Staleness check — apply refuses if plan inputs changed | `Models/ExecutionPlan.swift` | — | 4.1 | 5 min |
| 4.8 | Run full test suite | — | — | 4.1–4.7 | 5 min |

**Wave 4 PR**: `feat(shiki): plan/apply lifecycle + cost control`

---

### Wave 5: Reactor + Aspects (BR-39 → BR-47)

**Delivers**: Event-driven autonomous reactions, cross-cutting policy enforcement, agent self-registration.

| # | Task | File | Tests | Deps | Est. |
|---|------|------|-------|------|------|
| 5.1 | Create `Reactor.swift` — event bus with tag namespacing, glob-matched reactions, add/remove at runtime | `Services/Reactor.swift` | 6 | Wave 1 | 15 min |
| 5.2 | Create `Aspect.swift` protocol + `AspectRunner.swift` — visitor pattern, runs during plan synthesis | `Protocols/Aspect.swift`, `Services/AspectRunner.swift` | — | Wave 4 | 10 min |
| 5.3 | Create `CostAspect.swift` — reject over-budget plans | `Aspects/CostAspect.swift` | — | 5.2, 4.2 | 5 min |
| 5.4 | Create `QualityAspect.swift` — require tests on code-producing agents | `Aspects/QualityAspect.swift` | — | 5.2 | 5 min |
| 5.5 | Create `SLAAspect.swift` — max duration enforcement | `Aspects/SLAAspect.swift` | — | 5.2 | 5 min |
| 5.6 | Wire reactor into `HeartbeatLoop.swift` — emit events, process reactions | `Services/HeartbeatLoop.swift` | — | 5.1 | 10 min |
| 5.7 | Add governance gate flow — `awaitingApproval` → ntfy → `shiki decide` → `dispatched` | Multiple | — | 5.1, Wave 2 | 10 min |
| 5.8 | Create `ReactorTests.swift` + `AspectTests.swift` | Tests | 10 | 5.1–5.5 | 10 min |
| 5.9 | Run full test suite — verify all ~86 new + 38 existing green | — | — | All | 5 min |

**Wave 5 PR**: `feat(shiki): reactor system + aspect policies + governance gates`

---

### Implementation Readiness Gate

| Category | Count | Covered? |
|----------|-------|----------|
| Business Rules | 49 (BR-01 → BR-49) | All mapped to waves |
| Test Signatures | 86 across 9 test files | All defined in Phase 4 |
| New Files | 14 | All listed in architecture |
| Modified Files | 7 | All identified |
| Critical Bugs | 4 (from vision session) | All in Wave 2 |
| Research Sources | 9 projects | All patterns attributed |
| Breaking Changes | 0 | Verified — additive only |

---

## Phase 6 — Implementation Log

_To be filled during execution. Each wave gets a dated entry._

| Date | Wave | Event | Notes |
|------|------|-------|-------|
| — | — | — | Awaiting @Daimyo approval to begin |

---

## Phase 7 — Review History

| Date | Phase | Reviewer | Decision |
|------|-------|----------|----------|
| 2026-03-16 | Phase 1–5b | @Research Lab | Plan synthesized from 9 projects + vision + evolution plan |
| — | Phase 5b | @Daimyo | Pending approval |

---

## Appendix A: Research Provenance

All research findings are stored in Shiki DB (project `1b6da95d-6a93-4048-a975-f20e7885e669`):

| Project | DB Category | Key Patterns Adopted |
|---------|------------|---------------------|
| hashicorp/terraform | research | DAG walker (Wave 3), plan/apply (Wave 4), plugin protocol (future) |
| kestra-io/kestra | research | 17-state model → 11 states (Wave 1), concurrency control (Wave 3), retry (Wave 1) |
| pulumi/pulumi | research | Snapshot journaling (Wave 1), chain/antichain (Wave 3), Automation API (future) |
| saltstack/salt | research | Reactor system (Wave 5), grains/pillar (Wave 5), event bus (Wave 5) |
| aquasecurity/trivy | research | Self-registering analyzers (Wave 1), hook lifecycle (Wave 5) |
| GoogleCloudPlatform/terraformer | research | ServiceGenerator → SessionDiscoverer (Wave 1), 4-phase pipeline (Wave 1) |
| aws/aws-cdk | research | L1/L2/L3 abstractions (future), aspect system (Wave 5), synthesis (Wave 4) |
| Motion AI | research | Cross-project priority → TaskContext (Wave 1), SOP→workflow (future), at-risk alerts (Wave 4) |
| Paperclip | research | Orphan reaping (Wave 1), cost control (Wave 4), governance (Wave 5), goal hierarchy (Wave 1), wakeup coalescing (Wave 1) |

## Appendix B: Radar Watchlist

4 projects added to `/radar` for ongoing monitoring:

| Repo | Tier | Why |
|------|------|-----|
| kestra-io/kestra | Trial | Most architecturally relevant — DAG, state machine, concurrency, SLA |
| hashicorp/terraform | Assess | DAG walker + plan/apply + plugin protocol gold standard |
| pulumi/pulumi | Assess | Validates Swift-first, chain/antichain, Automation API |
| aws/aws-cdk | Assess | L1/L2/L3 constructs + aspect system |

## Appendix C: Vision Alignment

This plan implements the **inner circle** (Shiki Solo) of the concentric product model from the vision session:

```
        ┌─────────────────────────┐
        │    Shiki Platform       │  ← NOT IN SCOPE (6+ months)
        │  ┌───────────────────┐  │
        │  │ Shiki Workspaces  │  │  ← NOT IN SCOPE (2-3 months)
        │  │ ┌───────────────┐ │  │
        │  │ │  Shiki Solo   │ │  │  ← THIS PLAN (v3 orchestrator)
        │  │ │  Orchestrator │ │  │
        │  │ │  v3           │ │  │
        │  │ └───────────────┘ │  │
        │  └───────────────────┘  │
        └─────────────────────────┘
```

Architecture decisions that support future circles WITHOUT implementing them:
- `TaskContext.companyId` → ready for multi-workspace routing
- `SessionDiscoverer` protocol → extensible for remote agents
- `Reactor` event bus → ready for cross-workspace events
- `CostController` 3-layer budget → ready for per-workspace billing
- `Aspect` system → ready for team-level policies
