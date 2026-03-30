---
title: "Shikki v0.3.0 — Consolidated Spec Audit & Remaining Work"
status: audit
priority: P0
project: shikki
created: 2026-03-30
authors: "@Sensei audit + @Daimyo review"
---

# Shikki v0.3.0 — What's Done, What's Left, What's Dead

> 69 spec files. 19 implemented this dispatch. Here's the truth.

---

## 1. COMPLETED (can be archived)

These specs are fully implemented. The code exists on feature branches or merged to develop/integration.

| Spec | Branch | Status |
|------|--------|--------|
| p0-immediate-plan.md | merged to develop | curl cleanup + e2e skip flag |
| wave1-session-foundation.md | epic/shikki-v1 | SessionLifecycle, Registry, Journal, 32 tests |
| shiki-core.md | feature/shiki-core | 6 waves, 124 tests |
| shiki-knowledge-mcp.md | feature/shiki-knowledge-mcp | 15 MCP tools, 116 tests |
| shikki-blue-flame.md | feature/blue-flame | 5 emotions, animation engine, 78 tests |
| shikki-auto-diagnostic.md | feature/auto-diagnostic | ContextRecovery, DiagnosticCommand, 98 tests |
| shikki-memory-migration.md | feature/memory-migration + ph3-4 | Ph1-4 complete, 77+ tests |
| spec-brainytube-video-engine.md | feature/brainytube-v2 | Grid, nav, codecs, proxy, 43 tests |
| shikki-codegen-engine.md | feature/codegen-engine | 6-wave pipeline, 153 tests |
| shikki-ship-testflight.md | feature/ship-testflight | 12 gates, 79 tests |
| shikki-killer-features.md | feature/killer-features | Dashboard, init wizard, marketplace, 91 tests |
| shiki-observatory.md | on integration branch | 3 layers, 68 tests |
| spec-brainy-product-vision.md | feature/brainy-vision-v2 (local) | Models, vault, protocols, 64 tests |
| shiki-spec-syntax-s3.md | feature/s3-spec-syntax | Parser, validator, CLI, 72 tests |
| shiki-augmented-tui.md | feature/augmented-tui-v2 | Chat, editor, palette, 89 tests |
| shiki-enterprise-safety.md | feature/enterprise-safety | Budget ACL, audit, anomaly, 55 tests |
| shikki-answer-engine.md | feature/answer-engine | BM25, chunker, Q&A, 72 tests |
| shiki-community-flywheel.md | feature/community-flywheel-v2 | Risk scoring, calibration, 80 tests |
| moto-dns-for-code.md | feature/moto-dns-v2 | .moto dotfile, cache builder, MCP |
| maya-ground-quality (no spec file) | feature/maya-ground-quality | Surface detection, 62 tests |

**Total: 20 specs implemented, 1,421+ tests**

---

## 2. SUPERSEDED (can be deleted or archived)

These specs have been replaced by newer, more comprehensive specs.

| Old Spec | Replaced By | Reason |
|----------|------------|--------|
| shiki-v3-orchestrator-plan.md | shiki-core.md + shikki-distributed-orchestration.md | v3 plan absorbed into ShikiCore (6 waves) + distributed arch |
| shiki-orchestrator-v3.md | same as above | Detailed v3 design → now ShikiCore + NATS |
| shikki-dispatch-resilience.md | shikki-distributed-orchestration.md | Band-aid spec subsumed by full distributed architecture |
| shiki-autopilot-v2.md | shiki-core.md (Wave 4: DependencyTree, TestPlan, ConfidenceGate) | TPDD absorbed into ShikiCore Wave 4 |
| shiki-event-bus-architecture.md | Already implemented in ShikkiKit/Events/ | EventBus, EventRouter, ShikkiEvent all in code |
| shikki-orchestrator-dna.md | shikki-distributed-orchestration.md + shiki-core.md | Orchestrator identity now defined by kernel + NATS architecture |
| shikki-unified-command.md | shikki-commands-architecture.md | Merged into single architecture spec |
| p1-group-a-plan.md | Items tracked individually | Plan doc, items moved to backlog |
| p1-group-b-plan.md | Items tracked individually | Plan doc, items moved to backlog |
| p1-group-c-plan.md | Items implemented | Session registry + template done |
| p05-process-specs-plan.md | Items implemented/tracked | Epic branching + scoped testing done/in progress |

**Action: Archive these 11 specs to `features/archive/`**

---

## 3. STILL RELEVANT — NOT YET IMPLEMENTED

### P0 (blocks next release)

| Spec | What's Missing | Depends On |
|------|---------------|------------|
| spec-report-logger-nats.md | NATS foundation (NATSClient, NATSEventBridge, nats-server lifecycle) | Nothing — can start now |
| shikki-distributed-orchestration.md | Full distributed arch (5 waves) | NATS foundation |
| shikki-zero-downtime-upgrade.md | Blue/green node handoff | NATS foundation |
| shikki-native-scheduler.md | ShikkiKernel decomposition (8 services) | ShikiCore (done) |
| shikidb-distributed-nodes.md | Event-sourced sync between DB nodes | NATS + VPS setup |

### P1 (next features)

| Spec | What's Missing | Depends On |
|------|---------------|------------|
| shiki-mesh-protocol.md | Multi-node dispatch, capability manifests | NATS + distributed orch |
| shiki-event-router.md | Intelligent event middleware (classify → enrich → route → interpret) | Event bus (done) |
| shiki-pr-v2-ai-review.md | Risk triage + qmd search + AI fix agent | CodeGen engine (done) |
| shiki-push-stdin-prompt.md | Universal input protocol | NATS |
| shikki-flow-v1.md | Full 12-component pipeline TUI | Many dependencies |
| shikki-commands-architecture.md | Remaining skill → Swift migrations | Ongoing |
| shiki-scoped-testing.md | CI matrix integration, tiered test execution | GitHub Actions |
| shiki-epic-branching.md | ChangelogGate scoping, ShipCommand --epic | Ship (done) |
| shikki-pr-review-progression.md | File-level progress tracking in review | List reviewer (done) |
| shikki-license-protection.md | LicenseDetector, AttributionRegistry, provenance | Blocks public release |
| shikki-agent-persona-management.md | CRUD for agent personas | Agent system |

### P2+ (future)

| Spec | What's Missing | When |
|------|---------------|------|
| shiki-os-vision.md | Full OS vision — hardware + software | Post-revenue |
| shiki-product-separation.md | ShikiQA (visual review), ShikiWS (enterprise) | Post-v1 |
| shikki-creative-studio.md | Agent/persona designer | Post-v1 |
| project-distribution-plan.md | Research → action plan for 13 projects | When bandwidth allows |
| shiki-research-adoption-plan.md | gstack patterns, @Kenshi/@Metsuke | Post-v1 |

### Shikkimoji (emoji system — implementation exists on old branches)

| Spec | Status | Note |
|------|--------|------|
| shikki-emoji-protocol.md | Code exists on `story/shikkimoji-router` through `story/shikkimoji-wave5` | 5 wave branches merged to integration. EmojiRegistry, EmojiRouter, ChainParser, 30+ tests. **Spec says NOT IMPLEMENTED but code IS there.** |
| shikki-emoji-chaining.md | Same — ChainParser + ChainExecutor on `story/shikkimoji-chaining` | Already implemented. |

**Correction: Shikkimoji IS implemented (5 waves, merged to integration). Spec audit missed it because branches use `story/` prefix not `feature/`.**

---

## 4. REMAINING PLAN DOCS

| File | Status | Action |
|------|--------|--------|
| p0-immediate-plan.md | DONE | Archive |
| p2-challenge-review.md | PR verdicts assigned, some shipped | Keep for reference |
| shikki-v1-master-spec.md | Living doc | Keep updated |
| shikki-flow-v1.md | Active roadmap | Keep |

---

## 5. GAP ANALYSIS — Vision vs Reality

### What Shikki IS today (v0.3.0-pre)

```
A Swift CLI that:
✅ Manages companies with heartbeat monitoring
✅ Dispatches agents to worktrees (via Claude Code subagents)
✅ Tracks sessions, events, decisions
✅ Ships with 12 quality gates + TestFlight
✅ Generates code from specs (CodeGen Engine)
✅ Scores PR risk, detects anomalies
✅ Has an Observatory TUI for oversight
✅ Answers codebase questions (Answer Engine)
✅ Parses natural language specs (S3 Syntax)
✅ Has a Blue Flame mascot with emotions
✅ Has 1,421+ tests across 19 feature branches
```

### What Shikki SHOULD BE (vision)

```
A distributed AI orchestrator that:
⬚ Coordinates via NATS message bus (not Claude Code context)
⬚ Runs on multiple machines (mesh protocol)
⬚ Upgrades with zero downtime (blue/green handoff)
⬚ Auto-recovers from crashes (watchdog + DB snapshots)
⬚ Has a chat node separate from the brain
⬚ Manages context budgets per consumer
⬚ Syncs knowledge between DB nodes (event-sourced)
⬚ Runs overnight batch jobs on remote machines
⬚ Has a native iOS/macOS companion app
⬚ Is the OS for professional AI work
```

### The Bridge: What to Build Next

```
PRIORITY ORDER (critical path):

1. NATS Foundation (spec-report-logger-nats.md)
   └── Enables: distributed orch, mesh, zero-downtime, push protocol

2. ShikkiKernel Decomposition (shikki-native-scheduler.md)
   └── Enables: proper service lifecycle, timer coalescing

3. Distributed Orchestration (shikki-distributed-orchestration.md)
   └── Enables: context-safe dispatch, chat/brain separation

4. Zero-Downtime Upgrade (shikki-zero-downtime-upgrade.md)
   └── Enables: live upgrades, crash recovery

5. Merge all 18 feature branches → develop → release/v0.3.0
   └── Enables: actual shipping of everything built today
```

---

## 6. CLEANUP ACTIONS

### Archive (move to features/archive/)
11 superseded specs listed in Section 2.

### Update MEMORY.md backlog
- Remove items now implemented (ShikiCore, Knowledge MCP, Observatory, etc.)
- Add NATS foundation as new P0
- Add zero-downtime upgrade as new P0

### Branch hygiene
- 80+ stale worktree branches to prune
- 18 feature branches ready for PR review
- Brainy vision needs remote push

### Spec corrections
- Shikkimoji: mark as IMPLEMENTED (5 waves on story/* branches)
- p1-group-c-plan: mark as COMPLETED

---

## 7. @shi Mini-Challenge

1. **@Ronin**: 18 feature branches, zero merge conflicts checked. What's the blast radius of merging all of them to integration? Should we merge sequentially or use an octopus merge?
2. **@Katana**: The 80+ stale worktree branches — any of them contain uncommitted work we haven't rescued? Should we scan before pruning?
3. **@Sensei**: NATS is the critical path for everything. Should we skip the other P0s and go all-in on NATS + distributed orch?
