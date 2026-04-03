# Radar: NATS.io --- Connective Tissue for Distributed Systems
> Date: 2026-04-03 | Source: https://nats.io | GitHub: https://github.com/nats-io/nats-server

## Overview

NATS is a CNCF incubating project: a high-performance, open-source messaging system built as a single Go binary. It provides pub/sub, request/reply, streaming (JetStream), key-value store, and object store through a simple text-based protocol over TCP.

| Metric | Value |
|--------|-------|
| GitHub Stars | 19.5k |
| Downloads | 400M+ |
| Client Libraries | 45+ (15 official, 30+ community) |
| Contributors | 1,000+ |
| Latest Release | v2.12.6 (2026-03-24) |
| License | Apache 2.0 |
| Server Binary Size | ~20 MB |
| Language | Go (99.7%) |
| Security Audit | Trail of Bits (April 2025) |

Notable adopters: NVIDIA, Capital One, PayPal, Mastercard, AT&T, Walmart, Ericsson, VMware, GitLab, Palo Alto Networks.

## Architecture

### Protocol (Text-Based)

NATS uses a **simple text-based protocol** over TCP. Messages are CRLF-delimited, fields separated by whitespace. This is one of its most distinctive design choices --- no binary framing, no schema negotiation, trivially debuggable with netcat.

Core commands:

```
PUB <subject> [reply-to] <#bytes>\r\n[payload]\r\n
SUB <subject> [queue-group] <sid>\r\n
MSG <subject> <sid> [reply-to] <#bytes>\r\n[payload]\r\n
CONNECT {"verbose":false,"pedantic":false,...}\r\n
INFO {"server_id":"...", "version":"...", ...}\r\n
PING\r\n / PONG\r\n
```

Headers supported via `HPUB`/`HMSG` (NATS/1.0 header format). Subject wildcards: `*` (single token), `>` (tail match). Max payload default: 1 MB. Max control line: 1024 bytes. Max connections: 64k.

### Server Topology

Three connection modes, each on a dedicated port:

1. **Cluster (full mesh)**: All servers route to all other servers. Auto-discovery via gossip. Messages forwarded only one hop (no circular propagation). Self-healing --- nodes join/leave dynamically.

2. **Gateways (superclusters)**: Connect entire clusters into a full mesh of clusters. Interest-only propagation --- Gateway A only sends subjects Gateway B has subscribers for. Dramatically reduces connections: 3x30-node clusters need 180 gateway connections vs 4,005 for full mesh.

3. **Leaf Nodes (edge)**: Extend the mesh to edge/IoT. Separate auth domains. Acyclic graph topology (doesn't need to be reachable from cluster). TLS-first handshake (v2.10+). Local queue consumers prioritized over remote.

### JetStream (Persistence Layer)

Built-in persistence engine, no external dependencies. Replaces the deprecated STAN.

| Feature | Detail |
|---------|--------|
| Storage | Memory or file-backed, encryption at rest |
| Replication | R=1 (no HA), R=3 (recommended), R=5 (max resilience) |
| Consensus | NATS-optimized Raft |
| Consistency | Linearizable writes, serializable reads |
| Delivery | At-least-once (default), exactly-once (with dedup) |
| Retention | Limits (default), Work Queue (consume-once), Interest (active subs only) |
| Replay | All, last, by sequence, by timestamp; instant or original speed |
| KV Store | Atomic CAS, watch, history, bucket-based |
| Object Store | Chunked large object storage |

Performance: Core NATS delivers 15M+ msgs/sec at <100us latency. JetStream peaks at ~160K msgs/sec consumer throughput (persistence cost).

### Security

- Auth: username/password, JWT, tokens, TLS certificates, NKey with challenge
- TLS/mTLS for encryption and mutual auth
- Per-subject publish/subscribe permissions
- Account-based multi-tenancy
- Trail of Bits audited (April 2025)

## Swift Client Assessment

The official Swift client (`nats-io/nats.swift`) exists but is **immature**:

| Metric | Value |
|--------|-------|
| Stars | 50 |
| Latest Release | v0.4.0 (October 2024) |
| Contributors | 6 |
| Swift Version | 5.7+ |
| Platforms | iOS, macOS, Linux |
| SPM | Yes |
| JetStream | Not yet (roadmap) |
| API Style | async/await, AsyncStream |

The API surface is clean (connect/publish/subscribe/request-reply, headers, wildcards, TLS, auth), but no JetStream, no KV, no Object Store. For Shikki's current use (pub/sub dispatch + heartbeats + leader election), Core NATS is sufficient, so the Swift client works.

## What Shikki Already Built

Shikki has a substantial NATS integration layer (19 files in `Sources/ShikkiKit/NATS/`):

| File | Purpose |
|------|---------|
| `NATSClientProtocol.swift` | Transport-agnostic interface (publish, subscribe, request-reply) |
| `MockNATSClient.swift` | Test double --- no real nats-server in unit tests |
| `NATSServerManager.swift` | Lifecycle management --- find binary, launch, health check, stop |
| `NATSDispatcher.swift` | Orchestrator-side: publish tasks, collect results via subject patterns |
| `NATSWorker.swift` | Worker-side: receive tasks, execute, report progress |
| `LeaderElection.swift` | FSM: idle -> shadow -> verify -> promoting -> primary |
| `MeshTokenProvider.swift` | Pre-shared secret for mesh membership auth |
| `NodeRegistry.swift` | Track live nodes via heartbeat, detect stale |
| `NodeHeartbeat.swift` | Periodic identity + metrics broadcast |
| `NodeIdentity.swift` | Node ID, role, kind |
| `NATSHealthCheck.swift` | Connection health monitoring |
| `NATSConfig.swift` | Server configuration |
| `NATSEventBridge.swift` | Bridge ShikkiEvents to NATS subjects |
| `NATSEventTransport.swift` | Event transport layer |
| `NATSEventRenderer.swift` | Format events for NATS publication |
| `NATSMetricsCollector.swift` | Collect NATS performance metrics |
| `NATSReportAggregator.swift` | Aggregate reports from distributed nodes |
| `EventLoggerNATS.swift` | Log events via NATS |
| `DispatchTask.swift` | Task model for distributed dispatch |

Related specs on the roadmap:
- `shikki-node-security.md` --- NKey auth, leader election hardening (P0)
- `shikki-provider-nats-node.md` --- AI providers as discoverable mesh nodes (P0)
- `shikki-distributed-orchestration.md` --- Full NATS-backed multi-agent dispatch architecture

The architecture is sound: `NATSClientProtocol` abstracts the wire protocol, `MockNATSClient` enables testing without a server, and `NATSServerManager` manages the actual `nats-server` binary lifecycle. This is **exactly the right approach** --- use the real NATS server binary, wrap it with Swift protocols.

## Shikki Fit Assessment

### What We Get from Full NATS Server (vs custom protocol)

| Capability | Custom Protocol | NATS Server |
|-----------|----------------|-------------|
| Pub/sub | Must implement | Built-in, battle-tested |
| Request/reply | Must implement | Built-in with timeouts |
| Clustering | Must implement Raft | Built-in, auto-discovery |
| Leader election | Our FSM (LeaderElection.swift) | Could use JetStream KV for distributed lock |
| Persistence | ShikiDB only | JetStream streams + ShikiDB |
| Subject wildcards | Must implement | Built-in (`*`, `>`) |
| Auth | meshToken (pre-shared secret) | NKey, JWT, TLS, multi-tenant |
| Edge nodes | Not supported | Leaf nodes with separate auth |
| TLS | Must configure | Built-in, TLS-first option |
| Monitoring | Custom metrics | Built-in `/varz`, `/connz`, `/routez` |
| Protocol debug | Custom tooling | `nats` CLI, any TCP client |
| Throughput | Unknown | 15M+ msgs/sec |

### What We Lose

- **External dependency**: `nats-server` binary must be installed (but it's a single ~20 MB binary, easily bundled)
- **JetStream Swift gap**: No JetStream in Swift client yet --- but we use ShikiDB for persistence anyway
- **Overkill for single-node**: Core NATS adds little value when running one Shikki instance locally

### Verdict on Current Approach

**Shikki's current approach is correct**: use the full `nats-server` binary, managed by `NATSServerManager`, with Swift wrapping via `NATSClientProtocol`. This gives us:

1. Battle-tested messaging at 15M msgs/sec (we'll never hit this ceiling)
2. Built-in clustering when we go multi-node (no custom Raft implementation)
3. Leaf nodes for future edge deployments
4. A text-based protocol we can debug with netcat
5. The ability to swap the Swift client for the official `nats.swift` when it matures

## Comparison

| Feature | NATS | Redis Pub/Sub | ZeroMQ | gRPC Streams | RabbitMQ |
|---------|------|--------------|--------|--------------|----------|
| **Latency** | <100us | ~200us | ~50us | ~1ms | 1-2ms |
| **Throughput** | 15M msgs/s | ~1M msgs/s | ~10M msgs/s | ~500K msgs/s | ~500K msgs/s |
| **Protocol** | Text (TCP) | RESP (TCP) | Binary (TCP/IPC/inproc) | HTTP/2 + Protobuf | AMQP (binary) |
| **Persistence** | JetStream (opt-in) | None (streams separate) | None | None | Disk queues |
| **Clustering** | Built-in (gossip) | Redis Cluster (slots) | None (manual) | Load balancer | Erlang clustering |
| **Auth** | NKey/JWT/TLS/multi-tenant | ACL + password | None built-in | mTLS + interceptors | SASL + TLS |
| **Edge/IoT** | Leaf nodes | No | No | No | Shovel/Federation |
| **Single binary** | Yes (~20MB) | Yes (~8MB) | Library only | Library only | Erlang VM (~100MB+) |
| **Swift client** | v0.4.0 (basic) | SwiftRedis (mature) | ZeroMQ.swift (stale) | grpc-swift (mature) | RabbitMQ.swift (basic) |
| **KV Store** | JetStream KV | Redis core | No | No | No |
| **CNCF** | Incubating | No | No | Graduated | No |
| **License** | Apache 2.0 | BSD-3 | LGPL-3.0 | Apache 2.0 | MPL-2.0 |

### Why NATS Wins for Shikki

1. **Text protocol** --- debuggable, implementable in any language, matches Shikki's philosophy of simplicity
2. **Single binary** --- fits the "native binaries only, no Docker in prod" production model
3. **Leaf nodes** --- future-proof for edge deployments (Raspberry Pi, fleet)
4. **Built-in clustering** --- no need to implement our own Raft (unlike ZeroMQ)
5. **JetStream optional** --- use ShikiDB for persistence, NATS for transport (separation of concerns)
6. **Apache 2.0** --- compatible with Shikki's AGPL-3.0 + CLA model

### Why Not the Alternatives

- **Redis Pub/Sub**: Fire-and-forget only, no request/reply, no clustering for pub/sub, no leaf nodes. Redis is a cache with pub/sub bolted on.
- **ZeroMQ**: Library, not a server. Would require building our own discovery, clustering, auth. Lowest latency but highest implementation cost.
- **gRPC Streams**: Point-to-point, not pub/sub. Would need a service mesh for many-to-many. HTTP/2 overhead for simple messages.
- **RabbitMQ**: Heavyweight Erlang VM, complex setup, AMQP is enterprise bloat for agent dispatch.

## Action Items

| # | Action | Priority | Status |
|---|--------|----------|--------|
| 1 | **Keep current architecture** --- `NATSServerManager` wrapping real `nats-server` is correct | --- | VALIDATED |
| 2 | **Complete P0 node security** (`shikki-node-security.md`) --- NKey auth + leader election hardening | P0 | In backlog |
| 3 | **Monitor `nats.swift` v0.5+** for JetStream support --- could replace custom KV patterns | P1 | WATCH |
| 4 | **Evaluate JetStream KV for leader election** --- could simplify `LeaderElection.swift` FSM with distributed lock | P1 | EVALUATE |
| 5 | **Test leaf node topology** for Shikki edge scenario (Pi deployment, fleet) | P2 | FUTURE |
| 6 | **Add `nats-server` to Swift setup wizard** (`shikki-setup-swift.md`) as optional component with weight | P0 | Blocked by setup spec |
| 7 | **Benchmark Shikki dispatch latency** through NATS vs direct function calls | P2 | FUTURE |
| 8 | **Consider gateway topology** for multi-company orchestration (one NATS cluster per company) | P3 | FUTURE |

## Verdict

**Use full NATS server. Keep current architecture. Do not build a custom protocol.**

Shikki's existing approach is architecturally sound: wrap the real `nats-server` binary with `NATSServerManager`, abstract the wire protocol behind `NATSClientProtocol`, and mock everything in tests. The text-based protocol, single-binary deployment, built-in clustering, and leaf node topology are exactly what Shikki needs for distributed orchestration.

The only gap is the Swift client's lack of JetStream, but this is irrelevant because Shikki uses ShikiDB for persistence --- NATS is purely the real-time transport layer. When `nats.swift` matures, the JetStream KV store could simplify leader election, but the current FSM in `LeaderElection.swift` is functional.

**Bottom line**: NATS is the right choice. The 19-file NATS module in ShikkiKit is well-architected. Focus energy on the P0 security hardening (node auth + leader election), not on protocol alternatives.
