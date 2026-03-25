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

## Business Rules

## Test Plan

## Architecture

## Execution Plan

## Implementation Log

## Review History
| Date | Phase | Reviewer | Decision | Notes |
|------|-------|----------|----------|-------|
| 2026-03-25 | Phase 1 | @Daimyo | Started | First two nodes of the Shikki mesh |
