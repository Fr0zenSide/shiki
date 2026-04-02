# Radar: Syncthing — P2P Continuous File Synchronization

**Date:** 2026-04-03
**Source:** https://github.com/syncthing/syncthing
**Stars:** 81,355 | **Forks:** 4,979 | **License:** MPL-2.0
**Language:** Go (go 1.25.0) | **Latest:** v2.0.15 (2026-03-03)
**Created:** 2013-11-26 | **Active:** last updated 2026-04-02

---

## What It Is

Syncthing is a **continuous, peer-to-peer file synchronization program** — no central server, no cloud dependency. Files sync directly between devices over encrypted connections. Think "private Dropbox" where you own every node.

Priority-ordered goals (from their GOALS.md):
1. Safe from data loss
2. Secure against attackers
3. Easy to use
4. Automatic
5. Universally available
6. For individuals

---

## Architecture Deep Dive

### Codebase Structure

```
cmd/
  syncthing/          — main binary
  stdiscosrv/         — global discovery server
  strelaysrv/         — relay server
lib/
  protocol/           — BEP implementation, encryption, device IDs, vector clocks
  model/              — folder sync logic (send-receive, send-only, receive-only)
  discover/           — local + global device discovery
  connections/        — TCP, QUIC, relay dial/listen
  api/                — REST API (50+ endpoints)
  config/             — folder/device/GUI configuration
  versioner/          — file versioning (simple, staggered, trashcan, external)
  ignore/             — .stignore pattern parser (glob-based)
  scanner/            — filesystem walker + block hasher
  events/             — event bus for UI/API consumers
  nat/                — NAT traversal (UPnP + NAT-PMP)
  relay/              — relay protocol client
  fs/                 — filesystem abstraction layer
internal/
  db/                 — LevelDB-backed metadata database
  gen/bep/            — generated protobuf types
proto/bep/            — BEP protobuf definition
gui/                  — web UI (Angular)
```

### 1. How Syncthing Works — P2P Continuous Sync

No central server. Every node is equal. The sync loop:

1. **Scan** — filesystem watcher (fsnotify) + periodic rescan detects changes
2. **Index** — changed files are hashed into fixed-size blocks (128 KiB–16 MiB), metadata sent as `Index`/`IndexUpdate` messages to connected peers
3. **Compare** — vector clocks determine which version wins; concurrent edits = conflict
4. **Pull** — missing blocks are requested from peers via `Request`/`Response` messages
5. **Apply** — blocks assembled into files, permissions/xattrs synced, versioner archives old copies

Key constants: `MaxMessageLen = 500 MB`, `DesiredPerFileBlocks = 2000`, block sizes auto-scale with file size.

### 2. Block Exchange Protocol (BEP)

Defined in `proto/bep/bep.proto`. Protobuf-based, 8 message types:

| Type | Purpose |
|------|---------|
| `ClusterConfig` | Declare shared folders + devices on connection |
| `Index` | Full file list for a folder |
| `IndexUpdate` | Delta update (new/changed/deleted files) |
| `Request` | Ask peer for a specific block of a file |
| `Response` | Return block data (or error code) |
| `DownloadProgress` | Progress updates for in-flight downloads |
| `Ping` | Keep-alive |
| `Close` | Graceful shutdown with reason |

Pre-auth `Hello` message exchanges device name, client version, connection count, timestamp.

Compression: LZ4 on messages > 128 bytes. Configurable per-device: metadata-only, always, never.

File metadata includes: name, size, mtime, permissions, block hashes, vector clock version, platform data (Unix uid/gid, Windows owner, xattrs per OS), symlink targets.

### 3. Device Discovery

Three layers, managed by `discover.Manager`:

**Local discovery** (`lib/discover/local.go`):
- IPv4/IPv6 UDP broadcast/multicast on LAN
- Magic number `0x2EA7D90B`, beacon every 30 seconds
- Cache lifetime: 3x broadcast interval (90s)
- Zero-config — devices on same LAN find each other automatically

**Global discovery** (`lib/discover/global.go`):
- HTTPS announcements to discovery servers (default: `discovery.syncthing.net`)
- Devices announce their addresses every 30 minutes
- Lookup via GET request with device ID
- Supports custom/private discovery servers (`stdiscosrv`)
- Negative cache: 5 minutes on failed lookups

**Relay discovery** (`lib/relay/`):
- For devices behind restrictive NATs/firewalls
- Relay servers (`strelaysrv`) proxy encrypted traffic
- Device connects to relay, other devices connect through it
- Last resort — direct connection always preferred

**NAT traversal** (`lib/nat/`, `lib/pmp/`, `lib/upnp/`):
- UPnP and NAT-PMP port mapping
- STUN for external address detection (`lib/stun/`)

### 4. Encryption & Security

**Transport encryption:**
- Mutual TLS on every connection (both TCP and QUIC)
- TLS 1.2 minimum, TLS 1.3 preferred
- Each device generates an ECDSA certificate on first run
- Certificate pinning via device IDs

**Device IDs** (`lib/protocol/deviceid.go`):
- SHA-256 hash of the device's TLS certificate (32 bytes)
- Displayed as base32 with Luhn check digits: `MFZWI3D-BONSGYC-YLTMRWG-...`
- Identity = cryptographic key. No usernames, no passwords, no accounts.
- Sharing a device ID = granting access. Revoking = removing the ID.

**Untrusted/encrypted nodes** (`lib/protocol/encryption.go`):
- `FOLDER_TYPE_RECEIVE_ENCRYPTED` — node stores data but cannot read it
- ChaCha20-Poly1305 (XChaCha, 24-byte nonce) for block encryption
- AES-SIV (miscreant) for filename encryption
- scrypt + HKDF for key derivation from folder password
- Encrypted file names get `.syncthing-enc` extension on disk
- Per-file keys derived from folder key + file path
- LRU caches for folder keys (1000) and file keys (5000)

### 5. Conflict Resolution

**Vector clocks** (`lib/protocol/vector.go`):
- Each device has a counter in the version vector
- `Vector.Compare()` returns: `Equal`, `Greater`, `Lesser`, `ConcurrentLesser`, `ConcurrentGreater`
- Concurrent = true conflict (independent modifications on different devices)

**Conflict detection** (`FileInfo.InConflictWith()`):
- If new version is `GreaterEqual` → not a conflict, fast-forward
- If `PreviousBlocksHash` matches existing `BlocksHash` → content-based resolution (new file built on old content, not a conflict even if vectors are concurrent)
- Otherwise → conflict

**Conflict winner** (`FileInfo.WinsConflict()`):
1. Invalid file loses
2. Newer `ModTime` wins
3. Tie-breaker: device ID comparison via version vector (`ConcurrentGreater`)

**Conflict handling** (`moveForConflict()`):
- Loser renamed to `filename.sync-conflict-20260403-120000-DEVICEID.ext`
- `MaxConflicts` setting (default: 10) — oldest conflict copies pruned
- `MaxConflicts = 0` → no conflict copies (loser deleted)
- `MaxConflicts = -1` → unlimited conflict copies
- Conflicts on existing conflict copies are not re-copied (avoids cascade)

### 6. Folder Types

Four types defined in BEP protobuf:

| Type | Direction | Use Case |
|------|-----------|----------|
| `SendReceive` | Bidirectional | Default. Full two-way sync between peers |
| `SendOnly` | Push only | Source of truth. Local changes sent, remote changes ignored |
| `ReceiveOnly` | Pull only | Mirror/backup. Receives changes, local changes stay local |
| `ReceiveEncrypted` | Pull + encrypt | Untrusted node. Data stored encrypted, cannot decrypt |

**ReceiveEncrypted** is the key innovation for cloud backup — a VPS can store your encrypted photos without being able to read them.

### 7. REST API

50+ endpoints on `localhost:8384` (default), HTTPS with auto-generated certs.

**System endpoints:**
- `GET /rest/system/status` — device ID, uptime, memory, connections
- `GET /rest/system/connections` — active peers, bandwidth, crypto
- `GET /rest/system/discovery` — discovered devices
- `POST /rest/system/restart|shutdown|pause|resume`
- `GET /rest/noauth/health` — unauthenticated health check

**Database/sync endpoints:**
- `GET /rest/db/status` — folder sync status (% complete, bytes needed)
- `GET /rest/db/completion` — completion percentage per device per folder
- `GET /rest/db/need` — files still needed (paginated)
- `GET /rest/db/file` — single file metadata + block info
- `GET /rest/db/browse` — browse folder contents
- `POST /rest/db/scan` — trigger rescan of folder or subfolder
- `POST /rest/db/override` — force send-only folder state to peers
- `POST /rest/db/revert` — revert receive-only local changes

**Configuration endpoints:**
- `GET/PUT /rest/config` — full config
- `GET/PUT/POST/DELETE /rest/config/folders/:id` — CRUD folders
- `GET/PUT/POST/DELETE /rest/config/devices/:id` — CRUD devices

**Events:**
- `GET /rest/events` — long-poll event stream (SSE-like)
- `GET /rest/events/disk` — disk change events only
- Event types: `LocalChangeDetected`, `RemoteChangeDetected`, `FolderCompletion`, `DeviceConnected`, `ItemStarted`, `ItemFinished`, etc.

**Auth:** API key in `X-API-Key` header or HTTP basic auth. CSRF protection via token.

### 8. Ignore Patterns (.stignore)

Glob-based pattern matching (`lib/ignore/`, uses `gobwas/glob`):

```
// Ignore thumbnails
*.thumb
*.tmp

// Ignore macOS metadata
.DS_Store
._*

// Ignore by directory
/photos/raw/**

// Negate (include despite parent ignore)
!/photos/raw/favorites/**

// Case-insensitive
(?i)thumbs.db

// Deletable (can be deleted when removed from source)
(?d)/old-backups/**

// Include from another file
#include .stglobalignore
```

Features: glob patterns, negation (`!`), case-insensitive (`(?i)`), deletable flag (`(?d)`), `#include` directives, `#escape` for special characters, SHA-256 hash of ignore state for change detection.

---

## Versioning Strategies

Four built-in versioners + external:

| Versioner | Behavior |
|-----------|----------|
| **Simple** | Keep N versions (default: 5), optional cleanout after N days |
| **Staggered** | Time-based thinning: 30s intervals for 1h, 1h for 1d, 1d for 30d, 1w for 1y |
| **Trashcan** | Move to `.stversions/`, clean after N days |
| **External** | Shell out to user-defined command |

All versioners implement: `Archive(path)`, `GetVersions()`, `Restore(path, time)`, `Clean(ctx)`.

---

## Key Dependencies

- `quic-go` — QUIC transport (alongside TCP)
- `golang.org/x/crypto` — ChaCha20-Poly1305, scrypt, HKDF
- `miscreant.go` — AES-SIV for deterministic filename encryption
- `goleveldb` — metadata database
- `suture/v4` — service supervision tree
- `lz4/v4` — message compression
- `protobuf` — BEP wire format
- `gobwas/glob` — ignore pattern matching
- `gopsutil` — system metrics
- `prometheus/client_golang` — metrics export

---

## Relevance to Shiki Projects

### Private Cloud Photo Backup (Phone → VPS → NAS)

**Direct fit.** The three-node photo pipeline maps perfectly:

```
iPhone (SendOnly)  →  VPS (ReceiveEncrypted)  →  NAS (SendReceive)
                          untrusted relay           trusted archive
```

- Phone runs Syncthing (iOS app: Möbius Sync) as `SendOnly` — photos push out, nothing comes back
- VPS stores encrypted blobs via `ReceiveEncrypted` — cannot read photos even if compromised
- NAS decrypts and archives via `SendReceive` — full plaintext access at home

Key advantages over rsync:
- **Continuous** — no cron, syncs as photos are taken
- **Resumable** — block-level transfer, survives network drops
- **Encrypted at rest on VPS** — rsync requires plaintext or separate encryption layer
- **Conflict-safe** — vector clocks prevent data loss
- **REST API** — programmatic monitoring from Shikki dashboard

### rsync Replacement for shid Node Sync

Syncthing's block-level deduplication and delta sync match rsync's efficiency but add:
- Bidirectional sync (rsync is unidirectional)
- Automatic conflict resolution
- No SSH/cron setup — just share device IDs
- `.stignore` replaces rsync `--exclude` patterns

For ShikiDB replication between nodes, Syncthing could sync the SQLite WAL files or export directories, though dedicated DB replication (Litestream, rqlite) may be more appropriate for transactional consistency.

### Headscale Mesh Network Fit

Syncthing over Headscale/Tailscale is a proven pattern:
- Headscale provides the encrypted WireGuard mesh
- Syncthing handles file sync over the mesh
- Local discovery works on the virtual LAN
- No need for global discovery servers or relays (mesh handles NAT traversal)
- Device IDs provide an independent authentication layer on top of WireGuard

### Go Implementation Alignment

Same language as Moto/Hanko protocols. Shared patterns:
- Protobuf for wire format (BEP ↔ Moto protocol)
- `suture/v4` supervision trees (production-grade service management)
- LevelDB for local state (similar to Hanko vault)
- TLS mutual auth with certificate-based identity

### ShikiDB Replication Layer

Partial fit. Syncthing syncs files, not database transactions. Options:
1. **Export-based**: ShikiDB exports to JSON/SQLite files in a synced folder → eventual consistency
2. **WAL sync**: Sync SQLite WAL files (risky — not crash-safe without coordination)
3. **Better alternative**: Use Syncthing for media/document sync, dedicated DB replication for ShikiDB

---

## Action Items

| # | Action | Priority | Project |
|---|--------|----------|---------|
| 1 | Deploy Syncthing on VPS + NAS for photo backup pipeline | P1 | Infrastructure |
| 2 | Configure `ReceiveEncrypted` on VPS, `SendOnly` on phone | P1 | Infrastructure |
| 3 | Set up Syncthing over Headscale mesh (bypass global discovery) | P1 | Infrastructure |
| 4 | Add `/rest/system/status` + `/rest/db/completion` to Shikki monitoring | P2 | Shikki |
| 5 | Evaluate Möbius Sync (iOS Syncthing) for phone integration | P2 | Infrastructure |
| 6 | Use `.stignore` patterns for RAW/HEIC filtering on backup nodes | P2 | Infrastructure |
| 7 | Explore staggered versioning for NAS photo archive | P3 | Infrastructure |
| 8 | Benchmark Syncthing vs rsync for large initial photo migration | P3 | Infrastructure |

---

## Verdict

**Strong adopt for private cloud photo backup.** Syncthing is battle-tested (81k stars, 12+ years, v2.0), the `ReceiveEncrypted` folder type solves the untrusted-VPS problem elegantly, and the REST API enables Shikki integration. The Go codebase is clean, well-structured, and aligned with the Moto/Hanko stack. Not a fit for database replication, but excellent for media and document sync across the Headscale mesh.
