# Feature: Shiki Knowledge MCP — From API Calls to Intelligent Knowledge Layer

> **Type**: /md-feature
> **Priority**: P0 — foundational, blocks reliable agent autonomy
> **Status**: Spec (validated by @Daimyo 2026-03-17)
> **Depends on**: Shiki DB (existing), Event Bus (Wave 2A — DONE)
> **Supersedes**: Raw curl API calls, ad-hoc data-sync POSTs

---

## 1. Problem

Agents interact with Shiki DB via raw `curl` commands to REST endpoints. This is broken:

### 1A. Error Blindness
`curl -sf` is used 30+ times across the codebase. It conflates HTTP errors (validation failures, 500s) with connection failures. On 2026-03-17, a validation error (`payload` vs `data` field name) was misdiagnosed as "DB down" — the DB had 36h uptime. **Every silent fallback is a lie.**

### 1B. Schema Drift
No contract between agent and DB. Agents guess field names (`payload` vs `data`), guess endpoints (`/api/data-sync` vs `/api/memories/search`), guess query parameters. One typo = silent data loss.

### 1C. No Knowledge Construction
Agents POST raw events but never READ intelligently. There's no "what do I know about this topic?" query. The DB is write-only for most agent workflows. The knowledge sits there unused because querying requires knowing the exact API shape.

### 1D. No Validation at Source
Agents can POST garbage data — wrong types, missing fields, invalid references. The API returns a 422 that `curl -sf` hides. The agent thinks it saved data. It didn't.

## 2. Solution — MCP Server for Shiki DB

Replace raw curl API calls with a **Model Context Protocol (MCP) server** that:
1. **Typed tools** — agents call `shiki_db.save_decision()` not `curl -X POST`
2. **Validated schemas** — tool definitions enforce field types, required fields, valid enums
3. **Intelligent queries** — `shiki_db.search("what architecture decisions did we make for sessions?")` returns structured results
4. **No silent failures** — MCP errors are surfaced to the agent context, not swallowed

### Why MCP over API

| Aspect | Raw API (curl) | MCP Server |
|--------|---------------|------------|
| Error handling | `curl -sf` hides errors | MCP errors in agent context |
| Schema | Agent guesses fields | Tool definition enforces schema |
| Discovery | Agent must know endpoints | Tools are self-documenting |
| Validation | Server-side only (hidden) | Client-side + server-side |
| Knowledge query | Manual SQL/filter params | Semantic search built-in |
| Agent DX | Copy-paste curl commands | Call typed functions |
| Documentation | Scattered in .md files | In the tool definition itself |

## 3. MCP Tool Definitions

### 3.1 Write Tools

```
shiki_save_decision
  - category: enum (architecture|implementation|process|tradeOff|scope)
  - question: string (required)
  - choice: string (required)
  - rationale: string (required)
  - alternatives: string[] (optional)
  - impact: enum (architecture|implementation|process)
  - parentDecisionId: string (optional — for chain traceability)
  - project: string (optional)
  - branch: string (optional)

shiki_save_plan
  - planName: string (required)
  - planPath: string (required)
  - status: enum (draft|validated|executed|abandoned)
  - approvedBy: enum (user|agent|daimyo)
  - context: string (required — why this plan)
  - deliverables: string[] (required)
  - branch: string (optional)
  - company: string (optional)

shiki_save_event
  - type: string (required — event type from EventType enum)
  - scope: string (required — global|session|project|pr|file)
  - scopeId: string (optional — session id, project slug, PR number)
  - data: object (required — event payload)

shiki_save_agent_report
  - sessionId: string (required)
  - persona: enum (investigate|implement|verify|critique|review|fix)
  - taskTitle: string (required)
  - beforeState: string (required)
  - afterState: string (required)
  - keyDecisions: object[] (optional)
  - filesChanged: string[] (optional)
  - testsAdded: int (optional)
  - redFlags: string[] (optional)

shiki_save_context
  - sessionId: string (required)
  - reason: enum (compaction|checkpoint|handoff|shutdown)
  - summary: string (required)
  - activeTask: string (optional)
  - progress: string (optional)
```

### 3.2 Read Tools

```
shiki_search
  - query: string (required — natural language or keyword)
  - projectId: string (optional — scope to project)
  - types: string[] (optional — filter by event/decision/plan/report)
  - since: string (optional — ISO8601 date)
  - limit: int (default 10)
  Returns: ranked results with relevance score

shiki_get_decisions
  - since: string (optional — date filter)
  - category: string (optional — architecture|implementation|etc.)
  - project: string (optional)
  - chainFrom: string (optional — get full decision chain from a root)
  Returns: decision list with chain links

shiki_get_reports
  - sessionId: string (optional)
  - company: string (optional)
  - since: string (optional)
  Returns: agent report cards

shiki_get_context
  - sessionId: string (required)
  Returns: latest context snapshot for session recovery

shiki_get_plans
  - status: string (optional — validated|executed|abandoned)
  - since: string (optional)
  Returns: plan list with metadata

shiki_health
  Returns: DB status, uptime, event counts, last sync time
```

### 3.3 Analytics Tools

```
shiki_daily_summary
  - date: string (optional — defaults to today)
  Returns: decisions made, plans validated, agents completed,
           red flags, blockers hit/resolved, test counts

shiki_decision_chain
  - decisionId: string (required)
  Returns: full tree from root decision to all children

shiki_agent_effectiveness
  - since: string (optional)
  Returns: per-persona success rates, avg duration, context resets
```

## 4. Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Claude Code Agent (any session)                         │
│  ├─ calls: shiki_save_decision(...)                      │
│  ├─ calls: shiki_search("session architecture")          │
│  └─ calls: shiki_get_decisions(chainFrom: "d-001")       │
└─────────────┬───────────────────────────────────────────┘
              │ MCP protocol (stdio or SSE)
              ▼
┌─────────────────────────────────────────────────────────┐
│  Shiki MCP Server (Node/Deno process)                    │
│  ├─ Tool schema validation (zod)                         │
│  ├─ BM25 + vector search (existing embed pipeline)       │
│  ├─ Decision chain resolver                              │
│  └─ Analytics aggregator                                 │
└─────────────┬───────────────────────────────────────────┘
              │ HTTP (internal, not exposed to agents)
              ▼
┌─────────────────────────────────────────────────────────┐
│  Shiki Backend (Deno, port 3900)                         │
│  ├─ /api/data-sync (write)                               │
│  ├─ /api/memories/search (read)                          │
│  └─ PostgreSQL (TimescaleDB)                             │
└─────────────────────────────────────────────────────────┘
```

**Key**: agents never call the HTTP API directly. The MCP server is the ONLY interface. It validates, enriches (adds timestamp, session context, project IDs), and handles errors — then calls the backend internally.

## 5. Migration Path

### Phase 1: MCP Server Skeleton
- Deno MCP server with tool definitions
- Proxies to existing `/api/data-sync` and `/api/memories/search`
- Schema validation via zod
- Proper error messages (not swallowed)

### Phase 2: Claude Code Integration
- Add to `.claude/settings.json` as MCP server
- Agents automatically get `shiki_*` tools
- Remove `curl` commands from agent prompts (autopilot, heartbeat)
- Remove `curl -sf` from pipeline skills

### Phase 3: Knowledge Construction
- `shiki_search` uses BM25 + vector embeddings (LM Studio)
- Decision chain resolver builds tree from `parentDecisionId`
- Analytics aggregator for daily/weekly summaries

### Phase 4: Agent Self-Improvement
- Agents query past decisions before making new ones: "what did we decide about X last time?"
- Recovery manager uses `shiki_get_context` for session restoration
- Watchdog thresholds adjust based on `shiki_agent_effectiveness`

## 6. What Dies

| Old Pattern | Replaced By |
|-------------|-------------|
| `curl -sf POST /api/data-sync` | `shiki_save_event(...)` |
| `curl -sf POST /api/memories/search` | `shiki_search(...)` |
| Raw `curl` in autopilot prompts | Agent has MCP tools natively |
| `curl -sf` with silent fallback | MCP error in agent context |
| Guessing field names | Typed tool schemas |
| No validation | Zod schemas on write |
| Write-only DB | Read + search + analytics |

## 7. Knowledge Graph Effect

Over time, the MCP layer builds a queryable knowledge graph:

```
Plan "v3 orchestrator" (2026-03-17)
  ├── Decision "actor over class" (architecture)
  │     └── Evidence: SessionLifecycle.swift passes 8 tests
  ├── Decision "JSONL over SQLite" (architecture)
  │     └── Evidence: journal prune works, 6 tests pass
  ├── Decision "defer Wave 2C" (scope)
  │     └── Rationale: shell-level, not Swift deliverable
  ├── Report: maya:spm-wave3 (implement, 2h14m, success)
  │     └── 31 tests, 3 files, 0 red flags
  └── Gate: /pre-pr passed (all 9 gates)
        └── Issues: 3 found + fixed in Gate 2
```

Agents querying this graph get richer context with every session. This is the **self-improving knowledge construction** you described — every agent interaction enriches the graph that future agents query.

## 8. Deliverables

- `tools/shiki-mcp/` — MCP server (Deno/TypeScript)
- `tools/shiki-mcp/tools/` — tool definitions with zod schemas
- `.claude/settings.json` — MCP server registration
- Migration: remove `curl -sf` from all pipeline skills
- Migration: update autopilot prompt to reference MCP tools
- Documentation: `docs/mcp-tools-reference.md`

## 9. Tests

- Tool schema validation (10 tests — one per write tool)
- Search relevance (5 tests — keyword + semantic)
- Decision chain resolution (3 tests — tree building)
- Error handling (5 tests — validation errors surfaced, not swallowed)
- Health check (2 tests — DB up/down distinction)
- ~25 total

## 10. Success Criteria

1. Zero `curl -sf` calls to Shiki API in agent prompts or skills
2. Every write operation validated before hitting DB
3. Agents can query "what do we know about X?" and get ranked results
4. Decision chains traceable from root to leaf
5. Daily summary available via `shiki_daily_summary`
6. No more false "DB down" diagnostics
