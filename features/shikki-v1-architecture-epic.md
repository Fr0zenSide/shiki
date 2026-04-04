---
title: "V1 Architecture Epic — Workspace + MCP-First + Distributed Sync"
status: draft
priority: P0
project: shikki
created: 2026-04-04
authors: ["@Daimyo"]
tags: [epic, architecture, v1, workspace, mcp, distributed, multi-tenant]
epic-branch: epic/v1-architecture
validated-commit: —
test-run-id: —
---

# V1 Architecture Epic — Workspace + MCP-First + Distributed Sync
> Created: 2026-04-04 | Status: Draft — Awaiting @Daimyo Review | Owner: @Daimyo

## Why This Epic Exists

Three architectural debts block Shikki v1:
1. **Repo = workspace** — personal data in git, hardcoded paths, no portability
2. **3 paths to one DB** — BackendClient (curl→Deno), MCP (stdio→PostgreSQL), InMemoryStore (RAM). Should be ONE: MCP.
3. **Single-machine only** — no sync between company server and user devices, no multi-tenant

These are sequential — you can't delete Deno until workspace paths are clean, you can't distribute until MCP is the only interface. This epic orders the work as 12 unified waves across 3 phases.

## Source Specs

This epic unifies:
- `features/shikki-workspace-separation.md` (27 BRs, 17 tests, 4 waves)
- `features/shikki-deno-sunset.md` (17 BRs, 11 tests, 4 waves)
- `features/shikki-distributed-sync.md` (40 BRs, pending tests)

Total: **84 BRs** across 3 phases, **12 waves**.

---

## Phase 0: Test Coverage Gate (Wave 0)

**Goal**: Every command that will be migrated has tests BEFORE migration. No blind rewiring.
**Unblocks**: Phase 1 and Phase 2 (safe to migrate with test safety net)

### Wave 0 — TDD Coverage for 24 Untested Commands

**What**: Write characterization tests for all 24 commands that currently have zero tests. These tests capture CURRENT behavior — they're the safety net for migration.

**Coverage audit (current state)**:
| Status | Count | Commands |
|---|---|---|
| Has tests | 2 | ReviewCommand (4), BacklogCommand (3) |
| NO tests | 24 | AskCommand, BoardCommand, CodirCommand, DaemonCommand, DecideCommand, FastCommand, HeartbeatCommand, HistoryCommand, InboxCommand, IngestCommand, InitCommand, MotoCommand, PauseCommand, PRCommand, QuickCommand, ReportCommand, RestartCommand, SearchCommand, ShipCommand, SpecCommand, SpecCheckCommand, SpecMigrateCommand, StartupCommand, StatusCommand, TemplatesCommand, WakeCommand, WaveCommand |

**Priority order** (highest risk = uses both CWD + BackendClient):
1. StartupCommand, StatusCommand, HeartbeatCommand, WakeCommand (both patterns)
2. BoardCommand, DecideCommand, ReportCommand, PauseCommand, InboxCommand (BackendClient)
3. QuickCommand, ShipCommand, SpecCommand, SearchCommand (CWD-heavy)
4. Remaining commands

**TDD Migration Protocol (mandatory for every command)**:
```
Step 1: Write characterization tests for current behavior → GREEN
Step 2: Migrate (WorkspaceResolver / MCPClient swap)
Step 3: Same tests → GREEN (behavior preserved, plumbing changed)
Step 4: shikki-test full suite → GREEN
Step 5: Only then move to next command
```

**Files**: One test file per command in `Tests/ShikkiKitTests/Commands/`
**Gate**: All 26 commands have tests → `shikki-test` full suite green
**Parallel**: Yes — test files are independent, dispatch in batches of 5-6

**Estimated scope**: ~50 tests (2 per command average), ~2,000 LOC tests

---

## Phase 1: Workspace Separation (Waves 1-4)

**Goal**: Clean repo, portable paths, multi-workspace support.
**Unblocks**: Phase 2 (commands use WorkspaceResolver, not hardcoded paths)

### Wave 1 — WorkspaceResolver + Config
**What**: The core path resolution engine. Every command uses `WorkspaceResolver.root` instead of `currentDirectoryPath`.
**Files**:
- `Sources/ShikkiKit/Kernel/Core/WorkspaceResolver.swift` — $SHI_WS resolution chain (env → config → cwd)
- `Sources/ShikkiKit/Kernel/Core/WorkspaceConfig.swift` — config.yaml parser
- `Sources/ShikkiKit/Kernel/Core/WorkspacePaths.swift` — .features, .memory, .reports, .projects
- Tests: `WorkspaceResolverTests.swift`
**Key BRs**: BR-04 ($SHI_WS), BR-05 (resolution chain), BR-06 (all commands use it)
**Gate**: `swift test --filter Workspace` green
**Parallel**: Yes — no dependencies

### Wave 2 — Command Migration (20+ files)
**What**: Replace ALL `currentDirectoryPath` with `WorkspaceResolver`. Remove ALL hardcoded `/Users/*` paths. Update scripts to use `$SHI_WS`.
**Files**: 20+ commands in `Sources/shikki/Commands/`, 4 scripts, `.mcp.json`
**Key BRs**: BR-06 (WorkspaceResolver), BR-07 ($SHI_WS in scripts), BR-09 (zero hardcoded paths)
**Gate**: `grep -rn "/Users/jeoffrey" Sources/ scripts/` returns 0
**Blocked by**: Wave 1

### Wave 3 — Workspace CLI
**What**: `shi ws list|create|switch|suggest|link|unlink|links`. Multi-workspace management.
**Files**:
- `Sources/shikki/Commands/WorkspaceCommand.swift`
- `Sources/ShikkiKit/Setup/WorkspaceMigration.swift` — repo-as-workspace → proper workspace
- Tests: `WorkspaceCommandTests.swift`
**Key BRs**: BR-13..BR-15 (ws CLI), BR-17 (migration), BR-18c..BR-18k (SPM linking)
**Gate**: `shi ws list` + `shi ws switch` + `shi ws link` work
**Blocked by**: Wave 2

### Wave 4 — Repo Restructure
**What**: Move personal data out of git. Clean .gitignore. Update README. Update Package.swift local paths.
**Files**: .gitignore, README.md, CONTRIBUTING.md, Package.swift
**Key BRs**: BR-01 (repo = CLI source only), BR-10 (no personal data), BR-18 (deps by URL)
**Gate**: Fresh clone + `shi setup` → working workspace
**Blocked by**: Wave 3

**Phase 1 deliverable**: Clean repo. Any contributor clones, builds, runs. Your personal data lives in `~/.shikki/workspaces/`. All commands workspace-aware.

---

## Phase 2: Deno Sunset / MCP-First (Waves 5-8)

**Goal**: MCP is the ONLY interface to PostgreSQL. Delete Deno, InMemoryStore, BackendClient, ShikiServer.
**Unblocks**: Phase 3 (clean MCP interface, no legacy HTTP)

### Wave 5 — shi event + MCPClient
**What**: Lightweight event command for hooks/scripts. MCPClient that speaks stdio JSON-RPC to shikki-mcp binary.
**Files**:
- `Sources/shikki/Commands/EventCommand.swift` — `shi event --type X --data '{}'`
- `Sources/ShikkiKit/Kernel/Persistence/MCPClient.swift` — stdio pipe to shikki-mcp
- Tests: `MCPClientTests.swift`
**Key BRs**: BR-01 (MCP only), BR-03 (shi event), BR-04 (usable from bash)
**Gate**: `shi event --type test` → saved to PostgreSQL via MCP
**Blocked by**: Wave 4 (workspace paths clean)

### Wave 6 — Rewire 16 Commands
**What**: Replace every `BackendClient` call with an MCP tool call. Add 3 new MCP tools.
**Files**: 16 commands + `packages/ShikiMCP/` (add `shiki_update_company`, `shiki_update_backlog`, `shiki_board_overview`)
**Key BRs**: BR-02 (all commands via MCP), BR-09 (replace BackendClientProtocol), BR-15 (new MCP tools)
**Gate**: `grep -r "BackendClient" Sources/` → 0 matches
**Blocked by**: Wave 5

### Wave 7 — Delete Dead Code (~4,200 LOC)
**What**: Delete ShikiServer, InMemoryStore, ServerRoutes, BackendClient, DBSyncClient, Deno backend. Simplify docker-compose. Rewire hooks to `shi event`.
**Deleted**:
- `Sources/ShikkiKit/Server/ShikiServer.swift` (392 LOC)
- `Sources/ShikkiKit/Server/ServerRoutes.swift` (141 LOC)
- `Sources/ShikkiKit/Server/InMemoryStore.swift` (161 LOC)
- `Sources/ShikkiKit/Kernel/Persistence/BackendClient.swift` (~300 LOC)
- `Sources/ShikkiKit/Kernel/Persistence/BackendClientProtocol.swift` (~50 LOC)
- `Sources/ShikkiKit/Kernel/Persistence/DBSyncClient.swift` (~150 LOC)
- `src/backend/` (13 files, ~3,000 LOC)
**Key BRs**: BR-05..BR-08 (delete), BR-10 (delete Deno), BR-12 (simplify Docker), BR-13 (rewire hooks)
**Gate**: `swift build` clean + zero curl/Deno/localhost:3900 references
**Blocked by**: Wave 6

### Wave 8 — Extract Vue Frontend
**What**: Move `src/frontend/` to `plugins/shikki-web-dashboard/`. Not rebuilt — parked for later.
**Files**: Move `src/frontend/` → `plugins/shikki-web-dashboard/frontend/`
**Key BRs**: BR-11 (extract Vue)
**Gate**: `src/` directory gone from repo root
**Blocked by**: Wave 7

**Phase 2 deliverable**: MCP is the ONLY path. ~4,200 LOC deleted. Zero Deno, zero HTTP middleware. Hooks use `shi event`. Docker has only PostgreSQL + Ollama + ntfy.

---

## Phase 3: Distributed Sync (Waves 9-12)

**Goal**: Company server + user device replicas + bidirectional NATS sync.
**Unblocks**: Enterprise multi-tenant deployment.

### Wave 9 — Server Setup + Multi-Tenant
**What**: `shi setup --server` installs PostgreSQL+NATS+PgBouncer on Linux. `shi tenant add/remove/list`. Tenant config files.
**Files**:
- `Sources/shikki/Commands/ServerSetupCommand.swift`
- `Sources/shikki/Commands/TenantCommand.swift`
- `Sources/ShikkiKit/Kernel/Core/TenantConfig.swift`
- `/etc/shikki/tenants/*.yaml` config format
- Tests: `TenantConfigTests.swift`
**Key BRs**: BR-01..BR-07 (server), BR-29..BR-32 (tenant CLI)
**Gate**: `shi tenant add obyw` creates database + config
**Blocked by**: Wave 7 (MCP-first architecture)

### Wave 10 — User Onboarding + Local Replica
**What**: `shi setup --join <server> --token <invite>`. Install local PostgreSQL + NATS leaf. Initial sync.
**Files**:
- `Sources/shikki/Commands/JoinCommand.swift`
- `Sources/ShikkiKit/Kernel/Core/NATSLeafConfig.swift`
- `Sources/ShikkiKit/Kernel/Persistence/LocalReplicaManager.swift`
- Tests: `JoinCommandTests.swift`, `LocalReplicaTests.swift`
**Key BRs**: BR-08..BR-13 (user device), BR-37..BR-40 (onboarding)
**Gate**: `shi setup --join` creates local DB + NATS leaf + initial sync completes
**Blocked by**: Wave 9

### Wave 11 — Sync Protocol + Conflict Resolution
**What**: Event-sourced bidirectional sync via NATS JetStream. UUID v7 ordering. LWW conflicts. Offline buffer + replay.
**Files**:
- `Sources/ShikkiKit/NATS/SyncEngine.swift` — bidirectional event sync
- `Sources/ShikkiKit/NATS/ConflictResolver.swift` — LWW with vector clocks
- `Sources/ShikkiKit/NATS/OfflineBuffer.swift` — NATS leaf buffer management
- Tests: `SyncEngineTests.swift`, `ConflictResolverTests.swift`
**Key BRs**: BR-21..BR-28 (sync protocol)
**Gate**: Two devices sync events bidirectionally, survive offline period
**Blocked by**: Wave 10

### Wave 12 — Data Protection + User Management
**What**: TTL wipe for stale devices. Confidential data server-only. User add/revoke. Device decommission.
**Files**:
- `Sources/ShikkiKit/Kernel/Core/DataTTLEnforcer.swift`
- `Sources/shikki/Commands/UserCommand.swift` — `shi user add/revoke`
- Tests: `DataTTLTests.swift`, `UserCommandTests.swift`
**Key BRs**: BR-14..BR-20 (data protection), BR-33..BR-36 (user management)
**Gate**: Revoked user's device wipes data after TTL, confidential data never leaves server
**Blocked by**: Wave 11

**Phase 3 deliverable**: Full distributed architecture. Company server (Linux) serves N tenants × M users. User devices work offline with scoped replicas. NATS syncs everything. Data protected against device theft.

---

## Unified Wave Dispatch Tree

```
PHASE 0: TEST COVERAGE GATE
════════════════════════════

Wave 0: Characterization Tests for 24 Commands ─────────── no deps
  ├── Batch A (5): StartupCommand, StatusCommand, HeartbeatCommand, WakeCommand, BoardCommand
  ├── Batch B (5): DecideCommand, ReportCommand, PauseCommand, InboxCommand, HistoryCommand
  ├── Batch C (5): QuickCommand, ShipCommand, SpecCommand, SearchCommand, MotoCommand
  ├── Batch D (5): DaemonCommand, RestartCommand, InitCommand, IngestCommand, PRCommand
  └── Batch E (4): FastCommand, SpecCheckCommand, SpecMigrateCommand, TemplatesCommand, WaveCommand
  Gate: shikki-test full suite → ALL GREEN (existing + ~50 new tests)
  Parallel: YES — each batch is independent, dispatch 5 agents
  ║
  ║
PHASE 1: WORKSPACE SEPARATION
══════════════════════════════
  ║
Wave 1: WorkspaceResolver ──────────────────────────────────── ← Wave 0
  ║
  ╚══ Wave 2: Command Migration (20+ files) ──────────────── ← Wave 1
       ║
       ╚══ Wave 3: Workspace CLI (shi ws) ────────────────── ← Wave 2
            ║
            ╚══ Wave 4: Repo Restructure ─────────────────── ← Wave 3
                 ║
                 ║
PHASE 2: DENO SUNSET / MCP-FIRST
═════════════════════════════════
                 ║
                 ╚══ Wave 5: shi event + MCPClient ───────── ← Wave 4
                      ║
                      ╚══ Wave 6: Rewire 16 Commands ────── ← Wave 5
                           ║
                           ╚══ Wave 7: Delete ~4,200 LOC ── ← Wave 6
                                ║
                                ╠══ Wave 8: Extract Vue ──── ← Wave 7
                                ║
                                ║
PHASE 3: DISTRIBUTED SYNC
══════════════════════════
                                ║
                                ╚══ Wave 9: Server Setup ─── ← Wave 7
                                     ║
                                     ╚══ Wave 10: User Join ─ ← Wave 9
                                          ║
                                          ╚══ Wave 11: Sync ── ← Wave 10
                                               ║
                                               ╚══ Wave 12: Data Protection ── ← Wave 11
```

## Parallel Opportunities

Even though waves are sequential within a phase, some cross-phase work can start early:

| Can start during | Work item | Why |
|---|---|---|
| Wave 1 | New MCP tools (Wave 6 prep) | MCP tools don't depend on workspace paths |
| Wave 2 | Capacity monitoring setup | Infrastructure, not code |
| Wave 5 | NATS leaf node config design (Wave 10 prep) | Design only, no code deps |
| Wave 7 | Vue plugin structure (Wave 8 prep) | Just directory setup |
| Wave 8 | Tenant config format (Wave 9 prep) | Design only |

## BR Coverage Summary

| Phase | Spec | BRs | Tests |
|---|---|---|---|
| 1: Workspace | shikki-workspace-separation.md | 27 | 17 |
| 2: MCP-First | shikki-deno-sunset.md | 17 | 11 |
| 3: Distributed | shikki-distributed-sync.md | 40 | TBD |
| **Total** | | **84** | **28+** |

## Estimated Scope

| Phase | Waves | New files | Modified | LOC added | LOC deleted | Tests | Est. Budget (Opus) |
|---|---|---|---|---|---|---|---|
| 0: Test Gate | 1 (5 batches) | ~24 | 0 | ~2,000 | 0 | ~50 | ~$8-12 |
| 1: Workspace | 4 | ~8 | ~25 | ~1,200 | ~200 | ~17 | ~$10-15 |
| 2: MCP-First | 4 | ~5 | ~20 | ~800 | ~4,200 | ~11 | ~$12-18 |
| 3: Distributed | 4 | ~12 | ~5 | ~3,000 | 0 | ~30 | ~$15-25 |
| **Total** | **13** | **~49** | **~50** | **~7,000** | **~4,400** | **~108** | **~$45-70** |

**Budget estimation basis** (Claude Opus, parallel agent dispatch):
- Wave 0: 5 parallel agents × ~$2 each = ~$10. Mechanical test writing, low complexity.
- Phase 1: 4 sequential waves. W1 simple (~$2), W2 high-touch 20+ files (~$5), W3 medium (~$3), W4 low (~$2).
- Phase 2: W5 medium (~$3), W6 high-touch 16 commands + 3 MCP tools (~$6), W7 deletion (~$2), W8 simple move (~$1).
- Phase 3: All new code, complex distributed logic. W9 (~$4), W10 (~$4), W11 sync engine (~$8), W12 security (~$5).

**Cost drivers**: Parallel agents multiply throughput but each agent costs ~$1.5-3 per wave. Phase 2 Wave 6 is the most expensive single wave (16 commands to rewire). Phase 3 Wave 11 (sync protocol) is the most complex.

**Comparison**: This session (2026-04-03/04) shipped 280 tests across ~15 agents for an estimated ~$25-35. The full V1 epic is roughly 2-3x that.

Net: **+2,600 LOC** (add 7K, delete 4.4K). The codebase grows modestly while gaining multi-tenant distributed sync.

## Risk Assessment

| Wave | Risk | Mitigation |
|---|---|---|
| 2 (Command Migration) | 20+ files touched, high regression surface | Run full test suite after each command, one PR per batch of 5 |
| 6 (Rewire 16 Commands) | MCP tool gaps (missing shiki_update_company) | Implement new MCP tools BEFORE rewiring commands |
| 7 (Delete 4,200 LOC) | Point of no return for Deno | Wave 6 proves everything works on MCP before deleting |
| 10 (User Join) | PostgreSQL + extensions install across platforms | Script it, test on Ubuntu + macOS in CI |
| 11 (Sync Protocol) | Conflict resolution edge cases | Start with LWW (simple), upgrade to CRDT if needed |
| 12 (Data Protection) | TTL wipe could destroy user data unexpectedly | Multiple warnings before wipe, admin override |

## @Daimyo Review Checklist

Before dispatching, validate these decisions:

- [ ] **Phase ordering**: Workspace → MCP → Distributed. Agree?
- [ ] **Wave 2**: 20+ commands migrated in one wave — or split into batches?
- [ ] **Wave 7**: Delete Deno permanently — point of no return. Ready?
- [ ] **Wave 8**: Vue frontend parked as plugin — no rebuild planned. OK?
- [ ] **Wave 9**: Shared schema + RLS (capacity audit recommendation) vs database-per-tenant?
- [ ] **Wave 11**: LWW conflict resolution vs CRDT — LWW is simpler, CRDT is more correct. Which?
- [ ] **Wave 12**: TTL default for stale device wipe — 7 / 14 / 30 days?
- [ ] **BR-08**: Local PostgreSQL on every user device — acceptable install weight?
- [ ] **BR-20**: Confidential data never on devices — how to classify what's confidential?
- [ ] **Parallel**: Start new MCP tools (Wave 6 prep) during Wave 1?
