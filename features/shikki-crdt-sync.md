---
title: "CRDT Sync — Automerge-Powered Conflict-Free Multi-User Collaboration"
status: draft
priority: P0
project: shikki
created: 2026-04-04
authors: ["@Daimyo"]
tags: [crdt, automerge, sync, collaboration, distributed, conflict-resolution]
depends-on: [shikki-distributed-sync.md, shikki-nats-client-wiring.md]
relates-to: [shikki-v1-architecture-epic.md]
epic-branch: feature/crdt-sync
validated-commit: —
test-run-id: —
---

# Feature: CRDT Sync — Automerge-Powered Conflict-Free Multi-User Collaboration
> Created: 2026-04-04 | Status: Draft | Owner: @Daimyo

## Context

Jeoffrey and Faustin work on the same specs, backlog items, tasks, and decisions constantly — often simultaneously, often offline. LWW (Last-Writer-Wins) loses data: if both edit the same item, one edit vanishes. This is not acceptable. CRDT (Conflict-free Replicated Data Types) guarantees every edit is preserved and merged mathematically — no data loss, no manual conflict resolution, no merge UI.

### Why Automerge

| Library | Engine | Types | Sync Protocol | Text CRDT | Status |
|---|---|---|---|---|---|
| **automerge-swift** | Rust FFI | Map, List, Text, Counter | Built-in | Yes | 0.7.2, active, MIT |
| heckj/CRDT | Pure Swift | GCounter, ORSet, LWWRegister | None | No | 0.5.0-alpha, stale |
| loro-swift | Rust FFI | Map, List, Tree, Text (Fugue) | None (transport-level) | Yes (superior) | 1.10.3, experimental API |

Automerge is the only library with ALL of: sync protocol, text CRDT, binary format, cross-language interop (JS, Rust, Python, Go, Swift), and active maintenance.

## How It Works

```
Jeoffrey edits spec #42 offline     Faustin edits spec #42 offline
  title: "Fix auth"                   title: "Fix authentication"
  adds tag: "security"                adds tag: "p0"
  writes paragraph in body            edits different paragraph
       │                                    │
       └──── both reconnect ────────────────┘
                    │
              Automerge merge:
                title: "Fix authentication"  (LWW by actor timestamp)
                tags: ["security", "p0"]     (OR-Set union — BOTH kept)
                body: both paragraphs merged (Text CRDT — character-level)
                
              Zero data loss. Zero manual merge. Automatic.
```

## Business Rules

```
BR-01: Every syncable entity (spec, backlog, task, decision, memory) MUST be stored as an Automerge Document
BR-02: automerge-swift (0.7.x) MUST be added as SPM dependency — Rust core via FFI
BR-03: Each user device MUST have a unique actor ID (UUID) registered with the Automerge document
BR-04: Entity fields MUST map to Automerge types:
       - Scalar fields (status, priority, assignee, title) → Automerge Map keys (LWW per key)
       - Collection fields (tags, labels, watchers) → Automerge List (OR-Set behavior)
       - Text fields (body, description, notes) → Automerge Text (character-level merge)
       - Numeric fields (budget, time_spent) → Automerge Counter (increment/decrement)
BR-05: Local edits MUST be applied to the local Automerge document instantly (offline-first)
BR-06: On save, incremental changes MUST be broadcast to NATS: shikki.crdt.change.{entityType}.{entityId}
BR-07: Other online nodes MUST apply received changes via doc.load_incremental(bytes) — auto-merge
BR-08: NATS JetStream MUST persist change streams — offline nodes replay missed changes on reconnect
BR-09: PostgreSQL MUST store the Automerge binary document as BYTEA alongside denormalized queryable columns
BR-10: Server-side merge: on receiving changes, load server doc + merge incoming doc + extract queryable fields + upsert
BR-11: Denormalized columns (status, priority, tags, title) MUST be extracted after every merge for SQL queryability
BR-12: Full CRDT doc MUST only be loaded when editing or merging — queries use denormalized columns
BR-13: Automerge SyncState per peer MUST be persisted locally for efficient reconnection (bloom filter, not full resend)
BR-14: shi sync MUST trigger full Automerge sync protocol with server (for catching up after long offline)
BR-15: Document history MUST be preserved — Automerge stores full operation history for audit/undo/time-travel
```

## Entity → Automerge Mapping

```
Spec Document (Automerge Map at root):
  ├── title: String (LWW)
  ├── status: String (LWW) — "draft" | "implementing" | "done"
  ├── priority: String (LWW) — "P0" | "P1" | "P2"
  ├── assignee: String (LWW)
  ├── tags: List<String> (OR-Set behavior)
  ├── body: Text (character-level collaborative editing)
  ├── wave_count: Counter
  ├── test_count: Counter
  └── updated_at: String (LWW, ISO8601)

Backlog Item (Automerge Map at root):
  ├── title: String (LWW)
  ├── status: String (LWW)
  ├── priority: String (LWW)
  ├── assignee: String (LWW)
  ├── tags: List<String> (OR-Set)
  ├── description: Text (collaborative)
  └── estimated_hours: Counter

Task (Automerge Map at root):
  ├── title: String (LWW)
  ├── status: String (LWW)
  ├── assignee: String (LWW)
  ├── project: String (LWW)
  └── notes: Text (collaborative)

Decision (Automerge Map at root):
  ├── question: String (LWW)
  ├── answer: String (LWW)
  ├── context: Text (collaborative)
  ├── decided_by: String (LWW)
  └── tags: List<String> (OR-Set)
```

## PostgreSQL Schema

```sql
CREATE TABLE crdt_entities (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entity_type  TEXT NOT NULL,        -- 'spec', 'backlog', 'task', 'decision'
    entity_key   TEXT NOT NULL,        -- 'shikki-dry-enforcement', 'p0-fixengine'
    tenant_id    TEXT NOT NULL,        -- 'obyw', 'shikki' (multi-tenant)

    -- CRDT document (Automerge binary blob)
    crdt_doc     BYTEA NOT NULL,

    -- Denormalized queryable fields (extracted after every merge)
    status       TEXT,
    priority     TEXT,
    assignee     TEXT,
    title        TEXT,
    tags         TEXT[],
    
    -- Metadata
    last_actor   TEXT NOT NULL,
    version      BIGINT NOT NULL DEFAULT 0,
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE(tenant_id, entity_type, entity_key)
);

CREATE INDEX idx_crdt_type_status ON crdt_entities(tenant_id, entity_type, status);
CREATE INDEX idx_crdt_tags ON crdt_entities USING GIN(tags);
CREATE INDEX idx_crdt_assignee ON crdt_entities(tenant_id, assignee);

-- TimescaleDB hypertable for change history (audit trail)
CREATE TABLE crdt_changes (
    id           UUID DEFAULT gen_random_uuid(),
    entity_id    UUID NOT NULL REFERENCES crdt_entities(id),
    actor_id     TEXT NOT NULL,
    change_bytes BYTEA NOT NULL,      -- Automerge incremental save
    occurred_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
SELECT create_hypertable('crdt_changes', 'occurred_at', chunk_time_interval => INTERVAL '7 days');
```

## NATS Integration

```
Subjects:
  shikki.{tenant}.crdt.change.{entityType}.{entityId}   — incremental changes (broadcast)
  shikki.{tenant}.crdt.sync.{entityType}.{entityId}     — full sync protocol (request-reply)

JetStream Streams:
  CRDT_{TENANT} — subjects: shikki.{tenant}.crdt.change.>
  Retention: 30 days or 10GB (whichever first)
  Replay: on reconnect, consumer replays from last acknowledged sequence
```

### Change Broadcast Flow (normal operation)

```swift
// After local edit:
let changes = doc.encodeChangesSince(heads: lastSyncedHeads)
try await nats.publish(
    subject: "shikki.\(tenant).crdt.change.\(entityType).\(entityId)",
    data: changes
)
lastSyncedHeads = doc.heads()

// On receiving changes from other user:
for await message in nats.subscribe(subject: "shikki.\(tenant).crdt.change.\(entityType).>") {
    try doc.applyEncodedChanges(message.data)
    // Auto-merged — UI updates if visible
}
```

### Full Sync Protocol (after long offline)

```swift
// Reconnect after 3 days offline — use Automerge's built-in sync:
var syncState = loadPersistedSyncState(peerId: "server")

while true {
    guard let message = doc.generateSyncMessage(state: &syncState) else { break }
    let response = try await nats.request(
        subject: "shikki.\(tenant).crdt.sync.\(entityType).\(entityId)",
        data: Data(message),
        timeout: .seconds(10)
    )
    try doc.receiveSyncMessage(state: &syncState, message: response.data)
}

persistSyncState(syncState, peerId: "server")
```

## TDDP — Test Summary Table

| Test | BR | Tier | Type | Scenario |
|------|-----|------|------|----------|
| T-01 | BR-01 | Core (80%) | Unit | When creating entity → Automerge Document created |
| T-02 | BR-04 | Core (80%) | Unit | When setting scalar field → LWW in Automerge Map |
| T-03 | BR-04 | Core (80%) | Unit | When adding tag → OR-Set preserves both on merge |
| T-04 | BR-04 | Core (80%) | Unit | When editing text body → character-level merge |
| T-05 | BR-04 | Core (80%) | Unit | When incrementing counter → both increments preserved |
| T-06 | BR-05, BR-07 | Core (80%) | Unit | When two users edit same entity → merge preserves both changes |
| T-07 | BR-06 | Core (80%) | Unit | When saving locally → incremental changes broadcast to NATS |
| T-08 | BR-08 | Core (80%) | Integration | When user offline → JetStream replays missed changes on reconnect |
| T-09 | BR-09, BR-10 | Core (80%) | Unit | When merging on server → BYTEA updated + denormalized columns extracted |
| T-10 | BR-11 | Core (80%) | Unit | When querying entities → SQL uses denormalized columns, not CRDT blob |
| T-11 | BR-13 | Core (80%) | Unit | When reconnecting → SyncState loaded, efficient bloom filter exchange |
| T-12 | BR-15 | Core (80%) | Unit | When requesting history → full operation history from Automerge doc |

### S3 Test Scenarios

```
T-01 [BR-01, Core 80%]:
When creating a new spec entity:
  → Automerge Document created with unique actor ID
  → root is a Map with keys: title, status, priority, tags, body
  → doc.save() produces non-empty Data

T-02 [BR-04, Core 80%]:
When setting status on a spec:
  → doc.put(obj: .ROOT, key: "status", value: .String("implementing"))
  → reading back: doc.get(obj: .ROOT, key: "status") == "implementing"
When two users set status concurrently:
  → merge keeps the later timestamp's value (LWW per key)
  → earlier value still in history

T-03 [BR-04, Core 80%]:
When Jeoffrey adds tag "security" and Faustin adds tag "p0" concurrently:
  → Jeoffrey's doc: tags = ["security"]
  → Faustin's doc: tags = ["p0"]
  → after merge: tags = ["security", "p0"] (OR-Set union, both preserved)
When both remove the same tag concurrently:
  → tag removed (observed-remove semantics)

T-04 [BR-04, Core 80%]:
When Jeoffrey edits paragraph 1 and Faustin edits paragraph 3 of spec body:
  → both changes preserved after merge (different positions)
When both edit the same sentence:
  → characters interleaved (Automerge's CRDT text algorithm)
  → no data lost, may need human review for readability

T-05 [BR-04, Core 80%]:
When Jeoffrey increments time_spent by 2 and Faustin increments by 3:
  → after merge: time_spent = original + 5 (both increments applied)

T-06 [BR-05, BR-07, Core 80%]:
When two users fork a document and make independent edits:
  → doc1.fork() creates doc2
  → edit doc1: title = "A", add tag "x"
  → edit doc2: status = "done", add tag "y"
  → doc1.merge(other: doc2)
  → title = "A", status = "done", tags = ["x", "y"]
  → zero data loss

T-07 [BR-06, Core 80%]:
When user saves a local edit:
  → doc.encodeChangesSince(heads: lastSyncedHeads) produces incremental bytes
  → bytes published to NATS subject shikki.{tenant}.crdt.change.{type}.{id}
  → lastSyncedHeads updated to doc.heads()

T-08 [BR-08, Core 80%, Integration]:
When user is offline for 2 hours:
  → 5 changes from other users stored in JetStream
  → on reconnect: JetStream consumer replays from last sequence
  → local doc applies all 5 changes via load_incremental
  → local state matches server state

T-09 [BR-09, BR-10, Core 80%]:
When server receives changes from user:
  → loads current crdt_doc from PostgreSQL (BYTEA)
  → creates Automerge Document from bytes
  → merges incoming changes
  → extracts: status, priority, title, tags, assignee
  → upserts row with updated crdt_doc + denormalized columns

T-10 [BR-11, Core 80%]:
When querying "all P0 specs in progress":
  → SQL: SELECT * FROM crdt_entities WHERE priority = 'P0' AND status = 'implementing'
  → uses indexed denormalized columns
  → does NOT deserialize crdt_doc BYTEA

T-11 [BR-13, Core 80%]:
When reconnecting after offline:
  → loads persisted SyncState for server peer
  → generateSyncMessage produces compact bloom filter (not full doc)
  → typically converges in 1-3 round trips

T-12 [BR-15, Core 80%]:
When requesting entity history:
  → Automerge doc contains full operation history
  → can replay changes with timestamps and actor IDs
  → supports undo: revert specific actor's changes
```

## Wave Dispatch Tree

```
Wave 1: CRDTDocument wrapper + entity mapping
  ├── CRDTDocument.swift — wraps Automerge Document with entity-specific accessors
  ├── CRDTEntityType.swift — enum mapping entity types to Automerge schemas
  ├── CRDTStore.swift — local file-based document storage (~/.shikki/crdt/)
  └── Package.swift — add automerge-swift dependency
  Input:  Automerge library
  Output: Create, edit, save, load CRDT documents for all entity types
  Tests:  T-01, T-02, T-03, T-04, T-05, T-06
  Gate:   swift test --filter CRDT → green
  ║
  ╠══ Wave 2: NATS sync transport ← BLOCKED BY Wave 1
  ║   ├── CRDTSyncTransport.swift — broadcast changes via NATS
  ║   ├── CRDTChangeListener.swift — subscribe to changes from other users
  ║   └── JetStream config for CRDT streams
  ║   Input:  CRDTDocument + NATSClientProtocol
  ║   Output: Real-time change sync between nodes
  ║   Tests:  T-07, T-08
  ║   Gate:   Two MockNATSClient instances sync a document
  ║
  ╠══ Wave 3: PostgreSQL storage ← BLOCKED BY Wave 1
  ║   ├── CRDTPostgresStore.swift — BYTEA storage + denormalized column extraction
  ║   ├── crdt_entities table migration
  ║   ├── crdt_changes hypertable migration
  ║   └── Server-side merge logic
  ║   Input:  CRDTDocument + ShikiMCP
  ║   Output: Durable CRDT storage with queryable fields
  ║   Tests:  T-09, T-10
  ║   Gate:   Merge + query round-trip works
  ║
  ╚══ Wave 4: Full sync protocol + history ← BLOCKED BY Wave 2 + 3
      ├── CRDTFullSync.swift — Automerge sync protocol over NATS request-reply
      ├── SyncState persistence
      └── History/undo from Automerge operation log
      Input:  Waves 2 + 3 complete
      Output: Offline reconnect + full history
      Tests:  T-11, T-12
      Gate:   Offline → reconnect → full sync converges
```

## Implementation Waves

### Wave 1: CRDTDocument + Entity Mapping
**Files:**
- `Sources/ShikkiKit/CRDT/CRDTDocument.swift` — wraps Automerge with typed accessors
- `Sources/ShikkiKit/CRDT/CRDTEntityType.swift` — entity schemas
- `Sources/ShikkiKit/CRDT/CRDTStore.swift` — file-based local storage
- `projects/shikki/Package.swift` — add `automerge-swift` dep
- `Tests/ShikkiKitTests/CRDT/CRDTDocumentTests.swift`
**Tests:** T-01..T-06
**BRs:** BR-01..BR-05
**Gate:** `swift test --filter CRDT` green

### Wave 2: NATS Sync Transport ← BLOCKED BY Wave 1
**Files:**
- `Sources/ShikkiKit/CRDT/CRDTSyncTransport.swift` — change broadcast + listener
- `Tests/ShikkiKitTests/CRDT/CRDTSyncTransportTests.swift`
**Tests:** T-07, T-08
**BRs:** BR-06..BR-08
**Gate:** MockNATSClient sync works

### Wave 3: PostgreSQL Storage ← BLOCKED BY Wave 1
**Files:**
- `Sources/ShikkiKit/CRDT/CRDTPostgresStore.swift` — BYTEA + denormalized
- `src/db/migrations/003-crdt-entities.sql` — schema migration
- `Tests/ShikkiKitTests/CRDT/CRDTPostgresStoreTests.swift`
**Tests:** T-09, T-10
**BRs:** BR-09..BR-12
**Gate:** Merge + query round-trip

### Wave 4: Full Sync + History ← BLOCKED BY Wave 2 + 3
**Files:**
- `Sources/ShikkiKit/CRDT/CRDTFullSync.swift` — Automerge sync protocol
- `Sources/ShikkiKit/CRDT/CRDTHistory.swift` — operation log, undo
- `Tests/ShikkiKitTests/CRDT/CRDTFullSyncTests.swift`
**Tests:** T-11, T-12
**BRs:** BR-13..BR-15
**Gate:** Offline reconnect converges

## @t Review

### @Sensei (CTO)
Automerge-swift via Rust FFI is the right call — battle-tested engine, MIT license, cross-language (if we ever add a web editor, same docs work in JS). The hybrid storage (BYTEA + denormalized columns) is clever — SQL queries stay fast, CRDT merge happens in Swift not PostgreSQL. The only risk is Automerge's memory footprint for very large documents (10K+ operations), but our entities are small (specs, tasks, not Google Docs).

### @Ronin (Adversarial)
- **Automerge binary size**: The Rust FFI adds ~5MB to the shi binary. Acceptable?
- **Text CRDT interleaving**: When two users type in the same sentence simultaneously, characters interleave. The result is readable 90% of the time, garbage 10%. Consider detecting "same-sentence conflict" and flagging for human review.
- **Counter overflow**: Automerge counters are i64. Budget tracking in cents avoids float issues but watch for overflow on large projects.
- **Actor ID proliferation**: Each device gets a unique actor ID. If a user reinstalls, they get a new actor. Old actor's changes are still in history. Not a bug, but document sizes grow with actor count.

### @Katana (Security)
- CRDT documents contain full operation history including who changed what and when. This is an audit trail AND a data leak risk if the device is stolen. The TTL wipe (distributed-sync BR-16) must cover CRDT files in `~/.shikki/crdt/`.
- Automerge's Rust core has had zero CVEs. MIT license compatible with AGPL-3.0.
