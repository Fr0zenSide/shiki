---
title: "Inbox v2 — ShikiDB-Backed Priority Dashboard"
status: draft
priority: P0
project: shikki
created: 2026-04-02
authors: "@Daimyo + @Sensei"
tags:
  - inbox
  - shikidb
  - dashboard
  - productivity
depends-on:
  - shikki-spec-tracking-fields.md (test-run-id, validated-commit)
  - shikki-spec-metadata-v2.md (frontmatter lifecycle)
relates-to:
  - shiki-knowledge-mcp.md (ShikiDB event/search API)
  - spec-backlog-inbox-managers.md (v1 inbox architecture)
---

# Inbox v2 — ShikiDB-Backed Priority Dashboard

> Replace 20 tmux windows with one command. ShikiDB is the brain, `shikki inbox` is the view.

---

## 1. Context

The current inbox is dead plumbing. Every source has a fragile dependency: PRs need `gh` auth (fails silently), specs scan the filesystem (slow, no cross-worktree), decisions/tasks/gates need the backend running (usually down during local dev). Nothing persists between invocations -- no dismiss, no lifecycle, no "I already looked at this" state. No `--project` filter exists, so a user working on shikki cannot filter out maya noise. The result: the user opens tmux windows to "remember" what is in flight. The inbox should replace that mental model entirely.

---

## 2. Business Rules

```
BR-01: ALL inbox items MUST be stored in ShikiDB as InboxEntry records. No filesystem, no gh CLI, no backend dependency for reads.
BR-02: Three scope levels — personal (all items), company (filtered by company slug), project (filtered by project slug). Default is personal.
BR-03: Every spec in draft/review/implementing status MUST auto-create an inbox item on status change. Source: spec_status_changed events in ShikiDB.
BR-04: Every pending decision event MUST auto-create an inbox item. Source: decision_pending events in ShikiDB.
BR-05: Every pre-PR gate result (pass or fail) MUST auto-create an inbox item. Source: gate_completed events in ShikiDB.
BR-06: GitHub PR data is an OPTIONAL feed. If gh is not authenticated or returns errors, the inbox still works. PR items appear in a separate "GitHub" section, hidden if empty.
BR-07: Urgency scoring uses the existing UrgencyCalculator (age 0-40 + priority 0-30 + blocking 0-30 = 0-100). No changes to the formula.
BR-08: Inbox items follow a lifecycle: pending -> in-review -> validated -> dismissed. Dismissed items are hidden from default view but queryable with --dismissed.
BR-09: `shikki inbox --count` MUST return in <100ms by querying a ShikiDB count endpoint, not fetching all items.
BR-10: The status line (prompt integration) MUST show inbox count without blocking the shell. Reads from a local cache file updated on each `shikki inbox` call.
BR-11: `shikki inbox --dismiss {type}:{id}` transitions an item to dismissed status in ShikiDB.
BR-12: Dismissed items auto-expire after 30 days (ShikiDB retention policy).
```

---

## 3. Data Model — InboxEntry (ShikiDB)

Stored in a new `inbox_entries` table, accessed via `shiki_save_event` / `shiki_search`.

```sql
CREATE TABLE inbox_entries (
    id          TEXT PRIMARY KEY,        -- "spec:shikki-inbox-v2"
    type        TEXT NOT NULL,           -- pr, decision, spec, task, gate
    title       TEXT NOT NULL,
    subtitle    TEXT,
    status      TEXT NOT NULL DEFAULT 'pending',  -- pending, in-review, validated, dismissed
    project     TEXT,                    -- "shikki", "maya", "wabisabi"
    company     TEXT,                    -- company slug for multi-company filtering
    urgency     INTEGER NOT NULL,        -- 0-100 composite score
    is_blocking BOOLEAN DEFAULT FALSE,
    metadata    JSONB,                   -- type-specific fields
    source_event TEXT,                   -- ShikiDB event ID that created this entry
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    dismissed_at TIMESTAMPTZ            -- NULL until dismissed
);

CREATE INDEX idx_inbox_status ON inbox_entries(status) WHERE status != 'dismissed';
CREATE INDEX idx_inbox_project ON inbox_entries(project);
CREATE INDEX idx_inbox_company ON inbox_entries(company);
```

Maps to the existing `InboxItem` Swift model. The v1 `InboxItem` struct stays unchanged -- `InboxEntry` is the DB-side representation, and `InboxManager` maps between them.

---

## 4. CLI Interface

```
shikki inbox                            # all items, personal scope
shikki inbox --company maya             # maya company only
shikki inbox --project shikki           # shikki project only
shikki inbox --type spec                # specs only
shikki inbox --count                    # count only (fast path)
shikki inbox --dismissed                # show dismissed items
shikki inbox --dismiss spec:shikki-inbox-v2   # dismiss an item
shikki inbox --json                     # JSON output for piping
```

Output format unchanged from v1 (type badge + urgency score + title + company tag + age).

---

## 5. Event-Driven Ingestion

Instead of polling sources at read time (v1), inbox v2 reacts to ShikiDB events via reactors.

| Event | Reactor | Inbox Entry ID | Blocking? |
|-------|---------|----------------|-----------|
| `spec_status_changed` (draft/review/implementing) | `SpecStatusReactor` | `spec:{slug}` | No |
| `spec_status_changed` (validated/shipped) | `SpecStatusReactor` | updates to `validated` | -- |
| `decision_pending` | `DecisionReactor` | `decision:{id}` | Yes (tier-1) |
| `gate_completed` | `GateReactor` | `gate:{branch-slug}` | Yes (if failures > 0) |
| `gh pr list` (optional sync) | `PRSyncSource` | `pr:{number}` | No |

Gate and PR entries use upsert -- latest result wins. PR sync runs on `shikki inbox` only if `gh auth status` succeeds; stale PRs (>7 days, no matching open PR) auto-dismiss.

---

## 6. Implementation Waves

### Wave 1: ShikiDB Schema + InboxEntry CRUD (P0)
- Define `inbox_entries` table in ShikiDB migration
- `InboxEntryRepository` with create/upsert/query/dismiss methods
- Wire to `shiki_save_event` and `shiki_search` MCP tools
- Update `InboxManager` to read from ShikiDB instead of live sources
- **Files**: `InboxEntryRepository.swift`, `InboxManager.swift`, ShikiDB migration
- **Tests**: 4 (CRUD operations, filter queries, dismiss lifecycle, count fast path)

### Wave 2: Event Reactors (P0)
- `SpecStatusReactor` — listens for `spec_status_changed`, upserts inbox entry
- `DecisionReactor` — listens for `decision_pending`, creates inbox entry
- `GateReactor` — listens for `gate_completed`, upserts inbox entry
- Wire reactors into existing event posting sites (`SpecReviewCommand`, `DecideCommand`, `PrePRGates`)
- **Files**: `SpecStatusReactor.swift`, `DecisionReactor.swift`, `GateReactor.swift`
- **Tests**: 3 (one per reactor: event in -> inbox entry created with correct fields)

### Wave 3: CLI Enhancements (P1)
- Add `--project` filter to `InboxCommand`
- Add `--dismiss` subcommand
- Add `--dismissed` flag
- Status line cache: write `.shikki/inbox-count` on every `shikki inbox` call
- **Files**: `InboxCommand.swift`, `InboxFilters.swift`
- **Tests**: 2 (project filter, dismiss round-trip)

### Wave 4: PR Sync + Polish (P1)
- `PRSyncSource` — upserts PR inbox entries from `gh pr list` on demand
- Stale PR auto-dismiss (>7 days since last sync, no matching open PR)
- `--type` accepts multiple values
- Dismissed item expiry (30-day retention)
- **Files**: `PRSyncSource.swift`, `InboxCommand.swift`
- **Tests**: 2 (PR sync upsert, stale auto-dismiss)

---

## 7. Test Scenarios

| # | Scenario | Setup | Action | Expect |
|---|----------|-------|--------|--------|
| T-01 | Fresh inbox empty | Empty `inbox_entries` | `shikki inbox` | "Inbox is empty.", exit 0 |
| T-02 | Spec status creates entry | Spec transitions draft->review | `SpecStatusReactor` processes event | Entry id=`spec:shikki-inbox-v2`, status=pending |
| T-03 | Gate failure = blocking | pre-PR fails 2 gates | `GateReactor` processes event | Entry is_blocking=true, urgency >= 60 |
| T-04 | Dismiss hides item | 3 items exist | `--dismiss spec:shikki-inbox-v2` | Item dismissed, default view shows 2 |
| T-05 | Project filter works | Items for shikki + maya | `--project shikki` | Only shikki items returned |
| T-06 | Count fast path | 50 items | `--count` | Returns count in <100ms |
| T-07 | PR sync upserts | gh returns #42, #43; pr:42 exists | `PRSyncSource` runs | pr:42 updated, pr:43 created, total=2 |
| T-08 | Urgency calculation | age=18h, priority=25, blocking=false | `UrgencyCalculator.score` | 30 + 25 + 0 = 55 |
| T-09 | Stale PR auto-dismiss | pr:99 last synced 8d ago, not in gh | `PRSyncSource` runs | pr:99 dismissed |
| T-10 | ShikiDB down fallback | ShikiDB unreachable | `shikki inbox` | Cached count or "unavailable", no crash |

---

## 8. Migration from v1

v1 `InboxDataSource` conformers remain as fallback during Wave 1-2. Once reactors are stable, `InboxManager` switches primary read to ShikiDB. v1 sources become bootstrap-only (seed DB on first install), marked `@available(*, deprecated)`. `InboxItem` model unchanged; `InboxFilters` gains `projectSlug` alongside `companySlug`.

---

## 9. @shi Mini-Challenge

1. **@Ronin**: The reactor pattern means inbox entries are created as side effects of other commands. What happens when a reactor fails silently? A spec transitions to `review` but the inbox entry is never created. Should reactors be fire-and-forget, or should command execution fail if the inbox write fails? Recommendation: fire-and-forget with a retry queue (logged to ShikiDB as `reactor_failure` event).

2. **@Katana**: Dismissed items have a 30-day retention. But what about inbox entries for specs that are actively being worked on for months? A user dismisses a draft spec, then 31 days later the spec moves to `review` — should a new inbox entry be created, or should the dismissed one be resurrected? The upsert pattern (keyed on `id`) means the reactor would update the dismissed entry back to `pending`, which is correct. But verify the upsert does not lose the original `created_at`.

3. **@Sensei**: The status line cache (`.shikki/inbox-count`) is a file written on every `shikki inbox` call. This means the count goes stale between calls. Alternative: a lightweight daemon that subscribes to ShikiDB events and keeps the cache file warm. But that adds a process to manage. Is the stale-on-read tradeoff acceptable for v2, with a daemon as a v3 enhancement?
