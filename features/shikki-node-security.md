# Feature: Shikki Node Security — Auth + Leader Election
> Created: 2026-03-30 | Status: Phase 3 — Business Rules | Owner: @Daimyo

## Context

NATS node discovery (`shikki.discovery.announce`) currently accepts any JSON payload that decodes to `HeartbeatPayload`. There is zero authentication — any NATS publisher on the bus can register a fake node, claim the primary role, and hijack the dispatch loop.

Additionally, there is no leader election protocol. `NodeIdentity.current()` defaults `role: .primary`, and `NodeRegistry.register()` blindly stores whatever role the heartbeat claims. Two nodes can both declare themselves primary simultaneously, causing a split-brain condition where both dispatch work, duplicate events, and corrupt state.

This must be fixed before multi-node goes live. The zero-downtime upgrade spec (`shikki-zero-downtime-upgrade.md`) depends on a PROMOTE step that assumes exactly one primary at any time.

## Inspiration
### Diagnostic (2026-03-30)

Code audit of `NodeRegistry.swift`, `NodeHeartbeat.swift`, and `NodeIdentity.swift`:

| # | Vulnerability | Source | Severity | Impact |
|---|--------------|--------|:--------:|:------:|
| 1 | No auth on `shikki.discovery.announce` — any publisher registers a node | @Katana | **Critical** | Rogue node takeover, event poisoning |
| 2 | `NodeRegistry.register()` accepts any role claim without validation | @Katana | **Critical** | Split brain — multiple primaries |
| 3 | No leader election — `NodeIdentity.current()` defaults to `.primary` | @Sensei | **Blocking** | Every new node self-declares primary |
| 4 | No fencing mechanism — no way to resolve conflicting primary claims | @Sensei | **Blocking** | Unrecoverable split brain |
| 5 | No `shikki.node.primary` subject — PROMOTE step from zero-downtime spec has no wire protocol | @Sensei | High | Upgrade handoff cannot execute |
| 6 | Heartbeat rejection leaks info (error response to invalid payload) | @Katana | Medium | Attacker fingerprints the mesh |
| 7 | meshToken not implemented — no pre-shared secret for mesh membership | @Katana | **Critical** | Zero-trust boundary missing |
| 8 | No `primaryCount` observable — split brain undetectable by monitoring | @Ronin | Medium | Silent data corruption |

### Selected Ideas
All 8 vulnerabilities retained — they form a cohesive authentication + leader election layer.

## Synthesis

**Goal**: Add mesh authentication via pre-shared meshToken and implement deterministic leader election so exactly one node holds primary at any time.

**Scope**:
- Add `meshToken` field to `HeartbeatPayload` and validate on receipt
- `NodeRegistry` rejects payloads with missing or invalid meshToken
- Leader election via fencing: oldest `startedAt` wins in case of conflict
- New node must go through SHADOW -> VERIFY -> PROMOTE sequence to claim primary
- Publish primary claim to `shikki.node.primary` subject
- Expose `primaryCount` for split-brain alerting
- Auto-promote shadow when primary is silent for 3 heartbeat intervals
- Secure meshToken storage (env var `SHIKKI_MESH_TOKEN`, never in git)

**Out of scope**:
- TLS/mTLS between NATS nodes (handled by NATS server config)
- Certificate-based auth (future — meshToken is sufficient for v0.3)
- Multi-cluster mesh (single NATS cluster assumed)

**Success criteria**:
- Heartbeat without valid meshToken is silently dropped
- At any point in time, `primaryCount` is 0 or 1
- When primary goes silent, shadow auto-promotes within 3 heartbeat intervals
- Zero-downtime upgrade PROMOTE step works against this leader election
- No information leak on invalid heartbeat

**Dependencies**:
- `NodeIdentity.swift`, `NodeHeartbeat.swift`, `NodeRegistry.swift` (modify)
- `NATSSubjectMapper` in `EventLoggerNATS.swift` (add `nodePrimary` subject)
- `MockNATSClient.swift` (test infrastructure already exists)

## Business Rules

```
BR-01: Every heartbeat payload MUST include a meshToken (pre-shared secret)
BR-02: NodeRegistry MUST reject registration if meshToken doesn't match the configured mesh secret
BR-03: Only ONE node may have role `.primary` at any time
BR-04: If a second node claims primary, the OLDER primary wins (fencing by startedAt)
BR-05: New node requesting primary MUST go through SHADOW -> VERIFY -> PROMOTE sequence
BR-06: Primary claim MUST be published to `shikki.node.primary` with the node's signature (nodeId + startedAt + meshToken hash)
BR-07: NodeRegistry MUST expose `primaryCount` and alert when > 1
BR-08: meshToken MUST be stored securely (not in git — use env var SHIKKI_MESH_TOKEN or Vaultwarden)
BR-09: Heartbeat without valid meshToken MUST be silently dropped (no error response that leaks info)
BR-10: Leader election timeout: if primary is silent for 3 heartbeat intervals, shadow auto-promotes
```

## Test Plan

### Scenario 1: Valid heartbeat with meshToken (BR-01, BR-02)
```
GIVEN a NodeHeartbeat configured with meshToken "mesh-secret-42"
WHEN  it publishes a heartbeat to shikki.discovery.announce
THEN  the HeartbeatPayload.meshToken field equals the SHA-256 hash of "mesh-secret-42"
AND   NodeRegistry accepts the registration
AND   the node appears in activeNodes
```

### Scenario 2: Invalid meshToken rejected silently (BR-02, BR-09)
```
GIVEN NodeRegistry configured with meshToken "mesh-secret-42"
WHEN  a heartbeat arrives with meshToken hash of "wrong-token"
THEN  NodeRegistry does NOT register the node
AND   no error message is published to NATS (silent drop)
AND   activeNodes count remains unchanged
AND   no log line above .debug level is emitted (no info leak)
```

### Scenario 3: Missing meshToken rejected (BR-01, BR-09)
```
GIVEN NodeRegistry configured with meshToken "mesh-secret-42"
WHEN  a heartbeat arrives with meshToken == nil (legacy payload)
THEN  NodeRegistry does NOT register the node
AND   activeNodes count remains unchanged
```

### Scenario 4: Split-brain prevention — older primary wins (BR-03, BR-04)
```
GIVEN NodeA is primary with startedAt = T0
AND   NodeB is primary with startedAt = T0 + 30s
WHEN  NodeB's heartbeat arrives claiming role .primary
THEN  NodeRegistry keeps NodeA as primary (older startedAt wins)
AND   NodeB is demoted to .shadow
AND   primaryCount == 1
```

### Scenario 5: SHADOW -> VERIFY -> PROMOTE sequence (BR-05, BR-06)
```
GIVEN NodeA is primary (startedAt T0)
AND   NodeB joins as .shadow
WHEN  NodeB requests promotion via shikki.node.primary
THEN  NodeB enters VERIFY state (observes for 1 heartbeat interval)
AND   after VERIFY, NodeB publishes a PrimaryClaim to shikki.node.primary
AND   the claim includes nodeId, startedAt, and meshTokenHash
AND   NodeA receives the claim and enters .draining
AND   NodeRegistry confirms exactly 1 primary (NodeB)
```

### Scenario 6: Auto-promote on primary silence (BR-10)
```
GIVEN NodeA is primary with heartbeat interval 30s
AND   NodeB is shadow
WHEN  NodeA sends no heartbeat for 90s (3 intervals)
THEN  NodeRegistry marks NodeA as stale
AND   NodeB auto-promotes to primary
AND   NodeB publishes PrimaryClaim to shikki.node.primary
AND   primaryCount == 1
```

### Scenario 7: primaryCount alert (BR-07)
```
GIVEN NodeA is primary
WHEN  a bug or race causes NodeB to also be registered as primary
THEN  primaryCount == 2
AND   NodeRegistry emits a .warning log "Split brain detected: 2 primaries"
AND   the older primary (by startedAt) is preserved
AND   the newer primary is demoted to .shadow
```

### Scenario 8: meshToken from environment (BR-08)
```
GIVEN SHIKKI_MESH_TOKEN env var is set to "env-secret-99"
WHEN  MeshTokenProvider.load() is called
THEN  it returns "env-secret-99"
AND   the token is never written to disk or logs

GIVEN SHIKKI_MESH_TOKEN is not set
WHEN  MeshTokenProvider.load() is called
THEN  it throws MeshTokenError.notConfigured
AND   the error message instructs the user to set SHIKKI_MESH_TOKEN
```

## Architecture

### Files to Modify

| File | Modification | BRs |
|------|-------------|-----|
| `NodeIdentity.swift` | Add `meshTokenHash: String?` field to `HeartbeatPayload` | BR-01 |
| `NodeIdentity.swift` | Add `PrimaryClaim` struct for leader election messages | BR-06 |
| `NodeHeartbeat.swift` | Hash meshToken into every heartbeat before publish | BR-01, BR-08 |
| `NodeHeartbeat.swift` | Add `onPrimaryLost` callback + auto-promote logic for shadow | BR-10 |
| `NodeRegistry.swift` | Add `meshTokenHash` config + validate on `register()` | BR-02, BR-09 |
| `NodeRegistry.swift` | Add `primaryCount` computed property + split-brain detection | BR-03, BR-04, BR-07 |
| `NodeRegistry.swift` | Enforce single-primary invariant with startedAt fencing | BR-04 |
| `EventLoggerNATS.swift` | Add `NATSSubjectMapper.nodePrimary` subject | BR-06 |
| `MockNATSClient.swift` | No changes — already supports `injectMessage` for testing | — |

### Files to Create

| File | Purpose | BRs |
|------|---------|-----|
| `NATS/MeshTokenProvider.swift` | Load meshToken from env var, hash with SHA-256 | BR-08 |
| `NATS/LeaderElection.swift` | `LeaderElection` actor — SHADOW->VERIFY->PROMOTE FSM, auto-promote timer | BR-05, BR-06, BR-10 |
| `Tests/NodeSecurityTests.swift` | All 8 test scenarios | All BRs |

### New Types

```swift
// MeshTokenProvider.swift
public enum MeshTokenError: Error, Sendable {
    case notConfigured
}

public struct MeshTokenProvider: Sendable {
    public static func load() throws -> String  // reads SHIKKI_MESH_TOKEN
    public static func hash(_ token: String) -> String  // SHA-256 hex
}

// LeaderElection.swift
public enum ElectionState: String, Sendable {
    case idle       // no election in progress
    case shadow     // observing, not claiming
    case verify     // pre-promote observation window
    case promoting  // publishing claim
    case primary    // won election
}

public actor LeaderElection {
    public init(identity: NodeIdentity, registry: NodeRegistry,
                nats: any NATSClientProtocol, meshToken: String,
                heartbeatInterval: Duration = .seconds(30))

    public func start() async throws   // subscribe to shikki.node.primary
    public func requestPromotion() async throws  // SHADOW -> VERIFY -> PROMOTE
    public func handlePrimarySilence() async     // auto-promote after 3 intervals
    public var state: ElectionState { get }
}

// NodeIdentity.swift additions
public struct PrimaryClaim: Codable, Sendable {
    public let nodeId: String
    public let startedAt: Date
    public let meshTokenHash: String
    public let claimedAt: Date
}
```

### Modified HeartbeatPayload

```swift
// Add to existing HeartbeatPayload in NodeIdentity.swift
public struct HeartbeatPayload: Codable, Sendable {
    public let identity: NodeIdentity
    public let timestamp: Date
    public let uptimeSeconds: TimeInterval
    public let activeAgents: Int
    public let contextUsedPct: Int
    public let meshTokenHash: String?  // NEW — nil means legacy/unauthenticated
}
```

### Modified NodeRegistry.register()

```swift
// NodeRegistry — new validation flow
public func register(_ identity: NodeIdentity, meshTokenHash: String?) {
    // BR-09: silently drop if no token or wrong token
    guard let hash = meshTokenHash,
          hash == self.expectedMeshTokenHash else {
        return  // silent drop — no log above .debug
    }

    // BR-04: if claiming primary and another primary exists, fence by startedAt
    if identity.role == .primary, let existing = currentPrimary {
        if existing.identity.startedAt <= identity.startedAt {
            // Existing primary is older — demote incoming to shadow
            var demoted = identity
            demoted.role = .shadow
            nodes[identity.nodeId] = NodeEntry(identity: demoted, lastSeen: Date(), isStale: false)
            return
        }
        // Incoming is older — demote existing
        nodes[existing.identity.nodeId]?.identity.role = .shadow
    }

    nodes[identity.nodeId] = NodeEntry(identity: identity, lastSeen: Date(), isStale: false)
}
```

## Execution Plan

### Task 1: MeshTokenProvider
- **Files**: Create `NATS/MeshTokenProvider.swift`
- **Implement**: `load()` reads `SHIKKI_MESH_TOKEN` env var, `hash()` produces SHA-256 hex string via `CryptoKit`
- **Verify**: Unit test — set env, load, verify hash matches expected
- **BRs**: BR-08
- **Time**: ~5 min

### Task 2: Add meshTokenHash to HeartbeatPayload
- **Files**: Modify `NodeIdentity.swift`
- **Implement**: Add `meshTokenHash: String?` field with default `nil` for backward compat. Add `PrimaryClaim` struct.
- **Verify**: Existing tests still compile. Encode/decode round-trip with new field.
- **BRs**: BR-01, BR-06
- **Time**: ~5 min

### Task 3: NodeHeartbeat hashes meshToken into payloads
- **Files**: Modify `NodeHeartbeat.swift`
- **Implement**: Accept `meshToken: String` in init, hash it via `MeshTokenProvider.hash()`, include in every `publishHeartbeat()` call
- **Verify**: Mock NATS captures published payload with `meshTokenHash` field
- **BRs**: BR-01, BR-08
- **Time**: ~5 min

### Task 4: NodeRegistry validates meshToken on register
- **Files**: Modify `NodeRegistry.swift`
- **Implement**: Add `expectedMeshTokenHash: String?` to init. In `register()`, silently drop if hash missing or mismatched. No log above `.debug`.
- **Verify**: Test scenario 2 + 3 — invalid/missing token leaves activeNodes unchanged
- **BRs**: BR-02, BR-09
- **Time**: ~8 min

### Task 5: Single-primary invariant with startedAt fencing
- **Files**: Modify `NodeRegistry.swift`
- **Implement**: In `register()`, if incoming role is `.primary` and another primary exists, compare `startedAt`. Older wins. Add `primaryCount` computed property. Log warning if ever > 1 during transient window.
- **Verify**: Test scenario 4 + 7 — older primary preserved, newer demoted
- **BRs**: BR-03, BR-04, BR-07
- **Time**: ~10 min

### Task 6: LeaderElection actor
- **Files**: Create `NATS/LeaderElection.swift`
- **Implement**: FSM with states `idle -> shadow -> verify -> promoting -> primary`. Subscribe to `shikki.node.primary`. `requestPromotion()` transitions through verify (1 interval wait) then publishes `PrimaryClaim`. `handlePrimarySilence()` triggers auto-promote after 3 intervals.
- **Verify**: Test scenario 5 + 6 — full promotion sequence + auto-promote on silence
- **BRs**: BR-05, BR-06, BR-10
- **Time**: ~15 min

### Task 7: Add `nodePrimary` to NATSSubjectMapper
- **Files**: Modify `EventLoggerNATS.swift`
- **Implement**: `public static var nodePrimary: String { "shikki.node.primary" }`
- **Verify**: Compile check
- **BRs**: BR-06
- **Time**: ~1 min

### Task 8: NodeSecurityTests
- **Files**: Create `Tests/ShikkiKitTests/NodeSecurityTests.swift`
- **Implement**: All 8 scenarios from test plan. Use `MockNATSClient` + `@Suite("NodeSecurity")`. Test meshToken validation, split-brain prevention, auto-promote, PrimaryClaim wire format.
- **Verify**: `swift test --filter NodeSecurityTests` — all pass
- **BRs**: All
- **Time**: ~20 min

### Task 9: Update NodeHeartbeat subscription to validate meshToken
- **Files**: Modify `NodeHeartbeat.swift`
- **Implement**: In the `subscribe(subject: discoveryAnnounce)` handler, pass `meshTokenHash` to `registry.register()` instead of calling `register(payload.identity)` directly
- **Verify**: End-to-end test — inject invalid heartbeat via MockNATS, verify node not registered
- **BRs**: BR-02, BR-09
- **Time**: ~5 min

## Implementation Readiness Gate

| Check | Status | Detail |
|-------|--------|--------|
| BR Coverage | PASS | 10/10 BRs mapped to tasks |
| Test Coverage | PASS | 8/8 scenarios mapped to Task 8 |
| File Alignment | PASS | 5 modify + 3 create — all identified |
| Task Dependencies | PASS | Tasks 1-2 first (types), 3-5 (consumers), 6-7 (election), 8-9 (tests + wiring) |
| Task Granularity | PASS | All tasks 1-20 min |
| Testability | PASS | MockNATSClient already supports injectMessage for all scenarios |
| Security Review | PASS | meshToken hashed (never sent raw), silent drop (no info leak), env var storage |

**Verdict: PASS** — ready for Phase 6.

## @shi Mini-Challenge

1. **@Ronin**: During the VERIFY phase, the new node observes for 1 heartbeat interval. What if the old primary crashes exactly during this window? The new node is in verify, not yet primary — who handles dispatch for that interval? Should verify have a fast-path if primary disappears mid-verification?
2. **@Katana**: meshToken is a pre-shared secret stored in an env var. If an attacker has shell access, they can read env vars. Should we add a secondary factor — e.g., the node's binary hash must match a known-good hash from the DB? Or is that overengineering for v0.3?
3. **@Sensei**: `startedAt` fencing means a long-running node always wins. But what if the long-running node is the one with the bug (stale binary)? Should the zero-downtime upgrade PROMOTE explicitly override fencing, or should the old node voluntarily yield by switching to `.draining` before the new node claims?

## Review History
| Date | Phase | Reviewer | Decision | Notes |
|------|-------|----------|----------|-------|
| 2026-03-30 | Phase 1-5b | @Katana | APPROVED | Code audit + spec in one session |
