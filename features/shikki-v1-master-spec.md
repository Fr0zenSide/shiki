# Shikki v1.0 — Master Spec

> Created: 2026-03-21 | Deadline: Sunday 2026-03-23 23:59
> Status: APPROVED PLAN — execute on validation
> Owner: @Daimyo | Engine: ShikiCore + shiki-ctl
> Epic branch: `epic/shikki-v1`

---

## What is v1.0?

v0.2 is Claude with extra files. v1.0 is an orchestration engine with compiled behavior, real telemetry, and multi-project dispatch. The gap is 10 concrete deliverables — no moonshots, no maybes.

**Source of truth**: `docs/shikki-flow-current-vs-vision.md` (the gap diagram)

---

## Dependency Graph

```
═══════════════════════════════════════════════════════════════
EPIC 1: epic/shikki-v1 — The Engine (ships first)
═══════════════════════════════════════════════════════════════

Friday (Day 1) — CLI Foundation

  ┌──────────────────────┐  ┌──────────────────────┐  ┌──────────────────────┐
  │ F2a: Session Resume  │  │ F2b: Auto-Save Exit  │  │ F2c: PRGate epic/*   │
  │ Launches Tmux        │  │ Hook/Trap in CLI     │  │ Accept epic/story/*  │
  │ shiki-ctl            │  │ shiki-ctl            │  │ ShikiCore + skills   │
  └──────────┬───────────┘  └──────────┬───────────┘  └──────────┬───────────┘
             │                         │                         │
             └─────────────┬───────────┘                         │
                           ▼                                     │
                ┌──────────────────────┐                         │
                │ F3: /pre-pr --autofix│◄────────────────────────┘
                │ Auto-fix + re-run    │
                └──────────────────────┘

Saturday (Day 2) — Engine Core

  ┌──────────────────────┐  ┌──────────────────────┐  ┌──────────────────────┐
  │ S1a: Sub-Agent       │  │ S1b: Real Spend      │  │ S1c: Scoped Testing  │
  │ Dispatch Protocol    │  │ Tracking             │  │ TestScope on WaveNode│
  │ ShikiCore            │  │ AgentProvider        │  │ ShikiCore + QualGate │
  └──────────┬───────────┘  └──────────┬───────────┘  └──────────┬───────────┘
             │                         │                         │
             └─────────────┬───────────┴─────────────────────────┘
                           ▼
                ┌──────────────────────┐
                │ S2: Orchestrator DNA │
                │ + Shikki Flow Proto  │
                │ 8-step + 10-step     │
                │ ShikiCore Swift      │
                └──────────────────────┘

Sunday (Day 3) — Polish + Ship

  ┌──────────────────────┐  ┌──────────────────────┐  ┌──────────────────────┐
  │ U1a: Personality.md  │  │ U1b: Animated Splash │  │ U1c: Epic Branching  │
  │ Append-only behavior │  │ Terminal art + state  │  │ ChangelogGate scope  │
  │ ShikiCore + CLI      │  │ shiki-ctl            │  │ ShikiCore + CLI      │
  └──────────────────────┘  └──────────────────────┘  └──────────────────────┘
             │                         │                         │
             └─────────────┬───────────┴─────────────────────────┘
                           ▼
                ┌──────────────────────┐
                │ U2: Ship v1.0        │
                │ README + /pre-pr all │
                │ Tag v1.0.0           │
                └──────────────────────┘

═══════════════════════════════════════════════════════════════
EPIC 2: epic/shikki-v1-test-drive — Built WITH Shikki v1
═══════════════════════════════════════════════════════════════
(runs AFTER epic 1 /pre-pr passes — uses v1.0 to orchestrate)

  ┌──────────────────────┐  ┌──────────────────────┐  ┌──────────────────────┐
  │ T1a: Maya Animations │  │ T1b: WabiSabi Anim.  │  │ T2: SUI Video API    │
  │ 5 components, 23 t.  │  │ 5 components, 30 t.  │  │ Core Recorder, 38 t. │
  │ Dispatched BY Shikki │  │ Dispatched BY Shikki │  │ Dispatched BY Shikki │
  │ into projects/Maya/  │  │ into projects/wabi/  │  │ into packages/Media/ │
  └──────────────────────┘  └──────────────────────┘  └──────────────────────┘
             │                         │                         │
             └─────────────┬───────────┴─────────────────────────┘
                           ▼
                ┌──────────────────────┐
                │ T3: /pre-pr on each  │
                │ Run BY Shikki v1     │
                │ Review epic branches │
                └──────────────────────┘
```

**Two epics, two purposes:**
- **Epic 1** builds the engine (Shikki v1.0 itself)
- **Epic 2** is the FIRST PROJECT built with that engine — proving it works

**Parallelism**: F2a-F2c parallel → F3. S1a-S1c parallel → S2. U1a-U1c parallel → U2. Epic 2 waves T1a, T1b, T2 all parallel (dispatched by Shikki v1 orchestrator).

---

## Business Rules

| ID | Rule |
|----|------|
| BR-01 | Every wave has a TestScope — scoped tests only during dev |
| BR-02 | Full test suite runs ONCE at /pre-pr on the epic |
| BR-03 | All work on feature/ branches, merged via PR to develop |
| BR-04 | Sub-agents report to ShikkiDB (task_started, test_passed, pr_created, etc.) |
| BR-05 | No code without failing test first (TPDD) |
| BR-06 | All animations respect accessibilityReduceMotion |
| BR-07 | Orchestrator DNA is a protocol in ShikiCore, not just a markdown file |
| BR-07b | Shikki Flow (the 10-step production process) is also a protocol in ShikiCore — spec→validate→dispatch→monitor→collect→pre-pr→review→merge→ship→report |
| BR-08 | Session resume must complete in < 3 seconds (warm start) |
| BR-09 | Splash screen is < 2 seconds, skippable, non-blocking |
| BR-10 | README is < 100 lines, first 3 lines explain the product to anyone who has used an LLM |
| BR-11 | Animations (Maya, WabiSabi) and SUI Video API are implemented AFTER v1.0 epic /pre-pr passes — they become the first project built WITH Shikki v1, not part of it |

---

## Friday (Day 1) — Foundation + Animations

### Wave F1a: Maya Animations

**Spec**: `features/maya-animations-v1.md`
**Agent**: Sub-agent in `projects/Maya/`
**Branch**: `feature/maya-animations` from `epic/shikki-v1`
**Dependencies**: None (parallel)

| # | Component | Source File | Test File | Tests |
|---|-----------|-------------|-----------|-------|
| 1 | AsyncActionButton | `Core/Abstracts/Presentation/DesignSystem/Components/Commons/AsyncActionButton.swift` | `MayaFitTests/Components/Animations/AsyncActionButtonTests.swift` | 6 |
| 2 | WorkoutCompletionCelebration | `Commons/WorkoutCompletionCelebration.swift` | `Animations/WorkoutCompletionCelebrationTests.swift` | 4 |
| 3 | ProgressWaveFill | `Commons/ProgressWaveFill.swift` | `Animations/ProgressWaveFillTests.swift` | 5 |
| 4 | SyncIndicator | `Commons/SyncIndicator.swift` | `Animations/SyncIndicatorTests.swift` | 4 |
| 5 | StreakMilestone | `Commons/StreakMilestone.swift` | `Animations/StreakMilestoneTests.swift` | 4 |

**TestScope**:
```
Package: projects/Maya
Filter: AsyncActionButtonTests|WorkoutCompletionCelebrationTests|ProgressWaveFillTests|SyncIndicatorTests|StreakMilestoneTests
Expected new tests: 23
```

**Success criteria**:
- `swift test --filter "AnimationTests"` — 23/23 green
- All 5 components render in previews
- accessibilityReduceMotion tested per BR-06
- PR created to `epic/shikki-v1`

**Estimated LOC**: ~600 (5 components + 5 test files)

---

### Wave F1b: WabiSabi Animations

**Spec**: `features/wabisabi-animations-v1.md`
**Agent**: Sub-agent in `projects/wabisabi/`
**Branch**: `feature/wabisabi-animations` from `epic/shikki-v1`
**Dependencies**: None (parallel)

| # | Component | Source Dir | Test Dir | Tests |
|---|-----------|-----------|---------|-------|
| 1 | PracticeLoader | `Components/PracticeLoader/` (2 files: View + VM) | `PracticeLoader/PracticeLoaderTests.swift` | 5 |
| 2 | ModeToggle | `Components/ModeToggle/` (3 files: View + VM + Shape) | `ModeToggle/ModeToggleTests.swift` | 5 |
| 3 | HabitAddExpand | `Components/HabitAddExpand/` (2 files: View + VM) | `HabitAddExpand/HabitAddExpandTests.swift` | 6 |
| 4 | BreathingGuide | `Components/BreathingGuide/` (3 files: View + VM + Shape) | `BreathingGuide/BreathingGuideTests.swift` | 8 |
| 5 | FocusSwitch | `Components/FocusSwitch/` (2 files: View + VM) | `FocusSwitch/FocusSwitchTests.swift` | 6 |

**TestScope**:
```
Package: projects/wabisabi
Filter: PracticeLoaderTests|ModeToggleTests|HabitAddExpandTests|BreathingGuideTests|FocusSwitchTests
Expected new tests: 29 (corrected: 30 from spec)
```

**Success criteria**:
- 29 tests green (scoped)
- Palette extraction: `CanvasRenderers.Palette` made `internal` or extracted to shared scope
- All VMs use `@Observable` (not ObservableObject)
- accessibilityReduceMotion on every component (BR-06)
- PR created to `epic/shikki-v1`

**Estimated LOC**: ~900 (12 source files + 5 test files)

---

### Wave F2a: Session Resume Launches Tmux

**Branch**: `feature/session-resume-tmux` from `epic/shikki-v1`
**Dependencies**: None (parallel with F1)

| File | Action | Purpose |
|------|--------|---------|
| `tools/shiki-ctl/Sources/ShikiCtlKit/Services/SessionLifecycle.swift` | Modify | Add `launchTmux()` call on resume path |
| `tools/shiki-ctl/Sources/ShikiCtlKit/Services/TmuxLauncher.swift` | Create | Thin wrapper: restore layout, start segments, attach |
| `tools/shiki-ctl/Tests/ShikiCtlKitTests/SessionLifecycleTests.swift` | Modify | Add resume-launches-tmux tests |
| `tools/shiki-ctl/Tests/ShikiCtlKitTests/TmuxLauncherTests.swift` | Create | Unit tests for tmux command generation |

**TestScope**:
```
Package: tools/shiki-ctl
Filter: SessionLifecycleTests|TmuxLauncherTests
Expected new tests: 6
```

**Tests** (6):
1. `resume_withCheckpoint_launchesTmux` — tmux session created on resume
2. `resume_existingTmuxSession_attaches` — no duplicate sessions
3. `resume_noCheckpoint_skipsLaunch` — graceful degradation
4. `tmuxLauncher_generatesCorrectSessionName` — session naming
5. `tmuxLauncher_restoresLayout` — pane layout from checkpoint
6. `resume_completesWithinThreeSeconds` — BR-08 performance gate

**Success criteria**:
- `shikki session resume` starts tmux with correct layout
- Warm start < 3 seconds (BR-08)
- Works when tmux is already running (attach, not create)

**Estimated LOC**: ~200

---

### Wave F2b: Auto-Save on Exit

**Branch**: `feature/session-autosave` from `epic/shikki-v1`
**Dependencies**: None (parallel with F1)

| File | Action | Purpose |
|------|--------|---------|
| `tools/shiki-ctl/Sources/ShikiCtlKit/Services/SessionLifecycle.swift` | Modify | Register SIGINT/SIGTERM trap, auto-checkpoint |
| `tools/shiki-ctl/Sources/ShikiCtlKit/Services/SessionCheckpointManager.swift` | Modify | Add `autoSaveOnExit()` method, debounced |
| `tools/shiki-ctl/Tests/ShikiCtlKitTests/SessionCheckpointTests.swift` | Modify | Add auto-save tests |

**TestScope**:
```
Package: tools/shiki-ctl
Filter: SessionCheckpointTests
Expected new tests: 5
```

**Tests** (5):
1. `autoSave_onExit_createsCheckpoint` — checkpoint file written
2. `autoSave_debounces_multipleSignals` — no duplicate checkpoints
3. `autoSave_includesActiveAgentState` — sub-agent state captured
4. `autoSave_emitsEvent_toShikkiDB` — session_paused event
5. `autoSave_failsGracefully_onDiskError` — no crash on write failure

**Success criteria**:
- Exit (Ctrl-C, terminal close, kill) triggers checkpoint
- Checkpoint includes: branch, active agents, budget state, timestamp
- ShikkiDB event emitted (session_paused)

**Estimated LOC**: ~120

---

### Wave F2c: PRGate Accepts epic/* and story/*

**Branch**: `feature/prgate-epic-targets` from `epic/shikki-v1`
**Dependencies**: None (parallel with F1)

| File | Action | Purpose |
|------|--------|---------|
| `packages/ShikiCore/Sources/ShikiCore/Pipeline/QualityGate.swift` | Modify | Accept epic/* and story/* as valid PR targets |
| `.claude/commands/pre-pr.md` | Modify | Document epic/* support in /pre-pr |
| `packages/ShikiCore/Tests/ShikiCoreTests/Pipeline/QualityGateTests.swift` | Modify | Add target validation tests |

**TestScope**:
```
Package: packages/ShikiCore
Filter: QualityGateTests
Expected new tests: 4
```

**Tests** (4):
1. `qualityGate_acceptsDevelopTarget` — existing behavior preserved
2. `qualityGate_acceptsEpicTarget` — epic/* branches valid
3. `qualityGate_acceptsStoryTarget` — story/* branches valid
4. `qualityGate_rejectsMainTarget` — main/master still blocked

**Success criteria**:
- `/pre-pr` works on branches targeting `epic/*` and `story/*`
- Existing develop-targeting PRs unaffected
- Error message when targeting main/master

**Estimated LOC**: ~80

---

### Wave F3: /pre-pr --autofix

**Branch**: `feature/prepr-autofix` from `epic/shikki-v1`
**Dependencies**: F2a, F2b, F2c must complete

| File | Action | Purpose |
|------|--------|---------|
| `.claude/commands/pre-pr.md` | Modify | Add --autofix flag behavior |
| `tools/shiki-ctl/Sources/ShikiCtlKit/Services/PrePRRunner.swift` | Create | Autofix orchestrator: run gates, fix failures, re-run |
| `tools/shiki-ctl/Tests/ShikiCtlKitTests/PrePRRunnerTests.swift` | Create | Autofix loop tests |

**TestScope**:
```
Package: tools/shiki-ctl
Filter: PrePRRunnerTests
Expected new tests: 6
```

**Tests** (6):
1. `autofix_lintFailure_fixesAndReRuns` — auto-fix cycle works
2. `autofix_testFailure_reportsNotAutoFixed` — test failures escalated, not silently fixed
3. `autofix_maxRetries_stopsAfterThree` — no infinite loop
4. `autofix_allGatesPass_noFixNeeded` — happy path
5. `autofix_emitsEvents_toShikkiDB` — gate_autofix_applied events
6. `autofix_reportsFixSummary` — what was fixed, what was not

**Success criteria**:
- `/pre-pr --autofix` auto-fixes lint/format issues and re-runs gates
- Test failures are reported, not auto-fixed (humans fix logic)
- Maximum 3 retry cycles, then report
- ShikkiDB events emitted for each fix applied

**Estimated LOC**: ~250

---

## Saturday (Day 2) — Engine

### Wave S1a: Sub-Agent Dispatch Protocol

**Branch**: `feature/dispatch-protocol` from `epic/shikki-v1`
**Dependencies**: None (parallel)

| File | Action | Purpose |
|------|--------|---------|
| `packages/ShikiCore/Sources/ShikiCore/Orchestration/Dispatch.swift` | Create | Dispatch struct: project, branch, spec, testScope, successCriteria |
| `packages/ShikiCore/Sources/ShikiCore/Orchestration/DispatchResult.swift` | Create | Result enum: completed, failed, blocked |
| `packages/ShikiCore/Sources/ShikiCore/Agent/ShikiAgentClient.swift` | Create | Actor: dispatch(Dispatch) -> DispatchResult, manages Claude sessions |
| `packages/ShikiCore/Sources/ShikiCore/Events/DispatchEvent.swift` | Create | Events: task_started, wave_started, test_passed/failed, pr_created, task_completed, blocker_hit |
| `packages/ShikiCore/Tests/ShikiCoreTests/Orchestration/DispatchTests.swift` | Create | Dispatch struct + validation tests |
| `packages/ShikiCore/Tests/ShikiCoreTests/Agent/ShikiAgentClientTests.swift` | Create | Agent client dispatch/cancel tests |

**TestScope**:
```
Package: packages/ShikiCore
Filter: DispatchTests|ShikiAgentClientTests
Expected new tests: 10
```

**Tests** (10):
1. `dispatch_hasRequiredFields` — project, branch, spec, testScope
2. `dispatch_encodesDecode_roundTrip` — Codable conformance
3. `dispatch_validatesBranchNaming` — must be feature/ or fix/
4. `dispatchResult_completed_hasMetrics` — LOC, test count, files changed
5. `dispatchResult_failed_hasError` — error description preserved
6. `agentClient_dispatchEmitsTaskStarted` — ShikkiDB event on dispatch
7. `agentClient_cancelStopsAgent` — cancellation propagates
8. `agentClient_dispatchSetsWorkingDirectory` — project path applied
9. `agentClient_dispatchCreatesBranch` — git branch from baseBranch
10. `agentClient_completionEmitsTaskCompleted` — ShikkiDB event on finish

**Success criteria**:
- `Dispatch` struct is the contract between orchestrator and sub-agent
- `ShikiAgentClient` actor dispatches via `claude -p` with correct cwd
- All lifecycle events emitted to ShikkiDB
- Agent isolation: each sub-agent gets its own context (worktree or project dir)

**Estimated LOC**: ~350

---

### Wave S1b: Real Spend Tracking

**Branch**: `feature/spend-tracking` from `epic/shikki-v1`
**Dependencies**: None (parallel)

| File | Action | Purpose |
|------|--------|---------|
| `packages/ShikiCore/Sources/ShikiCore/Agent/AgentProvider.swift` | Modify | Add `currentSessionSpend: Decimal` property to protocol |
| `packages/ShikiCore/Sources/ShikiCore/Agent/ClaudeProvider.swift` | Modify | Parse Claude API spend from session metadata |
| `packages/ShikiCore/Sources/ShikiCore/Orchestration/BudgetEnforcer.swift` | Modify | Integrate real spend (not placeholder) |
| `tools/shiki-ctl/Sources/ShikiCtlKit/Segments/BudgetSegment.swift` | Modify | Display real spend in tmux status bar |
| `packages/ShikiCore/Tests/ShikiCoreTests/Agent/AgentProviderTests.swift` | Create | Spend tracking tests |
| `packages/ShikiCore/Tests/ShikiCoreTests/Orchestration/BudgetEnforcerTests.swift` | Modify | Real spend integration tests |

**TestScope**:
```
Package: packages/ShikiCore
Filter: AgentProviderTests|BudgetEnforcerTests
Expected new tests: 8
```

**Tests** (8):
1. `agentProvider_currentSessionSpend_startsAtZero`
2. `agentProvider_currentSessionSpend_accumulatesAcrossDispatches`
3. `claudeProvider_parsesSpend_fromSessionMetadata`
4. `claudeProvider_returnsZero_whenMetadataMissing` — graceful degradation
5. `budgetEnforcer_realSpend_respectsDailyLimit`
6. `budgetEnforcer_realSpend_pausesOnExceed`
7. `budgetEnforcer_multiProvider_aggregatesSpend`
8. `budgetSegment_displaysRealAmount_notPlaceholder`

**Success criteria**:
- tmux status bar shows real $ spend (e.g., `$12/$31`), not `$0`
- BudgetEnforcer uses real per-provider spend data
- Graceful degradation when spend data unavailable

**Estimated LOC**: ~200

---

### Wave S1c: Scoped Testing Enforced

**Spec**: `features/shiki-scoped-testing.md`
**Branch**: `feature/scoped-testing` from `epic/shikki-v1`
**Dependencies**: None (parallel)

| File | Action | Purpose |
|------|--------|---------|
| `packages/ShikiCore/Sources/ShikiCore/Planning/WaveNode.swift` | Modify | Add `testScope: TestScope?` property |
| `packages/ShikiCore/Sources/ShikiCore/Planning/TestScope.swift` | Create | TestScope struct: packagePath, filterPattern, sourceGlob, expectedNewTests, runCommand |
| `packages/ShikiCore/Sources/ShikiCore/Pipeline/QualityGate.swift` | Modify | Scoped mode via PipelineContext, not gate constructor |
| `packages/ShikiCore/Tests/ShikiCoreTests/Planning/TestScopeTests.swift` | Create | TestScope tests |
| `packages/ShikiCore/Tests/ShikiCoreTests/Planning/WaveNodeTests.swift` | Modify | Add testScope field tests |

**TestScope**:
```
Package: packages/ShikiCore
Filter: TestScopeTests|WaveNodeTests|QualityGateTests
Expected new tests: 8
```

**Tests** (8):
1. `testScope_runCommand_singlePackage` — correct swift test command
2. `testScope_runCommand_withFilter` — --filter flag included
3. `testScope_runCommand_emptyFilter_omitsFlag` — package-only scope
4. `testScope_expectedNewTests_validated` — parse output, assert count >= expected
5. `waveNode_testScope_optional` — nil for waves without tests
6. `waveNode_testScope_encodesDecodes` — Codable round-trip
7. `qualityGate_scopedMode_usesFilterCommand` — not full suite
8. `qualityGate_epicMode_runsFull` — nil scope = full suite

**Success criteria**:
- Every WaveNode can declare a TestScope
- QualityGate respects scope during dev, runs full at /pre-pr
- Test count assertion catches zero-match filter typos
- TestScope stored in DependencyTree, queryable

**Estimated LOC**: ~200

---

### Wave S2: Orchestrator DNA Compiled

**Spec**: `features/shikki-orchestrator-dna.md`
**Branch**: `feature/orchestrator-dna` from `epic/shikki-v1`
**Dependencies**: S1a, S1b, S1c must complete

| File | Action | Purpose |
|------|--------|---------|
| `packages/ShikiCore/Sources/ShikiCore/Orchestration/OrchestratorProtocol.swift` | Create | Protocol: understand, scope, plan, present, dispatch, monitor, collect, report |
| `packages/ShikiCore/Sources/ShikiCore/Orchestration/OrchestratorLoop.swift` | Create | Default implementation of the 8-step loop |
| `packages/ShikiCore/Sources/ShikiCore/Orchestration/CompanyManager.swift` | Modify | Conform to OrchestratorProtocol, integrate Dispatch + events |
| `packages/ShikiCore/Sources/ShikiCore/Lifecycle/FeatureLifecycle.swift` | Modify | Connect to dispatch protocol for building stage |
| `packages/ShikiCore/Tests/ShikiCoreTests/Orchestration/OrchestratorLoopTests.swift` | Create | 8-step loop tests |
| `packages/ShikiCore/Tests/ShikiCoreTests/Orchestration/CompanyManagerIntegrationTests.swift` | Create | Multi-lifecycle coordination tests |

**TestScope**:
```
Package: packages/ShikiCore
Filter: OrchestratorLoopTests|CompanyManagerIntegrationTests
Expected new tests: 12
```

**Tests** (12):
1. `orchestratorLoop_understandPhase_parsesIntent`
2. `orchestratorLoop_scopePhase_identifiesProjects`
3. `orchestratorLoop_planPhase_createsWaves`
4. `orchestratorLoop_presentPhase_emitsPlanEvent`
5. `orchestratorLoop_dispatchPhase_launchesAgents`
6. `orchestratorLoop_monitorPhase_pollsEvents`
7. `orchestratorLoop_collectPhase_aggregatesResults`
8. `orchestratorLoop_reportPhase_emitsSummary`
9. `orchestratorLoop_blockerEscalation_notifiesDaimyo`
10. `companyManager_multiLifecycle_runsInParallel`
11. `companyManager_budgetExhausted_pausesRemaining`
12. `companyManager_crashRecovery_resumesFromCheckpoint`

**Success criteria**:
- `OrchestratorProtocol` defines the 8 steps as protocol requirements (BR-07)
- Default implementation in `OrchestratorLoop` is testable
- CompanyManager runs N lifecycles concurrently
- Each step emits events to ShikkiDB
- Full loop: intent in, PRs out

**Estimated LOC**: ~450

---

### Wave S3: SUI Video API — Wave 1

**Spec**: `features/shiki-sui-video-api.md` (Wave 1 only)
**Branch**: `feature/sui-video-core` from `epic/shikki-v1`
**Dependencies**: None (parallel with S1/S2)

| File | Action | Purpose |
|------|--------|---------|
| `packages/MediaKit/Package.swift` | Modify | Ensure SPM manifest correct |
| `packages/MediaKit/Sources/MediaKit/SUIDevice.swift` | Create | Device definitions |
| `packages/MediaKit/Sources/MediaKit/RecorderConfiguration.swift` | Create | Frame rate, max duration, scale |
| `packages/MediaKit/Sources/MediaKit/RecorderError.swift` | Create | Typed errors |
| `packages/MediaKit/Sources/MediaKit/FrameCapture.swift` | Create | Protocol + UIHostingController impl |
| `packages/MediaKit/Sources/MediaKit/VideoWriter.swift` | Create | AVAssetWriter + pixel buffer adaptor |
| `packages/MediaKit/Sources/MediaKit/SUIVideoRecorder.swift` | Create | Public API, actor-protected state |
| `packages/MediaKit/Tests/MediaKitTests/SUIDeviceTests.swift` | Create | Device dimension tests |
| `packages/MediaKit/Tests/MediaKitTests/VideoWriterTests.swift` | Create | Writer tests |
| `packages/MediaKit/Tests/MediaKitTests/SUIVideoRecorderTests.swift` | Create | Recorder state machine tests |

**TestScope**:
```
Package: packages/MediaKit
Filter: MediaKitTests
Expected new tests: 15
```

**Tests** (15):
1. `iPhone16_hasCorrectDimensions`
2. `iPhoneSE_hasCorrectDimensions`
3. `iPadPro13_hasCorrectDimensions`
4. `recorderConfig_defaultFrameRate_is30`
5. `recorderConfig_frameRateClamps_toValidRange`
6. `recorderError_stopWithoutStart_throws`
7. `recorderError_doubleStart_throws`
8. `recorder_isSendable_compiles`
9. `videoWriter_writesValidMP4`
10. `videoWriter_h264Codec_inOutput`
11. `videoWriter_respectsFrameRate`
12. `videoWriter_diskFull_cleansUp`
13. `frameCapture_offscreen_producesPixelBuffers`
14. `recorder_startStop_controlsDuration`
15. `recorder_maxDuration_stopsAutomatically`

**Success criteria**:
- `SUIVideoRecorder` records a SwiftUI view to .mp4 on simulator
- Approach B (custom, no XCTest dependency)
- Actor-protected state, `Sendable` (Swift 6)
- 15 tests green

**Estimated LOC**: ~500

---

## Sunday (Day 3) — Polish + Ship

### Wave U1a: Personality.md

**Branch**: `feature/personality-persistence` from `epic/shikki-v1`
**Dependencies**: None (parallel)

| File | Action | Purpose |
|------|--------|---------|
| `tools/shiki-ctl/Sources/ShikiCtlKit/Services/PersonalityManager.swift` | Create | Append-only observations, load at session start |
| `memory/personality.md` | Create | Initial personality file (append-only) |
| `tools/shiki-ctl/Sources/ShikiCtlKit/Services/SessionLifecycle.swift` | Modify | Load personality at session start |
| `tools/shiki-ctl/Tests/ShikiCtlKitTests/PersonalityManagerTests.swift` | Create | Personality tests |

**TestScope**:
```
Package: tools/shiki-ctl
Filter: PersonalityManagerTests
Expected new tests: 5
```

**Tests** (5):
1. `personality_appendObservation_addsEntry` — append-only write
2. `personality_appendPreservesExisting` — never overwrites
3. `personality_loadAtSessionStart_populatesContext`
4. `personality_emptyFile_returnsDefaults` — graceful on first run
5. `personality_entriesAreTimestamped` — chronological ordering

**Success criteria**:
- `memory/personality.md` is append-only (never rewritten, only appended)
- Loaded at session start, available to Orchestrator
- Entries are timestamped behavioral observations, not facts
- ShikkiDB event: `personality_observation_recorded`

**Estimated LOC**: ~150

---

### Wave U1b: Animated Splash Screen

**Branch**: `feature/splash-screen` from `epic/shikki-v1`
**Dependencies**: None (parallel)

| File | Action | Purpose |
|------|--------|---------|
| `tools/shiki-ctl/Sources/ShikiCtlKit/Views/SplashScreen.swift` | Create | Terminal art renderer + resume state display |
| `tools/shiki-ctl/Sources/shiki-ctl/ShikiCtl.swift` | Modify | Show splash on startup before command dispatch |
| `tools/shiki-ctl/Tests/ShikiCtlKitTests/SplashScreenTests.swift` | Create | Splash rendering tests |

**TestScope**:
```
Package: tools/shiki-ctl
Filter: SplashScreenTests
Expected new tests: 5
```

**Tests** (5):
1. `splash_rendersWithinTwoSeconds` — BR-09 performance gate
2. `splash_displaysResumeState_whenCheckpointExists` — shows branch, agents, budget
3. `splash_displaysCleanState_whenNoCheckpoint` — fresh start message
4. `splash_isSkippable_viaFlag` — `--no-splash` flag
5. `splash_nonBlocking_commandExecutes` — does not delay command dispatch

**Success criteria**:
- Terminal art renders on `shikki` startup
- Shows resume state (branch, active agents, budget) if checkpoint exists
- < 2 seconds (BR-09), skippable, non-blocking
- `--no-splash` flag for scripts/CI

**Estimated LOC**: ~180

---

### Wave U1c: Epic Branching — ChangelogGate Scoping

**Spec**: `features/shiki-epic-branching.md`
**Branch**: `feature/epic-branching` from `epic/shikki-v1`
**Dependencies**: None (parallel)

| File | Action | Purpose |
|------|--------|---------|
| `packages/ShikiCore/Sources/ShikiCore/Planning/DependencyTree.swift` | Modify | Add `epicBranch: String` and `targetBranch: String` properties |
| `tools/shiki-ctl/Sources/ShikiCtlKit/Services/ShipService.swift` | Modify | ChangelogGate scopes to epic range |
| `tools/shiki-ctl/Sources/shiki-ctl/Commands/ShipCommand.swift` | Modify | `--epic` flag for scoped changelog |
| `packages/ShikiCore/Tests/ShikiCoreTests/Planning/DependencyTreeTests.swift` | Modify | Epic context tests |
| `tools/shiki-ctl/Tests/ShikiCtlKitTests/ShipServiceTests.swift` | Modify | Scoped changelog tests |

**TestScope**:
```
Package: packages/ShikiCore
Filter: DependencyTreeTests
---
Package: tools/shiki-ctl
Filter: ShipServiceTests
Expected new tests: 6
```

**Tests** (6):
1. `dependencyTree_epicBranch_setsContext`
2. `dependencyTree_waveBranches_targetEpic` — baseBranch = epic
3. `changelogGate_scopedToEpic_excludesOtherCommits`
4. `changelogGate_epicToDevelop_aggregatesAllWaves`
5. `shipCommand_epicFlag_producesEpicChangelog`
6. `shipCommand_noEpicFlag_usesDefaultRange`

**Success criteria**:
- `DependencyTree` has epicBranch + targetBranch
- `shiki ship --epic` changelog scoped to epic commits only
- Wave branches always target the epic branch
- Nested epics explicitly forbidden

**Estimated LOC**: ~200

---

### Wave U2: Ship v1.0

**Branch**: `epic/shikki-v1` (final merge prep)
**Dependencies**: ALL previous waves must complete

| Task | Description |
|------|-------------|
| README rewrite | < 100 lines, 3-line hook (BR-10). What Shikki is, for whom, install. |
| /pre-pr on all epic branches | Full test suite across all packages (BR-02) |
| Tag v1.0.0 | Annotated tag on develop after epic merge |
| ShikkiDB event | `release_shipped { version: "1.0.0", testCount, locDelta }` |

**Tests**: 0 new (runs existing full suite)

**Success criteria**:
- All wave PRs merged to `epic/shikki-v1`
- Full test suite green across ALL packages
- `epic/shikki-v1` merged to `develop` via single PR
- Tagged `v1.0.0`
- README rewritten
- ShikkiDB event recorded

**Estimated LOC**: ~80 (README only)

---

## Totals

| Metric | Count |
|--------|-------|
| **Waves** | 13 (F1a, F1b, F2a, F2b, F2c, F3, S1a, S1b, S1c, S2, S3, U1a, U1b, U1c) + U2 ship |
| **New tests** | **~163** |
| **Estimated LOC** | **~4,460** |
| **New files** | ~40 |
| **Modified files** | ~20 |
| **New SPM types** | Dispatch, DispatchResult, DispatchEvent, TestScope, OrchestratorProtocol, OrchestratorLoop, TmuxLauncher, PrePRRunner, PersonalityManager, SplashScreen, SUIVideoRecorder, SUIDevice, VideoWriter, FrameCapture, RecorderConfiguration, RecorderError, VideoArtifact |

### Test Breakdown by Day

| Day | Waves | Tests |
|-----|-------|-------|
| Friday | F1a (23) + F1b (29) + F2a (6) + F2b (5) + F2c (4) + F3 (6) | **73** |
| Saturday | S1a (10) + S1b (8) + S1c (8) + S2 (12) + S3 (15) | **53** |
| Sunday | U1a (5) + U1b (5) + U1c (6) + U2 (0) | **16** + full suite |
| **Total** | | **~163 new tests** |

### LOC Breakdown by Day

| Day | LOC |
|-----|-----|
| Friday | ~2,150 (animations dominate) |
| Saturday | ~1,700 (engine core) |
| Sunday | ~610 (polish + ship) |
| **Total** | **~4,460** |

---

## Risk Assessment

| Risk | Severity | Likelihood | Mitigation |
|------|----------|------------|------------|
| **Maya/WabiSabi project build issues** | High | Medium | Sub-agents validate `swift build` before implementing. Abort early if project won't compile. |
| **S2 Orchestrator DNA scope creep** | High | Medium | Strict scope: protocol + default impl + CompanyManager integration. No runtime agent scheduling. |
| **SUI Video API simulator dependency** | Medium | Medium | Tests use mock FrameCapture protocol. Real recording validated manually, not in CI for v1. |
| **Session resume tmux flakiness** | Medium | Low | TmuxLauncher uses deterministic commands. Tests mock tmux binary. |
| **ShikiDB unavailable** | Low | Low | All event emissions use graceful degradation (log + continue). |
| **Context budget for 3-day sprint** | Medium | Medium | Compaction checkpoint at end of each day. ShikkiDB session events. |
| **F3 depends on F2 completion** | Medium | Low | F2 waves are small (~400 LOC total). If delayed, F3 starts Saturday morning. |

---

## Rollback Plan

If Sunday 23:59 is not green, ship what is green:

### Tier 1 — Must Ship (the moat)
- **Orchestrator DNA compiled** (S2) — this IS the v1.0 differentiator
- **Sub-agent dispatch protocol** (S1a) — the orchestrator needs this
- **Scoped testing** (S1c) — velocity for all future work
- **Session resume launches tmux** (F2a) — the visible UX improvement
- **Auto-save on exit** (F2b) — data safety

### Tier 2 — Should Ship (value-add)
- **Epic branching** (U1c) — workflow improvement
- **PRGate epic/* targets** (F2c) — enables epic workflow
- **/pre-pr --autofix** (F3) — quality of life
- **Real spend tracking** (S1b) — honest metrics

### Tier 3 — Can Defer to v1.1 (nice-to-have)
- **Animations** (F1a, F1b) — project-specific, not engine
- **SUI Video API** (S3) — infrastructure, not user-facing
- **Personality.md** (U1a) — append-only file, easy to add later
- **Animated splash screen** (U1b) — cosmetic
- **README rewrite** (U2 partial) — can ship post-tag

### Minimum Viable v1.0
If only Tier 1 ships, tag as `v1.0.0-rc1` and complete Tier 2 Monday for `v1.0.0`. The compiled orchestrator DNA + dispatch protocol + scoped testing is the engine. Everything else is polish.

---

## Review History

| Date | Phase | Reviewer | Decision | Notes |
|------|-------|----------|----------|-------|
| 2026-03-21 | Master Spec | @Daimyo | DRAFT | 13 waves, 163 tests, 4,460 LOC, 3-day sprint |
