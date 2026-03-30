---
title: "Shikki Distributed Orchestration — NATS-Backed Context-Safe Multi-Agent Dispatch"
status: spec
priority: P0
project: shikki
created: 2026-03-30
authors: "@shi full team brainstorm + @Daimyo"
depends-on:
  - spec-report-logger-nats.md (NATS foundation)
  - shiki-mesh-protocol.md (multi-node)
  - shiki-event-bus-architecture.md (event types)
  - shikki-native-scheduler.md (ShikkiKernel)
  - shikki-dispatch-resilience.md (band-aid, subsumed by this)
replaces:
  - shikki-dispatch-resilience.md (Layer 1-4 become protocol-native)
---

# Shikki Distributed Orchestration

> The orchestrator is not a chat. The conversation is disposable. The state is permanent.

---

## 1. Problem

On 2026-03-29, a 6-agent parallel dispatch crashed the orchestrator session at Wave 1→2 handoff. Three compounding failures:

1. **Context saturation** — 6 agents × ~4K tokens of results = 24K tokens dumped into orchestrator context per wave. After 2 waves + bookkeeping, 50%+ of the 200K context was consumed by non-thinking overhead.
2. **Worktree CWD trap** — orchestrator tried to remove a worktree it was standing in → `fatal: Unable to read current working directory`.
3. **Compaction in dead CWD** — Claude Code compacted while CWD was a deleted worktree → unrecoverable zombie session.

Root cause: **a Claude Code chat is being used as an orchestrator**. It's a text stream with a fixed buffer, not a process manager. Every agent result fights for the same tokens the orchestrator needs to think.

### Additional failures observed

4. **`shikki status` blind spot** — after crash, `shikki status` reported "session running" because the heartbeat loop was independent of the Claude session. The system couldn't distinguish "kernel alive, orchestrator dead" from "everything healthy."
5. **`/login` invalidation** — when compaction fails in a broken CWD, the Claude session token appears to get invalidated, forcing manual re-login. This is a Claude Code bug, but our architecture should make it irrelevant.
6. **No auto-recovery** — agent worktrees with partial work sat idle until manual `/retry`. No system detected the stall.

---

## 2. Architecture: Separation of Concerns

```
                        ┌──────────────────────┐
                        │     ShikiDB (VPS)    │
                        │  ┌────────────────┐  │
                        │  │ agent_results   │  │  ← full results (unlimited)
                        │  │ dispatch_state  │  │  ← wave checkpoints
                        │  │ agent_events    │  │  ← lifecycle events
                        │  │ context_budgets │  │  ← per-node budget tracking
                        │  └────────────────┘  │
                        └──────────┬───────────┘
                                   │ sync (Lamport)
     NATS Bus ═══════════╤════════╪═════╤═══════════╤══════════
                         │        │     │           │
                    ┌────┴────┐ ┌─┴──┐ ┌┴────┐ ┌───┴────┐
                    │ Kernel  │ │Agt1│ │Agt2│ │  Chat  │
                    │ (Swift) │ │    │ │    │ │  Node  │
                    │         │ │    │ │    │ │(Claude)│
                    │ no UI   │ │ wt │ │ wt │ │        │
                    │ no ctxt │ │    │ │    │ │ 200K   │
                    └─────────┘ └────┘ └────┘ └────────┘
                    Dispatcher   Workers        Human UI
```

### Role Separation

| Component | Responsibility | State | Context |
|-----------|---------------|-------|---------|
| **ShikkiKernel** | Dispatch, scheduling, health monitoring, recovery | Stateless (reads DB) | None (Swift process) |
| **NATS** | Real-time event transport, pub/sub | In-flight messages only | N/A |
| **ShikiDB** | Persistent state, checkpoints, full results | Source of truth | Unlimited |
| **Agent (Claude)** | Code generation in worktree | Worktree + local context | Own 200K window |
| **Chat Node (Claude)** | Human interface, ad-hoc queries | Disposable conversation | Own 200K window |

**Key insight**: The kernel has zero context window. It's a compiled Swift binary that reads state from DB and publishes commands to NATS. It can run indefinitely without accumulation.

---

## 3. Context-Aware Exchange Protocol

### Problem it solves

Agent produces 4,000 tokens of result. Orchestrator can afford 500. Today: 4,000 tokens dumped in, context explodes. Tomorrow: agent advertises metadata, consumer requests what fits.

### Protocol: Three-Phase Envelope

#### Phase 1: ADVERTISE (agent → NATS)

```
Subject: shikki.agent.{agent_id}.result.advertise

{
  "agent_id": "w2-1-s3-spec",
  "status": "complete",               // complete | failed | partial
  "branch": "feature/s3-spec-syntax",
  "commits": 1,
  "tests": { "passed": 72, "failed": 0 },
  "result_token_estimate": 2400,
  "sections": [
    { "key": "summary",       "tokens": 150,  "priority": "critical" },
    { "key": "files_changed", "tokens": 300,  "priority": "high" },
    { "key": "test_report",   "tokens": 800,  "priority": "medium" },
    { "key": "build_log",     "tokens": 1150, "priority": "low" }
  ],
  "full_result_ref": "shikidb://agent-results/{agent_id}"
}
```

**Always stored to DB** — the full result goes to `agent_results` table regardless of who requests what.

#### Phase 2: REQUEST (consumer → NATS)

```
Subject: shikki.agent.{agent_id}.result.request

{
  "requester": "kernel",              // or "chat-node-{session_id}"
  "budget_tokens": 500,
  "sections_wanted": ["summary", "files_changed"],
  "max_priority": "high",             // only sections >= this priority
  "format": "compact"                 // compact | full | json
}
```

**Budget calculation** (consumer-side):

```swift
struct ContextBudget: Sendable {
    let capacity: Int           // ~200K for Claude, unlimited for kernel
    let systemOverhead: Int     // ~40K (prompt + memory + skills)
    let conversationUsed: Int   // estimated from message count
    let reserved: Int           // ~20K buffer for user interaction

    var available: Int { capacity - systemOverhead - conversationUsed - reserved }

    func perAgent(activeCount: Int) -> Int {
        available / max(activeCount, 1)
    }
}
```

For the kernel (Swift binary): budget is unlimited → always request full result.
For chat node: budget is `available / activeAgentCount`.

#### Phase 3: DELIVER (agent → NATS, scoped)

```
Subject: shikki.agent.{agent_id}.result.deliver

{
  "summary": "S3 Spec Syntax: validator + statistics + CLI. 72 tests passing.",
  "files_changed": ["S3Validator.swift", "S3Statistics.swift", "SpecCheckCommand.swift", ...],
  "truncated_sections": ["test_report", "build_log"],
  "full_result_ref": "shikidb://agent-results/w2-1-s3-spec"
}
```

Consumer gets exactly what fits. Full result is always in DB for later inspection.

---

## 4. Agent Lifecycle on NATS

### Subject Map (additions to spec-report-logger-nats.md)

```
shikki.dispatch.wave.{n}.plan          # kernel publishes wave plan
shikki.dispatch.wave.{n}.checkpoint    # kernel publishes completion state
shikki.agent.{id}.spawned             # kernel → agent created
shikki.agent.{id}.heartbeat           # agent → kernel (every 30s)
shikki.agent.{id}.progress            # agent → kernel (commit made, test run, etc.)
shikki.agent.{id}.result.advertise    # agent → bus (I'm done, here's metadata)
shikki.agent.{id}.result.request      # consumer → agent (give me this much)
shikki.agent.{id}.result.deliver      # agent → consumer (scoped result)
shikki.agent.{id}.failed              # agent → kernel (I died, here's why)
shikki.agent.{id}.rate_limited        # agent → kernel (API rate limit hit)
shikki.recovery.scan                  # kernel → bus (looking for stale agents)
shikki.recovery.found                 # kernel → bus (found stale agent, recovering)
```

### Heartbeat Protocol

Every agent publishes a heartbeat every 30 seconds:

```json
{
  "agent_id": "w2-1-s3-spec",
  "worktree": "/path/to/worktree",
  "phase": "implementing",           // reading_spec | implementing | testing | pushing
  "commits": 0,
  "files_changed": 3,
  "last_tool_call": "2026-03-30T06:15:00Z",
  "context_used_pct": 45
}
```

**Silence detection**: If kernel gets no heartbeat for 3 intervals (90s), the agent is stalled.

### Rate Limit Coordination

When any agent hits a rate limit:

```json
{
  "subject": "shikki.agent.{id}.rate_limited",
  "payload": {
    "provider": "anthropic",
    "resets_at": "2026-03-30T07:00:00+02:00",
    "requests_remaining": 0
  }
}
```

Kernel receives this and:
1. Publishes `shikki.dispatch.pause` to all agents
2. Records pause event to DB
3. Sets timer for `resets_at`
4. On timer: publishes `shikki.dispatch.resume`

**No agent burns tokens discovering the rate limit independently.** First one to hit it alerts the mesh.

---

## 5. Auto-Recovery Protocol

### Self-Healing Loop (in ShikkiKernel)

```swift
// In RecoveryService (ManagedService, runs every 120s)
func tick(snapshot: KernelSnapshot) async {
    // 1. Find stalled agents (no heartbeat for 3 intervals)
    let stalled = snapshot.agents.filter {
        $0.lastHeartbeat.distance(to: .now) > .seconds(90)
    }

    for agent in stalled {
        // 2. Check worktree state
        let worktreeState = await checkWorktree(agent.worktreePath)

        switch worktreeState {
        case .hasCommits(let count):
            // Partial work — push what's there, mark as partial
            await pushPartialWork(agent)
            await publish(.agentRecovered(agent.id, .partial(commits: count)))

        case .dirtyNoCommits(let files):
            // Work in progress but uncommitted — commit WIP
            await commitWIP(agent, files: files)
            await publish(.agentRecovered(agent.id, .wipSaved(files: files.count)))

        case .clean:
            // No progress — full retry
            await publish(.agentRecovered(agent.id, .needsRetry))

        case .missing:
            // Worktree gone — full retry
            await publish(.agentRecovered(agent.id, .needsRetry))
        }

        // 3. Re-queue the task if incomplete
        if agent.status != .complete {
            await requeueTask(agent.task, recoveryHint: worktreeState)
        }
    }
}
```

### Worktree Safety (kernel-owned)

Agents never clean up their own worktrees. The kernel does, after confirming:

```swift
func cleanupWorktree(_ path: String) async throws {
    // 1. Verify no process has CWD in this worktree
    let procs = try await findProcessesInDirectory(path)
    guard procs.isEmpty else {
        logger.warning("Worktree \(path) still in use by \(procs.count) processes, deferring cleanup")
        return
    }

    // 2. Kernel's own CWD is always repo root (set at startup)
    assert(FileManager.default.currentDirectoryPath == repoRoot)

    // 3. Remove with absolute path
    try await shell("git", "-C", repoRoot, "worktree", "remove", path, "--force")
}
```

**The CWD trap is eliminated by design** — the kernel is always at repo root, agents never remove worktrees.

---

## 6. Chat Node as Thin Client

### What changes for Claude Code sessions

Today: Claude Code IS the orchestrator. It reads specs, dispatches agents, accumulates results, manages worktrees, tracks state, and talks to the user — all in one conversation.

Tomorrow: Claude Code is a **read-write terminal** to the mesh.

```
User says: "go wave 2"

Chat Node:
  1. POST to NATS: shikki.dispatch.request { wave: 2, specs: [...] }
  2. Subscribe: shikki.agent.*.result.advertise (budget-filtered)
  3. Show user: "Wave 2 dispatched. 4 agents running."
  4. As results arrive: show 3-line summaries
  5. User closes terminal → agents keep running
  6. User reopens → queries DB for current state

Chat Node NEVER:
  - Holds dispatch state in conversation
  - Accumulates agent results beyond budget
  - Manages worktrees
  - Tracks wave progress (kernel does that)
```

### Session Resume (after compaction or crash)

```
Chat Node starts:
  1. Query DB: GET /api/dispatch/state → current wave, agent statuses
  2. Subscribe NATS: shikki.agent.*.result.advertise
  3. Show user: "Resuming. Wave 2 in progress: 3/4 complete."

  Zero spec re-reading. Zero state reconstruction.
  DB is the brain. Chat is the mouth.
```

---

## 7. Moto Cache Integration

### Context compression for agents

Today: each agent reads the full spec file (~500-2000 tokens) + explores codebase (~5000-10000 tokens) before writing code. With 6 agents, that's 33K-72K tokens of redundant codebase reading.

With `.moto` cache:

```
Agent startup:
  1. Read .moto manifest → 200 tokens (project structure, types, protocols)
  2. Read task-specific spec → 500-2000 tokens
  3. Query moto MCP for relevant types → 300 tokens
  4. START CODING

Total context per agent: ~1000-2500 tokens (vs 5500-12000 today)
Savings: 60-80% of agent startup context
```

This means more agents can run in parallel without hitting rate limits, because each agent uses fewer API calls to understand the codebase.

---

## 8. `shikki status` Upgrade

Current `shikki status` reports kernel health but is blind to orchestrator health. New model:

```
$ shikki status

Shikki Orchestrator
────────────────────────────────────────────────────────
Workspace: /Users/jeoffrey/Documents/Workspaces/shiki
Kernel:    🟢 running (pid 12345)
NATS:      🟢 connected (localhost:4222)
DB:        🟢 healthy (VPS sync: 2s ago)
────────────────────────────────────────────────────────

Dispatch: Wave 2 in progress
  W2-1  S3 Spec Syntax     ✅ complete  72t  pushed
  W2-2  Augmented TUI      🔥 running   phase: testing (45% ctx)
  W2-3  Enterprise Safety  🔥 running   phase: implementing (62% ctx)
  W2-4  Answer Engine      ✅ complete  72t  pushed

  Queue: Wave 3 (3 specs) — waiting for W2 completion

Chat Nodes:
  session-abc123  🟢 connected  context: 38% used
  (no other nodes)

Recovery:
  Last scan: 45s ago  |  Stalled: 0  |  Recovered: 0
────────────────────────────────────────────────────────
```

Each component reports independently. If the chat node dies, kernel + agents keep running and status reflects reality.

---

## 9. Implementation Waves

### Wave 1: NATS Foundation (depends on spec-report-logger-nats.md)
- `NATSClient` protocol + `SwiftNATSClient` implementation
- `NATSEventBridge` actor (dual-sink: NATS + DB)
- `NATSSubjectMapper` (event type → subject routing)
- nats-server lifecycle in `StartCommand`
- **28 tests** estimated

### Wave 2: Agent Protocol
- Envelope protocol (advertise → request → deliver)
- `ContextBudget` struct with per-consumer calculation
- Agent heartbeat publisher (30s interval)
- Rate limit coordination (pause/resume)
- `AgentLifecycleManager` in kernel
- **35 tests** estimated

### Wave 3: Recovery + Worktree Safety
- `RecoveryService` as ManagedService (120s tick)
- Worktree state inspector (commits? dirty? missing?)
- WIP commit + push for partial work
- Task requeue with recovery hints
- Worktree cleanup (kernel-owned, CWD-safe)
- **25 tests** estimated

### Wave 4: Chat Node Thin Client
- Dispatch request via NATS (not direct agent spawning)
- Budget-filtered result subscription
- DB-first session resume
- Status display from NATS stream
- **20 tests** estimated

### Wave 5: Status + Observability
- `shikki status` upgrade (kernel + NATS + DB + agents + chat nodes)
- `shikki agents` command (live agent dashboard)
- `shikki dispatch history` (past waves from DB)
- NATS subject monitoring
- **15 tests** estimated

---

## 10. Acceptance Criteria

- [ ] Dispatch of 10+ specs completes without any session death
- [ ] Chat node crash during dispatch → agents keep running, new session resumes from DB
- [ ] Agent rate limit → all agents pause, resume after cooldown
- [ ] Stalled agent → auto-recovery within 3 minutes (no human intervention)
- [ ] Agent result never exceeds consumer's context budget
- [ ] `shikki status` shows independent health of kernel, NATS, DB, agents, chat nodes
- [ ] Worktree cleanup never crashes regardless of CWD state
- [ ] Wave checkpoint in DB → `/retry` resumes from exact failure point

---

## 11. @shi Mini-Challenge

1. **@Ronin**: If the kernel itself crashes, who restarts it? launchd/systemd watchdog? What if NATS is down?
2. **@Katana**: The envelope protocol trusts agents to accurately report `result_token_estimate`. What if they lie (hallucinate a low count)? Should DB validate?
3. **@Sensei**: Should the chat node keep a local SQLite mirror of dispatch state for offline mode (airplane, no VPS)?
4. **@Hanami**: When the user opens a new chat and there's a dispatch running, what's the first thing they should see? Full status dump or just "Wave 2: 3/4 done"?
5. **@Kintsugi**: The "conversation is disposable" principle — does this change the relationship between user and AI? Is there grief in letting go of session continuity?
