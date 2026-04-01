# Feature: Fix Backend Docker Healthcheck
> Created: 2026-04-01 | Status: Phase 5b — Execution Plan | Owner: @Daimyo

## Context

The backend Docker healthcheck uses `curl` but the `denoland/deno:2.0.0` base image doesn't ship `curl`. The healthcheck silently fails, Docker marks the backend as `unhealthy`, and the frontend (which depends on `backend: condition: service_healthy`) refuses to start. The entire stack is bricked on fresh `docker compose up -d`.

## Inspiration

### Root Cause Analysis

| # | Finding | Source | Impact |
|---|---------|--------|--------|
| 1 | `denoland/deno:2.0.0` is Debian-slim — no `curl`, no `wget` | Dockerfile inspection | Healthcheck always fails |
| 2 | `docker-compose.yml` backend healthcheck uses `curl -sf` | docker-compose.yml:87 | Container marked unhealthy after 3 retries (30s) |
| 3 | Frontend depends on `backend: condition: service_healthy` | docker-compose.yml:99-100 | Frontend refuses to start |
| 4 | Error is silent — `docker compose up -d` shows no error for backend | Docker behavior | User thinks stack is up, but it's half-broken |
| 5 | ntfy uses `wget` (available in its image) — inconsistent approach | docker-compose.yml:120 | Each service uses whatever HTTP client is available |

### Selected Fix

Use Deno's built-in `fetch()` via `deno eval` — zero dependencies, already in the image, idiomatic.

## Synthesis

**Goal**: Make `docker compose up -d` bring the full stack up reliably on a clean machine.

**Scope**:
- Replace `curl`-based healthcheck with `deno eval fetch()` in `docker-compose.yml`
- Verify the fix works end-to-end (`docker compose down && docker compose up -d`)

**Out of scope**:
- Adding `curl` to the Deno image (bloats image, fragile)
- Changing the frontend dependency chain
- Adding a `/healthz` endpoint (the existing `/health` endpoint is fine)

**Success criteria**:
1. `docker compose up -d` brings all 5 services to healthy/running within 60s
2. `docker inspect shikki-backend-1 --format='{{.State.Health.Status}}'` returns `healthy`
3. Frontend starts without `dependency failed to start` error

## Business Rules

```
BR-01: The backend healthcheck MUST NOT depend on binaries absent from the base image
BR-02: The healthcheck MUST use Deno's built-in fetch() API via `deno eval`
BR-03: The healthcheck MUST exit with non-zero if the /health endpoint returns non-2xx
BR-04: The healthcheck timeout MUST remain ≤ 5s (Docker default: 30s is too lenient)
BR-05: The frontend MUST NOT start until the backend healthcheck passes (existing behavior, preserved)
```

## Test Plan

### Manual verification (no unit tests — this is infra config)

```
TEST-01 (BR-01, BR-02): Fresh build + start
  docker compose down --remove-orphans
  docker compose build backend --no-cache
  docker compose up -d
  → All containers reach healthy/running within 60s

TEST-02 (BR-03): Healthcheck detects backend failure
  docker compose stop db
  → Backend healthcheck fails within 30s
  → docker inspect shows "unhealthy"

TEST-03 (BR-04): Timeout respected
  Observe healthcheck logs: each check completes < 5s
  docker inspect shikki-backend-1 --format='{{json .State.Health.Log}}' | python3 -m json.tool
  → No "Output": "..." entries with curl/wget errors

TEST-04 (BR-05): Dependency chain works
  docker compose up -d
  → Frontend starts AFTER backend is healthy (check timestamps)
```

## Architecture

### Files to modify

| File | Change | Purpose |
|------|--------|---------|
| `docker-compose.yml` | Replace backend healthcheck command | Fix the actual bug |

### Before (broken)

```yaml
# docker-compose.yml line 86-91
healthcheck:
  test: ["CMD-SHELL", "curl -sf http://localhost:3900/health || exit 1"]
  interval: 10s
  timeout: 5s
  retries: 3
  start_period: 15s
```

### After (fixed)

```yaml
# docker-compose.yml line 86-91
healthcheck:
  test: ["CMD", "deno", "eval", "const r = await fetch('http://localhost:3900/health'); if (!r.ok) Deno.exit(1);"]
  interval: 10s
  timeout: 5s
  retries: 3
  start_period: 15s
```

### Why `deno eval` and not alternatives

| Alternative | Verdict | Reason |
|-------------|---------|--------|
| Install `curl` in Dockerfile | Rejected | Adds ~5MB, extra layer, dependency to maintain |
| Install `wget` in Dockerfile | Rejected | Same bloat issue |
| Use `/dev/tcp` bash trick | Rejected | Only checks port open, not HTTP 200 |
| Copy a healthcheck script | Rejected | Extra file to maintain, overkill |
| **`deno eval fetch()`** | **Selected** | Zero-dependency, uses the runtime already in the image, native HTTP |

## Execution Plan

### Task 1: Replace backend healthcheck in docker-compose.yml

- **Files**: `docker-compose.yml` (modify line 87)
- **Implement**: Replace the `curl`-based healthcheck test with `deno eval` using `fetch()`
- **Verify**: `docker compose config | grep -A5 healthcheck` shows the new command (no `curl`)
- **BRs**: BR-01, BR-02, BR-03, BR-04
- **Time**: ~1 min

### Task 2: End-to-end verification

- **Implement**: Run `docker compose down --remove-orphans && docker compose up -d` and verify all services healthy
- **Verify**:
  ```bash
  docker compose ps --format "table {{.Name}}\t{{.Status}}"
  # All services: Up (healthy) or Up
  docker inspect shikki-backend-1 --format='{{.State.Health.Status}}'
  # → healthy
  curl -s http://localhost:3900/health | python3 -c "import json,sys; d=json.load(sys.stdin); print('OK' if d['status']=='ok' else 'FAIL')"
  # → OK
  ```
- **BRs**: BR-01 through BR-05
- **Time**: ~2 min (mostly waiting for containers)

## Implementation Readiness Gate

| Check | Status | Detail |
|-------|--------|--------|
| BR Coverage | PASS | 5/5 BRs mapped to tasks |
| Test Coverage | PASS | 4/4 test cases mapped |
| File Alignment | PASS | 1/1 file covered |
| Task Dependencies | PASS | Linear: Task 1 → Task 2 |
| Task Granularity | PASS | Both tasks < 5 min |
| Testability | PASS | Both tasks have verify steps |

**Verdict: PASS** — ready for implementation.

## Implementation Log

| Date | Event | Detail |
|------|-------|--------|
| 2026-04-01 | Bug discovered | @Daimyo launching orchestrator stack for first time |
| 2026-04-01 | Root cause identified | `curl: not found` in healthcheck logs via `docker inspect` |
| 2026-04-01 | Fix applied | `deno eval fetch()` healthcheck — backend + frontend now start correctly |
| 2026-04-01 | Spec written | For contributor to formalize and validate the fix |

## Review History

| Date | Phase | Reviewer | Decision | Notes |
|------|-------|----------|----------|-------|
| 2026-04-01 | Phase 1-5b | @Daimyo | Approved | Fix already applied live, spec for formalization |
