# PR #3 Review Summary — feat(orchestrator): multi-company autonomous agency

**Branch**: `develop` -> `main`
**State**: OPEN, MERGEABLE, no reviews yet
**Size**: +16,446 / -0 across 135 files (100% additions -- greenfield)

---

## 1. PR Overview

Introduces the orchestrator layer for multi-company autonomous agency. Four major subsystems:

1. **DB foundation** (migrations 004-006): 5 new tables (`companies`, `task_queue`, `decision_queue`, `company_budget_log`, `audit_log`), 1 join table (`company_projects`), 2 views (`company_status`, `orchestrator_overview`, `dispatcher_queue`). Uses TimescaleDB hypertables with compression/retention for budget and audit logs. Partial unique index on `task_queue` for cross-company package lock atomicity.

2. **API layer** (`orchestrator.ts` + `routes.ts` + `schemas.ts`): 22 new REST endpoints covering company CRUD, atomic task claim (`FOR UPDATE SKIP LOCKED`), decision queue with auto-unblock, package locks, heartbeat, budget tracking, audit trail, daily report, session transcripts, dispatcher queue, board overview.

3. **Process skills** (`.claude/commands/` + `.claude/skills/`): 4 new slash commands (`/board`, `/company`, `/decide`, `/orchestrate`), 4 new skills (autopilot, company-management, decision-queue, orchestrator). The `/autopilot` skill alone is 500 lines defining the full 5-wave autonomous pipeline.

4. **Shared SPM packages** (`packages/`): CoreKit, NetworkKit, SecurityKit, DesignKit, ShikiKit -- full extracted package suite with sources + tests. ShikiKit contains typed DTOs for the entire Shiki platform (agents, dashboard, git events, ingest, memory, pipeline, project, radar, session, WebSocket messages).

5. **Scripts**: `board-watch.sh`, `orchestrate.sh`, `seed-companies.sh`, `shiki` CLI wrapper, `shiki-board.sh`.

---

## 2. Risk Assessment

| Risk | File / Area | Reason |
|------|-------------|--------|
| **HIGH** | `src/backend/src/orchestrator.ts` (778 lines) | Core business logic. Atomic task claim with `FOR UPDATE SKIP LOCKED`, budget cumulative calculation, decision auto-unblock. Any bug here causes data corruption or deadlocks. PR body notes 3 critical fixes already applied (arg mismatch, TOCTOU race, non-atomic budget). |
| **HIGH** | `src/db/migrations/004_orchestrator.sql` (186 lines) | Schema foundation. FK references to `projects` and `pipeline_runs` tables -- migration will fail if those don't exist. Hypertable creation requires TimescaleDB extension. Partial unique index on `metadata->>'package'` is clever but non-obvious. |
| **HIGH** | `src/db/migrations/005_dispatcher_model.sql` (100 lines) | Drops `idx_companies_project` unique index, migrates data to `company_projects` join table. Destructive DDL -- must run after 004. `CREATE OR REPLACE VIEW company_status` replaces the view from 004 (ordering dependency). |
| **HIGH** | `src/backend/src/routes.ts` (+308 lines) | 22 new route handlers in a single file. Path matching uses regex and string splitting (`path.split("/")[3]`) -- fragile, no param extraction middleware. Route ordering matters (e.g., `/api/decision-queue/pending` must come before `/api/decision-queue/:id`). |
| **MEDIUM** | `src/backend/src/schemas.ts` (+121 lines) | Zod validation schemas. Lower risk but must stay in sync with TS interfaces and SQL schema. |
| **MEDIUM** | `packages/ShikiKit/` (25 files, ~2,400 lines) | Typed DTOs + routes + WebSocket messages. Risk is in decode fidelity -- stringified JSONB from Postgres needs flexible decoders. Well-tested (8 test files). |
| **MEDIUM** | `packages/CoreKit/` (21 files, ~1,700 lines) | DI container, coordinator, cache, extensions. Extracted from WabiSabi. Risk: thread safety in `Container` (noted in backlog as `ContainerTests thread safety`). 3 test files with 576 lines. |
| **MEDIUM** | `.claude/skills/shiki-process/autopilot.md` (500 lines) | Defines the autonomous pipeline behavior. Risk is in correctness of instructions rather than code -- bad instructions cause bad agent behavior at scale. |
| **LOW** | `packages/NetworkKit/` (13 files) | Standard HTTP + WebSocket abstractions. Well-tested. |
| **LOW** | `packages/SecurityKit/` (9 files) | Keychain + auth persistence with mocks. 2 test files. |
| **LOW** | `packages/DesignKit/` (11 files) | Theme tokens, view modifiers. 3 test files. Note: DesignKit is deprecated (replaced by DSKintsugi per MEMORY.md) -- should this still be in the PR? |
| **LOW** | `scripts/` (5 files) | Shell scripts for board display and seeding. Operational tooling. |
| **LOW** | `docs/cheatsheet.md`, `features/swift-platform-migration.md` | Documentation only. |

---

## 3. Key Concerns

### 3.1 Migration ordering and TimescaleDB dependency
Migration 004 calls `create_hypertable()` and `add_compression_policy()` which require the TimescaleDB extension. If the target DB doesn't have it installed, migration fails silently or crashes. Migration 005 drops an index created in 004 and replaces a view from 004 -- ordering is implicit (filename-based), not enforced.

### 3.2 Route handler fragility
All 22 new endpoints are added to a single `handleRequest()` function using string splitting and regex matching. `path.split("/")[3]` is used to extract IDs, which breaks if the path structure changes. The route for `/api/decision-queue/pending` vs `/api/decision-queue/:id` depends on declaration order. This is a maintenance burden and a source of subtle routing bugs.

### 3.3 DesignKit included but already deprecated
MEMORY.md states DesignKit is deprecated and replaced by DSKintsugi. Including it in this PR adds 11 files and ~1,000 lines of code that should not be used. Either remove it or add a deprecation notice.

### 3.4 Budget `spent_today_usd` is stored in the JSONB default but computed atomically elsewhere
The `companies.budget` column defaults to `{"spent_today_usd": 0}` but the PR body mentions cumulative budget is "computed atomically (single INSERT with subquery)" in `company_budget_log`. The `spent_today` in `dispatcher_queue` view uses `SUM(amount_usd)` from the log table, not the JSONB field. This dual-source could cause confusion -- which is the source of truth?

### 3.5 PR targets `main` instead of `develop`
The PR base branch is `main`, but MEMORY.md states: "All PRs target `develop`, never `main` directly. Only `release/*` merges to `main`." This violates the project's git flow convention.

---

## 4. Test Coverage

| Package / Area | Test Files | Approx. Assertions | Coverage Quality |
|----------------|-----------|--------------------|--------------------|
| CoreKit | 3 (CacheRepository, Container, Resolve) | ~30 | GOOD -- covers DI lifecycle, cache expiry, property wrapper |
| NetworkKit | 3 (EndPoint, MockNetwork, NetworkService) | ~15 | GOOD -- covers endpoint building, mock stubbing, basic requests |
| SecurityKit | 2 (AuthPersistence, Keychain) | ~14 | ADEQUATE -- covers CRUD, error cases |
| DesignKit | 3 (ColorTokens, Spacing, Theme) | ~15 | ADEQUATE -- covers token values, theme switching |
| ShikiKit | 8 (DTOs, Dashboard, GitEvent, Ingest/Radar/Pipeline, Memory, ShikiError, WSMessage, ShikiKit) | ~50+ | GOOD -- covers decode from both native and stringified JSONB, error mapping, WebSocket message types |
| Backend (orchestrator.ts) | 0 unit tests in PR | 82 E2E assertions (per PR body) | **GAP** -- no unit tests for orchestrator.ts in the repo. E2E test mentioned in PR body but not included in the diff. |
| Backend (routes.ts) | 0 | 0 | **GAP** -- no route-level tests |
| Migrations (SQL) | 0 | 0 | **GAP** -- no migration verification tests |
| Scripts | 0 | 0 | LOW RISK -- operational tooling |

**Total test files in PR**: 19 (all Swift SPM packages)
**Backend test gap**: The 82-assertion E2E test referenced in the PR body is not present in the diff. Either it lives outside this PR or was run manually.

---

## 5. Verdict

A large, well-structured greenfield PR that introduces a significant orchestration layer. The Swift packages are well-tested and cleanly extracted. The main risks are in the backend: no unit tests for 778 lines of orchestrator logic, fragile route handling, and a migration chain that depends on TimescaleDB. The PR targeting `main` instead of `develop` should be corrected before merge.
