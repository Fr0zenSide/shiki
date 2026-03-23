# Feature: Shiki Mesh Protocol
> Created: 2026-03-22 | Status: Phase 1 — Inspiration | Owner: @Daimyo

## Context
Shiki needs a universal protocol for distributed compute across heterogeneous devices (Mac, Linux VPS, iPhone, iPad, gaming PC) AND virtual nodes (Claude API, OpenAI, any external LLM). Every node — physical or virtual — registers capabilities, receives work, returns results. The mesh enables: distributed inference (exo-style model sharding), overnight batch processing (3D render farm model), team compute pooling, and agent migration between devices.

Key insight from @Daimyo: **external AI services (Claude Code, OpenCode, any LLM API) are virtual nodes with the capacity of an LLM/agent and a budget**. They join the mesh like any other device — just with different capability profiles and cost structures.

## Inspiration
### Brainstorm Results

| # | Idea | Source | Feasibility | Impact | Project Fit | Verdict |
|---|------|--------|:-----------:|:------:|:-----------:|--------:|
| 1 | **Capability Passport** — Signed capability manifest per node (hw specs, model support, latency SLA, cost/token). Routes tasks by matching job requirements to node passports. Claude API and Mac Studio are first-class peers with negotiable contracts. | @Shogun | Medium | High | Strong | BUILD |
| 2 | **Deterministic Replay Rail** — Every agent invocation recorded as typed immutable event (input hash → output hash → node ID → latency → cost). Full replay, diff-based regression, audit without re-running inference. Karpathy's march of nines operationalized. | @Shogun | Medium | High | Strong | BUILD |
| 3 | **Overnight Batch Governor** — 3D render farm scheduling. Queues compute-heavy jobs, dispatches to cheapest nodes during off-peak. Teams define budget envelope + deadline, Governor optimizes across the mesh. Zero YAML, zero ops. | @Shogun | High | Medium | Strong | BUILD |
| 4 | **Heartbeat Map** — Ambient display (terminal pane, menu bar, iPhone widget) showing every node as pulsing dot. Size = load, color = health, lines trace active agents. You feel the mesh breathing. | @Hanami | Medium | High | Strong | BUILD |
| 5 | **Handoff Shadow** — Close laptop lid → shadow copy of agent context migrates to nearest node before lid shuts. iPhone notification: "Picked up by Mac Studio · 3 tasks running." No lost work, no manual intervention. | @Hanami | Medium | High | Strong | BUILD |
| 6 | **Budget Conscience** — Virtual nodes carry visible spend meter. Glows amber near threshold. One-tap: "This will cost ~$0.18 — run on local node instead?" Financial sovereignty without micromanaging. | @Hanami | High | High | Strong | BUILD |
| 7 | **En-Graph (縁グラフ)** — Affinity routing: tasks flow toward nodes with historical context, warm cache, relational proximity. Continuity as respect for the work. Routing as tending relationships, not load-balancing. | @Kintsugi | Medium | High | Strong | BUILD |
| 8 | **Wabi-Budget** — Nodes declare what they *choose not to do* (refusal vocabulary) alongside capabilities. Mesh honors refusals as first-class signals. A node's limits are its character, not a failure condition. | @Kintsugi | High | Medium | Strong | BUILD |
| 9 | **CapabilityManifest + TopologyGraph** — Signed `CapabilityManifest` struct per node. ShikiCore maintains `TopologyGraph` (rustworkx/Swift graph) reconciling manifests via SwiftNIO/mDNS. AgentProvider gains `resolve(task:) -> Node`. Claude API = node with `backend: .api(provider: .anthropic)`, `costPerToken: 0.000015`. | @Sensei | Medium | High | Strong | BUILD |
| 10 | **PipelineSlice** — Inference as DAG of numbered LayerSlice stages, each assignable to any compatible node. Mac Studio owns early layers (MLX), gaming PC owns late layers (CUDA), API node = terminal black-box stage. SwiftNIO ByteBuffer frames carry inter-slice tensors over mTLS. | @Sensei | Low | High | Medium | DEFER |

### Selected Ideas

**@Daimyo selection**: BUILD all 9 (ideas 1-9). DEFER #10 (PipelineSlice — use exo as a mesh node instead of reimplementing tensor sharding). Ideas #1 and #9 merge into one: **CapabilityManifest** (@Sensei's implementation of @Shogun's Capability Passport).

**8 pillars carried forward:**
1. CapabilityManifest + TopologyGraph (foundation protocol)
2. Deterministic Replay Rail (audit + reliability)
3. Overnight Batch Governor (render farm scheduling)
4. Heartbeat Map (ambient mesh visualization)
5. Handoff Shadow (agent migration on lid close)
6. Budget Conscience (virtual node cost UX)
7. En-Graph (affinity routing)
8. Wabi-Budget (refusal vocabulary)

## Synthesis

### Feature Brief

**Goal**: A universal protocol where any device (physical) or AI service (virtual) joins the Shiki mesh by declaring capabilities, receives work matched to its profile, and returns results — enabling distributed compute, agent migration, overnight batch processing, and team compute pooling.

**Scope (v1)**:
- CapabilityManifest struct: hardware profile, backends, cost, latency, availability, refusal set
- Node registration + discovery (mDNS for local, manual for remote/virtual)
- TopologyGraph: live map of all nodes and their capabilities
- Task routing: `resolve(task:) -> Node` via AgentProvider
- Virtual node adapter: Claude API, OpenAI, any LLM API as mesh nodes with budget
- Budget tracking per node (physical = compute credits, virtual = API spend)
- Heartbeat protocol: nodes report health, load, active tasks
- Basic affinity hints (warm cache, last-used-for-company)

**Scope (v2 — post-v1)**:
- Handoff Shadow (agent state migration between nodes)
- Overnight Batch Governor (scheduled off-peak dispatch)
- Heartbeat Map TUI / iPhone widget
- Deterministic Replay Rail (event log + replay)
- Team compute pooling (multi-user mesh join)
- En-Graph affinity routing (full relational scoring)
- exo integration as a mesh node (distributed model inference)

**Out of scope**:
- Tensor-level layer sharding (PipelineSlice — use exo directly)
- Model training / fine-tuning orchestration
- Payment/billing between team members
- Custom hardware driver development

**Success criteria**:
- A Mac Studio and a Claude API key register as mesh nodes with the same protocol
- `shiki mesh status` shows all nodes, capabilities, health, spend
- Task dispatch routes to optimal node based on capability + cost + affinity
- iPhone can join as edge node (CoreML, approvals)
- Linux VPS can join as headless node (CPU inference, DB, API gateway)
- Budget limits respected: virtual node stops when daily spend hits threshold

**Dependencies**:
- ShikiCore (FeatureLifecycle FSM, AgentProvider protocol)
- ShikiDB (node registry, event persistence)
- SwiftNIO (networking layer)
- ShikiMCP (mesh status queries)

## Business Rules

### Node Identity & Registration

```
BR-01: Every mesh node has a unique NodeID (UUID v4) generated on first registration
       and persisted locally. The ID survives reboots.
BR-02: A node is either PHYSICAL (device with compute) or VIRTUAL (API endpoint with budget).
       The mesh treats both identically at the protocol level.
BR-03: Registration requires a CapabilityManifest containing:
       - nodeId, nodeType (physical|virtual), displayName
       - compute: backends[] (mlx, cuda, coreml, ggml, cpu, api), vram, memory
       - cost: costPerToken (0 for physical), dailyBudget, spentToday
       - availability: schedule (always|scheduled|mobile), latencyP50ms
       - refusals: taskKinds[] the node will NOT accept (Wabi-Budget)
BR-04: A node may update its manifest at any time (e.g., budget spent changes,
       availability shifts from "always" to "sleeping"). Updates propagate within
       one heartbeat cycle.
```

### Discovery & Topology

```
BR-05: Local network nodes are discovered via mDNS (Bonjour on Apple, Avahi on Linux).
       Zero configuration required for LAN devices.
BR-06: Remote nodes (VPS, API endpoints) are added manually via
       `shiki mesh add --url <endpoint>` or config file (~/.config/shiki/mesh.toml).
BR-07: The TopologyGraph is maintained by the orchestrator node (the one running
       ShikiCore). All other nodes report TO the orchestrator via heartbeat.
BR-08: If the orchestrator goes offline, nodes continue their current work but
       do not accept new tasks. On reconnect, state reconciles automatically.
BR-09: A node that misses 3 consecutive heartbeats is marked STALE.
       After 10 missed heartbeats, marked DEAD and removed from routing.
```

### Task Routing

```
BR-10: Task routing uses a scoring function:
       score(node, task) = capability_match * (1 / cost_weight) * affinity_bonus * availability
       Highest score wins. Ties broken by lowest latency.
BR-11: A task specifies required capabilities as TaskRequirements:
       - minVram, requiredBackends[], maxLatencyMs, maxCostPerToken
       - preferredNodeId (affinity hint, not mandatory)
BR-12: If no node satisfies TaskRequirements, the task is queued with status WAITING.
       The orchestrator retries on each heartbeat cycle.
BR-13: A node may reject a dispatched task (overloaded, budget exceeded, in refusal set).
       The orchestrator re-routes to the next-best node.
BR-14: Virtual nodes (API) are scored with a cost penalty proportional to spend/budget
       ratio. As spend approaches dailyBudget, the node becomes less preferred,
       naturally routing to local nodes first.
```

### Budget & Cost

```
BR-15: Physical nodes have cost = 0 per token (electricity is externalized).
       Virtual nodes declare costPerToken from their API pricing.
BR-16: Each virtual node has a dailyBudget. When spentToday >= dailyBudget,
       the node transitions to BUDGET_PAUSED and stops accepting tasks.
BR-17: Budget resets daily at midnight in the node's configured timezone.
BR-18: Budget alerts trigger at 80% spent (amber) via the mesh event bus.
       At 95%, a T1 decision is created: "Continue spending or pause?"
BR-19: The Budget Conscience UX surfaces cost comparison before dispatch:
       "Task X: ~$0.18 on Claude, ~0s on Mac Studio (free). Route locally?"
       This is a suggestion, not a block — @Daimyo always decides.
```

### Heartbeat & Health

```
BR-20: Every node sends a heartbeat every 60 seconds containing:
       - nodeId, timestamp, status (active|idle|sleeping|paused)
       - load: activeTasks, cpuPct, memoryPct, gpuPct
       - spend: spentToday, budgetRemaining (virtual nodes only)
BR-21: The orchestrator aggregates heartbeats into the TopologyGraph.
       The Heartbeat Map visualizes this data.
BR-22: Mobile nodes (iPhone/iPad) send heartbeats at reduced frequency
       (every 5 minutes) to preserve battery. They declare availability: "mobile".
```

### Affinity & Warm Routing (En-Graph)

```
BR-23: Each node maintains a local affinity cache: {companySlug -> lastUsedAt, taskCount}.
       Nodes that recently worked on a company get an affinity bonus in scoring.
BR-24: Affinity decays over time (halves every 24h). A cold node has no affinity advantage.
BR-25: Explicit affinity override: `shiki mesh pin <company> <nodeId>` forces routing.
```

### Refusal Vocabulary (Wabi-Budget)

```
BR-26: A node's refusal set is a list of TaskKind values it will never accept.
       Example: iPhone refuses "heavy_inference", VPS refuses "xcode_build".
BR-27: Refusals are honored unconditionally — the routing function skips refused
       task kinds before scoring. A refusal is not a failure, it's a boundary.
BR-28: A node may update its refusal set dynamically (e.g., laptop on battery
       adds "heavy_inference" to refusals, removes it when plugged in).
```

### Transport Protocol

```
BR-29: Node-to-node communication uses gRPC over HTTP/2 with protobuf serialization.
       The protocol is defined in shiki-mesh.proto (source of truth).
BR-30: All inter-node connections use mTLS (mutual TLS) for authentication.
       Node certificates are generated on first registration and stored locally.
BR-31: The orchestrator runs the gRPC server. All other nodes are gRPC clients
       that maintain a persistent bidirectional stream for heartbeat + dispatch.
BR-32: Virtual nodes implement the same gRPC client interface via a shim that
       translates DispatchTask into provider-specific API calls (REST, SDK, etc.).
BR-33: Data plane transfers (agent migration, context sync) use gRPC streaming
       with chunked transfer (max 4MB per chunk) and SHA-256 integrity verification.
BR-34: Mobile nodes (iPhone/iPad) may use a lightweight gRPC-Web variant over
       HTTPS if full gRPC is unavailable (Network.framework fallback).
```

### Orchestrator Failover

```
BR-35: The mesh has a designated failover chain: an ordered list of nodes
       eligible to become orchestrator, ranked by priority.
       Default: [primary-mac, vps, secondary-mac, any-node-with-db].
       Configured in ~/.config/shiki/mesh.toml.
BR-36: Each node in the failover chain runs a passive ShikiDB replica
       (libsql read replica or pg streaming). Only the active orchestrator
       writes. On promotion, the new orchestrator upgrades to read-write.
BR-37: Failover detection: a failover-eligible node promotes itself when
       the current orchestrator misses 3 consecutive heartbeats AND the node
       confirms unreachability via a secondary path (direct ping, not just
       missed gRPC stream). Prevents false positives from network blips.
BR-38: On promotion, the new orchestrator:
       (a) Broadcasts ORCHESTRATOR_CHANGED event to all nodes
       (b) Reads last state from its ShikiDB replica
       (c) Begins accepting heartbeats and dispatching tasks
       (d) Sends ntfy notification: "Orchestrator moved to {node}"
BR-39: When the original orchestrator comes back online, it does NOT
       automatically reclaim leadership. It joins as a regular node.
       Manual reclaim via `shiki mesh promote <nodeId>` only.
       Reason: avoid flip-flopping if the primary is unstable.
BR-40: During failover gap (0-90s), agents continue autonomous work.
       They buffer heartbeats locally and replay them on reconnect.
       No work is lost — only coordination pauses.
BR-41: Each node maintains a fallback URL list for reconnection:
       [primary-orchestrator, failover-1, failover-2].
       On orchestrator loss, nodes try each URL in order.
```

## Test Plan

### Unit Tests — Node Identity & Registration

```
BR-01 → test_nodeId_persistsAcrossReboots()
BR-01 → test_nodeId_isUUIDv4()
BR-02 → test_nodeType_physicalAndVirtual_bothConformToProtocol()
BR-03 → test_capabilityManifest_containsAllRequiredFields()
BR-03 → test_capabilityManifest_encodesDecodesToProtobuf()
BR-03 → test_capabilityManifest_refusalSet_encodedCorrectly()
BR-04 → test_manifestUpdate_propagatesWithinOneHeartbeat()
```

### Unit Tests — Discovery & Topology

```
BR-05 → test_mDNSDiscovery_registersLocalNode()
BR-05 → test_mDNSDiscovery_ignoresDuplicateRegistration()
BR-06 → test_remoteNode_addedManuallyViaConfig()
BR-06 → test_meshToml_parsesNodeList()
BR-07 → test_topologyGraph_addsNodeOnRegistration()
BR-07 → test_topologyGraph_removesNodeOnDeath()
BR-08 → test_orchestratorOffline_nodesKeepCurrentWork()
BR-08 → test_orchestratorReconnect_stateReconciles()
BR-09 → test_missedHeartbeats_3_marksStale()
BR-09 → test_missedHeartbeats_10_marksDead()
BR-09 → test_deadNode_removedFromRouting()
```

### Unit Tests — Task Routing

```
BR-10 → test_scoringFunction_prefersHighCapabilityLowCost()
BR-10 → test_scoringFunction_tiesBrokenByLatency()
BR-11 → test_taskRequirements_filtersByMinVram()
BR-11 → test_taskRequirements_filtersByRequiredBackend()
BR-11 → test_taskRequirements_preferredNodeId_boostsScore()
BR-12 → test_noMatchingNode_taskQueued_statusWaiting()
BR-12 → test_waitingTask_dispatchedWhenNodeBecomesAvailable()
BR-13 → test_nodeRejectsTask_reroutes_toNextBest()
BR-14 → test_virtualNode_costPenalty_increasesWithSpend()
BR-14 → test_virtualNode_nearBudget_scoresLowerThanPhysical()
```

### Unit Tests — Budget & Cost

```
BR-15 → test_physicalNode_costPerToken_isZero()
BR-16 → test_virtualNode_budgetExhausted_transitionsToPaused()
BR-16 → test_pausedNode_stopsAcceptingTasks()
BR-17 → test_budgetReset_atMidnight_inNodeTimezone()
BR-18 → test_budgetAlert_at80Percent()
BR-18 → test_budgetAlert_at95Percent_createsT1Decision()
BR-19 → test_budgetConscience_surfacesCostComparison()
```

### Unit Tests — Heartbeat & Health

```
BR-20 → test_heartbeat_containsRequiredFields()
BR-20 → test_heartbeat_virtualNode_includesSpend()
BR-21 → test_orchestrator_aggregatesHeartbeats_intoTopology()
BR-22 → test_mobileNode_heartbeatFrequency_5min()
BR-22 → test_mobileNode_declaresAvailability_mobile()
```

### Unit Tests — Affinity (En-Graph)

```
BR-23 → test_affinityCache_tracksLastUsedPerCompany()
BR-23 → test_affinityBonus_appliedInScoring()
BR-24 → test_affinityDecay_halvesEvery24h()
BR-24 → test_coldNode_noAffinityBonus()
BR-25 → test_pinCommand_forcesRouting()
BR-25 → test_pinnedNode_overridesScoring()
```

### Unit Tests — Refusal / Wabi-Budget

```
BR-26 → test_refusalSet_skippedBeforeScoring()
BR-26 → test_iPhone_refusesHeavyInference()
BR-27 → test_refusal_isNotAFailure_noRetry()
BR-28 → test_dynamicRefusal_onBattery_addsHeavyInference()
BR-28 → test_dynamicRefusal_onPower_removesHeavyInference()
```

### Unit Tests — Transport Protocol

```
BR-29 → test_grpcMessage_serializesToProtobuf()
BR-29 → test_grpcMessage_deserializesFromProtobuf()
BR-30 → test_mTLS_rejectsUnauthenticatedNode()
BR-30 → test_mTLS_acceptsValidCertificate()
BR-31 → test_bidirectionalStream_heartbeatAndDispatch()
BR-32 → test_virtualNodeShim_translatesDispatchToAPICall()
BR-32 → test_virtualNodeShim_reportsActualCost()
BR-33 → test_streamingTransfer_chunkedAt4MB()
BR-33 → test_streamingTransfer_sha256Integrity()
BR-34 → test_mobileNode_fallsBackToGrpcWeb()
```

### Unit Tests — Orchestrator Failover

```
BR-35 → test_failoverChain_parsedFromConfig()
BR-35 → test_failoverChain_defaultOrder()
BR-36 → test_dbReplica_receivesWrites_fromPrimary()
BR-36 → test_promotion_upgradesToReadWrite()
BR-37 → test_failoverDetection_3missedHeartbeats_plusSecondaryCheck()
BR-37 → test_failoverDetection_noFalsePositive_onNetworkBlip()
BR-38 → test_promotion_broadcastsOrchestratorChanged()
BR-38 → test_promotion_readsLastState_fromReplica()
BR-38 → test_promotion_sendsNtfyNotification()
BR-39 → test_originalOrchestrator_doesNotAutoReclaim()
BR-39 → test_manualReclaim_viaPromoteCommand()
BR-40 → test_agents_bufferHeartbeats_duringGap()
BR-40 → test_agents_replayHeartbeats_onReconnect()
BR-41 → test_fallbackUrlList_triedInOrder()
BR-41 → test_nodeReconnects_toNewOrchestrator()
```

### Integration Tests

```
INT-01 → test_fullRegistrationFlow_mDNS_toTopologyGraph()
INT-02 → test_taskDispatch_routesToOptimalNode()
INT-03 → test_virtualNode_claudeShim_dispatchAndCostReport()
INT-04 → test_failover_primaryDies_standbyPromotes_nodesReconnect()
INT-05 → test_agentContinuesWork_duringOrchestratorOutage()
INT-06 → test_budgetExhaustion_reroutes_toLocalNode()
INT-07 → test_affinityRouting_warmNode_preferred()
INT-08 → test_refusal_reroutes_withoutRetry()
INT-09 → test_heartbeatReplay_afterReconnect_noDataLoss()
INT-10 → test_meshStatus_showsAllNodes_health_spend()
```

## Architecture

> Phase 5 — @Sensei | 2026-03-22
> Status: Ready for implementation

### Package Manifest

`packages/ShikiMesh/Package.swift` — swift-tools-version: 6.0, macOS 14+.

Dependencies:
- ShikiCore (local) — FeatureLifecycle, AgentProvider, EventPersisting
- ShikiKit (local) — shared DTOs
- CoreKit (local) — Container, DIAssembly, AppLog
- grpc-swift (1.x) — gRPC server/client
- swift-protobuf (1.x) — protobuf codegen
- swift-nio (2.x) — async networking
- swift-nio-ssl (2.x) — mTLS
- swift-log (1.x) — structured logging

---

### File Map

#### Proto Definitions

| Path | Purpose |
|------|---------|
| `packages/ShikiMesh/Proto/shiki-mesh.proto` | Wire types: NodeManifest, TaskSubmission, TaskResult, Heartbeat, TopologySnapshotProto. gRPC service: MeshService (SubmitTask, SendHeartbeat, SyncTopology, StreamEvents). |
| `packages/ShikiMesh/Sources/ShikiMesh/Generated/shiki_mesh.pb.swift` | Generated protobuf messages (gitignored, build plugin). |
| `packages/ShikiMesh/Sources/ShikiMesh/Generated/shiki_mesh.grpc.swift` | Generated gRPC stubs (gitignored, build plugin). |

#### Models

| Path | Purpose |
|------|---------|
| `Sources/ShikiMesh/Models/NodeIdentity.swift` | `NodeId` (UUID typealias), `NodeType` enum (.physical, .virtual), `NodeIdentity` struct (id, type, displayName, joinedAt). |
| `Sources/ShikiMesh/Models/CapabilityManifest.swift` | `CapabilityManifest`: nodeId, nodeType, computeProfile, costPerToken, availability (0..1), supportedModels, refusals. Codable + Sendable. |
| `Sources/ShikiMesh/Models/ComputeProfile.swift` | `ComputeProfile`: cpuCores, ramGB, gpuVRAM_GB, platform (macOS/iOS/linux/cloud), architecture (arm64/x86_64). Nil fields for virtual nodes. |
| `Sources/ShikiMesh/Models/TaskRequirements.swift` | `TaskRequirements`: requiredCapabilities, minimumRAM_GB, preferredPlatform, maxCostPerToken, affinityHint (NodeId?), deadline (Date?). |
| `Sources/ShikiMesh/Models/MeshTask.swift` | `MeshTask`: id (UUID), dispatchRequest (ShikiCore.DispatchRequest), requirements, priority, createdAt, assignedNode, status. Identifiable + Sendable. |
| `Sources/ShikiMesh/Models/MeshTaskStatus.swift` | `MeshTaskStatus` enum: .queued, .routed, .executing, .completed(AgentResult), .failed(MeshError), .rerouted(fromNode: NodeId). |
| `Sources/ShikiMesh/Models/MeshPriority.swift` | `MeshPriority` enum: .critical(0), .high(1), .normal(2), .background(3). RawRepresentable Int for sort. |
| `Sources/ShikiMesh/Models/MeshError.swift` | `MeshError` enum: .nodeUnreachable, .budgetExhausted, .noCapableNode, .taskRefused, .heartbeatTimeout, .mTLSFailure, .topologyDesync, .failoverExhausted. |
| `Sources/ShikiMesh/Models/RefusalVocabulary.swift` | `RefusalEntry`: capability (String), reason (String). Wabi-Budget declarations. |
| `Sources/ShikiMesh/Models/MeshEvent.swift` | Factory enum following CoreEvent pattern. Produces `LifecycleEventPayload` for: nodeJoined, nodeLeft, taskRouted, taskCompleted, budgetAlert, failoverTriggered, heartbeatMissed. |

#### Services

| Path | Purpose |
|------|---------|
| `Sources/ShikiMesh/Services/TopologyGraph.swift` | Actor. Live graph `[NodeId: CapabilityManifest]` + `[NodeId: any MeshNode]`. Add/remove/query/snapshot. |
| `Sources/ShikiMesh/Services/TaskRouter.swift` | Actor. Scoring function picks optimal node. Depends on TopologyGraph, AffinityCache, NodeBudgetTracker, TaskScoring. |
| `Sources/ShikiMesh/Services/DefaultTaskScorer.swift` | `DefaultTaskScorer: TaskScoring`. The scoring formula implementation. |
| `Sources/ShikiMesh/Services/NodeBudgetTracker.swift` | Actor. Per-node daily budget. Mirrors BudgetEnforcer pattern keyed by NodeId. Alerts at 80%/95%. |
| `Sources/ShikiMesh/Services/AffinityCache.swift` | Actor. En-Graph: nodeId+taskType -> lastExecution+count. Exponential decay over 24h. |
| `Sources/ShikiMesh/Services/FailoverManager.swift` | Actor. Static failover chains. No election. Walks chain on heartbeat timeout. |
| `Sources/ShikiMesh/Services/HeartbeatAggregator.swift` | Actor. Receives pings, detects timeouts (60s desktop, 300s mobile). Notifies TopologyGraph + FailoverManager. |
| `Sources/ShikiMesh/Services/MeshOrchestrator.swift` | Actor. Top-level entry point. Submit -> route -> dispatch -> failover. Max 3 reroute hops. |

#### Networking

| Path | Purpose |
|------|---------|
| `Sources/ShikiMesh/Networking/MeshGRPCServer.swift` | gRPC server via SwiftNIO. Implements MeshServiceProvider. Configurable port. mTLS. |
| `Sources/ShikiMesh/Networking/MeshGRPCClient.swift` | gRPC client. Connection pooling, reconnect, deadline propagation. |
| `Sources/ShikiMesh/Networking/MDNSDiscovery.swift` | mDNS/Bonjour via NWBrowser. Publishes `_shikimesh._tcp`. Emits NodeDiscoveryEvent stream. |
| `Sources/ShikiMesh/Networking/ManualNodeRegistry.swift` | Loads static node config from `~/.config/shiki-mesh/nodes.json`. File watcher for live reload. |
| `Sources/ShikiMesh/Networking/MeshTLSConfig.swift` | mTLS cert loading + peer validation. Wraps NIOSSLContext. Certs at `~/.config/shiki-mesh/certs/`. |

#### Virtual Node Shims

| Path | Purpose |
|------|---------|
| `Sources/ShikiMesh/VirtualNodes/VirtualNodeShim.swift` | Protocol extending MeshNode + AgentProvider. Adds apiEndpoint, supportedModels, costPerToken. Default `execute(task:)` calls `dispatch()`. |
| `Sources/ShikiMesh/VirtualNodes/ClaudeShim.swift` | Wraps ShikiCore's ClaudeProvider. Produces manifest with claude-specific capabilities. |
| `Sources/ShikiMesh/VirtualNodes/OpenAIShim.swift` | OpenAI API. GPT-4/o1/o3 models. Reads `OPENAI_API_KEY` from env. |
| `Sources/ShikiMesh/VirtualNodes/LMStudioShim.swift` | LM Studio at 127.0.0.1:1234. OpenAI-compatible. Cost = 0. |
| `Sources/ShikiMesh/VirtualNodes/GenericAPIShim.swift` | Any OpenAI-compatible endpoint. Configurable base URL + key + models. |

#### Configuration

| Path | Purpose |
|------|---------|
| `Sources/ShikiMesh/Config/MeshConfig.swift` | `MeshConfig`: grpcPort, heartbeatIntervalDesktop (60s), heartbeatIntervalMobile (300s), budgetAlertThresholds ([0.80, 0.95]), affinityDecayHours (24), certsPath, nodesConfigPath. Loads from `~/.config/shiki-mesh/config.json` with defaults. |

#### DI Assembly

| Path | Purpose |
|------|---------|
| `Sources/ShikiMesh/DI/MeshAssembly.swift` | `MeshAssembly: DIAssembly`. Registers all services into CoreKit Container. |

#### Tests

| Path | Purpose |
|------|---------|
| `Tests/ShikiMeshTests/TopologyGraphTests.swift` | Add/remove nodes, snapshot consistency, concurrent access, markUnreachable. |
| `Tests/ShikiMeshTests/TaskRouterTests.swift` | Scoring formula, tie-breaking, refusal filtering, noCapableNode error. |
| `Tests/ShikiMeshTests/DefaultTaskScorerTests.swift` | Unit tests for scoring math: cost normalization, affinity boost, budget ratio. |
| `Tests/ShikiMeshTests/NodeBudgetTrackerTests.swift` | Daily reset, 80%/95% alerts, exhaustion blocking, trySpend atomicity. |
| `Tests/ShikiMeshTests/AffinityCacheTests.swift` | Warm bonus, 24h decay math, pruneExpired, pin override. |
| `Tests/ShikiMeshTests/FailoverManagerTests.swift` | Chain promotion, exhaustion error, skip-unreachable, no-election guarantee. |
| `Tests/ShikiMeshTests/HeartbeatAggregatorTests.swift` | Timeout detection at 60s/300s, miss callback fires, mobile interval respected. |
| `Tests/ShikiMeshTests/MeshOrchestratorTests.swift` | End-to-end: submit -> route -> dispatch -> reroute on failure -> max 3 hops. |
| `Tests/ShikiMeshTests/MDNSDiscoveryTests.swift` | Service publish/resolve with mock NWBrowser. |
| `Tests/ShikiMeshTests/ManualNodeRegistryTests.swift` | JSON parsing, reload on change, invalid config handling. |
| `Tests/ShikiMeshTests/VirtualNodeShimTests.swift` | Manifest generation, dispatch delegation, cost reporting. |
| `Tests/ShikiMeshTests/MeshConfigTests.swift` | Defaults, file loading, override merging. |
| `Tests/ShikiMeshTests/Mocks/MockAgentProvider.swift` | Test double for AgentProvider. |
| `Tests/ShikiMeshTests/Mocks/MockEventPersisting.swift` | Captures persisted events for assertion. |
| `Tests/ShikiMeshTests/Mocks/MockTopologyGraph.swift` | Controllable topology for router/orchestrator tests. |

#### CLI Commands (in shiki-ctl)

| Path | Purpose |
|------|---------|
| `tools/shiki-ctl/Sources/shikki/Commands/MeshCommand.swift` | `MeshCommand: AsyncParsableCommand` parent group. |
| `tools/shiki-ctl/Sources/shikki/Commands/MeshStatusCommand.swift` | `shikki mesh status` — topology, budget, active tasks. |
| `tools/shiki-ctl/Sources/shikki/Commands/MeshAddCommand.swift` | `shikki mesh add <url> --name --type` — adds manual node. |
| `tools/shiki-ctl/Sources/shikki/Commands/MeshRemoveCommand.swift` | `shikki mesh remove <nodeId>` — removes node. |
| `tools/shiki-ctl/Sources/shikki/Commands/MeshPromoteCommand.swift` | `shikki mesh promote <nodeId> --for <primaryId>` — reorders failover chain. |
| `tools/shiki-ctl/Sources/shikki/Commands/MeshPinCommand.swift` | `shikki mesh pin <taskType> <nodeId>` — permanent affinity. |
| `tools/shiki-ctl/Sources/shikki/Commands/MeshBudgetCommand.swift` | `shikki mesh budget <nodeId> [--set <limit>]` — view/set budget. |
| `tools/shiki-ctl/Sources/shikki/Commands/MeshDiscoverCommand.swift` | `shikki mesh discover` — trigger mDNS scan. |

---

### Key Protocols

#### `MeshNode`

```swift
/// Any entity that can execute tasks in the mesh.
public protocol MeshNode: Sendable {
    var identity: NodeIdentity { get }
    var manifest: CapabilityManifest { get async }
    var isReachable: Bool { get async }
    func execute(task: MeshTask) async throws -> AgentResult
}
```

All physical and virtual nodes conform. Physical nodes forward via gRPC client. Virtual nodes call their API directly.

#### `VirtualNodeShim`

```swift
/// Adapts an API endpoint to behave as a MeshNode.
/// Inherits AgentProvider for dispatch compatibility with ShikiCore.
public protocol VirtualNodeShim: MeshNode, AgentProvider {
    var apiEndpoint: URL { get }
    var supportedModels: [String] { get }
    var costPerToken: Double { get }
}
```

Default `execute(task:)` implementation calls `dispatch(prompt:workingDirectory:options:)` from AgentProvider, wrapping the result.

#### `NodeDiscovery`

```swift
/// Source of mesh node appearance/disappearance events.
public protocol NodeDiscovery: Sendable {
    func start() async throws -> AsyncStream<NodeDiscoveryEvent>
    func stop() async
}

public enum NodeDiscoveryEvent: Sendable {
    case found(NodeIdentity, host: String, port: Int)
    case lost(NodeId)
}
```

Two conformances: `MDNSDiscovery` (LAN auto-discovery) and `ManualNodeRegistry` (static JSON config).

#### `TaskScoring`

```swift
/// Pluggable scoring strategy for task routing.
public protocol TaskScoring: Sendable {
    func score(
        node: CapabilityManifest,
        requirements: TaskRequirements,
        affinity: Double,       // 0..1 from AffinityCache
        budgetRemaining: Double // 0..1 ratio from NodeBudgetTracker
    ) -> Double
}
```

Default: `DefaultTaskScorer`. Inject a custom scorer for specialized routing.

#### `BudgetAlertHandler`

```swift
/// Receives budget threshold notifications.
public protocol BudgetAlertHandler: Sendable {
    func budgetAlert(nodeId: NodeId, threshold: Double, spent: Double, limit: Double) async
}
```

---

### Key Actor Signatures

#### TopologyGraph

```swift
public actor TopologyGraph {
    private var manifests: [NodeId: CapabilityManifest] = [:]
    private var meshNodes: [NodeId: any MeshNode] = [:]
    private var unreachable: Set<NodeId> = []

    public func addNode(_ manifest: CapabilityManifest, node: any MeshNode)
    public func removeNode(_ id: NodeId)
    public func markUnreachable(_ id: NodeId)
    public func markReachable(_ id: NodeId)
    public func node(for id: NodeId) -> (any MeshNode)?
    public func allManifests() -> [CapabilityManifest]
    public func allReachable() -> [CapabilityManifest]  // filters out unreachable
    public func snapshot() -> TopologySnapshot
}

public struct TopologySnapshot: Codable, Sendable {
    public let nodes: [CapabilityManifest]
    public let timestamp: Date
    public let reachableCount: Int
    public let unreachableIds: [NodeId]
}
```

#### TaskRouter

```swift
public actor TaskRouter {
    private let topology: TopologyGraph
    private let affinity: AffinityCache
    private let budget: NodeBudgetTracker
    private let scorer: any TaskScoring

    public init(topology: TopologyGraph, affinity: AffinityCache,
                budget: NodeBudgetTracker, scorer: any TaskScoring)

    /// Best node for requirements. Throws .noCapableNode if none qualifies.
    public func route(_ requirements: TaskRequirements) async throws -> NodeId

    /// All candidates with scores, for debugging / `mesh status`.
    public func scoredCandidates(_ requirements: TaskRequirements) async -> [(NodeId, Double)]
}
```

#### NodeBudgetTracker

```swift
public actor NodeBudgetTracker {
    private var budgets: [NodeId: NodeBudget]
    private let alertThresholds: [Double]  // [0.80, 0.95]
    private var alertHandler: (any BudgetAlertHandler)?

    public init(alertThresholds: [Double] = [0.80, 0.95])

    public func setDailyLimit(nodeId: NodeId, limit: Double)
    public func canSpend(nodeId: NodeId, amount: Double) -> Bool
    public func record(nodeId: NodeId, amount: Double) async   // fires alert if threshold crossed
    public func trySpend(nodeId: NodeId, amount: Double) async -> Bool
    public func remaining(nodeId: NodeId) -> Double?
    public func ratioRemaining(nodeId: NodeId) -> Double       // 0..1 for scorer
    public func setAlertHandler(_ handler: any BudgetAlertHandler)
}

private struct NodeBudget {
    var dailyLimit: Double
    var spentToday: Double
    var lastResetDate: String  // ISO8601 date
}
```

#### AffinityCache

```swift
public actor AffinityCache {
    private var entries: [AffinityKey: AffinityEntry] = [:]
    private let decayHours: Double  // default 24

    public init(decayHours: Double = 24)

    public func recordExecution(nodeId: NodeId, taskType: String)
    public func affinity(nodeId: NodeId, taskType: String) -> Double   // 0..1
    public func pin(nodeId: NodeId, taskType: String)                  // permanent max affinity
    public func unpin(nodeId: NodeId, taskType: String)
    public func pruneExpired()                                         // removes > 3*decayHours
}

// Decay: exp(-hoursElapsed / decayHours)
// Pruned: entries older than 3 * decayHours (72h default)
```

#### FailoverManager

```swift
public actor FailoverManager {
    private var chains: [NodeId: [NodeId]] = [:]  // primary -> [fallback1, fallback2, ...]
    private let topology: TopologyGraph

    public init(topology: TopologyGraph)

    public func setChain(for primary: NodeId, fallbacks: [NodeId])
    public func nextInChain(after failedNode: NodeId, excluding: Set<NodeId>) async -> NodeId?
    public func triggerFailover(nodeId: NodeId) async  // called by HeartbeatAggregator
    public func promote(nodeId: NodeId, inChainOf primary: NodeId)  // moves to position 0
}
```

No election. Chains configured statically. `nextInChain` walks array, skips unreachable/excluded.

#### HeartbeatAggregator

```swift
public actor HeartbeatAggregator {
    private let topology: TopologyGraph
    private var lastSeen: [NodeId: Date] = [:]
    private let desktopInterval: TimeInterval   // 60
    private let mobileInterval: TimeInterval    // 300
    private var monitorTask: Task<Void, Never>?

    public init(topology: TopologyGraph, desktopInterval: TimeInterval = 60,
                mobileInterval: TimeInterval = 300)

    public func receiveHeartbeat(from nodeId: NodeId, platform: Platform)
    public func startMonitoring() async   // launches background check loop
    public func stopMonitoring()

    /// Callback on heartbeat timeout.
    public var onTimeout: ((NodeId) async -> Void)?
}
```

#### MeshOrchestrator

```swift
public actor MeshOrchestrator {
    private let router: TaskRouter
    private let topology: TopologyGraph
    private let failover: FailoverManager
    private let budget: NodeBudgetTracker
    private let affinity: AffinityCache
    private let grpcClient: MeshGRPCClient
    private let persister: (any EventPersisting)?
    private let maxFailoverHops = 3
    private var activeTasks: [UUID: MeshTask] = [:]

    public init(router: TaskRouter, topology: TopologyGraph, failover: FailoverManager,
                budget: NodeBudgetTracker, affinity: AffinityCache,
                grpcClient: MeshGRPCClient, persister: (any EventPersisting)? = nil)

    /// Submit task. Routes, dispatches, handles failover (max 3 hops).
    public func submit(_ task: MeshTask) async throws -> AgentResult

    /// Current mesh status for CLI.
    public func status() async -> MeshStatus
}

public struct MeshStatus: Sendable {
    public let topology: TopologySnapshot
    public let activeTasks: [MeshTask]
    public let budgetSummary: [NodeId: String]  // "$12/$31" format
}
```

---

### Data Flow: Task Submission to Execution

```
User / ShikiCore CompanyManager
│
│  DispatchRequest + TaskRequirements
▼
┌──────────────────────┐
│   MeshOrchestrator   │  (entry point — actor)
└──────────┬───────────┘
           │
           │ 1. Build MeshTask from DispatchRequest
           │ 2. Query TopologyGraph for live nodes
           ▼
┌──────────────────────┐
│    TopologyGraph      │  actor — [NodeId: CapabilityManifest]
└──────────┬───────────┘
           │ returns [CapabilityManifest] (reachable only)
           ▼
┌──────────────────────┐
│     TaskRouter        │  actor
│                       │
│  For each candidate:  │
│   ├─ FILTER: has required capabilities?
│   ├─ FILTER: capability NOT in refusal set? (Wabi-Budget BR-26/27)
│   ├─ FILTER: meets minimumRAM, preferredPlatform?
│   ├─ FILTER: costPerToken <= maxCostPerToken?
│   │                       │
│   │  Surviving nodes:     │
│   ├─ query AffinityCache ─┼──► AffinityCache (warm bonus, decayed)
│   ├─ query BudgetTracker ─┼──► NodeBudgetTracker (remaining ratio)
│   │                       │
│   │  Score each via       │
│   │  TaskScoring protocol:│
│   │  score = capMatch     │
│   │    * (1/normCost)     │
│   │    * affinityBonus    │
│   │    * budgetRatio      │
│   │                       │
│   └─ sort DESC, return    │
│      winner NodeId        │
└──────────┬───────────┘
           │ winner: NodeId
           ▼
┌──────────────────────┐
│  MeshOrchestrator    │  (dispatch phase)
│                      │
│  Resolve MeshNode    │
│  from TopologyGraph  │
│                      │
│  ┌─ Physical node? ──┼──► MeshGRPCClient.submitTask(proto)
│  │                   │    gRPC / HTTP2 / mTLS to remote
│  │                   │
│  └─ Virtual node? ───┼──► VirtualNodeShim.execute(task)
│                      │    direct API: Claude/OpenAI/LMStudio
│                      │
│  await AgentResult   │
│                      │
│  ┌─ Success? ────────┼──► budget.record(nodeId, cost)
│  │                   │    affinity.recordExecution(nodeId, taskType)
│  │                   │    persist MeshEvent.taskCompleted
│  │                   │    return AgentResult
│  │                   │
│  └─ Failure? ────────┼──► failover.nextInChain(winner, excluding: tried)
│                      │    tried.count >= maxFailoverHops?
│                      │      YES → throw .failoverExhausted
│                      │      NO  → persist MeshEvent.failoverTriggered
│                      │            retry with next node
└──────────────────────┘

Background loops (started at mesh boot):

┌───────────────────────┐
│ HeartbeatAggregator    │  receives pings every 60s / 300s
│                        │  on timeout:
│                        │    topology.markUnreachable(nodeId)
│                        │    failover.triggerFailover(nodeId)
│                        │    persist MeshEvent.heartbeatMissed
└────────────────────────┘

┌───────────────────────┐
│ MDNSDiscovery          │  publishes _shikimesh._tcp
│                        │  on .found:
│                        │    gRPC handshake → fetch manifest
│                        │    topology.addNode(manifest, node)
│                        │  on .lost:
│                        │    topology.removeNode(id)
└────────────────────────┘

┌───────────────────────┐
│ ManualNodeRegistry     │  watches ~/.config/shiki-mesh/nodes.json
│                        │  on file change:
│                        │    diff old vs new → add/remove nodes
└────────────────────────┘
```

#### Scoring Formula (DefaultTaskScorer)

```
score = capabilityMatch * (1.0 / normalizedCost) * affinityBonus * budgetRatio

capabilityMatch: 1.0 if all required capabilities met, 0.0 otherwise
                 (nodes with 0.0 are pre-filtered, never reach scorer)
normalizedCost:  costPerToken / maxCostInMesh
                 cheapest node = highest value
                 physical nodes (cost=0) get normalizedCost = epsilon (0.001)
                   → 1/0.001 = 1000 — massive preference for free compute
affinityBonus:   1.0 + (0.5 * exp(-hoursElapsed / decayHours))
                 warm cache: up to 1.5x boost, decays to 1.0x over 24h
                 pinned nodes: permanent 1.5x
budgetRatio:     remaining / dailyLimit (0..1)
                 physical nodes: always 1.0 (no budget)
                 near-exhaustion: naturally deprioritizes expensive APIs

Tie-breaking: lowest latencyP50ms wins.
```

---

### DI Registration Plan

`MeshAssembly: DIAssembly` registers all services into CoreKit's Container.

```swift
public struct MeshAssembly: DIAssembly {
    public init() {}

    public func assemble(container: Container, environment: DIEnvironment) {

        // -- Config --
        container.register(MeshConfig.self) { _ in
            MeshConfig.load()
        }

        // -- Core Services (actors, .cached scope = singleton) --
        container.register(TopologyGraph.self) { _ in
            TopologyGraph()
        }

        container.register(AffinityCache.self) { r in
            let config = try r.resolve(MeshConfig.self)
            return AffinityCache(decayHours: config.affinityDecayHours)
        }

        container.register(NodeBudgetTracker.self) { r in
            let config = try r.resolve(MeshConfig.self)
            return NodeBudgetTracker(alertThresholds: config.budgetAlertThresholds)
        }

        container.register(HeartbeatAggregator.self) { r in
            let topology = try r.resolve(TopologyGraph.self)
            let config = try r.resolve(MeshConfig.self)
            return HeartbeatAggregator(
                topology: topology,
                desktopInterval: config.heartbeatIntervalDesktop,
                mobileInterval: config.heartbeatIntervalMobile
            )
        }

        container.register(FailoverManager.self) { r in
            let topology = try r.resolve(TopologyGraph.self)
            return FailoverManager(topology: topology)
        }

        // -- Scoring (protocol registration) --
        container.register((any TaskScoring).self) { _ in
            DefaultTaskScorer()
        }

        // -- Router --
        container.register(TaskRouter.self) { r in
            TaskRouter(
                topology: try r.resolve(TopologyGraph.self),
                affinity: try r.resolve(AffinityCache.self),
                budget: try r.resolve(NodeBudgetTracker.self),
                scorer: try r.resolve((any TaskScoring).self)
            )
        }

        // -- Discovery --
        container.register(MDNSDiscovery.self) { _ in
            MDNSDiscovery()
        }

        container.register(ManualNodeRegistry.self) { r in
            let config = try r.resolve(MeshConfig.self)
            return ManualNodeRegistry(configPath: config.nodesConfigPath)
        }

        // -- Networking --
        container.register(MeshTLSConfig.self) { r in
            let config = try r.resolve(MeshConfig.self)
            return try MeshTLSConfig(certsPath: config.certsPath)
        }

        container.register(MeshGRPCServer.self) { r in
            let config = try r.resolve(MeshConfig.self)
            let tls = try r.resolve(MeshTLSConfig.self)
            return MeshGRPCServer(port: config.grpcPort, tlsConfig: tls)
        }

        container.register(MeshGRPCClient.self) { r in
            let tls = try r.resolve(MeshTLSConfig.self)
            return MeshGRPCClient(tlsConfig: tls)
        }

        // -- Virtual Shims (named registrations for multiple conformances) --
        container.register((any VirtualNodeShim).self, name: "claude") { r in
            ClaudeShim(provider: try r.resolve((any AgentProvider).self))
        }

        container.register((any VirtualNodeShim).self, name: "openai") { _ in
            OpenAIShim()
        }

        container.register((any VirtualNodeShim).self, name: "lmstudio") { _ in
            LMStudioShim()
        }

        // -- Orchestrator (top-level) --
        container.register(MeshOrchestrator.self) { r in
            let persister: (any EventPersisting)? = r.resolveOptional((any EventPersisting).self)
            return MeshOrchestrator(
                router: try r.resolve(TaskRouter.self),
                topology: try r.resolve(TopologyGraph.self),
                failover: try r.resolve(FailoverManager.self),
                budget: try r.resolve(NodeBudgetTracker.self),
                affinity: try r.resolve(AffinityCache.self),
                grpcClient: try r.resolve(MeshGRPCClient.self),
                persister: persister
            )
        }
    }
}
```

**Activation**: Lazy assembly — mesh only initializes on first resolve:
```swift
Container.default.addLazyAssembly(MeshAssembly(), environment: .production)
```

**Test override**: In tests, register `MockTopologyGraph`/`MockAgentProvider` before resolving `MeshOrchestrator`. CoreKit's Container resolves latest registration.

---

### Proto Schema

```protobuf
syntax = "proto3";
package shiki.mesh;
option swift_prefix = "SM";

enum NodeType {
    NODE_TYPE_UNSPECIFIED = 0;
    NODE_TYPE_PHYSICAL = 1;
    NODE_TYPE_VIRTUAL = 2;
}

enum Platform {
    PLATFORM_UNSPECIFIED = 0;
    PLATFORM_MACOS = 1;
    PLATFORM_IOS = 2;
    PLATFORM_LINUX = 3;
    PLATFORM_CLOUD = 4;
}

enum TaskStatus {
    TASK_STATUS_UNSPECIFIED = 0;
    TASK_STATUS_QUEUED = 1;
    TASK_STATUS_ROUTED = 2;
    TASK_STATUS_EXECUTING = 3;
    TASK_STATUS_COMPLETED = 4;
    TASK_STATUS_FAILED = 5;
    TASK_STATUS_REROUTED = 6;
}

message NodeManifest {
    string node_id = 1;
    NodeType type = 2;
    string display_name = 3;
    ComputeProfile compute = 4;
    double cost_per_token = 5;
    double availability = 6;
    repeated string supported_models = 7;
    repeated RefusalEntry refusals = 8;
}

message ComputeProfile {
    int32 cpu_cores = 1;
    double ram_gb = 2;
    double gpu_vram_gb = 3;
    Platform platform = 4;
    string architecture = 5;
}

message RefusalEntry {
    string capability = 1;
    string reason = 2;
}

message TaskSubmission {
    string task_id = 1;
    string prompt = 2;
    string working_directory = 3;
    TaskRequirements requirements = 4;
    int32 priority = 5;
}

message TaskRequirements {
    repeated string required_capabilities = 1;
    double minimum_ram_gb = 2;
    Platform preferred_platform = 3;
    double max_cost_per_token = 4;
    string affinity_hint_node_id = 5;
}

message TaskResult {
    string task_id = 1;
    string node_id = 2;
    TaskStatus status = 3;
    string output = 4;
    int32 exit_code = 5;
    int64 tokens_used = 6;
    int64 duration_ms = 7;
    string error_message = 8;
}

message Heartbeat {
    string node_id = 1;
    int64 timestamp_ms = 2;
    Platform platform = 3;
    double load_average = 4;
}

message TopologySnapshotProto {
    repeated NodeManifest nodes = 1;
    int64 timestamp_ms = 2;
}

message HeartbeatAck { bool accepted = 1; }
message TopologyRequest {}
message EventStreamRequest { string subscriber_id = 1; }

message MeshEventProto {
    string event_type = 1;
    string node_id = 2;
    string task_id = 3;
    int64 timestamp_ms = 4;
    map<string, string> data = 5;
}

service MeshService {
    rpc SubmitTask(TaskSubmission) returns (TaskResult);
    rpc SendHeartbeat(Heartbeat) returns (HeartbeatAck);
    rpc SyncTopology(TopologyRequest) returns (TopologySnapshotProto);
    rpc StreamEvents(EventStreamRequest) returns (stream MeshEventProto);
}
```

---

### ShikiCore Integration

ShikiMesh plugs into ShikiCore via DI. No modifications to ShikiCore source.

1. **CompanyManager route-through**: When mesh is active, CompanyManager calls `MeshOrchestrator.submit()` instead of `AgentProvider.dispatch()`. Detection: `resolveOptional(MeshOrchestrator.self) != nil`.

2. **Event unification**: `MeshEvent` produces `LifecycleEventPayload` (ShikiCore type). Same `EventPersisting` persister. Mesh events flow into ShikiDB alongside lifecycle events.

3. **Budget layering**: `NodeBudgetTracker` (per-node) is separate from `BudgetEnforcer` (per-company). Company budget is the ceiling; node budget prevents one API from consuming the whole allocation.

---

### Implementation Waves

| Wave | Scope | Files | Tests | LOC |
|------|-------|-------|-------|-----|
| **W1** | Models + Config + Package.swift | 12 | MeshConfigTests | ~400 |
| **W2** | TopologyGraph + AffinityCache | 3 | 3 test files | ~350 |
| **W3** | NodeBudgetTracker + HeartbeatAggregator | 2 | 2 test files | ~300 |
| **W4** | TaskRouter + DefaultTaskScorer + FailoverManager | 3 | 3 test files | ~350 |
| **W5** | Proto + gRPC server/client + mDNS + ManualRegistry + TLS | 6 | 2 test files | ~500 |
| **W6** | Virtual shims + MeshOrchestrator + MeshAssembly | 7 | 3 test files | ~450 |
| **W7** | CLI commands (8 subcommands in shiki-ctl) | 8 | integration | ~300 |

**Total: ~2,650 LOC source, ~11 test files, ~80 tests.**

---

### Non-Goals (explicitly out of scope for v1)

- **No consensus / Raft / Paxos** — single orchestrator, static failover chains.
- **No data replication** — state in orchestrator actor. Crash recovery from ShikiDB events.
- **No multi-orchestrator** — one mesh orchestrator per Shiki instance.
- **No iOS as executor** — iPhone is monitoring client only (300s heartbeat). Not a compute node.
- **No automatic cost optimization** — scorer deprioritizes expensive nodes, but no "shift to save money" planner. Phase 6.
- **No tensor sharding** — use exo as a mesh node instead of reimplementing PipelineSlice.
