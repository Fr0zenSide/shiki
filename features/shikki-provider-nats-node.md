---
title: "Provider NATS Node — AI Providers as Discoverable Mesh Nodes"
status: draft
priority: P0
project: shikki
created: 2026-04-03
authors: "@Daimyo + @shi brainstorm"
tags:
  - nats
  - providers
  - discovery
  - fallback
depends-on:
  - shikki-node-security.md (mesh auth + heartbeat)
  - shikki-openai-compatible-provider.md (rename + multi-instance)
  - shikki-distributed-orchestration.md (NATS foundation)
relates-to:
  - shikki-dynamic-election-timing.md (latency telemetry feeds provider routing)
---

# Provider NATS Node

> If the orchestrator does not know your GPU is online, your GPU does not exist.

---

## 1. Problem

`FallbackProviderChain` is statically configured at compile time. The order is hardcoded: try Claude, then try LM Studio. There is no runtime awareness of which providers are actually online. If LM Studio is down, the chain still tries it (wasting timeout seconds). If a new Ollama server comes online, the chain has no way to discover it. Provider selection is blind.

Meanwhile, the NATS mesh already handles node discovery via `shikki.discovery.announce`. Every Shikki kernel node publishes heartbeats with identity and metrics. AI providers should be first-class mesh citizens with the same pattern.

---

## 2. Solution

Introduce `NodeKind.provider` alongside the existing orchestrator nodes. Each AI provider instance publishes heartbeats with model info (name, context window, speed). The orchestrator discovers available providers via `NodeRegistry` and builds `FallbackProviderChain` dynamically from the live registry. `shi nodes ls` shows providers alongside kernel nodes. Rate limit events publish to NATS so the mesh can route around saturated providers.

---

## 3. Business Rules

| ID | Rule |
|----|------|
| BR-01 | `NodeKind` enum added to `NodeIdentity`: `.orchestrator`, `.provider`, `.watcher` |
| BR-02 | Provider heartbeat includes: `modelName`, `contextWindow`, `speedTokensPerSec` (optional benchmark) |
| BR-03 | `NodeRegistry` tracks providers separately: `activeProviders` computed property |
| BR-04 | `shi nodes ls` displays providers with model info, latency, and health status |
| BR-05 | `FallbackProviderChain` can be rebuilt from `NodeRegistry.activeProviders` at dispatch time |
| BR-06 | Rate limit detection (429) MUST publish `shikki.provider.{nodeId}.rate_limited` NATS event |
| BR-07 | Provider health status: `.healthy`, `.degraded` (slow), `.offline` (stale heartbeat) |
| BR-08 | Provider auto-discovery: new provider heartbeat -> auto-added to available pool |
| BR-09 | Provider disappearance: stale heartbeat (3 intervals) -> removed from pool |
| BR-10 | tmux status line reads provider count from `.shikki/provider-status` cache |

---

## 4. TDDP

| # | Test | State |
|---|------|-------|
| 1 | `NodeKind` enum exists with `.orchestrator`, `.provider`, `.watcher` cases | RED |
| 2 | Impl: Add `NodeKind` to `NodeIdentity`, default `.orchestrator` for backward compat | GREEN |
| 3 | `ProviderHeartbeatPayload` includes modelName, contextWindow, speedTokensPerSec | RED |
| 4 | Impl: Extend `HeartbeatPayload` with optional provider metadata struct | GREEN |
| 5 | `NodeRegistry.activeProviders` returns only nodes with kind `.provider` | RED |
| 6 | Impl: Computed property filtering by `NodeKind` | GREEN |
| 7 | Provider auto-discovery: new heartbeat with kind `.provider` adds to registry | RED |
| 8 | Impl: `register()` handles `.provider` kind, stores provider metadata | GREEN |
| 9 | Provider stale removal: missing heartbeat for 3 intervals removes from `activeProviders` | RED |
| 10 | Impl: Stale detection reuses existing `isStale()`, filters in `activeProviders` | GREEN |
| 11 | `ProviderChainBuilder` creates FallbackProviderChain from registry | RED |
| 12 | Impl: Query `activeProviders`, instantiate `OpenAICompatibleProvider` per entry, build chain | GREEN |
| 13 | Rate limit publishes NATS event to `shikki.provider.{nodeId}.rate_limited` | RED |
| 14 | Impl: Catch 429 in provider, publish event via NATS client | GREEN |
| 15 | `shi nodes ls` output includes provider entries with model info | RED |
| 16 | Impl: `NodeCommand` formats provider entries with model, context window, health | GREEN |

---

## 5. S3 Scenarios

### Scenario 1: Provider registration via heartbeat (BR-01, BR-02, BR-08)
```
When  an OpenAI-compatible server publishes a heartbeat with kind .provider
  and  modelName "qwen2.5-coder-32b" and contextWindow 32768
Then  NodeRegistry adds it to activeProviders
  and  it appears in shi nodes ls
```

### Scenario 2: Dynamic chain building (BR-05)
```
When  NodeRegistry has 2 active providers:
      - "lm-studio" at :1234 with speed 45 tok/s
      - "ollama" at :11434 with speed 30 tok/s
Then  ProviderChainBuilder creates a FallbackProviderChain ordered by speed (fastest first)
  if  "lm-studio" goes stale
  then  next chain rebuild excludes it
```

### Scenario 3: Rate limit propagation (BR-06)
```
When  a provider returns HTTP 429
Then  the provider publishes shikki.provider.{nodeId}.rate_limited to NATS
  and  ProviderChainBuilder marks that provider as .degraded
  and  next chain rebuild deprioritizes it
```

### Scenario 4: Provider health lifecycle (BR-07, BR-09)
```
When  a provider sends regular heartbeats
Then  its health is .healthy
  if  response latency exceeds 2x its benchmark speed
  then  health transitions to .degraded
  if  no heartbeat for 3 intervals (90s default)
  then  health transitions to .offline and it is removed from activeProviders
```

### Scenario 5: shi nodes ls output (BR-04)
```
When  user runs shi nodes ls
Then  output shows:
      - Orchestrator nodes (existing format)
      - Provider nodes with: nodeId, modelName, contextWindow, health, latency
  depending on  provider health
    if  .healthy   then  green indicator
    if  .degraded  then  yellow indicator
    if  .offline   then  red indicator (only shown with --all flag)
```

### Scenario 6: tmux status line (BR-10)
```
When  provider status changes
Then  .shikki/provider-status cache is updated with provider count and health summary
  and  tmux status line reads from this file
```

---

## 6. Wave Dispatch Tree

```
Wave 1: NodeKind + Provider Metadata
  Input:   NodeIdentity.swift, HeartbeatPayload
  Output:  NodeKind enum, ProviderMetadata struct
  Gate:    Tests 1-4 green, existing heartbeat tests pass
  <- NOT BLOCKED

Wave 2: Registry + Auto-Discovery
  Input:   NodeRegistry.swift, NodeKind
  Output:  activeProviders, stale removal, provider health
  Gate:    Tests 5-10 green
  <- BLOCKED BY Wave 1

Wave 3: Dynamic Chain + Rate Limit Events
  Input:   FallbackProviderChain.swift, OpenAICompatibleProvider.swift, NATS
  Output:  ProviderChainBuilder, rate limit NATS events
  Gate:    Tests 11-14 green
  <- BLOCKED BY Wave 2

Wave 4: CLI + Status Line
  Input:   NodeCommand.swift, tmux integration
  Output:  shi nodes ls provider display, .shikki/provider-status
  Gate:    Tests 15-16 green
  <- BLOCKED BY Wave 2 (needs activeProviders)
```

---

## 7. Implementation Waves

### Wave 1: NodeKind + Provider Heartbeat Metadata
- **Files**: `Sources/ShikkiKit/NATS/NodeIdentity.swift` (extend)
- **Tests**: `Tests/ShikkiKitTests/NATS/NodeIdentityTests.swift` (extend)
- **BRs**: BR-01, BR-02
- **Deps**: None
- **Gate**: Tests 1-4 pass, existing `NodeIdentityTests` + `HeartbeatPayload` round-trip green

### Wave 2: Registry Provider Tracking
- **Files**: `Sources/ShikkiKit/NATS/NodeRegistry.swift` (extend)
- **Tests**: `Tests/ShikkiKitTests/NATS/NodeRegistryTests.swift` (extend)
- **BRs**: BR-03, BR-07, BR-08, BR-09
- **Deps**: Wave 1
- **Gate**: Tests 5-10 pass

### Wave 3: Dynamic Chain Builder + Rate Limit Events
- **Files**: `Sources/ShikkiKit/Providers/ProviderChainBuilder.swift` (new), `Sources/ShikkiKit/Providers/OpenAICompatibleProvider.swift` (add rate limit publish)
- **Tests**: `Tests/ShikkiKitTests/Providers/ProviderChainBuilderTests.swift`
- **BRs**: BR-05, BR-06
- **Deps**: Wave 2
- **Gate**: Tests 11-14 pass

### Wave 4: CLI Display + tmux Status
- **Files**: `Sources/shikki/Commands/NodeCommand.swift` (extend), tmux status integration
- **Tests**: `Tests/ShikkiKitTests/NATS/NodeCommandTests.swift`
- **BRs**: BR-04, BR-10
- **Deps**: Wave 2
- **Gate**: Tests 15-16 pass, `shi nodes ls` renders provider entries

---

## 8. @shi Mini-Challenge

1. **@Ronin**: `ProviderChainBuilder` orders providers by speed (tokens/sec from benchmark). But benchmark speed is self-reported via heartbeat -- a provider can lie. Should the orchestrator run its own micro-benchmark (10-token prompt, measure wall time) on first discovery, and use that instead of self-reported numbers?

2. **@Sensei**: Provider heartbeats use the same `shikki.discovery.announce` subject as orchestrator nodes. Should providers have their own subject (`shikki.discovery.provider`) to avoid polluting the orchestrator's discovery stream, or is a single subject with `NodeKind` filtering cleaner? Single subject is simpler but means every orchestrator node processes provider heartbeats it doesn't need.
