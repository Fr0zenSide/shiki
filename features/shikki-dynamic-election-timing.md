---
title: "Dynamic Election Timing — Latency-Adaptive Objection Window"
status: draft
priority: P0
project: shikki
created: 2026-04-03
authors: "@Daimyo + @shi brainstorm"
tags:
  - nats
  - leader-election
  - telemetry
  - resilience
depends-on:
  - shikki-node-security.md (LeaderElection + objection window)
  - shikki-distributed-orchestration.md (NATS foundation)
relates-to:
  - shikki-zero-downtime-upgrade.md (PROMOTE depends on election timing)
---

# Dynamic Election Timing

> A fixed 1s objection window is a lie. Network latency decides the real window.

---

## 1. Problem

`LeaderElection` uses a hardcoded `objectionWindow: .seconds(1)`. After publishing a `PrimaryClaim`, the node sleeps 1s then assumes primary. If any node has >500ms round-trip latency to the NATS bus, it cannot receive the claim, evaluate it, and publish an objection in time. Result: two primaries, split brain.

The 1s default is arbitrary. On a local Mac it is generous. On a VPS with transatlantic latency it is dangerously short. The window must adapt to observed network conditions.

---

## 2. Solution

Collect per-node latency telemetry via heartbeat round-trip measurement. Compute the objection window dynamically as `2.5x max(observed_latency)` -- enough time for the claim to reach the slowest node, that node to process it, and the objection to travel back. Enforce a floor (500ms) and ceiling (10s) for safety. Fall back to the current 1s default when no telemetry is available.

---

## 3. Business Rules

| ID | Rule |
|----|------|
| BR-01 | NodeHeartbeat MUST measure round-trip latency per heartbeat (publish timestamp vs ack/echo timestamp) |
| BR-02 | NodeRegistry MUST track rolling average latency per node (last 10 samples) |
| BR-03 | Dynamic objection window = `2.5 * max(avgLatency across all active nodes)` |
| BR-04 | Objection window MUST have a floor of 500ms (never shorter) |
| BR-05 | Objection window MUST have a ceiling of 10s (never longer) |
| BR-06 | When no telemetry data exists (cold start, single node), fall back to 1s default |
| BR-07 | LeaderElection MUST query `NodeRegistry.computedObjectionWindow` before entering the promoting state |
| BR-08 | Latency samples older than 5 minutes MUST be evicted from the rolling window |

---

## 4. TDDP

| # | Test | State |
|---|------|-------|
| 1 | `LatencyTracker` stores per-node latency samples, returns rolling average | RED |
| 2 | Impl: `LatencyTracker` with `record(nodeId:, latency:)` and `average(for:)` | GREEN |
| 3 | `LatencyTracker` evicts samples older than 5 minutes | RED |
| 4 | Impl: Timestamp-based eviction in `record()` | GREEN |
| 5 | `NodeRegistry.computedObjectionWindow` returns 2.5x max avg latency | RED |
| 6 | Impl: Query `LatencyTracker`, apply formula, clamp to [500ms, 10s] | GREEN |
| 7 | `computedObjectionWindow` returns 1s default when no telemetry exists | RED |
| 8 | Impl: Guard on empty tracker, return `.seconds(1)` | GREEN |
| 9 | `computedObjectionWindow` clamps to 500ms floor | RED |
| 10 | Impl: `max(floor, computed)` | GREEN |
| 11 | `computedObjectionWindow` clamps to 10s ceiling | RED |
| 12 | Impl: `min(ceiling, computed)` | GREEN |
| 13 | `LeaderElection.requestPromotion()` uses dynamic window instead of static | RED |
| 14 | Impl: Call `registry.computedObjectionWindow` before `Task.sleep` | GREEN |
| 15 | NodeHeartbeat publishes latency measurement on echo receipt | RED |
| 16 | Impl: Timestamp diff on heartbeat echo, call `registry.recordLatency()` | GREEN |

---

## 5. S3 Scenarios

### Scenario 1: Dynamic window from telemetry (BR-01, BR-02, BR-03)
```
When  NodeA records avg latency 200ms and NodeB records avg latency 400ms
Then  computedObjectionWindow = 2.5 * 400ms = 1000ms
```

### Scenario 2: Floor enforcement (BR-04)
```
When  all nodes have avg latency 50ms (2.5 * 50 = 125ms)
Then  computedObjectionWindow = 500ms (floor applied)
```

### Scenario 3: Ceiling enforcement (BR-05)
```
When  a node reports avg latency 5000ms (2.5 * 5000 = 12500ms)
Then  computedObjectionWindow = 10s (ceiling applied)
```

### Scenario 4: Cold start fallback (BR-06)
```
When  LatencyTracker has zero samples
Then  computedObjectionWindow = 1s (default)
```

### Scenario 5: Stale sample eviction (BR-08)
```
When  a latency sample was recorded 6 minutes ago
Then  it is evicted from the rolling window on next record() call
  if  no other samples remain for that node
  then  that node is excluded from max calculation
```

### Scenario 6: Election uses dynamic window (BR-07)
```
When  LeaderElection enters promoting state
Then  it queries registry.computedObjectionWindow
  and sleeps for that duration before claiming primary
  depending on  whether telemetry exists
    if  telemetry exists  then  dynamic window is used
    otherwise  1s default is used
```

---

## 6. Wave Dispatch Tree

```
Wave 1: LatencyTracker
  Input:   NodeIdentity.swift, NodeRegistry.swift
  Output:  LatencyTracker.swift (new), NodeRegistry+Latency (extension)
  Gate:    Tests 1-4 green
  ← NOT BLOCKED

Wave 2: Computed Objection Window
  Input:   LatencyTracker.swift, NodeRegistry.swift
  Output:  NodeRegistry.computedObjectionWindow
  Gate:    Tests 5-12 green
  ← BLOCKED BY Wave 1

Wave 3: Integration — LeaderElection + Heartbeat
  Input:   LeaderElection.swift, NodeHeartbeat.swift
  Output:  Dynamic window wiring, heartbeat latency recording
  Gate:    Tests 13-16 green
  ← BLOCKED BY Wave 2
```

---

## 7. Implementation Waves

### Wave 1: LatencyTracker (new file)
- **Files**: `Sources/ShikkiKit/NATS/LatencyTracker.swift`
- **Tests**: `Tests/ShikkiKitTests/NATS/LatencyTrackerTests.swift`
- **BRs**: BR-01, BR-02, BR-08
- **Deps**: None
- **Gate**: Tests 1-4 pass, `swift test --filter LatencyTracker`

### Wave 2: Computed Objection Window
- **Files**: `Sources/ShikkiKit/NATS/NodeRegistry.swift` (extend)
- **Tests**: `Tests/ShikkiKitTests/NATS/DynamicElectionTimingTests.swift`
- **BRs**: BR-03, BR-04, BR-05, BR-06
- **Deps**: Wave 1
- **Gate**: Tests 5-12 pass

### Wave 3: Integration
- **Files**: `Sources/ShikkiKit/NATS/LeaderElection.swift`, `Sources/ShikkiKit/NATS/NodeHeartbeat.swift`
- **Tests**: `Tests/ShikkiKitTests/NATS/LeaderElectionTests.swift` (extend)
- **BRs**: BR-07, BR-01 (heartbeat echo)
- **Deps**: Wave 2
- **Gate**: Tests 13-16 pass, existing `LeaderElectionTests` still green

---

## 8. @shi Mini-Challenge

1. **@Ronin**: The 2.5x multiplier assumes symmetric latency (same RTT in both directions). What if a node has asymmetric network (fast outbound, slow inbound)? The echo-based measurement sees the round trip, but the claim only travels one way. Should the formula use 1.5x RTT instead, since the claim needs one hop + processing + one hop back for the objection?

2. **@Katana**: A malicious node could artificially inflate its latency samples to force a longer objection window, creating a denial-of-service on election speed. Should `LatencyTracker` cap individual samples at a reasonable maximum (e.g., 5s) and discard outliers beyond 3 standard deviations?
