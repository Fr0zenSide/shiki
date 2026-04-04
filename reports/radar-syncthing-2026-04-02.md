# Radar: Syncthing -- Private Cloud File Sync

**Date:** 2026-04-02
**Source:** https://github.com/syncthing/syncthing
**Stars:** 81,356 | **Language:** Go | **License:** MPL-2.0 | **Go version:** 1.25.0

---

## What It Is

Syncthing is a continuous P2P file synchronization program. No central server, no cloud dependency. Files are synced directly between devices over encrypted connections. 10+ years of production use, battle-tested, CII Best Practices certified.

## How It Works

### Core Protocol: Block Exchange Protocol (BEP)

- Files split into blocks (adaptive size), each identified by SHA-256 hash
- Protobuf3 wire format with LZ4 compression
- Delta sync via version vectors (Lamport-clock-like counters per device)
- Index messages carry full file metadata: name, size, mtime, permissions, blocks, platform-specific data (Unix uid/gid, xattrs, Windows owner)
- Incremental index updates via sequence numbers (prev_sequence/last_sequence) -- only changed files sent

### Discovery: Two Layers

1. **Local:** UDP broadcast on port 21027, 30s interval. Protobuf Announce (device ID + addresses). Automatic LAN peer detection.
2. **Global:** HTTPS to discovery.syncthing.net (or self-hosted). Announces every 30min. TLS client cert for authentication.
3. **Static:** Manual address configuration, bypasses discovery entirely. Ideal for Headscale mesh where IPs are stable.

### Encryption & Identity

- **Device ID** = SHA-256 of TLS certificate, displayed as base32 + Luhn check digits
- **Transport:** TLS 1.2+ mutual authentication on all connections
- **Transports:** TCP (direct), QUIC (UDP, faster handshake), Relay (NAT traversal via relay servers)
- **NAT traversal:** UPnP + PMP port mapping, STUN for NAT type detection
- **Untrusted encryption:** XChaCha20-Poly1305 for data blocks, AES-SIV for filenames. Key derivation via scrypt + HKDF. Folder-level encryption passwords. LRU key caches (1000 folder keys, 5000 file keys).

### Conflict Resolution

- Version vectors track per-device modification counters
- Concurrent edits detected when neither version dominates
- Winner selected by deterministic vector comparison
- Loser saved as `filename.sync-conflict-YYYYMMDD-HHMMSS-DEVICEID.ext`
- `MaxConflicts` config (default 10) limits copies
- Four versioning strategies: Trashcan, Simple (N copies), Staggered (time-decay), External (custom command)

### Folder Types

| Type | Direction | Use Case |
|------|-----------|----------|
| **Send-Receive** | Bidirectional | Full sync between peers |
| **Send-Only** | Local -> Remote | Master copy, push only |
| **Receive-Only** | Remote -> Local | Mirror/backup, local changes tracked but not propagated |
| **Receive-Encrypted** | Remote -> Local (encrypted) | Untrusted storage node. Cannot decrypt. Perfect for cloud/VPS backup. |

### REST API

Full programmatic control on port 8384 (HTTPS + CSRF + API key auth):

- `GET /rest/system/status` -- system info
- `GET /rest/system/connections` -- connected devices
- `GET /rest/db/status?folder=X` -- sync status per folder
- `GET /rest/db/completion?device=X&folder=Y` -- sync completion %
- `GET /rest/events?since=N` -- SSE-style event stream
- `POST /rest/db/scan?folder=X` -- trigger rescan
- `POST /rest/db/override?folder=X` -- force send-only state
- `POST /rest/db/revert?folder=X` -- revert receive-only changes
- `GET /rest/noauth/health` -- unauthenticated health check
- `GET /metrics` -- Prometheus endpoint

---

## Verdicts

### 1. Private Cloud Photo Backup (Phone -> VPS -> NAS)

**Verdict: ADOPT**

This is the killer use case. The Receive-Encrypted folder type was designed exactly for this:

- Phone runs Syncthing, sends photos encrypted with a folder password
- VPS receives encrypted blobs it cannot read (Receive-Encrypted folder)
- NAS (at home, on Headscale) connects to VPS, receives same encrypted data, decrypts with folder password
- OR phone syncs directly to NAS when on same Headscale mesh, VPS is just a relay/buffer

No cloud provider sees plaintext. No rsync cron jobs. Continuous, automatic, conflict-safe. REST API lets shid monitor sync status and health. Docker or systemd deployment on VPS. Syncthing Android app is mature (F-Droid).

**Action items:**
1. Install Syncthing on VPS (systemd service)
2. Install on NAS (systemd or Docker)
3. Install Syncthing-Fork on phone (F-Droid)
4. Configure Receive-Encrypted on VPS, Send-Receive on NAS
5. Wire health into shid monitoring via `/rest/noauth/health` + `/rest/db/completion`

### 2. Replace rsync for File Sync Between shid Nodes

**Verdict: WATCH**

Different paradigms. rsync is one-shot unidirectional ("push this directory now"). Syncthing is continuous bidirectional ("keep these folders in sync always"). For batch operations (deploy configs, push specs), rsync is simpler and more predictable. Syncthing adds a persistent daemon and its own conflict model.

However, for specific shid use cases like continuous config replication or spec file sync across nodes, Syncthing could be superior to rsync cron jobs. Worth evaluating once multi-node shid is real.

**When to revisit:** When shid has 3+ nodes and config drift becomes a problem.

### 3. P2P Sync Over Headscale Mesh

**Verdict: ADOPT**

Syncthing + Tailscale/Headscale is a proven, documented pattern:

- Headscale provides stable IPs (100.x.y.z) and WireGuard encryption
- Syncthing configured with static addresses (no discovery servers needed)
- Direct device-to-device connections, no relay overhead
- Double encryption (WireGuard + TLS) -- can disable Syncthing TLS if desired for performance
- Go implementation same language as Moto/Hanko -- potential for deep integration

This is the natural transport layer for the Shikki private cloud. Every device on the Headscale mesh can sync folders with any other device, encrypted, without touching the public internet.

---

## Architecture Fit

| Aspect | Syncthing | Shikki Alignment |
|--------|-----------|-------------------|
| Language | Go | Same as Moto/Hanko |
| License | MPL-2.0 | Compatible with AGPL-3.0 |
| Deployment | Binary / systemd / Docker | Matches native-only prod philosophy |
| API | REST + Prometheus | Easy to integrate with shid monitoring |
| Config | XML file | Could template with Go |
| Protocol | BEP (protobuf) | Clean, well-documented |
| Encryption | XChaCha20-Poly1305 + AES-SIV | State of the art |

## Key Numbers

- 81k GitHub stars, 10+ years active development
- Go 1.25.0, single binary ~25MB
- 4 folder types, 4 versioner strategies
- 3 transport types (TCP, QUIC, Relay)
- 50+ REST API endpoints
- Prometheus metrics built-in

## Risk

- **Low.** Mature, widely deployed, active maintenance. MPL-2.0 is permissive enough. No vendor lock-in. Self-hosted everything (discovery, relay, data). Worst case: Syncthing project dies, we fork and maintain a focused subset.

---

*Saved to ShikiDB as ingest_chunks (session: radar-syncthing-2026-04-02)*
