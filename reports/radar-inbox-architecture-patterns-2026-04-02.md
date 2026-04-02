# Inbox Architecture Patterns — Research Report

**Date**: 2026-04-02
**Scope**: Linear, Plane, Huly, Anytype — architecture extraction for Shikki CLI inbox
**Method**: Source code analysis (Plane, Huly, Anytype repos) + public docs (Linear)

---

## 1. Linear — The Speed Benchmark

### Architecture (from public talks + docs)
- **Client-side sync engine**: Full dataset replicated to client IndexedDB. Queries run locally — zero network roundtrips for reads.
- **WebSocket delta sync**: Server pushes incremental changes via persistent WebSocket. Client applies deltas to local store.
- **Optimistic mutations**: All writes apply instantly to local state, then sync to server. Rollback on conflict.
- **Inbox model**: Subscription-based. Auto-subscribe on create/assign/mention. All subscribed issue events flow to inbox. Hard cap: 500 items.

### Key Patterns
| Aspect | Pattern |
|--------|---------|
| Data flow | WebSocket push (server -> client deltas) |
| State mgmt | Full local replica + delta sync |
| Priority | Chronological, no computed priority — user triages manually |
| Presentation | Minimal: title + actor + action + timestamp. Keyboard-first (J/K nav) |
| Architecture | **Local-first with sync** — reads never hit server |

### Inbox States
`unread` -> `read` (auto on view) -> `snoozed` (timed return) or `archived` (gone). No separate "done" state.

---

## 2. Plane — The Django/Celery Pipeline

### Data Model (from `plane/db/models/notification.py`)
```
Notification:
  workspace, project (FK)
  entity_identifier (UUID)  — points to Issue
  entity_name (string)      — "issue"
  title, message, message_html, message_stripped
  sender (string)           — action type ("mentioned", "assigned", etc.)
  triggered_by (FK User)
  receiver (FK User)
  read_at, snoozed_till, archived_at (nullable timestamps)
  data (JSON)               — arbitrary payload
```

**7 composite indexes** on receiver+workspace+state combinations for fast filtered queries.

### Notification Pipeline (from `notification_task.py`)
1. **Celery task** triggered on issue mutation (state change, comment, assignment, mention)
2. Task diffs old vs new issue state, computes affected users (assignees, subscribers, mentioned)
3. Creates `Notification` rows per receiver with JSON diff payload
4. Separate `EmailNotificationLog` for async email batching
5. Client polls via REST API with cursor pagination (300 per page)

### Inbox Store (from `project-inbox.store.ts` + `workspace-notifications.store.ts`)
- **MobX observable store** with cursor-based pagination
- Filters: `type` (assigned/created/subscribed), `snoozed`, `archived`, `read`
- Sorting: `snoozed_till` first, then `created_at DESC`
- **No WebSocket** — uses SWR (stale-while-revalidate) HTTP polling with `revalidateOnFocus`

### Key Patterns
| Aspect | Pattern |
|--------|---------|
| Data flow | Celery async task on mutation -> DB rows -> REST poll |
| State mgmt | Server-side notifications table, client MobX cache |
| Priority | No computed priority. Filter by type (assigned > subscribed) |
| Presentation | Issue title + actor + diff summary + relative time |
| Architecture | **CQRS-lite**: write side (Celery tasks) separate from read side (paginated API) |

---

## 3. Huly — The Event Bus Reference Architecture

### Architecture (from `ARCHITECTURE_OVERVIEW.md` + source)
**30+ microservices** with Redpanda (Kafka) as central event bus.

**Core flow**:
```
Transactor (WebSocket) --> Redpanda (Kafka topics) --> Consumers
                                                       ├── Fulltext (search indexing)
                                                       ├── HulyGun (event processor)
                                                       ├── Process (automation)
                                                       └── Media (processing)
```

- **Transactor**: Maintains WebSocket connections, processes all mutations, publishes events to Redpanda
- **HulyPulse**: WebSocket notification push server, backed by Redis pub/sub
- **CockroachDB**: All persistent state (ACID, distributed SQL)

### Notification Architecture (from source code)

**Event-driven trigger system**:
```
Message created -> notify() trigger
  -> iterate collaborators (cursor-batched, 500/batch)
  -> for each: create/update NotificationContext + create Notification event
  -> events flow through middleware pipeline
  -> BroadcastMiddleware matches events to active WebSocket sessions
```

**Data model**:
```
NotificationContext:
  id, cardId, account
  lastUpdate, lastView, lastNotify (Date)
  notifications[] (lazy-loaded)

Notification:
  id, contextId, cardId, account
  type (Message | Reaction)
  read (boolean)
  content { title, shortText, senderName }
  messageId, creator, blobId
  created (Date)
```

**Key: NotificationContext is the aggregation unit** — groups all notifications for one card (issue/channel) per user. `lastView` vs `lastUpdate` timestamps determine read/unread without scanning individual notifications.

### Middleware Chain
```
BroadcastMiddleware
  -> tracks active sessions + their card subscriptions
  -> on event: matches event to subscribed sessions
  -> pushes filtered events only to relevant WebSocket clients
```

### Key Patterns
| Aspect | Pattern |
|--------|---------|
| Data flow | Transactor -> Redpanda (Kafka) -> trigger functions -> notification events -> WebSocket push |
| State mgmt | NotificationContext (aggregation) + individual Notifications in CockroachDB |
| Priority | Implicit: lastNotify timestamp. No explicit priority scoring |
| Presentation | shortText (100 chars) + senderName + title (from card) |
| Architecture | **Event sourcing + reactive subscriptions** — notifications are derived from the event stream |

---

## 4. Anytype — The Local-First CRDT Model

### Architecture (from `any-sync` README + source)
- **CRDT-based DAGs**: All data stored as encrypted Directed Acyclic Graphs
- **any-sync protocol**: P2P sync of encrypted spaces. Each device independently applies and cryptographically verifies CRDT updates
- **Service Locator DI**: `any-sync/app` package for component registration
- **Subscription model**: `subscriptionTracker` per object type (properties, types, tags) with message buffer queues (`mb.MB[*pb.EventMessage]`)

### Local-First Sync Model
```
Local state (any-store)
  -> Changes as CRDT ops in DAG
  -> Encrypted, signed per-device
  -> Sync via any-sync-node (relay)
  -> Conflict resolution: CRDT merge (no consensus needed)
```

### Event Propagation (from `state/event.go`)
- Events are **protobuf messages** (`pb.EventMessage`) with typed value variants
- State applies events via pattern matching on event type (BlockSetText, BlockSetFile, etc.)
- Each block type has its own `ApplyEvent` method — visitor pattern

### Notification Object
- `NotificationObject` wraps a `SmartBlock` — notifications are first-class objects in the same data model as pages, databases, etc.
- Uses migration system for schema evolution

### Key Patterns
| Aspect | Pattern |
|--------|---------|
| Data flow | Local CRDT ops -> DAG -> encrypted P2P sync |
| State mgmt | Local-first: all state on device, sync is background |
| Priority | N/A — Anytype doesn't have a traditional inbox/priority system |
| Presentation | Objects are blocks with typed content |
| Architecture | **CRDT event log + local-first storage** — every change is a signed, encrypted DAG node |

---

## Synthesis: Patterns for Shikki CLI Inbox

### The Huly Pattern Wins

Huly's architecture maps almost 1:1 to Shikki's existing infrastructure:

| Huly | Shikki Equivalent |
|------|-------------------|
| Redpanda (Kafka) | NATS event bus |
| Transactor (event producer) | ShikiCore lifecycle events |
| CockroachDB | ShikiDB (PostgreSQL) |
| HulyPulse (WebSocket push) | CLI subscriber / TUI |
| Trigger functions | ShikiEvent handlers |
| NotificationContext | Computed view from ShikiDB |

### Recommended Architecture

**Inbox = Event Bus Subscriber + Computed View**

```
ShikiCore/Services emit ShikiEvents
  -> NATS subjects (spec.*, pipeline.*, review.*, etc.)
  -> InboxSubscriber listens to relevant subjects
  -> On event: upsert into ShikiDB `inbox_items` table
  -> CLI reads: query ShikiDB with filters/sorting
  -> State is ALWAYS queryable from DB (no separate inbox store)
```

**Three-layer design**:

1. **Event Ingestion Layer** — NATS subscriber with subject filters. Maps each `ShikiEvent` to an `InboxItem` via a pure function. No business logic here, just event-to-item transformation.

2. **State Layer** — ShikiDB table. NOT a separate notification store. The inbox IS a filtered, sorted query over existing ShikiDB data (specs, pipelines, reviews) enriched with per-user read/snooze/archive timestamps. Follows Huly's `NotificationContext` pattern: one context row per (user, entity) pair with `lastView`/`lastUpdate` timestamps to compute unread status without scanning individual events.

3. **Presentation Layer** — CLI renders from query results. Minimal display: `[priority-icon] entity-type: title — actor — relative-time`. Keyboard-driven triage (Linear's J/K/U/H pattern). No pagination in CLI — show top N, `--all` flag for full list.

### Why NOT the other patterns:

- **Linear's full local replica**: Overkill for CLI. We don't need IndexedDB or offline-first — ShikiDB is always local.
- **Plane's Celery polling**: Too much infrastructure for a CLI tool. NATS gives us push for free.
- **Anytype's CRDT DAG**: Designed for multi-device P2P sync we don't need. Our single-node ShikiDB is the source of truth.

### Key Design Decisions

1. **No separate notification table** — inbox items are computed views. A spec changing state IS the notification. The inbox query joins `specs` + `pipeline_runs` + `reviews` with a thin `inbox_read_state` table (user_id, entity_id, entity_type, read_at, snoozed_till, archived_at).

2. **NATS subject hierarchy for filtering** — subscribe to `shikki.event.spec.>` for spec events, `shikki.event.pipeline.>` for pipeline events. User preferences map to NATS subject filters.

3. **Priority is computed, not stored** — urgency = f(entity_type, state, age, user_role). Spec blocked > pipeline failed > review requested > FYI. Recalculated on query, never stale.

4. **Batch triage** — Linear's keyboard model adapted for CLI: `shikki inbox` shows list, arrow keys + single-key actions (r=read, s=snooze, a=archive, enter=open).

### Data Model

```sql
-- Thin state table (NOT a full notification store)
CREATE TABLE inbox_read_state (
  user_id     TEXT NOT NULL,
  entity_id   TEXT NOT NULL,
  entity_type TEXT NOT NULL,  -- 'spec', 'pipeline', 'review', 'gate'
  read_at     TIMESTAMPTZ,
  snoozed_till TIMESTAMPTZ,
  archived_at  TIMESTAMPTZ,
  PRIMARY KEY (user_id, entity_id, entity_type)
);

-- Inbox query: computed view, not stored
-- SELECT from specs/pipelines/reviews
-- LEFT JOIN inbox_read_state
-- ORDER BY computed_priority DESC, event_time DESC
```

### What Makes This Fast

- **Reads are local SQL** (Linear's key insight, applied to ShikiDB)
- **Writes are event-driven** (Huly's key insight, applied to NATS)
- **No notification fan-out** (unlike Plane's per-receiver row creation)
- **Priority is a pure function** (no stored state to drift)
