# Feature: ShikiCore — The Production Engine

> Created: 2026-03-19 | Status: Spec (validated by @Daimyo + @shi team) | Owner: @Daimyo
> Priority: **P0** — foundation everything else builds on
> Package: `packages/ShikiCore/` (new top-level SPM package)
> Depends on: CoreKit, ShikiKit (ShikiEvent protocol)

---

## Context

Shiki's feature production lifecycle — spec, decide, build, ship — exists today as prompt skills (markdown files Claude reads and follows). This is fragile: Claude may skip steps, hallucinate states, lose context after compaction. The lifecycle is too important to be interpreted — it must be compiled, tested, deterministic, and recoverable.

ShikiCore is the **production engine** of Shiki. It replaces prompt-based orchestration with compiled Swift code. Skills remain as the UI layer (slash commands). ShikiCore is the engine behind them.

### Architecture Decision (2026-03-19, @shi team unanimous)

- **Swift-only.** No TypeScript sidecar. No Agent SDK dependency.
- **AI-provider-agnostic.** AgentProvider protocol → Claude, OpenRouter, MLX.
- **Event-driven.** Every step emits ShikiEvent → DB. Crash recovery from checkpoints.
- **Governor principle.** Reactor prepares everything, stops at approval gates. @Daimyo walks through, or the gate doesn't open.

---

## Architecture

```
packages/ShikiCore/
  Sources/ShikiCore/
    ├── Lifecycle/
    │   ├── FeatureLifecycle.swift       ← FSM: idle→spec→approved→building→gating→shipping→done
    │   ├── LifecycleState.swift         ← typed states + transitions
    │   ├── LifecycleEvent.swift         ← ShikiEvent subtypes for lifecycle
    │   └── LifecycleCheckpoint.swift    ← persistence for crash recovery
    │
    ├── Orchestration/
    │   ├── CompanyManager.swift         ← runs N lifecycles across projects
    │   ├── DecisionQueue.swift          ← blocks → waits → resumes
    │   ├── BudgetEnforcer.swift         ← per-company daily caps
    │   └── CrashRecovery.swift          ← checkpoint → resume
    │
    ├── Agent/
    │   ├── AgentProvider.swift          ← protocol: dispatch(prompt:) → Result
    │   ├── ClaudeProvider.swift         ← claude -p --output-format json
    │   ├── OpenRouterProvider.swift     ← NetKit → OpenRouter API
    │   ├── LocalProvider.swift          ← MLX on-device (future)
    │   └── ShikiAgentClient.swift       ← actor: dispatch, resume, cancel, session mgmt
    │
    ├── Pipeline/
    │   ├── PipelineGate.swift           ← protocol (same pattern as ShipGate)
    │   ├── SpecGate.swift               ← /spec pipeline as gates
    │   ├── BuildGate.swift              ← SDD dispatch as gate
    │   ├── QualityGate.swift            ← pre-pr checks as gate
    │   ├── ShipGate.swift               ← shiki ship as gate
    │   └── PipelineRunner.swift         ← sequential gate executor
    │
    ├── Planning/
    │   ├── DependencyTree.swift         ← waves with parent links (from autopilot v2)
    │   ├── WaveNode.swift               ← name, branch, base, files, test count, status
    │   ├── TestPlan.swift               ← TPDD: scenarios, concerns, coverage target
    │   └── ConfidenceGate.swift         ← file conflict analysis → parallel vs sequential
    │
    └── Events/
        ├── CoreEvent.swift              ← all ShikiCore event types
        └── EventPersister.swift         ← ShikiDB checkpoint writer
```

### Peer Relationship

```
ShikiCore
  ├── FeatureLifecycle    ← the pipeline (/spec → /decide → /build → /ship)
  ├── CompanyManager      ← runs N pipelines across projects
  └── (peers, not parent-child)
```

The orchestrator doesn't *contain* the pipeline. It coordinates multiple instances of it. A single-project user runs one FeatureLifecycle. The CompanyManager runs N of them.

### SPM Dependency Graph

```
CoreKit (foundation)
  ↑
ShikiKit (ShikiEvent protocol, shared DTOs)
  ↑
ShikiCore (lifecycle, orchestration, agent dispatch)
  ↑
ShikiCtlKit (CLI services: ShipService, StatusRenderer, etc.)
  ↑
shiki-ctl (CLI commands: ShipCommand, etc.)
```

---

## FeatureLifecycle FSM

```
          ┌──────────────────────────────────────────────┐
          │                                              │
   idle ──→ spec_drafting ──→ spec_pending_approval       │
              (agent)           (governor: wait)          │
                                    │                    │
                              @Daimyo approves           │
                                    │                    │
                                    ▼                    │
                              decisions_needed            │
                              (queue T1/T2 questions)     │
                                    │                    │
                              @Daimyo answers             │
                                    │                    │
                                    ▼                    │
                              building                    │
                              (SDD in worktree)           │
                                    │                    │
                              tests pass                  │
                                    │                    │
                                    ▼                    │
                              gating                      │
                              (quality + review)          │
                                    │                    │
                              gates pass                  │
                                    │                    │
                                    ▼                    │
                              shipping                    │
                              (ShipService pipeline)      │
                                    │                    │
                              PR created                  │
                                    │                    │
                                    ▼                    │
                              done ───────────────────────┘
                                    │
                              (or failed/blocked at any step)
```

### Governor Gates (require @Daimyo)

| Gate | When | What happens |
|------|------|-------------|
| Spec approval | After spec draft | Reactor stops. @Daimyo reviews plan, approves or adjusts. |
| Decision answers | T1/T2 questions | Reactor stops. Questions queued. Resumes when answered. |
| Ship approval | Before PR creation | Preflight Glow manifest. @Daimyo presses Enter. |

### Autonomous Stages (no human needed)

| Stage | What happens |
|-------|-------------|
| Spec drafting | Agent writes scope, BRs, test plan, architecture, execution plan |
| Building | SDD protocol in worktree — TDD per task, auto-commit |
| Quality gating | Pre-pr gates, @Metsuke audit, auto-fix trivials |
| Changelog/version | ChangelogGenerator + VersionBumper (deterministic) |

---

## Implementation Waves

### Wave 1: Foundation (~400 LOC, ~20 tests)

**What**: The package skeleton + core types + AgentProvider protocol.

| File | Purpose | Tests |
|------|---------|-------|
| Package.swift | SPM manifest, depends on CoreKit + ShikiKit | — |
| LifecycleState.swift | FSM states enum + valid transitions | 6 |
| LifecycleEvent.swift | ShikiEvent subtypes for lifecycle | 2 |
| LifecycleCheckpoint.swift | Codable checkpoint for crash recovery | 3 |
| AgentProvider.swift | Protocol: dispatch(prompt:) async → AgentResult | 2 |
| ClaudeProvider.swift | claude -p --output-format json wrapper | 4 |
| CoreEvent.swift | All event type definitions | 1 |
| EventPersister.swift | POST events to ShikiDB (graceful degradation) | 2 |

**Deliverable**: `swift build --package-path packages/ShikiCore` compiles. Types usable from shiki-ctl.

### Wave 2: Pipeline Gates (~300 LOC, ~15 tests)

**What**: The gate protocol + concrete gates. Absorbs ShipGate from shiki ship spec.

| File | Purpose | Tests |
|------|---------|-------|
| PipelineGate.swift | Protocol: evaluate(context:) → GateResult | 2 |
| SpecGate.swift | Validates spec completeness (BRs, test plan, architecture) | 3 |
| BuildGate.swift | Dispatches SDD, verifies tests pass | 3 |
| QualityGate.swift | Pre-pr checks, @Metsuke audit | 3 |
| ShipGate.swift | Merged from shiki-ship spec (8 sub-gates) | 2 |
| PipelineRunner.swift | Sequential gate executor with events | 2 |

**Deliverable**: `PipelineRunner` can execute a gate sequence. shiki ship becomes `PipelineRunner` with ship-specific gates.

### Wave 3: FeatureLifecycle (~300 LOC, ~15 tests)

**What**: The FSM that drives one feature through the full pipeline.

| File | Purpose | Tests |
|------|---------|-------|
| FeatureLifecycle.swift | FSM: state machine with event-driven transitions | 8 |
| DecisionQueue.swift | Queue T1/T2 questions to DB, poll for answers | 4 |
| ShikiAgentClient.swift | Actor: dispatch/resume/cancel Claude sessions | 3 |

**Deliverable**: Single feature can go from idle → done autonomously (with governor stops).

### Wave 4: Planning + TPDD (~300 LOC, ~12 tests)

**What**: Dependency tree + test plan driven development. Absorbs autopilot v2 spec.

| File | Purpose | Tests |
|------|---------|-------|
| DependencyTree.swift | Waves with parent links, serializable | 5 |
| WaveNode.swift | Branch, base, files, test count, status | 2 |
| TestPlan.swift | Scenarios, concerns, coverage targets | 3 |
| ConfidenceGate.swift | File conflict analysis → parallel vs sequential | 2 |

**Deliverable**: Multi-wave plans with TPDD. Feeds into FeatureLifecycle's building stage.

### Wave 5: CompanyManager + Orchestration (~200 LOC, ~10 tests)

**What**: Multi-project coordination. Runs N lifecycles.

| File | Purpose | Tests |
|------|---------|-------|
| CompanyManager.swift | Runs N lifecycles, routes decisions, heartbeat | 5 |
| BudgetEnforcer.swift | Per-company daily caps, pause on exceed | 3 |
| CrashRecovery.swift | Checkpoint → detect stale → resume | 2 |

**Deliverable**: Full orchestrator. Multiple projects, budget enforcement, crash recovery.

### Wave 6: OpenRouter + Provider Expansion (~150 LOC, ~6 tests)

**What**: Multi-provider routing. AI-agnostic dispatch.

| File | Purpose | Tests |
|------|---------|-------|
| OpenRouterProvider.swift | NetKit → OpenRouter API, model fallbacks | 4 |
| LocalProvider.swift | MLX stub (future) | 2 |

**Deliverable**: AgentProvider routes to Claude, OpenRouter, or local. Cost optimization for non-critical agents.

---

## Totals

| Metric | Count |
|--------|-------|
| Waves | 6 |
| New files | ~25 |
| LOC (estimated) | ~1,650 |
| Tests (estimated) | ~78 |
| New SPM package | `packages/ShikiCore/` |

---

## What This Subsumes

| Previous Item | Where It Goes |
|--------------|---------------|
| `shiki ship` (P0 spec) | Wave 2 (ShipGate) + Wave 3 (lifecycle shipping stage). ShipCommand in shiki-ctl calls ShikiCore's PipelineRunner. |
| Autopilot v2 / TPDD (P1 spec) | Wave 4 (DependencyTree, TestPlan, ConfidenceGate). Planning layer of FeatureLifecycle. |
| Orchestrator v3 (P0 spec) | Wave 5 (CompanyManager, BudgetEnforcer, CrashRecovery). Multi-project coordination. |
| Autopilot prompt skill | **Superseded.** FeatureLifecycle replaces the 500-line markdown. Skills stay as UI triggers. |
| AgentProvider protocol | Wave 1 (foundation) + Wave 6 (OpenRouter, MLX). |
| Event Router (P0.5 spec) | CoreEvent + EventPersister in Wave 1. Route/classify/enrich logic in Wave 3. |

---

## Dependencies

| Dependency | Status | Blocks |
|-----------|--------|--------|
| CoreKit | Exists | — |
| ShikiKit (ShikiEvent) | Exists | — |
| NetKit | Exists (curl shell-out, migrating) | Wave 6 (OpenRouter) |
| ShikiDB | Running | All waves (event persistence, checkpoints) |
| ShikiQA extraction | In progress (other agent) | Wave 2 (no PRRiskEngine conflict) |
| shiki-ctl clean | In progress (other agent) | Wave 2+ (need stable base to integrate) |

---

## Non-Goals (v1)

- GUI / desktop app (ShikiCore is headless, CLI consumes it)
- iOS app integration (future — iOS app consumes events via API, not ShikiCore directly)
- Plugin system for third-party gates (not until v2)
- Process pool for concurrent Claude dispatches (optimize when 12-task pipeline is real)

---

## Review History

| Date | Phase | Reviewer | Decision | Notes |
|------|-------|----------|----------|-------|
| 2026-03-19 | Architecture | @shi team (unanimous) | Swift-only, no TS sidecar | AgentProvider protocol, governor principle |
| 2026-03-19 | Elevation | @Daimyo | FeatureLifecycle = peer of CompanyManager | Not a feature of orchestrator, IS the orchestrator |
| 2026-03-19 | Spec | @Sensei | 6 waves, ~1,650 LOC, ~78 tests | Subsumes ship, autopilot v2, orchestrator v3 |
