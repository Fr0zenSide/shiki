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
- `inbox_read_state` table migration in ShikiDB
- `InboxQueryBuilder` -- computed UNION query with filters
- `InboxReadStateRepository` -- upsert/read/archive/snooze CRUD
- Update `InboxManager` to use computed query instead of live source polling
- **Tests**: 4 (query correctness, project filter, archive hides, count fast path)

### Wave 2: NATS Subscriber (P0)
- `InboxSubscriber` -- subscribes to `shikki.spec.*`, `shikki.decision.*`, `shikki.gate.*`
- On event: insert-if-not-exists into `inbox_read_state`, preserve existing state
- Wire into ShikiCore event emission sites
- **Tests**: 3 (new entity = unread row, existing row preserved, unknown event ignored)

### Wave 3: CLI Enhancements (P1)
- `--project`, `--company` filters, `--archive`, `--snooze` subcommands, `--archived` flag
- Status line cache: write `.shikki/inbox-count` on every call
- **Tests**: 2 (project filter, archive round-trip)

### Wave 4: PR Sync + Polish (P1)
- `PRSyncSource` -- upserts from `gh pr list` on demand, stale auto-archive (>7d)
- `--type` accepts multiple values, 30-day archived expiry
- **Tests**: 2 (PR sync upsert, stale auto-archive)

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
