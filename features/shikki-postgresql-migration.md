---
title: "PostgreSQL Migration — Production Persistence for ShikiServer"
status: draft
priority: P0
project: shikki
created: 2026-04-03
authors: "@Daimyo + @shi brainstorm"
tags:
  - database
  - postgresql
  - persistence
  - migration
depends-on:
  - shikki-inbox-v2.md (inbox_read_state table)
  - shikki-spec-tracking-fields.md (test_run events need durable storage)
relates-to:
  - shikki-api-cleanup.md (route layer stays, storage swaps)
  - shiki-knowledge-mcp.md (MCP tools query the same store)
---

# PostgreSQL Migration

> In-memory is a prototype. Data that dies on restart is not data, it is a demo.

---

## 1. Problem

`InMemoryStore` is an actor holding two arrays (`events: [Data]`, `memories: [Data]`). Every restart erases all decisions, plans, contexts, and memories. Multi-user is impossible (single actor, single process). Text search is O(n) string matching. The inbox v2 spec requires `inbox_read_state` -- a relational join pattern that doesn't fit in-memory arrays. Test results from `shikki-spec-tracking-fields` need durable storage for orchestrator verification.

---

## 2. Solution

Replace `InMemoryStore` with `PostgreSQLStore` behind a `StorageProtocol`. Keep `InMemoryStore` as fallback when PostgreSQL is unavailable (dev mode, CI). Use `DATABASE_URL` for config. Versioned SQL migrations. PostgreSQL FTS (tsvector) for memory search. Add `inbox_read_state` table from inbox v2 spec.

---

## 3. Business Rules

| ID | Rule |
|----|------|
| BR-01 | `StorageProtocol` defines the contract: `addEvent`, `getEvents`, `addMemory`, `searchMemories`, `ingest` |
| BR-02 | `InMemoryStore` conforms to `StorageProtocol` (existing behavior, unchanged) |
| BR-03 | `PostgreSQLStore` conforms to `StorageProtocol` with real SQL queries |
| BR-04 | `ShikiServer` selects store at startup: `DATABASE_URL` set -> PostgreSQL, otherwise -> InMemory |
| BR-05 | Connection pool size configurable via `DB_POOL_SIZE` env var (default: 5) |
| BR-06 | Migrations are versioned SQL files in `Migrations/` dir, applied in order at startup |
| BR-07 | Memory search MUST use PostgreSQL FTS (`to_tsvector`/`ts_query`) when PG is active |
| BR-08 | `inbox_read_state` table created in migration V003 (schema from inbox v2 spec) |
| BR-09 | If PostgreSQL connection fails at startup, log warning and fall back to InMemoryStore |
| BR-10 | All queries MUST use parameterized statements (no string interpolation in SQL) |
| BR-11 | `events` table: id (UUID PK), type, project_id, data (JSONB), created_at (timestamptz, indexed) |
| BR-12 | `memories` table: id (UUID PK), project_id, data (JSONB), search_text (tsvector), created_at |

---

## 4. TDDP

| # | Test | State |
|---|------|-------|
| 1 | `StorageProtocol` declares `addEvent`, `getEvents`, `addMemory`, `searchMemories`, `ingest` | RED |
| 2 | Impl: Protocol definition with associated types | GREEN |
| 3 | `InMemoryStore` conforms to `StorageProtocol` (existing tests still pass) | RED |
| 4 | Impl: Add conformance annotation, adapt method signatures | GREEN |
| 5 | `PostgreSQLStore.addEvent` inserts into `events` table, returns enriched JSON | RED |
| 6 | Impl: INSERT with RETURNING, JSONB storage | GREEN |
| 7 | `PostgreSQLStore.getEvents` filters by `project_id` and `type` | RED |
| 8 | Impl: SELECT with optional WHERE clauses, LIMIT | GREEN |
| 9 | `PostgreSQLStore.searchMemories` uses FTS with `ts_query` | RED |
| 10 | Impl: SELECT with `to_tsquery`, rank by `ts_rank` | GREEN |
| 11 | Migration V001 creates `events` table with correct schema | RED |
| 12 | Impl: SQL migration file, `MigrationRunner` applies it | GREEN |
| 13 | Migration V002 creates `memories` table with tsvector column | RED |
| 14 | Impl: SQL migration file with GIN index on search_text | GREEN |
| 15 | Migration V003 creates `inbox_read_state` table | RED |
| 16 | Impl: SQL migration file matching inbox v2 schema | GREEN |
| 17 | `ShikiServer` selects PostgreSQLStore when DATABASE_URL is set | RED |
| 18 | Impl: Conditional store initialization in server bootstrap | GREEN |
| 19 | `ShikiServer` falls back to InMemoryStore when PG connection fails | RED |
| 20 | Impl: Try-catch on PG connect, log warning, swap store | GREEN |
| 21 | `MigrationRunner` applies pending migrations in order, skips applied | RED |
| 22 | Impl: `schema_migrations` tracking table, version comparison | GREEN |

---

## 5. S3 Scenarios

### Scenario 1: PostgreSQL selected on startup (BR-04)
```
When  DATABASE_URL is set to "postgresql://localhost:5432/shikki"
Then  ShikiServer initializes PostgreSQLStore
  and  migrations are applied
  and  all routes use PostgreSQLStore
```

### Scenario 2: Fallback to InMemory (BR-04, BR-09)
```
When  DATABASE_URL is not set
Then  ShikiServer initializes InMemoryStore
  and  logs "No DATABASE_URL — using in-memory store (data will not persist)"

When  DATABASE_URL is set but connection fails
Then  ShikiServer falls back to InMemoryStore
  and  logs warning with connection error details
```

### Scenario 3: Event CRUD via PostgreSQL (BR-03, BR-10, BR-11)
```
When  addEvent is called with type "decision" and projectId "abc"
Then  a row is inserted into events with JSONB data
  and  the returned JSON includes a server-generated UUID and created_at

When  getEvents is called with type "decision" and projectId "abc"
Then  only matching rows are returned, ordered by created_at DESC
```

### Scenario 4: FTS memory search (BR-07, BR-12)
```
When  searchMemories is called with query "leader election NATS"
Then  PostgreSQL ts_query is used with AND semantics per term
  and  results are ranked by ts_rank
  if  projectIds are provided
  then  results are filtered to those projects
```

### Scenario 5: Migration ordering (BR-06)
```
When  MigrationRunner runs at startup
Then  it reads schema_migrations table for applied versions
  and  applies only pending migrations in version order
  if  a migration fails
  then  the transaction is rolled back and startup aborts with error
```

### Scenario 6: inbox_read_state table (BR-08)
```
When  migration V003 is applied
Then  inbox_read_state table exists with columns:
      entity_type, entity_id, user_id, read_at, snoozed_until, archived_at
  and  composite primary key on (entity_type, entity_id, user_id)
```

---

## 6. Wave Dispatch Tree

```
Wave 1: StorageProtocol + InMemoryStore conformance
  Input:   InMemoryStore.swift, ShikiServer.swift
  Output:  StorageProtocol.swift, InMemoryStore conformance
  Gate:    Tests 1-4 green, existing server tests pass
  <- NOT BLOCKED

Wave 2: PostgreSQLStore + Migrations
  Input:   StorageProtocol.swift, SQL migration files
  Output:  PostgreSQLStore.swift, MigrationRunner.swift, V001-V003.sql
  Gate:    Tests 5-16 green (requires local PG or testcontainer)
  <- BLOCKED BY Wave 1

Wave 3: Server Integration + Fallback
  Input:   ShikiServer.swift, PostgreSQLStore.swift, InMemoryStore.swift
  Output:  Conditional store selection, graceful fallback
  Gate:    Tests 17-22 green
  <- BLOCKED BY Wave 2
```

---

## 7. Implementation Waves

### Wave 1: StorageProtocol + InMemoryStore Conformance
- **Files**: `Sources/ShikkiKit/Server/StorageProtocol.swift` (new), `Sources/ShikkiKit/Server/InMemoryStore.swift` (conform)
- **Tests**: `Tests/ShikkiKitTests/Server/StorageProtocolTests.swift`
- **BRs**: BR-01, BR-02
- **Deps**: None
- **Gate**: All existing `InMemoryStore` tests pass, protocol compiles

### Wave 2: PostgreSQLStore + Migration System
- **Files**: `Sources/ShikkiKit/Server/PostgreSQLStore.swift` (new), `Sources/ShikkiKit/Server/MigrationRunner.swift` (new), `Sources/ShikkiKit/Server/Migrations/V001_events.sql`, `V002_memories.sql`, `V003_inbox_read_state.sql`
- **Tests**: `Tests/ShikkiKitTests/Server/PostgreSQLStoreTests.swift`, `Tests/ShikkiKitTests/Server/MigrationRunnerTests.swift`
- **BRs**: BR-03, BR-05, BR-06, BR-07, BR-10, BR-11, BR-12
- **Deps**: Wave 1 (StorageProtocol)
- **Gate**: Tests 5-16 pass against local PostgreSQL

### Wave 3: Server Bootstrap + Fallback
- **Files**: `Sources/ShikkiKit/Server/ShikiServer.swift` (modify)
- **Tests**: `Tests/ShikkiKitTests/Server/ShikiServerTests.swift` (extend)
- **BRs**: BR-04, BR-08, BR-09
- **Deps**: Wave 2
- **Gate**: Tests 17-22 pass, `shikki server` starts with and without DATABASE_URL

---

## 8. @shi Mini-Challenge

1. **@Ronin**: The fallback from PostgreSQL to InMemoryStore is silent and lossy -- the user thinks they are persisting but they are not. Should the fallback be opt-in via a `--allow-memory-fallback` flag, or should the server refuse to start when DATABASE_URL is set but unreachable? Fail-loud vs fail-soft tradeoff.

2. **@Katana**: JSONB storage means SQL injection through JSON field values is still possible if any query concatenates JSONB paths. Should we add a `sanitizeJSON` step before INSERT, or is parameterized `$1::jsonb` sufficient for all query patterns we plan to use?
