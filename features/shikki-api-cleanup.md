---
title: "Embedded Server API Cleanup"
status: in-progress
priority: P0
epic-branch: fix/api-cleanup
created: 2026-04-02
author: "@Sensei"
tags: [api, cleanup, KISS, server, routes]
---

# Embedded Server API Cleanup

## Problem

`ServerRoutes.swift` (320 LOC) has 20+ routes copied from the old Deno backend. Half are dead stubs returning empty arrays. The embedded server should serve only the routes it actually implements with real data. Dead orchestrator/company/backlog/transcript stubs add cognitive load and maintenance surface for zero value.

Principle: if it can be an event bus subscription or a filtered event query, it does not need a dedicated HTTP route.

## Business Rules

- **BR-01**: The embedded server serves exactly 4 routes: `/health`, `/api/data-sync`, `/api/memories/search`, `/api/events`.
- **BR-02**: Decision queries (`/api/decisions`, `/api/decision-queue/pending`) become `GET /api/events?type=decision`.
- **BR-03**: Plan queries (`/api/plans`) become `GET /api/events?type=plan`.
- **BR-04**: Context queries (`/api/contexts`) become `GET /api/events?type=context`.
- **BR-05**: Decision patching (`PATCH /api/decision-queue/:id`) becomes a `POST /api/data-sync` with `type=decision_answer`.
- **BR-06**: All orchestrator stubs (`/api/orchestrator/*`) are removed from the embedded server.
- **BR-07**: All company stubs (`/api/companies`, `/api/companies/:id`) are removed from the embedded server.
- **BR-08**: All session transcript stubs (`/api/session-transcripts`) are removed from the embedded server. Transcript creation still works via `/api/data-sync` with `type=session_transcript`.
- **BR-09**: All backlog stubs (`/api/backlog/*`) are removed from the embedded server.
- **BR-10**: `BackendClient` methods that only target the real Deno backend (orchestrator, companies, backlog, transcripts) remain unchanged -- they still work when pointed at the real backend.
- **BR-11**: `InMemoryStore` dedicated decision/plan/context collections are replaced by event-type queries on the unified events collection.
- **BR-12**: Unknown routes return 404 with a descriptive error.

## TDDP (Test-Driven Development Plan)

### Tier: Core (80% coverage)

| # | Test | Scenario | Expected | Tier |
|---|------|----------|----------|------|
| T1 | `GET /health returns ok` | Hit health endpoint | `{"ok": true}`, status 200 | Core |
| T2 | `POST /api/data-sync ingests event` | Post event with type=heartbeat | 200, event stored | Core |
| T3 | `POST /api/data-sync ingests decision` | Post with type=decision | 200, queryable via events?type=decision | Core |
| T4 | `POST /api/data-sync ingests plan` | Post with type=plan | 200, queryable via events?type=plan | Core |
| T5 | `POST /api/data-sync ingests context` | Post with type=context_session_start | 200, queryable via events?type=context_session_start | Core |
| T6 | `POST /api/data-sync ingests memory` | Post with type=memory | 200, searchable via memories/search | Core |
| T7 | `GET /api/events returns all events` | No filters | Returns all stored events | Core |
| T8 | `GET /api/events?type=decision filters` | type=decision filter | Only decision events returned | Core |
| T9 | `GET /api/events?type=plan filters` | type=plan filter | Only plan events returned | Core |
| T10 | `GET /api/events?projectId=X filters` | projectId filter | Only matching events | Core |
| T11 | `GET /api/events?limit=5 limits` | limit=5 | Max 5 events returned | Core |
| T12 | `POST /api/memories/search works` | Search with query | Matching memories returned | Core |
| T13 | `Dead routes return 404` | GET /api/orchestrator/status | 404 Not found | Core |
| T14 | `Dead routes return 404 (backlog)` | GET /api/backlog | 404 Not found | Core |
| T15 | `Dead routes return 404 (companies)` | GET /api/companies | 404 Not found | Core |

## S3 Syntax Scenarios

```s3
Scenario: Health check returns OK
  Given the embedded server is running
  When  GET /health
  Then  status is 200
  And   body is {"ok": true}

Scenario: Data sync ingests a decision event
  Given the embedded server is running
  When  POST /api/data-sync {"type": "decision", "payload": {"question": "Actor or class?"}}
  Then  status is 200
  And   body contains {"ok": true}
  When  GET /api/events?type=decision
  Then  status is 200
  And   body is a JSON array with 1 entry
  And   entry[0].type is "decision"

Scenario: Data sync ingests a plan event
  Given the embedded server is running
  When  POST /api/data-sync {"type": "plan", "payload": {"title": "SPM migration"}}
  Then  status is 200
  When  GET /api/events?type=plan
  Then  body is a JSON array with 1 entry

Scenario: Events endpoint filters by type
  Given 3 events ingested: type=heartbeat, type=decision, type=plan
  When  GET /api/events?type=decision
  Then  body has exactly 1 entry with type=decision

Scenario: Events endpoint filters by projectId
  Given 2 events: projectId=proj-a, projectId=proj-b
  When  GET /api/events?projectId=proj-a
  Then  body has exactly 1 entry with projectId=proj-a

Scenario: Events endpoint respects limit
  Given 10 events ingested
  When  GET /api/events?limit=3
  Then  body has exactly 3 entries (most recent)

Scenario: Memory search returns relevant matches
  Given memory ingested with content "SwiftUI coordinator pattern"
  When  POST /api/memories/search {"query": "coordinator", "projectIds": []}
  Then  body is a JSON array with at least 1 entry

Scenario: Dead orchestrator routes return 404
  Given the embedded server is running
  When  GET /api/orchestrator/status
  Then  status is 404
  When  GET /api/orchestrator/board
  Then  status is 404

Scenario: Dead backlog routes return 404
  Given the embedded server is running
  When  GET /api/backlog
  Then  status is 404
  When  GET /api/backlog/count
  Then  status is 404

Scenario: Dead company routes return 404
  Given the embedded server is running
  When  GET /api/companies
  Then  status is 404

Scenario: Unknown routes return 404
  Given the embedded server is running
  When  GET /api/nonexistent
  Then  status is 404
  And   body contains "Not found"
```

## Waves

### Wave 1: Simplify InMemoryStore
- Remove dedicated `decisions`, `plans`, `contexts` collections
- Route ALL ingest types through `addEvent()` (unified events array)
- Keep `memories` separate (different query pattern -- text search)
- Remove `getDecisions()`, `getPlans()`, `getContexts()`, `updateDecision()` methods
- `getEvents(type:)` now serves all filtered queries

### Wave 2: Simplify ServerRoutes
- Remove all orchestrator routes (`/api/orchestrator/*`)
- Remove all company routes (`/api/companies*`)
- Remove all session transcript routes (`/api/session-transcripts*`)
- Remove all backlog routes (`/api/backlog*`)
- Remove decision-specific routes (`/api/decisions`, `/api/decision-queue/*`)
- Remove plan route (`/api/plans`)
- Remove context route (`/api/contexts`)
- Remove dead handler methods
- Keep exactly: `/health`, `/api/data-sync`, `/api/memories/search`, `/api/events`

### Wave 3: Tests
- Add `ServerRoutesTests.swift` with all TDDP scenarios
- Verify dead routes return 404
- Verify events filter by type, projectId, limit
- Run `swift test` -- fix any breakage
