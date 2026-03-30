# Shikki v0.3.0 — Mega Merge Review

> 23 branches | 66 commits | ~90,000 LOC touched | 254 test files
> Generated: 2026-03-30
> Reviewer: @Sensei + @Ronin + @Metsuke

---

## Executive Summary

This is the largest integration in Shikki history — 23 feature branches spanning CodeGen engine, NATS messaging, BrainTube video player, Maya ground quality AI, enterprise safety, and kernel decomposition. The integration branch already carries Observatory (3 layers), Shikkimoji, DLNA/NetKit, and 13 previously-merged features. Risk is **MEDIUM-HIGH** due to 11 branches modifying `ShikkiCommand.swift`, 9 branches modifying `ShikkiKernel.swift`, and 6 branches modifying `Package.swift`. However, most new code is additive (new files/modules) rather than mutating shared logic, which makes conflict resolution mechanical.

**Recommendation: SHIP WITH CONDITIONS** — merge in strict dependency order, resolve ShikkiCommand.swift and ShikkiKernel.swift conflicts incrementally, run full test suite after each wave.

---

## Merge Strategy

### Approach: Sequential rebase-merge, wave by wave

Octopus merge is NOT viable — too many branches touch the same files. Each branch must be merged sequentially with conflict resolution verified before the next.

### Dependency chains detected

1. `feature/memory-migration-ph3-4` is ancestor of `feature/moto-dns-v2` (shared commit `a687ec11`)
2. `feature/nats-event-logger` is ancestor of `feature/nats-report-aggregator-w4` (shared commit `70cc7289`)
3. 4 branches carry shared radar commits (`e105ace8`, `e31a955c`, `fd882f4a`) — will auto-resolve on first merge

### Conflict hotspots (files touched by N branches)

| File | Branches | Severity |
|------|----------|----------|
| `ShikkiCommand.swift` | 11 | CRITICAL — each branch adds subcommands |
| `ShikkiKernel.swift` | 9 | HIGH — service registration |
| `ShikkiKernelTests.swift` | 10 | HIGH — test additions |
| `TaskSchedulerService.swift` | 8 | MEDIUM — shared but stable |
| `TaskSchedulerTests.swift` | 8 | MEDIUM — additive |
| `Package.swift` | 6 | HIGH — target/dependency declarations |
| `LogCommand.swift` | 8 | MEDIUM — log subcommand extensions |
| `ManagedService.swift` | 8 | MEDIUM — protocol likely unchanged |

### Noise commits

4 branches (`augmented-tui-v2`, `answer-engine`, `nats-foundation`, `nats-node-discovery-v2`) carry 3 radar scan commits each. These will conflict on first merge but auto-resolve for subsequent branches. **Merge one of these first in each wave to absorb the radar commits.**

---

## Wave 0 — Foundation (6 branches)

### feature/shiki-core
- **Commits**: 3 | **New files**: 20 | **LOC**: +2,954 (new) / total diff: +4,092/-45,100
- **What it does**: Waves 2-3-6 of ShikiCore engine — ShipGate pipeline, DecisionQueue + ShikiAgentClient, OpenRouterProvider + LocalProvider
- **Risk**: MEDIUM — touches Package.swift, ShikkiCommand.swift, ShikkiKernel.swift, EventBus
- **Conflicts**: ShikkiCommand.swift, ShikkiKernel.swift, Package.swift, TaskSchedulerService.swift, EventBus.swift
- **Note**: Large deletion count is from rebasing/restructuring, not actual code removal. Real feature size is ~3K LOC.
- **Verdict**: SHIP — merge first as foundation for everything else

### feature/shiki-knowledge-mcp
- **Commits**: 3 | **New files**: 14 | **LOC**: +2,421 (new) / total diff: +4,539/-45,125
- **What it does**: ShikkiMCP rename, retry logic, batch saves, analytics tools (daily_summary, decision_chain, agent_effectiveness), 116 tests
- **Risk**: MEDIUM — touches Package.swift, ShikkiKernel.swift, EventBus
- **Conflicts**: ShikkiCommand.swift (no), ShikkiKernel.swift (yes), Package.swift (yes)
- **Note**: 116 tests is excellent coverage for an MCP server
- **Verdict**: SHIP — merge after shiki-core

### feature/memory-migration
- **Commits**: 2 | **New files**: 16 | **LOC**: +3,212 (new) / total diff: +4,305/-45,104
- **What it does**: Phase 1-2 of memory migration — classification engine + migration script + backend metadata
- **Risk**: LOW — mostly new files, minimal overlap with other features
- **Conflicts**: Package.swift, ShikkiKernel.swift, TaskSchedulerService.swift
- **Verdict**: SHIP

### feature/memory-migration-ph3-4
- **Commits**: 1 | **New files**: 8 | **LOC**: +1,781
- **What it does**: Phase 3-4 — verification + cleanup services for memory migration
- **Risk**: LOW — purely additive, no shared file modifications beyond base
- **Conflicts**: None beyond base
- **Note**: Is ancestor of `feature/moto-dns-v2` — merge this first
- **Verdict**: SHIP — merge immediately after memory-migration

### feature/auto-diagnostic
- **Commits**: 4 | **New files**: 12 | **LOC**: +2,634/-2,418
- **What it does**: 4-wave diagnostic system — recovery models, ContextRecoveryService, DiagnosticFormatter, DiagnosticCommand CLI
- **Risk**: LOW — well-structured 4-wave delivery, self-contained
- **Conflicts**: ShikkiCommand.swift (adds DiagnosticCommand)
- **Verdict**: SHIP

### feature/s3-spec-syntax
- **Commits**: 1 | **New files**: 6 | **LOC**: +1,640/-1
- **What it does**: S3 spec syntax — validator, statistics, spec-check CLI + edge case tests
- **Risk**: LOW — smallest branch, very clean, no shared file conflicts
- **Conflicts**: None — no ShikkiCommand.swift, no Package.swift, no Kernel
- **Verdict**: SHIP

---

## Wave 1 — Core Features (6 branches)

### feature/codegen-engine
- **Commits**: 7 | **New files**: 173 | **LOC**: +22,786 (new) / total diff: +23,508/-25,597
- **What it does**: Full 6-wave CodeGen engine — ArchitectureCache MCP, SpecParser + ContractVerifier, Parallel Dispatch, Merge Engine, Self-Healing Fix Loop, Pipeline orchestrator + FeatureLifecycle integration
- **Risk**: HIGH — largest branch by file count, 173 new files, 68 test files. Touches ShikkiCommand.swift and EventBus.
- **Conflicts**: ShikkiCommand.swift, EventBus.swift
- **Note**: This is effectively a sub-project. 68 test files is strong. Biggest single LOC contribution.
- **Verdict**: SHIP — merge early in Wave 1 to establish CodeGen module paths

### feature/killer-features
- **Commits**: 4 | **New files**: 186 | **LOC**: +26,549 (new) / total diff: +27,525/-25,595
- **What it does**: Template marketplace, project init wizard (`shikki init`), reactive tmux dashboard with EventBus subscription
- **Risk**: HIGH — largest branch by new LOC, 186 new files, 73 test files. Touches ShikkiCommand.swift, ShikkiKernel.swift, TaskSchedulerService.swift, EventBus.
- **Conflicts**: ShikkiCommand.swift (adds init, templates, dashboard), ShikkiKernel.swift, TaskSchedulerService.swift
- **Note**: 73 test files. Good coverage but enormous surface area. Template marketplace is a big commitment.
- **Verdict**: SHIP — the tmux dashboard + init wizard are high-value features

### feature/ship-testflight
- **Commits**: 2 | **New files**: 34 | **LOC**: +5,507 (new) / total diff: +7,223/-45,497
- **What it does**: Ship + TestFlight pipeline — 8-gate pipeline with 54 tests, 4 TestFlight gates (AppRegistry, BuildNumber, Archive, Upload) with 25 tests
- **Risk**: MEDIUM — 79 total tests, touches ShikkiCommand.swift, ShikkiKernel.swift, EventBus, Package.swift
- **Conflicts**: ShikkiCommand.swift, ShikkiKernel.swift, Package.swift, EventBus
- **Verdict**: SHIP

### feature/blue-flame
- **Commits**: 3 | **New files**: 7 | **LOC**: +1,670/-6,818
- **What it does**: Blue Flame personality engine — emotion model + resolver (28 tests), ASCII art + ANSI gradients (30 tests), animation engine with EventBus integration (20 tests)
- **Risk**: LOW — small footprint, 78 tests across 3 waves, well-isolated
- **Conflicts**: ShikkiCommand.swift, ShikkiKernel.swift, TaskSchedulerService.swift
- **Note**: Net deletion due to restructuring. Actual new code is ~1.7K LOC. 78 tests for a personality engine is excellent.
- **Verdict**: SHIP

### feature/enterprise-safety
- **Commits**: 1 | **New files**: 8 | **LOC**: +2,261
- **What it does**: Budget ACL + Audit Trail + Anomaly Detection — all three enterprise safety pillars in one commit
- **Risk**: LOW — purely additive, only 1 test file (flag for review)
- **Conflicts**: ShikkiCommand.swift
- **Note**: Only 1 test file for 2,261 LOC is below the project's usual test density. Verify test count.
- **Verdict**: SHIP WITH FIX — needs more test coverage before v0.3.0 release

### feature/answer-engine
- **Commits**: 1 (+ 3 radar noise) | **New files**: 22 | **LOC**: +2,761 (new) / total diff: +3,391/-66,698
- **What it does**: Wave 1 of Answer Engine — BM25 core with codebase-aware Q&A
- **Risk**: LOW-MEDIUM — carries 3 radar commits that will conflict with other branches
- **Conflicts**: ShikkiCommand.swift, plus radar file conflicts
- **Note**: Large deletion count is from radar divergence, not real deletions. Merge after any other radar-carrying branch to auto-resolve.
- **Verdict**: SHIP

---

## Wave 2 — Advanced Features (4 branches)

### feature/brainytube-v2
- **Commits**: 5 | **New files**: 33 | **LOC**: +4,376 (new) / total diff: +5,452/-45,100
- **What it does**: BrainTube video player overhaul — thumbnail architecture (replacing 9-AVPlayer grid), codec-aware quality selector, KeyRouter FSM, region-locked content handling, seek bar thumbnails
- **Risk**: MEDIUM — 33 new files, touches Package.swift, ShikkiKernel.swift, TaskSchedulerService.swift
- **Conflicts**: Package.swift, ShikkiCommand.swift, ShikkiKernel.swift
- **Note**: The AVPlayer grid replacement is architecturally significant. 9 test files.
- **Verdict**: SHIP

### feature/maya-ground-quality
- **Commits**: 5 | **New files**: 42 | **LOC**: +4,197 (new) / total diff: +5,273/-45,100
- **What it does**: Maya Ground Quality AI — sensor pipeline (vibration, surface classification), scoring engine, UI components (map overlay, real-time indicator, post-ride report), 62 tests across 12 suites
- **Risk**: MEDIUM — touches Package.swift, ShikkiKernel.swift. 62 tests is solid.
- **Conflicts**: Package.swift, ShikkiKernel.swift
- **Note**: Maya-specific feature but integrated through ShikkiKit. 13 test files, 62 tests.
- **Verdict**: SHIP

### feature/moto-dns-v2
- **Commits**: 2 (includes memory-migration-ph3-4 commit) | **New files**: 16 | **LOC**: +4,216
- **What it does**: Moto DNS for Code — .moto dotfile spec, cache builder, MCP interface
- **Risk**: LOW — purely additive, builds on memory-migration-ph3-4
- **Conflicts**: ShikkiCommand.swift
- **Note**: Must merge AFTER feature/memory-migration-ph3-4 (is descendant)
- **Verdict**: SHIP

### feature/community-flywheel-v2
- **Commits**: 1 | **New files**: 13 | **LOC**: +2,855
- **What it does**: Community Data Flywheel — risk scoring, outcome collection, benchmarks
- **Risk**: LOW — purely additive, 6 test files, self-contained
- **Conflicts**: None beyond base
- **Verdict**: SHIP

---

## Wave 3 — Ecosystem (2 branches)

### feature/augmented-tui-v2
- **Commits**: 1 (+ 3 radar noise) | **New files**: 24 | **LOC**: +2,687 (new) / total diff: +3,315/-103,058
- **What it does**: Augmented TUI — Command Palette Chat, Editor Mode, Intent Grammar
- **Risk**: LOW-MEDIUM — carries radar commits, large deletion count from divergence
- **Conflicts**: Radar files only (no ShikkiCommand.swift, no Package.swift)
- **Note**: The -103K deletion is radar divergence noise, not real. Actual feature is 2.7K LOC + 7 test files.
- **Verdict**: SHIP

### feature/kernel-decomposition-v2
- **Commits**: 1 | **New files**: 4 | **LOC**: +815/-10
- **What it does**: Kernel service decomposition — wake signals, escalation engine, new services extracted from monolithic kernel
- **Risk**: LOW — smallest LOC, but touches ShikkiKernel.swift which is the #2 hotspot
- **Conflicts**: ShikkiKernel.swift
- **Note**: Should merge LAST among branches touching ShikkiKernel.swift, since it's a decomposition/refactor
- **Verdict**: SHIP — merge last to avoid re-decomposition conflicts

---

## NATS Foundation (5 branches)

### feature/nats-foundation
- **Commits**: 1 (+ 3 radar noise + 1 import chore) | **New files**: 17 | **LOC**: +1,892 (new)
- **What it does**: NATS messaging foundation — base client, connection management, subject hierarchy
- **Risk**: LOW — foundation layer, no ShikkiCommand.swift or Kernel modifications
- **Conflicts**: Radar files only
- **Note**: Carries "import shikki project" chore commit. Merge first in NATS wave.
- **Verdict**: SHIP

### feature/nats-server-lifecycle
- **Commits**: 1 | **New files**: 6 | **LOC**: +1,464/-1
- **What it does**: Wave 2 — nats-server lifecycle management, config generation, health checks
- **Risk**: LOW — purely additive, depends on nats-foundation
- **Conflicts**: None
- **Verdict**: SHIP — merge after nats-foundation

### feature/nats-event-logger
- **Commits**: 1 | **New files**: 10 | **LOC**: +1,631/-15
- **What it does**: Wave 3 — EventLoggerNATS, NATSEventRenderer, enhanced LogCommand
- **Risk**: LOW — builds on NATS foundation, modifies LogCommand.swift
- **Conflicts**: LogCommand.swift (shared with 8 other branches)
- **Note**: Is ancestor of nats-report-aggregator-w4
- **Verdict**: SHIP — merge after nats-server-lifecycle

### feature/nats-report-aggregator-w4
- **Commits**: 2 (includes event-logger commit) | **New files**: 14 | **LOC**: +2,988/-16
- **What it does**: Wave 4 — ReportAggregator, MetricsCollector, enhanced `shikki report`
- **Risk**: LOW — builds on event-logger (which is its ancestor)
- **Conflicts**: Inherits event-logger conflicts
- **Note**: Must merge AFTER nats-event-logger (is descendant)
- **Verdict**: SHIP — merge after nats-event-logger

### feature/nats-node-discovery-v2
- **Commits**: 1 (+ 3 radar noise + 1 import chore) | **New files**: 24 | **LOC**: +3,269 (new)
- **What it does**: Node discovery + heartbeat — identity, registry, heartbeat protocol, CLI commands
- **Risk**: LOW — self-contained discovery module
- **Conflicts**: Radar files (shared with 3 other branches)
- **Note**: Can merge in parallel with nats-server-lifecycle (independent paths)
- **Verdict**: SHIP

---

## Conflict Analysis

### Critical: ShikkiCommand.swift (11 branches)

Every branch adding a CLI subcommand modifies the `@main struct ShikkiCommand` array. This is the #1 conflict hotspot.

**Branches touching it** (in recommended merge order):
1. feature/shiki-core
2. feature/codegen-engine
3. feature/killer-features
4. feature/ship-testflight
5. feature/blue-flame
6. feature/auto-diagnostic
7. feature/enterprise-safety
8. feature/answer-engine
9. feature/brainytube-v2
10. feature/moto-dns-v2
11. feature/kernel-decomposition-v2 (last — may not directly add subcommand)

**Resolution strategy**: Each merge adds entries to the subcommands array. Conflicts are trivial (add lines, keep both). Can be resolved mechanically. Consider a pre-merge script that validates the subcommand list.

### High: ShikkiKernel.swift (9 branches)

Service registration in the kernel. Each branch registers its services.

**Resolution strategy**: Same as ShikkiCommand.swift — additive entries. Merge kernel-decomposition-v2 LAST since it restructures the kernel.

### High: Package.swift (6 branches)

SPM target and dependency declarations.

**Branches**: shiki-core, shiki-knowledge-mcp, memory-migration, brainytube-v2, ship-testflight, maya-ground-quality

**Resolution strategy**: Each adds new targets/dependencies. Merge one, then manually add remaining targets from each subsequent branch. Validate with `swift package resolve` after each merge.

### Medium: EventBus / TaskScheduler (8 branches)

Mostly carrying the same base version with minor additions. Should auto-resolve if merged in order.

### Low: Radar commits (4 branches)

Shared commits `e105ace8`, `e31a955c`, `fd882f4a` across augmented-tui-v2, answer-engine, nats-foundation, nats-node-discovery-v2. First merge absorbs them; subsequent merges auto-resolve.

---

## Merge Order (recommended)

### Phase A — Absorb radar noise (1 merge)
1. **feature/nats-foundation** — absorbs radar commits, no feature conflicts

### Phase B — Foundation (5 merges)
2. **feature/shiki-core** — engine foundation, first to claim ShikkiCommand.swift + Package.swift
3. **feature/shiki-knowledge-mcp** — MCP layer, depends on core patterns
4. **feature/s3-spec-syntax** — zero conflicts, pure addition
5. **feature/memory-migration** — phases 1-2
6. **feature/memory-migration-ph3-4** — phases 3-4 (ancestor of moto-dns-v2)

### Phase C — Core features (7 merges)
7. **feature/auto-diagnostic** — 4-wave diagnostic, self-contained
8. **feature/codegen-engine** — massive but well-isolated in CodeGen/ directory
9. **feature/killer-features** — largest LOC, merge while CodeGen paths are fresh
10. **feature/ship-testflight** — ship pipeline
11. **feature/blue-flame** — personality engine
12. **feature/enterprise-safety** — safety gates (needs test fix)
13. **feature/answer-engine** — BM25 engine (radar commits already absorbed from step 1)

### Phase D — Advanced features (4 merges)
14. **feature/brainytube-v2** — video player overhaul
15. **feature/maya-ground-quality** — Maya sensor AI
16. **feature/moto-dns-v2** — depends on memory-migration-ph3-4 (step 6)
17. **feature/community-flywheel-v2** — pure addition, no conflicts

### Phase E — TUI + Ecosystem (2 merges)
18. **feature/augmented-tui-v2** — TUI enhancement (radar already absorbed)
19. **feature/kernel-decomposition-v2** — MERGE LAST among Shikki branches (kernel refactor)

### Phase F — NATS stack (4 merges, strict order)
20. **feature/nats-server-lifecycle** — Wave 2
21. **feature/nats-event-logger** — Wave 3
22. **feature/nats-report-aggregator-w4** — Wave 4 (includes Wave 3 commit)
23. **feature/nats-node-discovery-v2** — discovery module (radar already absorbed)

### Post-merge
- Run full `swift test` on integration branch
- Validate `swift package resolve` succeeds
- Verify all 23+ subcommands register in ShikkiCommand.swift
- Spot-check ShikkiKernel.swift service count matches expected

---

## Risk Matrix

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| ShikkiCommand.swift merge conflicts | LOW (mechanical) | CERTAIN | Merge in order, each adds entries |
| ShikkiKernel.swift registration conflicts | MEDIUM | HIGH | Merge kernel-decomposition-v2 last |
| Package.swift target conflicts | MEDIUM | HIGH | `swift package resolve` after each |
| Radar commit divergence | LOW | CERTAIN | Absorb in step 1 via nats-foundation |
| enterprise-safety undertested | MEDIUM | MEDIUM | Add tests before v0.3.0 release tag |
| codegen-engine too large (22K LOC) | HIGH if buggy | LOW | 68 test files, well-structured waves |
| killer-features too large (26K LOC) | HIGH if buggy | LOW | 73 test files, marketplace is isolatable |
| NATS chain broken | HIGH | LOW | Strict wave order enforced |
| memory-migration/moto-dns dependency | MEDIUM | LOW | Merge ph3-4 before moto-dns-v2 |
| Compilation failure mid-merge | HIGH | MEDIUM | `swift build` check after each merge |

---

## Flags for @Ronin (Adversarial Review)

1. **enterprise-safety**: 1 test file for 2,261 LOC. Budget ACL + anomaly detection with thin tests is a security risk. Needs at minimum: boundary tests for budget limits, audit trail completeness tests, anomaly false-positive rate tests.

2. **killer-features at 26K LOC**: Template marketplace is a supply-chain surface. Verify template install does not execute arbitrary code. Check `shikki templates install` sandboxing.

3. **codegen-engine Self-Healing Fix Loop**: Wave 5 auto-applies fixes. Verify there are guardrails (max iterations, rollback on failure, human confirmation for destructive changes).

4. **nats-node-discovery-v2**: Heartbeat + identity. Verify no unauthenticated node registration. Check if identity can be spoofed.

5. **answer-engine BM25**: Codebase-aware Q&A. Verify no accidental exposure of .env or credential files through search results.

---

## Flags for @Metsuke (Quality Inspector)

1. **Test density variance**: enterprise-safety (1 test file / 2.3K LOC) vs blue-flame (3 test files / 1.7K LOC with 78 tests). Enforce minimum test density.

2. **Branches with "chore: import" commits**: nats-foundation and nats-node-discovery-v2 carry project import commits. Verify these don't duplicate existing files.

3. **Shared commit deduplication**: memory-migration-ph3-4 commit `a687ec11` appears in both ph3-4 and moto-dns-v2. NATS event-logger commit `70cc7289` appears in both event-logger and report-aggregator-w4. Git handles this via merge-base, but verify no double-application.

4. **10 branches modify Observatory files** (DecisionJournal, AgentReportGenerator, ObservatoryRenderer). These were merged in the integration branch already. Verify no regression.

---

## Branch Count Reconciliation

The user stated 25 branches. This review covers **23 branches** found on origin. The 2 unaccounted branches:
- **feature/brainy-vision-v2**: Found only in worktree `agent-ad029af5`, not on origin. Last commit was Observatory Layer 3 (same as integration HEAD). Appears to be the worktree that built Observatory layers already merged. **No action needed.**
- **One branch may be the Shikkimoji feature** already merged into integration via worktree merges. **No action needed.**

---

## Final Verdict

**SHIP WITH CONDITIONS**

### Conditions:
1. **Merge in the exact order specified** (Phases A through F) — dependency chains and conflict resolution depend on it
2. **Run `swift build` after every merge** — catch compilation errors immediately, not after 23 merges
3. **Run `swift test` after each phase** (6 checkpoints) — isolate test failures to the phase that introduced them
4. **feature/enterprise-safety needs 3+ additional test files** before tagging v0.3.0 — budget ACL, audit trail, anomaly detection each need dedicated test suites
5. **feature/kernel-decomposition-v2 merges LAST** among non-NATS branches — it refactors ShikkiKernel.swift which 8 other branches modify
6. **After all 23 merges**: full `swift test`, verify ShikkiCommand subcommand count, verify `swift package resolve` clean

### Estimated merge time: 2-3 hours with a single operator following the order above.

### What's already in integration (for context):
- Observatory Layers 1-3 (Decision Journal, Agent Reports, Oversight TUI)
- Shikkimoji Waves 1-5
- NetKit DLNA (server + browser)
- 13 previously merged feature branches (event-logger, heartbeat-tests, ship-dogfood, ronin-v1.1-fixes, etc.)

This merge will bring Shikki from a CLI tool with basic orchestration to a full-featured platform with code generation, NATS messaging, video playback, AI-powered Q&A, template marketplace, enterprise safety, and ground quality sensing. It is the single biggest capability jump in Shikki's history.
