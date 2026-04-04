---
title: "Distributed Sync — Company Server + User Replicas + NATS Leaf Topology"
status: draft
priority: P1
project: shikki
created: 2026-04-04
authors: ["@Daimyo"]
tags: [architecture, distributed, sync, nats, postgresql, multi-tenant, enterprise]
depends-on: [shikki-deno-sunset.md, shikki-daemon-command.md, shikki-nats-client-wiring.md, shikki-workspace-separation.md]
relates-to: [shikki-node-security.md]
epic-branch: feature/distributed-sync
validated-commit: —
test-run-id: —
---

# Feature: Distributed Sync — Company Server + User Replicas + NATS Leaf Topology
> Created: 2026-04-04 | Status: Draft | Owner: @Daimyo

## Context

Shikki has 3 deployment layers:

1. **Company Server** (Linux VPS) — the heart. PostgreSQL + TimescaleDB + pgvector + NATS hub. Source of truth for company data. Serves N users. One server can host M companies (multi-tenant managed service).
2. **User Device** (macOS/Linux) — a scoped replica. Local PostgreSQL with same extensions. Works offline. Syncs bidirectionally with company server via NATS leaf nodes.
3. **Sync Layer** (NATS) — the nervous system. Real-time bidirectional event streaming. Offline buffering. Auto-reconnect with replay.

### The 3 Hard Problems

**P1: Offline-first with full PostgreSQL capabilities.** Users need hypertables, vector search, full-text search locally — not a dumbed-down SQLite cache. But local PostgreSQL has the full company dataset which is a knowledge theft risk if the device is stolen/compromised.

**P2: Bidirectional sync with conflict resolution.** Two users edit the same backlog item while one is offline. Who wins? How do we merge without losing data?

**P3: Multi-tenant server capacity.** How many companies × users × events/sec can one Linux box handle before needing to scale?

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    COMPANY SERVER (Linux VPS)                     │
│                                                                   │
│  ┌─────────────────┐  ┌──────────────┐  ┌───────────────────┐   │
│  │ PostgreSQL 17    │  │ NATS Server  │  │ shi daemon        │   │
│  │ + TimescaleDB    │  │ (hub mode)   │  │ (persistent)      │   │
│  │ + pgvector       │  │ + JetStream  │  │ serves all users  │   │
│  │ + pgvectorscale  │  │              │  │                   │   │
│  │                  │  │              │  │ MCP → PostgreSQL  │   │
│  │ DB: shikki_obyw  │  │ Subjects:    │  │                   │   │
│  │ DB: shikki_xyz   │  │ obyw.*       │  │ Tenants:          │   │
│  │                  │  │ xyz.*        │  │ ws-obyw, ws-xyz   │   │
│  └─────────────────┘  └──────┬───────┘  └───────────────────┘   │
│                              │                                    │
└──────────────────────────────┼────────────────────────────────────┘
                               │
              ┌────────────────┼────────────────┐
              │ NATS leaf      │ NATS leaf       │ NATS leaf
              ▼                ▼                 ▼
┌──────────────────┐ ┌──────────────────┐ ┌──────────────────┐
│ Jeoffrey's Mac   │ │ Faustin's Mac    │ │ New Dev's Linux  │
│                  │ │                  │ │                  │
│ PostgreSQL local │ │ PostgreSQL local │ │ PostgreSQL local │
│ (scoped replica) │ │ (scoped replica) │ │ (scoped replica) │
│                  │ │                  │ │                  │
│ shi daemon       │ │ shi daemon       │ │ shi daemon       │
│ (scheduled)      │ │ (scheduled)      │ │ (scheduled)      │
│                  │ │                  │ │                  │
│ NATS leaf node   │ │ NATS leaf node   │ │ NATS leaf node   │
│ → auto-reconnect │ │ → auto-reconnect │ │ → auto-reconnect │
│ → offline buffer │ │ → offline buffer │ │ → offline buffer │
└──────────────────┘ └──────────────────┘ └──────────────────┘
```

## Business Rules

```
## Server (Linux)

BR-01: Company server MUST run PostgreSQL 17 + TimescaleDB + pgvector + pgvectorscale as native packages (not Docker)
BR-02: One PostgreSQL instance MUST serve multiple companies via separate databases (multi-tenant)
BR-03: One NATS server MUST serve multiple companies via subject namespacing (shikki.{company}.*)
BR-04: shi daemon (persistent mode) MUST serve all tenants, reading tenant configs from /etc/shikki/tenants/*.yaml
BR-05: Adding a new tenant MUST be: drop a YAML config + create database + SIGHUP daemon. No restart.
BR-06: Server MUST accept NATS leaf node connections from user devices with NKey authentication per user
BR-07: Server MUST run PgBouncer for connection pooling — one pool per tenant database

## User Device (macOS/Linux)

BR-08: User device MUST run local PostgreSQL with same extensions (TimescaleDB, pgvector) for full offline capability
BR-09: Local PostgreSQL MUST contain only the user's scoped data — NOT the full company database
BR-10: Scope MUST be defined by the user's role/permissions: their projects, their assigned tasks, their memories, shared team data
BR-11: shi daemon (scheduled mode) MUST sync with company server on each tick via NATS
BR-12: User device MUST work fully offline — all shi commands work against local PostgreSQL
BR-13: On reconnect, NATS leaf node MUST replay buffered events (user → server) and receive missed events (server → user)

## Data Protection (anti-theft)

BR-14: Local PostgreSQL MUST be encrypted at rest — full disk encryption (FileVault/LUKS) is the minimum
BR-15: Local database MUST have a TTL (time-to-live) per record type — stale data auto-deleted after N days without sync
BR-16: shi daemon MUST check last sync timestamp on startup — if > N days without server contact, local data MUST be wiped (configurable per tenant: 7/14/30 days)
BR-17: User MUST NOT have direct psql access to company-scoped tables — only through shi CLI which enforces scope
BR-18: On device decommission, shi ws destroy MUST securely wipe local PostgreSQL data (VACUUM FULL + DROP DATABASE + overwrite)
BR-19: Server admin MUST be able to revoke a user's access — next sync attempt fails, local data TTL starts counting down to wipe
BR-20: Company-scoped memories with classification "confidential" MUST NOT be replicated to user devices — server-only, queried live via NATS request-reply

## Sync Protocol

BR-21: Sync MUST be event-sourced — all changes are events (created, updated, deleted), not state snapshots
BR-22: Each event MUST have a globally unique ID (UUID v7 — time-ordered) and a vector clock per user
BR-23: Events MUST be persisted to NATS JetStream on the server with per-tenant streams
BR-24: Conflict resolution MUST use last-writer-wins (LWW) with vector clock ordering — no manual merge
BR-25: Deleted records MUST use tombstones (soft delete with TTL) — not hard delete — so deletes sync correctly
BR-26: Initial sync (new device) MUST use NATS request-reply to download the user's scoped dataset as a batch
BR-27: Incremental sync MUST use NATS pub/sub with JetStream consumer tracking (last-delivered sequence per user)
BR-28: Sync MUST be resumable — if interrupted mid-transfer, resume from last acknowledged sequence

## Multi-Tenant Server

BR-29: shi setup --server MUST install PostgreSQL + extensions + NATS + PgBouncer + shi daemon on Linux
BR-30: shi tenant add <name> MUST create database + NATS credentials + tenant config + workspace
BR-31: shi tenant remove <name> MUST drop database + revoke credentials + remove config (with confirmation)
BR-32: shi tenant list MUST show all tenants with user count, DB size, last activity
BR-33: shi user add <tenant> <email> MUST create user credentials (NKey pair) + define scope
BR-34: shi user revoke <tenant> <email> MUST revoke NKey + trigger TTL countdown on all user devices
BR-35: Server MUST monitor per-tenant resource usage: connections, queries/sec, disk, NATS msg rate
BR-36: Server MUST alert when approaching capacity thresholds (configurable: connections, disk, CPU)

## User Onboarding

BR-37: New user runs shi setup --join <server-url> --token <invite-token>
BR-38: Setup MUST: install local PostgreSQL + extensions, configure NATS leaf to company server, create workspace, initial sync
BR-39: Invite token MUST be single-use, time-limited (24h default), tied to specific tenant + role
BR-40: After initial sync, user can work offline immediately — local DB has their scoped dataset
```

## Data Scoping — What Each User Gets

```
FULL REPLICA (always synced):
  ├── User's own events (commits, decisions, specs, time entries)
  ├── User's assigned tasks and backlog items
  ├── User's memories (personal + project-scoped)
  ├── Team shared data (announcements, company config, sprint goals)
  └── Project metadata for assigned projects (.moto caches, specs)

LIVE QUERY ONLY (not replicated, fetched via NATS request-reply):
  ├── Other users' events (team activity feed)
  ├── Confidential memories (classification: confidential)
  ├── Full project history (only recent N days replicated)
  └── Analytics/aggregates (computed server-side)

NEVER ON DEVICE:
  ├── Other tenants' data (database isolation)
  ├── Server admin credentials
  ├── Raw audit logs (server-only)
  └── Billing/payment data
```

## Sync Flow

### User → Server (push)

```
User creates event locally:
  1. Event written to local PostgreSQL
  2. Event published to NATS: shikki.{company}.user.{userId}.events.{type}
  3. NATS leaf forwards to hub server
  4. Server shi daemon receives, writes to company PostgreSQL
  5. Server fans out to other users subscribed to that project/team

If offline:
  1. Event written to local PostgreSQL
  2. Event queued in NATS leaf node buffer
  3. On reconnect: NATS replays buffered events to hub
  4. Server processes in order (UUID v7 = time-ordered)
```

### Server → User (pull)

```
Team event occurs on server:
  1. Event written to company PostgreSQL
  2. Event published to NATS: shikki.{company}.team.{type}
  3. NATS hub forwards to leaf nodes of users in that tenant
  4. User's shi daemon receives, writes to local PostgreSQL
  5. User sees update on next command (or live in dashboard)

If user offline:
  1. NATS JetStream stores event in persistent stream
  2. User's consumer tracks last-delivered sequence
  3. On reconnect: JetStream replays missed events from sequence N
  4. User's local DB catches up
```

### Conflict Resolution

```
Example: Jeoffrey and Faustin both edit backlog item #42 while offline

Jeoffrey's event:
  { id: "uuid-v7-A", type: "backlog_updated", item: 42, 
    title: "Fix auth bug", vclock: {jeoffrey: 5} }

Faustin's event:
  { id: "uuid-v7-B", type: "backlog_updated", item: 42,
    title: "Fix authentication issue", vclock: {faustin: 3} }

Server receives both on reconnect:
  → UUID v7 ordering: A before B (time-ordered)
  → LWW: Faustin's update wins (later timestamp)
  → Both events stored in history (audit trail)
  → Server publishes merged state to both users
  → Jeoffrey's local DB updated with Faustin's title
```

## Tenant Config Format

```yaml
# /etc/shikki/tenants/obyw.yaml
name: obyw
display_name: "OBYW.one"
database: shikki_obyw
nats_prefix: shikki.obyw
workspace: /var/lib/shikki/workspaces/ws-obyw

# Data protection
data_ttl_days: 14              # local device data expires after 14 days without sync
confidential_server_only: true  # confidential memories never replicated
max_users: 50

# Resource limits (per-tenant)
max_connections: 20            # PgBouncer pool size for this tenant
max_nats_subscriptions: 1000

# Users
users:
  - email: jeoffrey@obyw.one
    role: admin
    nkey: UABC123...          # NATS NKey public key
    scope: all                # admin sees everything
  - email: faustin@obyw.one
    role: developer
    nkey: UDEF456...
    scope: [wabisabi, maya]   # scoped to specific projects
```

## NATS Topology

```
Company Server (hub):
  nats-server --config /etc/nats/shikki-hub.conf
  
  # Hub config
  leafnodes {
    port: 7422
    authorization {
      users = [
        { nkey: "UABC123...", permissions: { publish: "shikki.obyw.user.jeoffrey.>", subscribe: "shikki.obyw.>" } }
        { nkey: "UDEF456...", permissions: { publish: "shikki.obyw.user.faustin.>", subscribe: "shikki.obyw.>" } }
      ]
    }
  }
  
  jetstream {
    store_dir: /var/lib/nats/jetstream
    max_mem: 1G
    max_file: 50G
  }

User Device (leaf):
  nats-server --config ~/.shikki/nats-leaf.conf
  
  # Leaf config
  leafnodes {
    remotes = [
      { url: "nats-leaf://company-server.example.com:7422", credentials: "~/.shikki/nats.creds" }
    ]
  }
```

## Installation Paths

### Server (Linux)

```bash
# One-liner install
curl -sSf https://get.shikki.dev/server | sh

# What it does:
# 1. Add Timescale apt repo + pgdg repo
# 2. apt install postgresql-17 timescaledb-2-postgresql-17 postgresql-17-pgvector
# 3. Download shi binary to /usr/local/bin/
# 4. Download nats-server to /usr/local/bin/
# 5. Install PgBouncer
# 6. Create /etc/shikki/ config structure
# 7. Enable systemd services: postgresql, nats-server, shi-daemon, pgbouncer
# 8. Run timescaledb-tune --yes
# 9. Create initial admin tenant

shi tenant add obyw --admin jeoffrey@obyw.one
shi user add obyw faustin@obyw.one --role developer --scope wabisabi,maya
```

### User Device (macOS)

```bash
# One-liner install
curl -sSf https://get.shikki.dev | sh

# What it does:
# 1. Download shi binary to ~/.shikki/bin/
# 2. Install PostgreSQL + extensions via brew
# 3. Configure local PostgreSQL for shikki
# 4. Add shi to PATH

# Join a company
shi setup --join company-server.example.com --token INVITE_TOKEN_HERE

# What --join does:
# 1. Authenticate with invite token (single-use, 24h expiry)
# 2. Receive NKey credentials + tenant config
# 3. Configure NATS leaf node → company server
# 4. Create local database with schema
# 5. Initial sync: download user's scoped dataset
# 6. Start shi daemon (scheduled mode)
# 7. Ready to work (online or offline)
```

### User Device (Linux)

```bash
# Same as macOS but uses apt instead of brew
curl -sSf https://get.shikki.dev | sh
# Installs via apt: postgresql-17, timescaledb, pgvector, nats-server

shi setup --join company-server.example.com --token INVITE_TOKEN_HERE
```

## @t Review

### @Sensei (CTO)
The event-sourced sync with NATS JetStream is the right pattern — it's exactly how Syncthing, CRDTs, and event-driven architectures work. UUID v7 for time-ordering eliminates clock sync issues (time is embedded in the ID). LWW conflict resolution is simple and predictable — no merge UI needed. The key risk is initial sync speed for large datasets — consider pagination (batch of 1000 events per NATS request-reply).

PgBouncer is essential for multi-tenant — without it, 10 tenants × 20 connections = 200 PostgreSQL connections, which hits the default limit fast. PgBouncer in transaction mode gives you 10x multiplexing.

### @Ronin (Adversarial)
- **TTL wipe is nuclear**: If a user goes on vacation for 15 days and TTL is 14, they come back to an empty local DB. Warn before wiping — send ntfy notification at 50% TTL, 75% TTL, 90% TTL.
- **Initial sync size**: A company with 2 years of events could be gigabytes. Need a "recent only" option — sync last 90 days, older data via live query.
- **NKey revocation**: NATS NKeys can't be revoked server-side without restarting nats-server (or using account JWTs instead). Consider NATS account/JWT model for user lifecycle management.
- **Device compromise**: If a laptop is stolen and the thief has disk decryption (biometrics/password), the local PostgreSQL is fully readable. Consider PostgreSQL TDE (transparent data encryption) with a key derived from shi login (user password + hardware key).

### @Katana (Security)
- NKey per user = zero shared secrets. Good.
- NATS permissions scope what each user can publish/subscribe — prevents lateral movement.
- Confidential data server-only (BR-20) is critical — some memories should never leave the server.
- TTL wipe (BR-16) is the last line of defense — device stolen, data expires.
- Invite tokens (BR-39) must be cryptographically random, stored hashed on server.
- Consider mTLS for NATS leaf connections (not just NKey) — defense in depth.

### @Kintsugi (Philosophy)
The company server is the heart — it holds the truth. User devices are hands — they do the work and report back. The sync layer is the bloodstream — events flow in both directions, keeping the organism alive. When a hand is severed (device lost), the heart keeps beating. When the heart is down (server outage), the hands keep working with what they have. This is resilience through architecture, not through redundancy.

## Capacity Planning (pending audit)

See `reports/capacity-audit-infra-2026-04-04.md` for hard numbers on:
- PostgreSQL: max tenants, connections, TPS, disk per VPS tier
- NATS: max leaf nodes, msg/sec, JetStream storage
- First bottleneck analysis
- Monitoring thresholds
- Scaling triggers
