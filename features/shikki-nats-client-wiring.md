---
title: "NATS Client Wiring — Connect nats-io/nats.swift to NATSClientProtocol"
status: draft
priority: P0
project: shikki
created: 2026-04-03
authors: ["@Daimyo"]
tags: [nats, client, networking, dispatch, mesh]
depends-on: [shikki-node-security.md]
relates-to: [shikki-kernel-extension-architecture.md]
epic-branch: feature/nats-client-wiring
validated-commit: —
test-run-id: —
---

# Feature: NATS Client Wiring — Connect nats-io/nats.swift to NATSClientProtocol
> Created: 2026-04-03 | Status: Draft | Owner: @Daimyo

## Context

All 19 NATS files in ShikkiKit (3,772 LOC) are implemented and tested against `NATSClientProtocol`. `MockNATSClient` provides an in-memory implementation for unit tests. `NATSServerManager` launches and manages the real `nats-server` binary. But there is NO concrete `NATSClient` that talks to the real server — every command using NATS currently injects `MockNATSClient()` with a TODO comment. The protocol boundary means zero consumer code changes — we just add one conformer.

## Business Rules

```
BR-01: NATSClient MUST conform to NATSClientProtocol (connect, disconnect, publish, subscribe, request)
BR-02: NATSClient MUST wrap nats-io/nats.swift (official Swift NATS client library)
BR-03: nats-io/nats.swift MUST be added to Package.swift with exact version pinning
BR-04: MockNATSClient MUST remain unchanged — all unit tests continue using the mock
BR-05: NATSClient MUST connect using URL from NATSConfig (default: nats://localhost:4222)
BR-06: NATSClient MUST include auth token from NATSConfig when connecting
BR-07: NATSClient MUST auto-reconnect on connection loss (delegate to nats.swift reconnect logic)
BR-08: NATSClient MUST map nats.swift subscription to AsyncStream<NATSMessage>
BR-09: NATSClient MUST implement request-reply with configurable timeout (Duration → TimeInterval conversion)
BR-10: Commands using MockNATSClient() with TODO comments MUST be updated to use real NATSClient when nats-server is available, fallback to mock when not
BR-11: Integration tests MUST require a running nats-server (tagged .integration, skipped in CI without server)
BR-12: NATSClient MUST be an actor for thread safety (matching MockNATSClient pattern)
```

## TDDP — Test Summary Table

| Test | BR | Tier | Type | Scenario |
|------|-----|------|------|----------|
| T-01 | BR-01, BR-02 | Core (80%) | Unit | When NATSClient created → conforms to NATSClientProtocol |
| T-02 | BR-05 | Core (80%) | Integration | When connect() called with valid URL → isConnected == true |
| T-03 | BR-06 | Core (80%) | Integration | When connecting with auth token → server accepts connection |
| T-04 | BR-08 | Core (80%) | Integration | When subscribe + publish → message received via AsyncStream |
| T-05 | BR-08 | Core (80%) | Integration | When subscribe with wildcard → matches published subjects |
| T-06 | BR-09 | Core (80%) | Integration | When request-reply → response received within timeout |
| T-07 | BR-09 | Core (80%) | Integration | When request-reply timeout exceeded → throws NATSClientError.timeout |
| T-08 | BR-10 | Core (80%) | Unit | When nats-server available → commands use NATSClient |
| T-09 | BR-10 | Core (80%) | Unit | When nats-server unavailable → commands fall back to MockNATSClient |
| T-10 | BR-04 | Core (80%) | Unit | When running existing mock tests → all still pass unchanged |
| T-11 | BR-07 | Smoke (CLI) | Integration | When nats-server restarts → client auto-reconnects |
| T-12 | BR-12 | Core (80%) | Unit | When concurrent publish calls → no data races (actor isolation) |

### S3 Test Scenarios

```
T-01 [BR-01, BR-02, Core 80%]:
When creating NATSClient(url: "nats://localhost:4222"):
  → type conforms to NATSClientProtocol
  → isConnected is false before connect()

T-02 [BR-05, Core 80%, Integration]:
When calling connect() on NATSClient with valid nats-server running:
  → isConnected becomes true
  → no error thrown
When calling connect() with no server running:
  → throws NATSClientError.connectionFailed with descriptive message

T-03 [BR-06, Core 80%, Integration]:
When nats-server requires auth token:
  if NATSClient provides correct token:
    → connection succeeds
  if NATSClient provides wrong token:
    → throws NATSClientError.connectionFailed("authorization violation")

T-04 [BR-08, Core 80%, Integration]:
When subscribing to "shikki.events.>" and publishing to "shikki.events.test":
  → AsyncStream yields a NATSMessage with subject "shikki.events.test"
  → message.data matches published data
  → message.replyTo is nil (no reply requested)

T-05 [BR-08, Core 80%, Integration]:
When subscribing to "shikki.dispatch.*":
  if message published to "shikki.dispatch.node1":
    → stream yields the message
  if message published to "shikki.dispatch.node1.sub":
    → stream does NOT yield (single-level wildcard)

T-06 [BR-09, Core 80%, Integration]:
When calling request(subject: "test.echo", data: payload, timeout: .seconds(2)):
  if a responder is subscribed and replies:
    → returns NATSMessage with response data within 2 seconds

T-07 [BR-09, Core 80%, Integration]:
When calling request with timeout .milliseconds(50) and no responder:
  → throws NATSClientError.timeout

T-08 [BR-10, Core 80%]:
When ReportCommand runs and NATSHealthCheck.ping() succeeds:
  → NATSClient is injected (not MockNATSClient)
  → client connects to real nats-server

T-09 [BR-10, Core 80%]:
When ReportCommand runs and NATSHealthCheck.ping() fails:
  → MockNATSClient is injected as fallback
  → warning logged: "nats-server not available, using mock"

T-10 [BR-04, Core 80%]:
When running full test suite:
  → all existing MockNATSClient-based tests pass unchanged
  → MockNATSClient not modified

T-11 [BR-07, Smoke CLI, Integration]:
When nats-server stops and restarts during active connection:
  → client detects disconnection
  → client auto-reconnects (nats.swift built-in behavior)
  → subscriptions resume delivering messages

T-12 [BR-12, Core 80%]:
When 10 concurrent publish calls from different tasks:
  → all complete without data race (actor serialization)
  → all messages arrive at subscriber
```

## Wave Dispatch Tree

```
Wave 1: NATSClient Implementation
  ├── Add nats-io/nats.swift to Package.swift (exact pin)
  ├── NATSClient.swift (actor conforming to NATSClientProtocol)
  └── NATSClientFactory.swift (creates real or mock based on server availability)
  Input:  NATSClientProtocol, NATSConfig, nats.swift library
  Output: Concrete NATSClient connecting to real nats-server
  Tests:  T-01, T-02, T-03, T-12
  Gate:   swift test --filter NATSClient → green (unit tests, no server needed)
  ║
  ╠══ Wave 2: Integration Tests ← BLOCKED BY Wave 1
  ║   ├── NATSClientIntegrationTests.swift (requires running nats-server)
  ║   └── Tagged .integration — skipped without server
  ║   Input:  NATSClient + running nats-server
  ║   Output: Verified pub/sub, request-reply, wildcards, reconnection
  ║   Tests:  T-04, T-05, T-06, T-07, T-11
  ║   Gate:   swift test --filter NATSClientIntegration → green (with nats-server)
  ║
  ╚══ Wave 3: Command Wiring ← BLOCKED BY Wave 1
      ├── Update ReportCommand.swift (replace MockNATSClient TODO)
      ├── Update LogCommand.swift (use NATSClientFactory)
      └── Verify MockNATSClient-based tests unchanged
      Input:  NATSClientFactory
      Output: Commands use real client when server available
      Tests:  T-08, T-09, T-10
      Gate:   swift test → all green (full suite, no regressions)
```

## Implementation Waves

### Wave 1: NATSClient Implementation
**Files:**
- `projects/shikki/Package.swift` — add `.package(url: "https://github.com/nats-io/nats.swift", exact: "0.4.0")`, add product dep to ShikkiKit
- `Sources/ShikkiKit/NATS/NATSClient.swift` — actor wrapping nats.swift Connection
- `Sources/ShikkiKit/NATS/NATSClientFactory.swift` — factory: ping server → real client, no server → mock + warning
- `Tests/ShikkiKitTests/NATS/NATSClientTests.swift` — unit tests (protocol conformance, actor safety)
**Tests:** T-01, T-02 (mock mode), T-12
**BRs:** BR-01, BR-02, BR-03, BR-05, BR-06, BR-12
**Deps:** none
**Gate:** `swift test --filter NATSClient` green

### Wave 2: Integration Tests ← BLOCKED BY Wave 1
**Files:**
- `Tests/ShikkiKitTests/NATS/NATSClientIntegrationTests.swift` — requires running nats-server
**Tests:** T-04, T-05, T-06, T-07, T-11
**BRs:** BR-07, BR-08, BR-09, BR-11
**Deps:** Wave 1 (NATSClient), running nats-server
**Gate:** `swift test --filter NATSClientIntegration` green with server

### Wave 3: Command Wiring ← BLOCKED BY Wave 1
**Files:**
- `Sources/shikki/Commands/ReportCommand.swift` — replace `MockNATSClient()` with `NATSClientFactory.create()`
- `Sources/shikki/Commands/LogCommand.swift` — same
- Any other commands with MockNATSClient TODOs
**Tests:** T-08, T-09, T-10
**BRs:** BR-04, BR-10
**Deps:** Wave 1 (NATSClientFactory)
**Gate:** `swift test` full suite green, no regressions

## Reuse Audit

| Utility | Exists In | Decision |
|---------|-----------|----------|
| NATSClientProtocol | NATSClientProtocol.swift | Conform to it — no changes |
| MockNATSClient | MockNATSClient.swift | Keep unchanged for unit tests |
| NATSConfig (URL, auth) | NATSConfig.swift | Read URL + token from it |
| NATSHealthCheck.ping() | NATSHealthCheck.swift | Use in NATSClientFactory for availability check |
| NATSServerManager | NATSServerManager.swift | No changes — still manages nats-server process |
| Duration+TotalSeconds | Kernel/Core/ | Use for timeout conversion (Duration → TimeInterval) |

## @t Review

### @Sensei (CTO)
This is the smallest high-impact change in the entire backlog — ONE file (NATSClient.swift, ~150 LOC) plus a factory. The protocol boundary was designed for exactly this moment. MockNATSClient stays untouched, all 71+ tests keep passing. The factory pattern (ping server → real, no server → mock) means the CLI works everywhere — laptop without nats-server, CI without nats-server, production with nats-server.

Pin nats.swift at exact `0.4.0`. It's the latest stable release. No JetStream yet in Swift, but we don't need it — ShikiDB handles persistence.

### @Ronin (Adversarial)
Watch for:
- **nats.swift API surface**: Their `NatsClient` class uses `NatsClientOptions` builder pattern. Map carefully to our protocol. Their subscription returns `NatsSubscription` with an `AsyncSequence` — adapt to our `AsyncStream<NATSMessage>`.
- **Auth token format**: nats-server expects `token: "xxx"` in config. nats.swift connects with `NatsClientOptions().token("xxx")`. Verify the token format matches what NATSConfig generates.
- **Reconnection behavior**: nats.swift has built-in reconnection with configurable max attempts and delay. Don't fight it — expose it through NATSClient init params.
- **Memory leak on subscription**: Each AsyncStream must clean up its nats.swift subscription when the stream is cancelled. Use `onTermination` handler.

### @Katana (Security)
nats-io/nats.swift is the official client from the NATS maintainers (Synadia). Apache-2.0 license, compatible with AGPL-3.0. Pin exact version. The mesh token auth (BR-06) is critical — ensure token is passed via TLS or at minimum not logged in plaintext. NATSConfig already generates tokens securely.

### @Kenshi (Release)
This unblocks `shi log --live` and `shi report --live` with real event streams instead of mock data. It's the bridge from "all tests pass with mocks" to "actually works in production." Should be in the next release cut.
