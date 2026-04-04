---
title: "Deno Sunset — MCP-First Architecture, Delete Backend, Extract Web Plugin"
status: draft
priority: P0
project: shikki
created: 2026-04-04
authors: ["@Daimyo"]
tags: [architecture, mcp, backend, deno, postgresql, migration, cleanup]
depends-on: []
relates-to: [shikki-workspace-separation.md, shikki-daemon-command.md]
epic-branch: feature/deno-sunset
validated-commit: —
test-run-id: —
---

# Feature: Deno Sunset — MCP-First Architecture
> Created: 2026-04-04 | Status: Draft | Owner: @Daimyo

## Context

The system has 3 parallel paths to the same database, built at different times:

```
PATH 1 (legacy):  shi CLI → BackendClient (curl) → Deno backend (80 routes) → PostgreSQL
PATH 2 (correct): shi CLI → MCP → ShikiMCP (15 tools) → PostgreSQL
PATH 3 (broken):  shi CLI → ShikiServer (embedded) → InMemoryStore (RAM, lost on restart)
```

Path 2 is the correct architecture. MCP is a direct stdio pipe between the CLI and the database — no HTTP, no middleware, no round-trips. The ShikiMCP package already has 15 tools covering search, save, read, analytics, all talking directly to PostgreSQL.

Path 1 (Deno) is legacy — 80 routes, most of which are dead or duplicated by MCP. 16 CLI commands still curl it instead of using MCP.

Path 3 (ShikiServer + InMemoryStore) was a failed experiment — two Swift arrays pretending to be a database. Data disappears on restart. Nobody uses it for anything real.

### What @Daimyo wants

- **MCP is the brain interface** — CLI ↔ DB, always connected, no HTTP
- **`shi event` command** — lightweight event interface for hooks/scripts that can't speak MCP stdio
- **Delete Deno** — the 13 TypeScript files, the Docker service, all of it
- **Delete ShikiServer + InMemoryStore + ServerRoutes** — zero value, throwaway RAM store
- **Delete BackendClient** — the curl-based HTTP client that 16 commands use
- **Extract Vue frontend** to `plugins/shikki-web-dashboard/` — rebuild later, not blocking
- **Keep PostgreSQL** — the brain stays, accessed exclusively via MCP

### Target Architecture

```
shi CLI ──→ MCP (stdio pipe) ──→ ShikiMCP ──→ PostgreSQL (@db)
                                     │
shi event ─────────────────────────────┘  (CLI wrapper for hooks/scripts)

shi daemon ──→ NATS ──→ event bus (real-time between nodes)
                  │
                  └──→ MCP ──→ PostgreSQL (persist events)

Vue frontend ──→ EXTRACTED plugin (not our problem, rebuild later)
Deno backend ──→ DELETED
ShikiServer  ──→ DELETED
InMemoryStore ──→ DELETED
BackendClient ──→ DELETED
```

## Business Rules

```
BR-01: MCP MUST be the ONLY interface between shi CLI and PostgreSQL — no HTTP, no curl, no middleware
BR-02: All 16 commands using BackendClient MUST be rewired to use MCP tool calls
BR-03: shi event <type> [--data <json>] MUST be a new CLI command that calls shiki_save_event via MCP
BR-04: shi event MUST be usable from bash hooks (one-liner: shi event --type heartbeat --data '{}')
BR-05: ShikiServer (embedded HTTP server) MUST be deleted — no Swift HTTP server in the CLI
BR-06: InMemoryStore MUST be deleted — no in-memory fake database
BR-07: ServerRoutes MUST be deleted — no HTTP routing in the CLI
BR-08: BackendClient MUST be deleted — no curl-based HTTP client
BR-09: BackendClientProtocol MUST be replaced by MCPClientProtocol (or direct MCP tool calls)
BR-10: src/backend/ (Deno, 13 TypeScript files) MUST be deleted from the repo
BR-11: src/frontend/ (Vue, 6 pages) MUST be moved to plugins/shikki-web-dashboard/
BR-12: docker-compose.yml MUST be simplified — keep only PostgreSQL + Ollama + ntfy. Remove Deno + Vue services
BR-13: Hooks (tmux-checkpoint.sh, practice-memory-capture.sh) MUST be rewired from curl → shi event
BR-14: ShikiMCP MUST remain a standalone package at packages/ShikiMCP/ — not merged into ShikkiKit
BR-15: ShikiMCP MAY need new tools for backlog CRUD, company management, session transcripts if not already covered
BR-16: The event bus (NATS) MUST persist events to PostgreSQL via MCP, not via HTTP data-sync
BR-17: shi doctor MUST check MCP health (shiki_health tool) instead of HTTP /health
```

## What Gets Deleted

| File/Directory | LOC | Why it dies |
|---|---|---|
| `Sources/ShikkiKit/Server/ShikiServer.swift` | 392 | No HTTP server needed — MCP is the interface |
| `Sources/ShikkiKit/Server/ServerRoutes.swift` | 141 | No routes — MCP tools replace them |
| `Sources/ShikkiKit/Server/InMemoryStore.swift` | 161 | Fake DB — data lost on restart, nobody uses it |
| `Sources/ShikkiKit/Kernel/Persistence/BackendClient.swift` | ~300 | curl → Deno, legacy path |
| `Sources/ShikkiKit/Kernel/Persistence/BackendClientProtocol.swift` | ~50 | Protocol for the curl client |
| `Sources/ShikkiKit/Kernel/Persistence/DBSyncClient.swift` | ~150 | curl → Deno for checkpoints |
| `src/backend/` (13 .ts files) | ~3000 | Deno backend, fully replaced by MCP |
| `src/backend/Dockerfile` | ~20 | Deno Docker image |
| **Total deleted** | **~4,200 LOC** | |

## What Gets Extracted (Plugin)

| File/Directory | What | Plugin |
|---|---|---|
| `src/frontend/` | Vue 3 + Vite + Tailwind (6 pages) | `plugins/shikki-web-dashboard/` |
| `src/frontend/package.json` | Vue deps | plugin's own deps |
| Web-only Deno routes (radar, charts, WebSocket) | If rebuilt, lives in plugin | plugin's own backend |

## What Stays

| Component | Why |
|---|---|
| `packages/ShikiMCP/` | The brain interface — 15 tools → PostgreSQL |
| PostgreSQL (docker-compose) | The brain — all persistence |
| Ollama (docker-compose) | Embeddings for memory search |
| ntfy (docker-compose) | Push notifications |
| NATS (nats-server binary) | Real-time event transport between nodes |

## Command Rewiring Map (BackendClient → MCP)

| Command | BackendClient call | → MCP tool | Notes |
|---|---|---|---|
| board | `getBoardOverview()` | `shiki_search` + aggregation | May need new `shiki_board_overview` tool |
| status | `getStatus()` | `shiki_get_context` (scope: orchestrator) | |
| decide | `getPendingDecisions()` | `shiki_get_decisions` (status: pending) | |
| decide | `answerDecision()` | `shiki_save_decision` | |
| report | `getDailyReport()` | `shiki_daily_summary` | Already exists |
| pause | `getCompanies()` | `shiki_search` (type: company) | |
| pause | `patchCompany()` | Need new `shiki_update_company` tool | |
| history | `getSessionTranscripts()` | `shiki_search` (type: session_transcript) | |
| history | `createSessionTranscript()` | `shiki_save_event` (type: session_transcript) | |
| backlog | `listBacklogItems()` | `shiki_search` (type: backlog) | |
| backlog | `createBacklogItem()` | `shiki_save_event` (type: backlog_created) | |
| backlog | `updateBacklogItem()` | Need new `shiki_update_backlog` tool | |
| inbox | `getCompanies()` + backlog | `shiki_search` (combined query) | |
| heartbeat | `sendHeartbeat()` | `shiki_save_event` (type: heartbeat) | |
| wake | `patchCompany()` | `shiki_update_company` | |
| codir | `getCompanies()` + report | `shiki_search` + `shiki_daily_summary` | |

**New MCP tools needed:**
- `shiki_update_company` — PATCH company status/settings
- `shiki_update_backlog` — PATCH backlog item
- `shiki_board_overview` — aggregated board view (companies + tasks + PRs)

## Hook Rewiring Map (curl → shi event)

| Hook | Before (curl) | After (shi event) |
|---|---|---|
| `tmux-checkpoint.sh` | `curl -X POST localhost:3900/api/data-sync -d '{...}'` | `shi event --type tmux_checkpoint --data '{"windows":...}'` |
| `practice-memory-capture.sh` | `curl -X POST localhost:3900/api/data-sync -d '{...}'` | `shi event --type command_invoked --data '{"skill":...}'` |
| `shiki-notify-lib.sh` | `curl localhost:3900/health` | `shi event --type health_check` (or just skip) |
| Claude Code Stop hook | `curl -X POST localhost:3900/api/data-sync` | `shi event --type session_stopped` |

## TDDP — Test Summary Table

| Test | BR | Tier | Type | Scenario |
|------|-----|------|------|----------|
| T-01 | BR-01 | Core (80%) | Unit | When command needs DB data → calls MCP, not HTTP |
| T-02 | BR-02 | Core (80%) | Integration | When board command runs → uses MCP, no BackendClient |
| T-03 | BR-03 | Core (80%) | Unit | When shi event --type X → calls shiki_save_event via MCP |
| T-04 | BR-04 | Smoke (CLI) | Integration | When bash hook calls shi event → event saved to PostgreSQL |
| T-05 | BR-05, BR-06, BR-07 | Core (80%) | Unit | When ShikiServer/InMemoryStore/ServerRoutes deleted → build clean |
| T-06 | BR-08 | Core (80%) | Unit | When BackendClient deleted → no curl calls in codebase |
| T-07 | BR-10 | Core (80%) | Unit | When src/backend/ deleted → no TypeScript in repo |
| T-08 | BR-12 | Smoke (CLI) | Integration | When docker compose up → only PostgreSQL + Ollama + ntfy start |
| T-09 | BR-13 | Smoke (CLI) | Integration | When hook fires → shi event saves to DB |
| T-10 | BR-15 | Core (80%) | Unit | When shiki_update_company called → company updated in DB |
| T-11 | BR-17 | Core (80%) | Unit | When shi doctor → checks MCP health, not HTTP |

### S3 Test Scenarios

```
T-01 [BR-01, Core 80%]:
When any shi command needs data from @db:
  → instantiates MCPClient (stdio pipe to shikki-mcp binary)
  → calls appropriate MCP tool (shiki_search, shiki_get_decisions, etc.)
  → no URLSession, no curl, no HTTP involved
  if shikki-mcp binary not found:
    → prints "MCP server not found — run: shi setup"

T-02 [BR-02, Core 80%]:
When shi board runs:
  → calls shiki_board_overview MCP tool
  → renders TUI output from MCP response
  → BackendClient not imported, not used
  → no localhost:3900 connection attempted

T-03 [BR-03, Core 80%]:
When shi event --type heartbeat --data '{"status":"alive"}':
  → parses --type and --data flags
  → calls shiki_save_event with type="heartbeat" and payload
  → prints "Event saved: heartbeat"
  → exit code 0

T-04 [BR-04, Smoke CLI]:
When a bash hook calls shi event:
  → event appears in PostgreSQL within 1 second
  → shiki_search for that event type returns the record
  → no HTTP server required

T-05 [BR-05, BR-06, BR-07, Core 80%]:
When ShikiServer.swift, InMemoryStore.swift, ServerRoutes.swift are deleted:
  → swift build completes with zero errors
  → no remaining imports of ShikiServer, InMemoryStore, or ServerRoutes

T-06 [BR-08, Core 80%]:
When BackendClient.swift and BackendClientProtocol.swift are deleted:
  → swift build completes with zero errors
  → grep -r "BackendClient" Sources/ returns 0 matches
  → grep -r "curl" Sources/ returns 0 matches (except ExternalTools detection)

T-07 [BR-10, Core 80%]:
When src/backend/ is deleted:
  → no .ts files in repository
  → no deno.json in repository

T-08 [BR-12, Smoke CLI]:
When docker compose up runs:
  → PostgreSQL container starts
  → Ollama container starts (if configured)
  → ntfy container starts (if configured)
  → NO Deno container
  → NO Vue dev server container

T-09 [BR-13, Smoke CLI]:
When tmux-checkpoint.sh hook fires:
  → calls shi event --type tmux_checkpoint --data '...'
  → event saved to PostgreSQL via MCP
  → no curl in the hook script

T-10 [BR-15, Core 80%]:
When shiki_update_company MCP tool called with {slug: "wabisabi", status: "paused"}:
  → PostgreSQL companies table updated
  → returns updated company record

T-11 [BR-17, Core 80%]:
When shi doctor runs:
  → calls shiki_health MCP tool
  → reports "DB: connected" or "DB: unreachable"
  → no HTTP health check attempted
```

## Wave Dispatch Tree

```
Wave 1: shi event command + MCPClient interface
  ├── EventCommand.swift — shi event --type X --data '{}'
  ├── MCPClient.swift — stdio pipe to shikki-mcp binary (in ShikkiKit)
  └── Wire event bus to persist via MCP instead of HTTP
  Input:  ShikiMCP binary (already built)
  Output: shi event works, hooks can use it
  Tests:  T-01, T-03, T-04
  Gate:   shi event --type test → saved to PostgreSQL
  ║
  ╠══ Wave 2: Rewire 16 commands from BackendClient to MCP ← BLOCKED BY Wave 1
  ║   ├── Replace BackendClient calls with MCPClient calls in all 16 commands
  ║   ├── Add 3 new MCP tools: shiki_update_company, shiki_update_backlog, shiki_board_overview
  ║   └── Update shi doctor to use MCP health
  ║   Input:  MCPClient, existing MCP tools + 3 new ones
  ║   Output: All commands talk MCP, zero HTTP
  ║   Tests:  T-02, T-10, T-11
  ║   Gate:   grep -r "BackendClient" Sources/ → 0 matches (except delete candidates)
  ║   ║
  ║   ╠══ Wave 3: Delete dead code ← BLOCKED BY Wave 2
  ║   ║   ├── Delete ShikiServer.swift, ServerRoutes.swift, InMemoryStore.swift
  ║   ║   ├── Delete BackendClient.swift, BackendClientProtocol.swift, DBSyncClient.swift
  ║   ║   ├── Delete src/backend/ (13 TypeScript files + Dockerfile)
  ║   ║   ├── Simplify docker-compose.yml (remove Deno + Vue services)
  ║   ║   └── Rewire hooks from curl → shi event
  ║   ║   Input:  All commands using MCP (Wave 2 done)
  ║   ║   Output: ~4,200 LOC deleted, zero TypeScript, zero HTTP middleware
  ║   ║   Tests:  T-05, T-06, T-07, T-08, T-09
  ║   ║   Gate:   swift build clean + no curl/BackendClient/Deno references
  ║   ║
  ║   ╚══ Wave 4: Extract Vue frontend to plugin ← BLOCKED BY Wave 3
  ║       ├── Move src/frontend/ → plugins/shikki-web-dashboard/
  ║       ├── Move relevant Deno web routes (radar, charts) to plugin if needed later
  ║       └── Update .gitignore, README
  ║       Input:  Deno deleted, frontend orphaned
  ║       Output: Clean repo, plugin extracted
  ║       Tests:  (manual — plugin is parked, not active)
  ║       Gate:   src/ directory gone from repo
```

## Implementation Waves

### Wave 1: shi event + MCPClient
**Files:**
- `Sources/shikki/Commands/EventCommand.swift` — `shi event --type X --data '{}'`
- `Sources/ShikkiKit/Kernel/Persistence/MCPClient.swift` — launches shikki-mcp via Process, communicates via stdio JSON-RPC
- `Tests/ShikkiKitTests/MCPClientTests.swift`
**Tests:** T-01, T-03, T-04
**BRs:** BR-01, BR-03, BR-04
**Deps:** packages/ShikiMCP (already built, 15 tools, 116 tests)
**Gate:** `shi event --type test` saves to PostgreSQL

### Wave 2: Rewire 16 Commands ← BLOCKED BY Wave 1
**Files (modify 16 commands):**
- Every command in Sources/shikki/Commands/ that imports BackendClient
- `packages/ShikiMCP/Sources/ShikkiMCP/Tools/WriteTools.swift` — add shiki_update_company, shiki_update_backlog
- `packages/ShikiMCP/Sources/ShikkiMCP/Tools/ReadTools.swift` — add shiki_board_overview
- `Sources/shikki/Commands/DoctorCommand.swift` — MCP health instead of HTTP
**Tests:** T-02, T-10, T-11
**BRs:** BR-02, BR-09, BR-15, BR-17
**Deps:** Wave 1 (MCPClient)
**Gate:** `grep -r "BackendClient" Sources/` → 0 matches

### Wave 3: Delete Dead Code ← BLOCKED BY Wave 2
**Files (delete):**
- `Sources/ShikkiKit/Server/ShikiServer.swift` (392 LOC)
- `Sources/ShikkiKit/Server/ServerRoutes.swift` (141 LOC)
- `Sources/ShikkiKit/Server/InMemoryStore.swift` (161 LOC)
- `Sources/ShikkiKit/Kernel/Persistence/BackendClient.swift` (~300 LOC)
- `Sources/ShikkiKit/Kernel/Persistence/BackendClientProtocol.swift` (~50 LOC)
- `Sources/ShikkiKit/Kernel/Persistence/DBSyncClient.swift` (~150 LOC)
- `src/backend/` (13 files, ~3000 LOC)
- `docker-compose.yml` — remove deno + vue services
- `scripts/tmux-checkpoint.sh` — curl → shi event
- `scripts/practice-memory-capture.sh` — curl → shi event
**Tests:** T-05, T-06, T-07, T-08, T-09
**BRs:** BR-05, BR-06, BR-07, BR-08, BR-10, BR-12, BR-13
**Deps:** Wave 2 (no command depends on deleted code)
**Gate:** `swift build` clean, `grep -r "localhost:3900" Sources/` → 0

### Wave 4: Extract Vue Frontend ← BLOCKED BY Wave 3
**Files (move):**
- `src/frontend/` → `plugins/shikki-web-dashboard/frontend/`
- `src/frontend/package.json` → plugin's own
- Web-only Deno routes (if worth saving) → plugin's own backend
- Update .gitignore, README
**Tests:** none (plugin is parked)
**BRs:** BR-11
**Deps:** Wave 3 (src/backend/ deleted, frontend orphaned)
**Gate:** `src/` directory gone from repo root

## Reuse Audit

| Utility | Exists In | Decision |
|---------|-----------|----------|
| MCP stdio protocol | packages/ShikiMCP/MCPProtocol.swift | Reuse — MCPClient speaks the same JSON-RPC |
| shiki_save_event | ShikiMCP/WriteTools.swift | Reuse — shi event calls this directly |
| shiki_search | ShikiMCP/ReadTools.swift | Reuse — replaces most BackendClient GET calls |
| shiki_get_decisions | ShikiMCP/ReadTools.swift | Reuse — replaces decision queue HTTP calls |
| PostgreSQL connection | ShikiMCP/ShikkiDBClient.swift | Reuse — already has connection pool + raw SQL |
| MockDBClient | ShikiMCP/Tests/MockDBClient.swift | Reuse — for testing MCPClient without real DB |

## @t Review

### @Sensei (CTO)
This is the architectural cleanup that makes everything else possible. MCP is faster than HTTP (no TCP round-trip, no JSON → HTTP → JSON), more reliable (no connection pool staleness), and simpler (one interface, one protocol). The 16-command rewire is mechanical — each BackendClient call maps to an MCP tool. The 3 new MCP tools (update_company, update_backlog, board_overview) are trivial SQL wrappers. The scary part is Wave 3 (deleting ~4,200 LOC) — but it's safe because Wave 2 already proved everything works on MCP.

### @Ronin (Adversarial)
- **MCPClient process lifecycle**: Each `shi event` spawns a shikki-mcp process, does one tool call, exits. For hooks firing every 30s, that's fine. For batch operations (16 events in a loop), consider keeping the MCP process alive for the session.
- **PostgreSQL dependency**: After this, shi CLI hard-requires PostgreSQL running. Today it can run without DB (InMemoryStore catches events). After deletion, `shi event` fails if DB is down. Is that OK? (Yes — MCP already requires DB, this just makes it explicit.)
- **Rollback risk**: Once Deno is deleted, there's no going back. Make sure ALL 16 commands work on MCP before deleting. Wave ordering enforces this.

### @Katana (Security)
- BackendClient used `curl` (spawns processes, passes JSON in command args). MCP uses stdio (no command injection surface). This is a security improvement.
- The Vue frontend had zero authentication. Extracting it to a plugin means it's not accidentally serving on an open port.

### @Kintsugi (Philosophy)
Three paths to one database is the opposite of wabi-sabi — it's accumulation without intention. MCP is the one path, chosen deliberately. Deleting the other two is not loss, it's clarity.
