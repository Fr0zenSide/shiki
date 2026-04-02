---
title: "Inbox v2 — Computed View over ShikiDB"
status: draft
priority: P0
project: shikki
created: 2026-04-02
updated: 2026-04-02
authors: "@Daimyo + @Sensei"
tags: [inbox, shikidb, dashboard, computed-view]
depends-on: [shikki-spec-tracking-fields.md, shikki-spec-metadata-v2.md]
relates-to: [shiki-knowledge-mcp.md, reports/radar-inbox-architecture-patterns-2026-04-02.md]
---

# Inbox v2 — Computed View over ShikiDB

> Replace 20 tmux windows with one command. ShikiDB entities ARE the inbox. No duplicate store, no fan-out.

---

## 1. Context

The current inbox is dead plumbing. Every source has a fragile dependency: PRs need `gh` auth (fails silently), specs scan the filesystem (slow, no cross-worktree), decisions/tasks/gates need the backend running (usually down during local dev). Nothing persists between invocations -- no dismiss, no lifecycle, no "I already looked at this" state. No `--project` filter. The result: tmux windows become the mental model. The inbox should replace that entirely.

---

## 2. Architecture: Computed View Pattern

Research across Linear, Plane, Huly, and Anytype (see radar report) shows Huly's event-bus + computed-view pattern maps directly to Shikki. Key insight: **inbox items are not a separate data store -- they are a query over existing ShikiDB entities with a thin read-state overlay**.

Why computed views beat materialized notifications:
- **No data duplication** -- specs, decisions, gates already live in ShikiDB. No second source of truth.
- **No fan-out cost** -- one user, no per-receiver rows (unlike Plane).
- **Never stale** -- priority computed at query time from live entity data.
- **Simpler schema** -- one small `inbox_read_state` table vs full `inbox_entries` with duplicated columns.

```
Event Bus (NATS) --> inbox subscribes to relevant subjects
ShikiDB entities (specs, decisions, gates) = source of truth
inbox_read_state = per-user overlay (read/snooze/archive timestamps)
shikki inbox = computed query: entities LEFT JOIN read_state
Priority = pure function(entity.age, entity.type, entity.urgency_weight)
```

---

## 3. Business Rules

```
BR-01: Inbox items are COMPUTED VIEWS over existing ShikiDB entities, not a separate store. inbox_read_state only tracks read/snooze/archive state per user.
BR-02: Three scopes -- personal (all), company (by slug), project (by slug). Default: personal.
BR-03: Every spec in draft/review/implementing status appears in inbox (specs table).
BR-04: Every pending decision appears in inbox (decisions table).
BR-05: Every pre-PR gate result appears in inbox (gates table, 7-day window).
BR-06: GitHub PR data is OPTIONAL. If gh fails, inbox still works. PRs in separate section.
BR-07: Urgency = pure function: age 0-40 + priority 0-30 + blocking 0-30 = 0-100. Never stored.
BR-08: Lifecycle: unread -> read (auto) -> snoozed (timed) or archived. All timestamps in read_state.
BR-09: `shikki inbox --count` returns in <100ms via COUNT query.
BR-10: Status line reads from `.shikki/inbox-count` cache, updated on each `shikki inbox` call.
BR-11: `shikki inbox --archive {type}:{id}` sets archived_at in inbox_read_state.
BR-12: Archived items auto-expire after 30 days.
BR-13: Board → inbox bridge: `shikki.agent.completed`, `shikki.agent.failed`, `shikki.agent.stuck` NATS events create inbox items automatically. Agent finished = "Review agent output", build failed = "Build broken on {branch}", rate limit = "{N} tasks queued, retry at {time}".
BR-14: `shikki.bg.result.*` events from `shi bg` background tasks create inbox items with the bg result summary.
```

## 3a. TDDP — Test-Driven Development Plan

| Test | BR | Tier | Type | Description |
|------|-----|------|------|-------------|
| T-01 | BR-01 | Core (80%) | Unit | Fresh inbox on empty DB returns "Inbox is empty.", exit 0 |
| T-02 | BR-03 | Core (80%) | Unit | Spec with status=review appears in computed query with type=spec |
| T-03 | BR-05,07 | Core (80%) | Unit | Gate with failures=3 gets urgency_weight=30, computed score >= 60 |
| T-04 | BR-08,11 | Core (80%) | Unit | `--archive spec:foo` sets archived_at, default view shows N-1 |
| T-05 | BR-02 | Core (80%) | Unit | `--project shikki` filters returns shikki items only |
| T-06 | BR-09,10 | Core (80%) | Unit | Count fast path returns correct count in <100ms |
| T-07 | BR-13 | Core (80%) | Integration | `spec.status_changed` NATS event creates read_state row with read_at=NULL |
| T-08 | BR-13 | Core (80%) | Integration | Existing archived row preserved on entity update (DO NOTHING) |
| T-09 | BR-08 | Core (80%) | Unit | Snooze lifecycle: hidden during snooze window, visible after expiry |
| T-10 | BR-06 | Core (80%) | Integration | ShikiDB unreachable — returns cached count or "unavailable" |
| T-11 | BR-04 | Core (80%) | Unit | Pending decisions appear in inbox computed query |
| T-12 | BR-12 | Core (80%) | Unit | Archived items auto-expire after 30 days |
| T-13 | BR-14 | Core (80%) | Integration | `shikki.bg.result.*` NATS event creates inbox item with bg summary |
| T-14 | BR-08 | Smoke (CLI) | Unit | `--snooze decision:42 --until 2h` sets snoozed_until correctly |

### S3 Test Scenarios

```
T-01 [BR-01, Core 80%]:
When querying inbox on an empty ShikiDB:
  → computed view returns zero rows
  → CLI prints "Inbox is empty."
  → exit code 0

T-02 [BR-03, Core 80%]:
When a spec exists with status=review:
  → computed UNION query includes spec in results
  → returned item has type=spec
  → title matches spec title from specs table

T-03 [BR-05,07, Core 80%]:
When a gate exists with failures=3:
  → urgency_weight set to 30 (blocking penalty)
  → age component computed from created_at
  → total computed score >= 60

T-04 [BR-08,11, Core 80%]:
When archiving an item with --archive spec:foo:
  → inbox_read_state.archived_at set to current timestamp
  → subsequent default inbox query returns N-1 items
  → archived item excluded by WHERE archived_at IS NULL

T-05 [BR-02, Core 80%]:
When filtering by project with --project shikki:
  → only entities where project='shikki' returned
  → entities from other projects (maya, brainy) excluded

T-06 [BR-09,10, Core 80%]:
When running shikki inbox --count:
  → COUNT query executes against computed view
  → result returned in <100ms
  → count written to ~/.shikki/inbox-count cache file

T-07 [BR-13, Core 80%]:
When spec.status_changed NATS event fires:
  → inbox_read_state row inserted for the spec entity
  → read_at is NULL (unread)
  → entity appears in next inbox query

T-08 [BR-13, Core 80%]:
When a NATS event fires for an already-archived entity:
  → INSERT ON CONFLICT DO NOTHING executes
  → existing archived_at timestamp preserved
  → entity remains archived in inbox view

T-09 [BR-08, Core 80%]:
When an item is snoozed with --snooze for 1 hour:
  if current time is within snooze window:
    → item hidden from default inbox query
  otherwise (snooze expired):
    → item visible again in inbox query
    → snoozed_until remains set (audit trail)

T-10 [BR-06, Core 80%]:
When ShikiDB is unreachable:
  if ~/.shikki/inbox-count cache exists:
    → cached count returned
  otherwise:
    → "unavailable" message displayed
    → exit code 0 (no crash)

T-11 [BR-04, Core 80%]:
When a pending decision exists in decisions table:
  → computed UNION query includes decision in results
  → returned item has type=decision
  → urgency_weight=30 (pending decisions are blocking)

T-12 [BR-12, Core 80%]:
When an archived item is older than 30 days:
  → auto-expiry sweep removes the inbox_read_state row
  → entity no longer appears in --archived view

T-13 [BR-14, Core 80%]:
When shikki.bg.result.* NATS event fires:
  → inbox_read_state row inserted with entity_type=bg_result
  → entity_id matches background task ID
  → item appears in inbox with bg result summary

T-14 [BR-08, Smoke CLI]:
When snoozing with --snooze decision:42 --until 2h:
  → snoozed_until set to now + 2 hours in inbox_read_state
  → decision:42 hidden from default inbox query for 2 hours
```

## 3b. Wave Dispatch Tree

```
Wave 1: Schema + Computed Query
  ├── inbox_read_state table migration
  ├── InboxQueryBuilder (UNION computed view)
  ├── InboxReadStateRepository (upsert/read/archive/snooze CRUD)
  └── Update InboxManager to use computed query
  Tests: T-01, T-02, T-03, T-04, T-05, T-06, T-09, T-11, T-12
  Gate: swift test --filter Inbox → all green

Wave 2: NATS Subscriber ← BLOCKED BY Wave 1
  ├── InboxSubscriber (spec/decision/gate/agent/bg subjects)
  ├── Insert-if-not-exists on event, preserve existing state
  └── Wire into ShikiCore event emission sites
  Tests: T-07, T-08, T-10, T-13
  Gate: swift test --filter Inbox → all green + NATS integration verified

Wave 3: CLI Enhancements ← BLOCKED BY Wave 1
  ├── --project, --company, --archive, --snooze flags
  ├── --archived flag for viewing archived items
  └── Status line cache: write .shikki/inbox-count
  Tests: T-05, T-14
  Gate: swift test --filter Inbox → all green

Wave 4: PR Sync + Polish ← BLOCKED BY Wave 2
  ├── PRSyncSource (gh pr list upsert, stale auto-archive)
  ├── --type multi-value filter
  └── 30-day archived expiry sweep
  Tests: T-12 (E2E)
  Gate: full swift test green + shikki inbox manual verification
```

---

## 4. Data Model

### inbox_read_state (ShikiDB)

```sql
CREATE TABLE inbox_read_state (
    user_id       TEXT NOT NULL,
    entity_type   TEXT NOT NULL,     -- 'spec', 'decision', 'gate', 'pr'
    entity_id     TEXT NOT NULL,     -- "shikki-inbox-v2", "gate:feature/foo"
    read_at       TIMESTAMPTZ,      -- NULL = unread
    snoozed_until TIMESTAMPTZ,      -- NULL = not snoozed
    archived_at   TIMESTAMPTZ,      -- NULL = active
    PRIMARY KEY (user_id, entity_type, entity_id)
);
CREATE INDEX idx_inbox_rs_active ON inbox_read_state(user_id) WHERE archived_at IS NULL;
```

### Computed inbox query (illustrative)

```sql
SELECT e.type, e.id, e.title, e.status, e.project, e.created_at, e.urgency_weight,
       rs.read_at, rs.snoozed_until, rs.archived_at
FROM (
    SELECT 'spec' AS type, slug AS id, title, status, project, created_at, 0 AS urgency_weight
      FROM specs WHERE status IN ('draft','review','implementing')
    UNION ALL
    SELECT 'decision', id::text, title, status, project, created_at, 30
      FROM decisions WHERE status = 'pending'
    UNION ALL
    SELECT 'gate', branch_slug, title, result, project, created_at,
           CASE WHEN failures > 0 THEN 30 ELSE 0 END
      FROM gates WHERE created_at > NOW() - INTERVAL '7 days'
) e
LEFT JOIN inbox_read_state rs ON rs.entity_type = e.type AND rs.entity_id = e.id AND rs.user_id = $1
WHERE rs.archived_at IS NULL
ORDER BY (LEAST(EXTRACT(EPOCH FROM NOW() - e.created_at)/3600 * 2.2, 40) + e.urgency_weight) DESC;
```

No read_state row = unread. Priority recalculated every query -- never stale.

---

## 5. Event-Driven Hydration

Inbox is a NATS subscriber. Events trigger `inbox_read_state` inserts for new entities only.

| NATS Subject | Trigger | Action |
|-------------|---------|--------|
| `shikki.spec.status_changed` | Spec -> draft/review/implementing | INSERT read_state if not exists |
| `shikki.decision.pending` | New decision | INSERT read_state if not exists |
| `shikki.gate.completed` | Gate run finishes | INSERT read_state if not exists |
| `shikki.agent.completed` | Agent finished work | INSERT read_state (type: agent_result) |
| `shikki.agent.failed` | Agent crashed/failed | INSERT read_state (type: agent_alert, urgency +30) |
| `shikki.agent.stuck` | Agent idle > threshold | INSERT read_state (type: agent_alert) |
| `shikki.bg.result.*` | Background task result | INSERT read_state (type: bg_result) |
| `shikki.ratelimit.*` | Rate limit hit | INSERT read_state (type: system_alert) |
| (on `shikki inbox`) | gh auth OK | PRSyncSource upserts; stale PRs (>7d) auto-archive |

```sql
INSERT INTO inbox_read_state (user_id, entity_type, entity_id)
VALUES ($1, $2, $3)
ON CONFLICT (user_id, entity_type, entity_id) DO NOTHING;
```

No update on conflict -- existing read/snooze/archive state wins. Initial hydration = computed query (no rows = everything unread).

---

## 6. CLI Interface

```
shikki inbox                                    # all items, personal scope
shikki inbox --company maya                     # maya company only
shikki inbox --project shikki                   # shikki project only
shikki inbox --type spec                        # specs only
shikki inbox --count                            # count only (fast path)
shikki inbox --archived                         # show archived items
shikki inbox --archive spec:shikki-inbox-v2     # archive an item
shikki inbox --snooze decision:42 --until 2h    # snooze for 2 hours
shikki inbox --json                             # JSON output for piping
```

Output format unchanged from v1 (type badge + urgency score + title + company tag + age).

---

## 7. Implementation Waves

### Wave 1: Schema + Computed Query (P0)
- **Files**: `ShikkiKit/Services/InboxQueryBuilder.swift`, `ShikkiKit/Services/InboxReadStateRepository.swift`, ShikiDB migration
- **Tests**: T-01, T-02, T-03, T-04, T-05, T-06, T-09, T-11, T-12
- **BRs**: BR-01, BR-02, BR-03, BR-04, BR-05, BR-07, BR-08, BR-09, BR-10, BR-11, BR-12
- **Deps**: ShikiDB (exists), InboxManager (exists)
- **Gate**: `swift test --filter Inbox` green

### Wave 2: NATS Subscriber (P0) ← BLOCKED BY Wave 1
- **Files**: `ShikkiKit/Services/InboxSubscriber.swift`, ShikiCore event wiring
- **Tests**: T-07, T-08, T-10, T-13
- **BRs**: BR-06, BR-13, BR-14
- **Deps**: Wave 1 (InboxReadStateRepository), NATSDispatcher (exists)
- **Gate**: `swift test --filter Inbox` green + NATS integration verified

### Wave 3: CLI Enhancements (P1) ← BLOCKED BY Wave 1
- **Files**: `Commands/InboxCommand.swift` (extend)
- **Tests**: T-05, T-14
- **BRs**: BR-02, BR-08
- **Deps**: Wave 1 (InboxQueryBuilder, InboxReadStateRepository)
- **Gate**: `swift test --filter Inbox` green

### Wave 4: PR Sync + Polish (P1) ← BLOCKED BY Wave 2
- **Files**: `ShikkiKit/Services/PRSyncSource.swift`
- **Tests**: T-12 (E2E)
- **BRs**: BR-06, BR-12
- **Deps**: Wave 2 (InboxSubscriber), `gh` CLI
- **Gate**: full `swift test` green + `shikki inbox` manual verification

---

## 8. Test Scenarios

| # | Scenario | Action | Expect |
|---|----------|--------|--------|
| T-01 | Fresh inbox empty | `shikki inbox` on empty DB | "Inbox is empty.", exit 0 |
| T-02 | Spec in inbox | Spec with status=review | Returned with type=spec |
| T-03 | Gate failure = high priority | Gate with failures=3 | urgency_weight=30, score >= 60 |
| T-04 | Archive hides item | `--archive spec:foo` | Default view shows N-1 |
| T-05 | Project filter | Items for shikki + maya | `--project shikki` returns shikki only |
| T-06 | Count fast path | 50 entities | Returns 50 in <100ms |
| T-07 | NATS creates unread | spec.status_changed fires | read_state row, read_at=NULL |
| T-08 | State preserved | Archived item, spec updates | archived_at unchanged (DO NOTHING) |
| T-09 | Snooze lifecycle | Snooze 1h | Hidden during, visible after |
| T-10 | DB down fallback | ShikiDB unreachable | Cached count or "unavailable" |

---

## 9. Migration from v1

v1 `InboxDataSource` conformers remain as fallback during Wave 1-2. Once computed query is stable, `InboxManager` switches primary read. v1 sources become bootstrap-only, marked `@available(*, deprecated)`. `InboxItem` model unchanged; `InboxFilters` gains `projectSlug`.

---

## 10. @shi Mini-Challenge

1. **@Ronin**: NATS subscriber down when event fires? Computed query still returns the entity (no read_state = unread), so no data loss. "New" item may be old. JetStream replay for v3?
2. **@Katana**: UNION ALL + LEFT JOIN on every read -- fast enough for <100ms with 500+ specs? WHERE clauses tight, read_state tiny. Benchmark after Wave 1.
3. **@Sensei**: `.shikki/inbox-count` goes stale between calls. NATS daemon to keep warm = v3?
