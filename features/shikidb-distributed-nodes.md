# Feature: ShikiDB Distributed Nodes
> Created: 2026-03-25 | Status: Phase 1 — Inspiration | Owner: @Daimyo

## Context
ShikiDB currently runs only on localhost:3900 (single-machine). Remote agents (Anthropic cloud triggers), Faustin's Mac, future mobile apps, and the VPS all need to read/write knowledge. This is the first real step of the Shikki Mesh Protocol — deploying a production ShikiDB node on the VPS with bidirectional sync to the local node. Two nodes, one knowledge graph.

## Inspiration
### Brainstorm Results

| # | Idea | Source | Feasibility | Impact | Project Fit | Verdict |
|---|------|--------|:-----------:|:------:|:-----------:|--------:|
| 1 | **Event-Sourced Append-Only Sync** — Immutable event WAL, push/pull via HMAC-signed HTTP. Master (VPS) applies in causal order (Lamport timestamps), LWW per field. Just more INSERT statements + a Caddy route. | @Sensei | High | High | Strong | BUILD |
| 2 | **Silent Sync, Loud Conflicts** — Sync is invisible (no spinners, no toasts). Conflicts surface as inbox items with diff + one-tap resolve. Offline writes queue silently, flush on reconnect. | @Hanami | High | High | Strong | BUILD |
| 3 | **Conflict-Free Knowledge Types** — Shape the schema so 95% of writes are structurally conflict-free: append-only logs, LWW timestamps, union-merge sets. Only free-text edits from 2 nodes need explicit resolve. | @Hanami | Medium | High | Strong | BUILD |
| 4 | **Kintsugi Merge — Scar-Visible Reconciliation** — Never silently pick a winner. Preserve both versions in `lineage` field, mark with `repaired_at` + `conflict_origin`. The scar IS the metadata. Conflict = provenance. | @Kintsugi | High | High | Strong | BUILD |
| 5 | **Patina Protocol — Time-Weighted Truth Decay** — Freshness score decays logarithmically from last confirmation. Referenced/corroborated = refreshed. Unreferenced = fades to `patina` state (queryable but dimmed). Never deleted. One corroboration from any node restores fully. | @Kintsugi | Medium | High | Strong | BUILD |
| 6 | **Node Presence Heartbeat** — Lightweight heartbeat per node. `shikki status` shows one-line mesh view: "VPS: 2s ago, MacBook: offline since 14:32". No dashboard, just a glanceable pulse. | @Hanami | High | Medium | Strong | BUILD |
| 7 | **CRDTs-over-HTTPS Mesh Sync** — CRDT-based delta patches over authenticated HTTPS. No central coordinator. Pattern from Linear/Figma. Each node is sovereign. | @Shogun | High | High | Strong | BUILD |
| 8 | **Hub-and-Spoke with VPS as Primary** — VPS = single source of truth. Simpler but creates SPOF. Standard client-server pattern. | @Shogun | High | Medium | Medium | DEFER |
| 9 | **CRDTs with Merkle Clock Convergence** — Full CRDT + Merkle DAG sync. Theoretically superior but violates raw-SQL principle, no production lib for Deno/Swift, over-engineers for 2-node. | @Sensei | Low | High | Weak | SKIP |
| 10 | **Embedded Vector Sync** — Sync via embedding fingerprints. Semantic dedup. Research-grade, not production-ready. Endgame layer, not foundation. | @Shogun | Low | High | Medium | SKIP |

### Selected Ideas

**@Daimyo** — select your top 3-5 to carry forward. My recommendation:

**Core (must-build):**
1. **Event-Sourced Append-Only Sync** (#1) — @Sensei's concrete architecture. Fits raw-SQL, event bus, systemd. This is the engine.
2. **Silent Sync, Loud Conflicts** (#2) — @Hanami's UX layer. Sync invisible, conflicts visible.
3. **Conflict-Free Knowledge Types** (#3) — Schema-level conflict avoidance (95% case).

**Soul (differentiators):**
4. **Kintsugi Merge** (#4) — Scar-visible reconciliation. Conflict as provenance. No other tool does this.
5. **Patina Protocol** (#5) — Time-weighted decay with corroboration. Memory ages with dignity.

**Nice-to-have:**
6. **Node Presence Heartbeat** (#6) — One-line mesh health in `shikki status`.

The combo of #1 (engine) + #2 (UX) + #3 (schema) + #4 (philosophy) gives us a distributed knowledge system with genuine soul. #5 and #6 are natural additions.

### @t Team Review (2026-03-25)

**@Ronin — Adversarial Review:**
- ✗ No offline queue/retry — events lost on network failure. Need Durable Outbox + Sync Watermark.
- ⚡ LWW silently destroys human writes (VPS always wins). Need LWW + Conflict Ledger (log every overwritten value).
- ◐ No schema versioning across nodes. Migration strategy needed.
- ~ Patina Protocol may be premature at 2-node scale (but approved for local-only quick win).
- ◐ Heartbeat ≠ sync health. Need sync lag metric (local_seq - remote_ack_seq).

**@Katana — Security Audit:**
- CRITICAL: Timing-unsafe API key comparison → use `timingSafeEqual`
- CRITICAL: WebSocket has zero auth → validate Bearer on upgrade + handshake timeout
- HIGH: CORS `Access-Control-Allow-Origin: *` → allowlist specific origins
- HIGH: No rate limiting → in-process rate limiter + Caddy `rate_limit`
- MEDIUM: No request body size limit → reject >1MB
- Recommendation: HMAC request signing per node (replaces static Bearer token)
- Recommendation: Caddy restrict to `/api/*` + `/health` only

**@Kenshi — Release Assessment:**
- No rollback mechanism → symlink-swap deploys (`/opt/shikidb/v0.x.x/`)
- No pre-deploy backup → `pg_dump` triggered by deploy script
- Zero-downtime impossible with single process → accept for v1, plan blue/green for v2
- systemd service needs: `Restart=on-failure`, `MemoryMax`, `After=postgresql.service`
- Recommendation: ntfy health alerts (reuse existing infra)

**@Metsuke — Quality Audit:**
- Split into Wave 1 (plumbing: #1+#2+#3) and Wave 2 (soul: #4+#5+#6)
- Kintsugi Merge + Patina need quantitative specs (decay rate, corroboration definition, thresholds)
- Build `sync_test_harness` with partition simulator before sync code
- CRDTs-over-HTTPS (#7) contradicts Event-Sourced Sync (#1) — pick one (picked #1)
- Heartbeat overlaps with Mesh Protocol spec pillar #4

**@Shogun — Competitive Gaps:**
- **Selective Sync Scopes** — `local | shared | restricted` per memory. Table stakes for multi-user trust. BUILD.
- **Conflict Resolution UI** — 3-way merge (mine/theirs/merge) with AI-suggested resolution. No competitor does this well. BUILD.

**@Hanami — Human Experience:**
- **Node Arrival Ceremony** — tamagotchi greets new node, shows "142 memories, 12 specs, 3 projects" onboarding. BUILD.
- **Presence Ghosts** — ambient awareness of other node activity. DEFER (needs solid sync first).

### @Daimyo Decisions (2026-03-25)
- All 6 core ideas: **APPROVED**
- VPS deploy: **DEFERRED** until NATS + sync engine + security hardening done properly. No half solutions.
- Quick wins approved: **Patina freshness field** (local) + **Node heartbeat in status** (local)
- @Metsuke wave split: acknowledged — Wave 1 plumbing first, Wave 2 soul after
- @Katana security fixes: **MUST DO** before any public deployment

## Synthesis

### Feature Brief

**Goal:** Enable bidirectional knowledge sync between ShikiDB nodes (VPS master, dev machine slaves) using event-sourced replication with conflict-visible reconciliation and zero data loss.

### Scope v1 — Sync Engine (Wave 1: Plumbing)
- **Event-sourced append-only sync**: Immutable event WAL (`sync_events` table), Lamport timestamps, push/pull over HTTPS
- **Durable outbox**: Append-only outbox with sync watermark per node, retry with exponential backoff — no event loss on network failure
- **Conflict-free knowledge types**: Schema-shaped to avoid conflicts for 95% of writes (append-only logs, LWW timestamps, union-merge sets)
- **Conflict ledger**: Every LWW overwrite logged with both values, origin node, and timestamp — never silently destroy
- **HMAC node auth**: Per-node HMAC request signing with `timingSafeEqual` comparison, replacing static Bearer tokens
- **Security hardening**: CORS origin allowlist, WS auth on upgrade with handshake timeout, rate limiting (in-process + Caddy), 1MB body size limit
- **Caddy routing**: Restrict public routes to `/api/*` + `/health`, HMAC-validated sync endpoints
- **Node identity**: `node_id` UUID, node manifest (name, role, capabilities), registration handshake
- **Schema versioning**: Migration version tracked per node, sync blocked if schemas diverge
- **Selective sync scopes**: `local | shared | restricted` per memory record
- **Node heartbeat**: Lightweight presence ping, sync lag metric (`local_seq - remote_ack_seq`)

### Scope v1.1 — Soul (Wave 2: Differentiation)
- **Kintsugi Merge**: Scar-visible reconciliation — both versions preserved in `lineage` field, marked with `repaired_at` + `conflict_origin`. Conflict = provenance, not error.
- **Patina Protocol integration**: Freshness score decay integrated with sync — corroboration from any node refreshes. Referenced memories stay bright, unreferenced fade to `patina` state.
- **Conflict inbox**: Conflicts surface as inbox items with 3-way diff (mine/theirs/base) + AI-suggested resolution
- **Node arrival ceremony**: Onboarding experience when a new node joins — summary of shared knowledge ("142 memories, 12 specs, 3 projects")

### Scope v2 — Mesh
- **NATS transport**: Replace HTTP polling with NATS JetStream for real-time event streaming
- **Multi-node topology**: Beyond 2-node — ephemeral nodes (CI agents, mobile), node discovery
- **Blue/green deploys**: Zero-downtime upgrades via symlink-swap + health checks

### Out of Scope
- Full CRDT implementation (too complex for raw-SQL, no production Deno lib)
- Embedded vector sync (research-grade, endgame layer)
- Presence ghosts / ambient awareness (needs solid sync first)
- Multi-user access control (single-owner for v1)
- Docker in production (native binaries + systemd only)

### Success Criteria
- SC-1: Two nodes (VPS + MacBook) sync a memory created on either side within 30 seconds
- SC-2: Network partition of 24h produces zero data loss — all events replayed on reconnect
- SC-3: Concurrent edits to the same field produce a conflict ledger entry (never silent overwrite)
- SC-4: `shikki status` shows node presence with sync lag < 5s under normal conditions
- SC-5: All @Katana CRITICAL/HIGH security findings resolved before first public deploy
- SC-6: Sync harness can simulate partition, clock skew, and concurrent writes in CI

### Dependencies
- **ShikiDB Deno backend** (localhost:3900) — sync endpoints added here
- **PostgreSQL** — new tables: `sync_events`, `sync_nodes`, `sync_outbox`, `conflict_ledger`
- **Caddy** — route configuration for sync API + rate limiting
- **systemd** — service config with `Restart=on-failure`, `MemoryMax`, `After=postgresql.service`
- **ntfy** — health alerts on sync failures (reuse existing infra)
- **ShikiCore EventPersister** — sync events feed into the event bus

## Business Rules

### Sync Protocol

**BR-01 — Event-Sourced Append-Only Log**
Every data mutation (create, update, delete) produces an immutable event in the `sync_events` table. Events are never modified or deleted. Schema: `(event_id UUID, node_id UUID, lamport_ts BIGINT, wall_clock TIMESTAMPTZ, table_name TEXT, row_id UUID, operation TEXT, payload JSONB, checksum TEXT)`.

**BR-02 — Push/Pull Replication**
Sync uses a pull-based model: each node requests events from peers since its last acknowledged sequence number. Push is optional (notification that new events exist). Pull endpoint: `POST /api/sync/pull` with `{node_id, since_seq, limit}`. Response: ordered event batch + `latest_seq`.

**BR-03 — Lamport Timestamps for Causal Order**
Every event carries a Lamport timestamp. On event creation: `lamport_ts = max(local_ts, last_received_ts) + 1`. Events applied in Lamport order. Wall clock used only as tiebreaker when Lamport timestamps are equal (same-node events).

**BR-04 — Master/Slave Topology**
VPS node is the master (authoritative). Dev machines are slaves. Master applies events in causal order and is the conflict resolution authority. Slaves push events to master and pull resolved state. Master failure does not block local writes — slaves queue to outbox.

### Node Identity

**BR-05 — Node Registration**
Each node has a stable `node_id` (UUID v4, generated once, persisted in `~/.config/shikki/node.json`). Registration: `POST /api/sync/register` with `{node_id, name, role, capabilities, schema_version}`. Master returns `{accepted: bool, node_secret: hex}`.

**BR-06 — Node Manifest**
Every node maintains a manifest: `{node_id, name, role (master|slave), schema_version, last_sync_seq, created_at, last_seen_at}`. Stored in `sync_nodes` table on master.

**BR-07 — Schema Version Gate**
Sync is blocked if the requesting node's `schema_version` does not match the master's. Response: `{error: "schema_mismatch", master_version, node_version, migration_url}`. Node must migrate before syncing.

### Conflict Resolution

**BR-08 — Conflict-Free Types (95% Case)**
Schema designed to minimize conflicts structurally:
- **Append-only**: `agent_events`, `sync_events`, `event_log` — no conflicts possible (insert-only)
- **LWW fields**: `memories.content`, `memories.metadata` — last writer wins, resolved by Lamport timestamp
- **Union-merge sets**: `memories.tags`, `memories.connections` — merge both sides, duplicates removed
- Only free-text concurrent edits from different nodes require explicit resolution.

**BR-09 — Conflict Ledger (Never Silently Destroy)**
Every LWW overwrite where both nodes modified the same field since last sync produces a `conflict_ledger` entry: `(conflict_id UUID, event_id UUID, table_name TEXT, row_id UUID, field_name TEXT, winner_value JSONB, loser_value JSONB, winner_node UUID, loser_node UUID, resolution TEXT, resolved_at TIMESTAMPTZ)`. Resolution types: `lww_auto`, `kintsugi_merge`, `user_resolved`, `ai_suggested`.

**BR-10 — Kintsugi Merge (v1.1)**
When conflict is detected on a text field: both versions preserved in a `lineage` JSONB array on the row. Fields added: `lineage JSONB DEFAULT '[]'`, `repaired_at TIMESTAMPTZ`, `conflict_origin UUID REFERENCES sync_nodes(node_id)`. The scar is the metadata — conflicts are provenance, not errors.

### Auth and Security

**BR-11 — HMAC Request Signing**
Every sync request is signed with a per-node HMAC-SHA256 key (issued at registration). Signature covers: `method + path + timestamp + body_hash`. Header: `X-Shikki-Signature: t=<unix_ts>,v1=<hmac_hex>`. Timestamp tolerance: 300 seconds.

**BR-12 — Timing-Safe Key Comparison**
All secret comparisons (HMAC verification, node secrets) use `crypto.timingSafeEqual`. No early-return string comparison. This is a hard requirement — PR blocked if violated.

**BR-13 — WebSocket Auth**
WebSocket upgrade requests must include `Authorization: Bearer <node_secret>` or `Sec-WebSocket-Protocol: auth, <node_secret>`. Handshake timeout: 5 seconds. Unauthenticated upgrades rejected with 401.

**BR-14 — CORS Origin Allowlist**
Replace `Access-Control-Allow-Origin: *` with explicit allowlist: `["http://localhost:3900", "https://back.obyw.one"]`. Configurable via environment variable `SHIKKI_CORS_ORIGINS`.

**BR-15 — Rate Limiting**
In-process rate limiter: 100 requests/minute per node_id for sync endpoints. Caddy `rate_limit` directive as outer layer: 200 requests/minute per IP. Burst allowance: 2x base rate for 10 seconds (reconnect surge).

**BR-16 — Request Body Size Limit**
Reject any request body exceeding 1MB with `413 Payload Too Large`. Configurable via `SHIKKI_MAX_BODY_BYTES`. Sync pull responses paginated to stay under limit.

### Schema Versioning

**BR-17 — Migration Protocol**
Each migration has a monotonic version number. `sync_nodes.schema_version` tracks each node's current version. Master broadcasts migration availability. Nodes must apply migrations in order. Migration SQL stored in `migrations/` directory, executed via raw SQL (no ORM).

**BR-18 — Migration Sync Block**
If a node is behind on migrations, sync pull returns `409 Conflict` with migration instructions. Node applies migrations locally, then re-registers with updated `schema_version`. No partial sync across schema boundaries.

### Durable Outbox

**BR-19 — Append-Only Outbox**
Every local mutation appends to `sync_outbox` table: `(outbox_id BIGSERIAL, event_id UUID, created_at TIMESTAMPTZ, pushed_at TIMESTAMPTZ NULL, retry_count INT DEFAULT 0, last_error TEXT NULL)`. Events stay in outbox until master acknowledges receipt.

**BR-20 — Sync Watermark**
Each node tracks `last_ack_seq` — the highest event sequence acknowledged by master. On pull: only request events after watermark. On push acknowledgment: advance watermark, mark outbox entries as pushed.

**BR-21 — Retry with Backoff**
Failed pushes retry with exponential backoff: 1s, 2s, 4s, 8s, ... capped at 5 minutes. After 100 consecutive failures, emit `sync_stalled` event to event bus + ntfy alert. Never drop events from outbox.

### Health and Heartbeat

**BR-22 — Node Heartbeat**
Each node sends `POST /api/sync/heartbeat` every 30 seconds with `{node_id, local_seq, schema_version, uptime_s}`. Master updates `sync_nodes.last_seen_at`. Node considered offline after 3 missed heartbeats (90 seconds).

**BR-23 — Sync Lag Metric**
Sync lag = `local_seq - remote_ack_seq`. Exposed in `shikki status` output. Warning threshold: lag > 100 events. Critical threshold: lag > 1000 events. Thresholds trigger ntfy alerts.

**BR-24 — Health Endpoint**
`GET /health` returns `{status: "ok"|"degraded"|"offline", node_id, schema_version, sync_lag, peers: [{node_id, last_seen, lag}], uptime_s}`. No auth required (public health check).

### Selective Sync

**BR-25 — Sync Scope per Record**
Every syncable record has a `sync_scope` field: `local` (never leaves this node), `shared` (synced to all nodes), `restricted` (synced only to nodes in allowlist). Default: `shared`. Scope changes are themselves sync events.

**BR-26 — Scope Enforcement on Pull**
Pull responses filter out `local` records and `restricted` records where the requesting node is not in the allowlist. Filtering happens on master before response — restricted data never leaves the master unless explicitly allowed.

## Test Plan

### Sync Protocol Tests

**TP-01 — Event creation produces sync event (BR-01)**
```swift
func testMutationProducesSyncEvent() async throws
// Insert a memory → verify sync_events row exists with correct payload, Lamport ts, checksum
```

**TP-02 — Pull returns events since watermark (BR-02)**
```swift
func testPullReturnsSinceSequence() async throws
// Create 10 events, pull since seq 5 → verify returns events 6-10 in order
```

**TP-03 — Lamport timestamp ordering (BR-03)**
```swift
func testLamportTimestampCausalOrder() async throws
// Simulate two nodes creating events, merge → verify Lamport ordering is correct
// Edge case: equal Lamport ts resolved by wall clock
```

**TP-04 — Pull with empty result (BR-02)**
```swift
func testPullWithNoNewEvents() async throws
// Pull since latest seq → verify empty batch, latest_seq unchanged
```

### Node Identity Tests

**TP-05 — Node registration handshake (BR-05)**
```swift
func testNodeRegistrationReturnsSecret() async throws
// POST /api/sync/register with valid manifest → verify accepted=true, node_secret returned
```

**TP-06 — Duplicate node registration rejected (BR-05)**
```swift
func testDuplicateRegistrationRejected() async throws
// Register same node_id twice → verify second returns error or updates manifest
```

**TP-07 — Schema version mismatch blocks sync (BR-07)**
```swift
func testSchemaVersionMismatchBlocksSync() async throws
// Register node with schema_version=2, master at version=3 → pull returns schema_mismatch error
```

### Conflict Resolution Tests

**TP-08 — Append-only tables produce no conflicts (BR-08)**
```swift
func testAppendOnlyTablesNeverConflict() async throws
// Two nodes insert into agent_events simultaneously → both accepted, no conflict ledger entry
```

**TP-09 — LWW resolves by Lamport timestamp (BR-08)**
```swift
func testLWWResolvedByLamportTimestamp() async throws
// Node A updates memory.content at Lamport 5, Node B at Lamport 7 → B wins
// Verify conflict_ledger entry records A's value as loser_value
```

**TP-10 — Union-merge on set fields (BR-08)**
```swift
func testUnionMergeOnTagFields() async throws
// Node A adds tag "swift", Node B adds tag "async" → merged result contains both
```

**TP-11 — Conflict ledger entry created on LWW overwrite (BR-09)**
```swift
func testConflictLedgerCreatedOnOverwrite() async throws
// Concurrent edit to same field → verify conflict_ledger row with winner/loser values and resolution="lww_auto"
```

**TP-12 — Kintsugi merge preserves lineage (BR-10)**
```swift
func testKintsugiMergePreservesLineage() async throws
// Concurrent text edit → verify lineage array contains both versions, repaired_at set, conflict_origin set
```

### Auth and Security Tests

**TP-13 — Valid HMAC signature accepted (BR-11)**
```swift
func testValidHMACSignatureAccepted() async throws
// Sign request with correct node HMAC → verify 200 response
```

**TP-14 — Invalid HMAC signature rejected (BR-11)**
```swift
func testInvalidHMACSignatureRejected() async throws
// Sign request with wrong key → verify 401 response
```

**TP-15 — Expired timestamp rejected (BR-11)**
```swift
func testExpiredTimestampRejected() async throws
// Sign request with timestamp older than 300s → verify 401 response
```

**TP-16 — Timing-safe comparison (BR-12)**
```swift
func testTimingSafeComparisonUsed() async throws
// Verify HMAC verification code path uses timingSafeEqual (code review + integration test)
```

**TP-17 — WebSocket without auth rejected (BR-13)**
```swift
func testWebSocketWithoutAuthRejected() async throws
// Attempt WS upgrade without Authorization header → verify 401
```

**TP-18 — CORS rejects unknown origin (BR-14)**
```swift
func testCORSRejectsUnknownOrigin() async throws
// Request with Origin: https://evil.com → verify no Access-Control-Allow-Origin in response
```

**TP-19 — Rate limiter throttles excess requests (BR-15)**
```swift
func testRateLimiterThrottlesExcess() async throws
// Send 150 requests in 1 minute from same node_id → verify 429 after 100th
```

**TP-20 — Oversized body rejected (BR-16)**
```swift
func testOversizedBodyRejected() async throws
// POST with 2MB body → verify 413 response
```

### Schema Versioning Tests

**TP-21 — Migration blocks sync until applied (BR-17, BR-18)**
```swift
func testMigrationBlocksSyncUntilApplied() async throws
// Node at v2, master at v3 → pull returns 409 → apply migration → pull succeeds
```

### Durable Outbox Tests

**TP-22 — Mutation appends to outbox (BR-19)**
```swift
func testMutationAppendsToOutbox() async throws
// Create memory offline → verify sync_outbox row with pushed_at=NULL
```

**TP-23 — Outbox cleared after master acknowledgment (BR-20)**
```swift
func testOutboxClearedAfterAck() async throws
// Push events, receive ack → verify outbox entries marked with pushed_at timestamp
```

**TP-24 — Watermark advances on ack (BR-20)**
```swift
func testWatermarkAdvancesOnAck() async throws
// Push 5 events, ack received for seq 5 → verify last_ack_seq = 5
```

**TP-25 — Retry with exponential backoff (BR-21)**
```swift
func testRetryWithExponentialBackoff() async throws
// Simulate 3 push failures → verify retry intervals: 1s, 2s, 4s
// Verify retry_count incremented, last_error populated
```

**TP-26 — Stall alert after 100 failures (BR-21)**
```swift
func testStallAlertAfterConsecutiveFailures() async throws
// Simulate 100 consecutive push failures → verify sync_stalled event emitted
```

**TP-27 — 24h partition produces zero data loss (SC-2)**
```swift
func testPartitionProducesZeroDataLoss() async throws
// Create 50 events on each node during simulated 24h partition
// Reconnect → verify all 100 events present on both nodes after sync
```

### Health and Heartbeat Tests

**TP-28 — Heartbeat updates last_seen (BR-22)**
```swift
func testHeartbeatUpdatesLastSeen() async throws
// Send heartbeat → verify sync_nodes.last_seen_at updated
```

**TP-29 — Node offline after 3 missed heartbeats (BR-22)**
```swift
func testNodeOfflineAfterMissedHeartbeats() async throws
// No heartbeat for 90s → verify node status = offline
```

**TP-30 — Sync lag metric accurate (BR-23)**
```swift
func testSyncLagMetricAccurate() async throws
// Node has local_seq=50, remote_ack_seq=30 → verify sync_lag=20
```

**TP-31 — Health endpoint returns correct status (BR-24)**
```swift
func testHealthEndpointReturnsStatus() async throws
// GET /health → verify JSON with status, node_id, sync_lag, peers array
```

### Selective Sync Tests

**TP-32 — Local scope records never synced (BR-25, BR-26)**
```swift
func testLocalScopeNeverSynced() async throws
// Create memory with sync_scope=local → pull from other node → verify not included
```

**TP-33 — Restricted scope filtered by allowlist (BR-26)**
```swift
func testRestrictedScopeFilteredByAllowlist() async throws
// Create memory with sync_scope=restricted, allowlist=[nodeA]
// Pull from nodeA → included. Pull from nodeB → excluded.
```

**TP-34 — Scope change syncs as event (BR-25)**
```swift
func testScopeChangeProducesSyncEvent() async throws
// Change memory sync_scope from shared to local → verify sync event created
// Other node receives scope change and stops syncing that record
```

### Integration Tests

**TP-35 — Full push/pull roundtrip (BR-01, BR-02, BR-04)**
```swift
func testFullPushPullRoundtrip() async throws
// Node A creates memory → push to master → Node B pulls → verify identical content
```

**TP-36 — Concurrent edit conflict detection + merge (BR-08, BR-09)**
```swift
func testConcurrentEditConflictDetectionAndMerge() async throws
// Node A and B edit same memory.content offline → both push → verify:
//   - Winner determined by Lamport ts
//   - Conflict ledger entry exists
//   - Both values preserved
```

**TP-37 — Reconnect after partition replays all events (BR-19, BR-21)**
```swift
func testReconnectAfterPartitionReplaysAll() async throws
// Simulate partition → create events on both sides → reconnect
// Verify outbox drained, watermarks advanced, all events present on master
```

**TP-38 — End-to-end sync under 30 seconds (SC-1)**
```swift
func testSyncCompletesUnder30Seconds() async throws
// Create memory on Node A → measure time until Node B has it → assert < 30s
```

## Architecture

## Execution Plan

## Implementation Log

## Review History
| Date | Phase | Reviewer | Decision | Notes |
|------|-------|----------|----------|-------|
| 2026-03-25 | Phase 1 | @Daimyo | Started | First two nodes of the Shikki mesh |
| 2026-03-25 | Phase 2 | @shi | Complete | Synthesis: v1/v1.1/v2 scope, success criteria, dependencies |
| 2026-03-25 | Phase 3 | @shi | Complete | 26 business rules: sync, auth, conflicts, outbox, health, scopes |
| 2026-03-25 | Phase 4 | @shi | Complete | 38 test signatures: unit + integration covering all BRs |
