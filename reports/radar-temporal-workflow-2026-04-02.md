# Radar: Temporal -- Durable Execution Engine for Workflow Orchestration

**Date**: 2026-04-02
**Source**: https://github.com/temporalio/temporal (19.3k stars, MIT)
**Website**: https://temporal.io
**Category**: Infrastructure / Workflow Engine / Durable Execution
**Verdict**: ADOPT (pattern) -- do NOT adopt the server, but steal the durable execution model for shid

---

## 1. Temporal Architecture Summary

### What it is
Temporal is a durable execution platform (originated as fork of Uber's Cadence). It guarantees that workflow functions survive crashes, restarts, and infrastructure failures by automatically checkpointing every step and replaying event history to recover state. Written in Go, MIT license.

### Core concepts

| Concept | What it does |
|---|---|
| **Workflow** | Deterministic orchestration function. Writes normal procedural code but state is automatically persisted |
| **Activity** | Non-deterministic side-effect (API call, file I/O, LLM call). Has retry policies and timeouts |
| **Worker** | Process that polls task queues and executes workflows/activities. Horizontally scalable |
| **Event History** | Append-only log of every step. Source of truth for replay and recovery |
| **Task Queue** | Matching service pairs available workers with pending tasks |
| **Signal** | External input into a running workflow (can modify state, trigger activities) |
| **Query** | Read-only state inspection without advancing workflow |
| **Continue-As-New** | Reset event history while keeping the same workflow ID. Essential for long-running workflows |

### How state persistence works

1. Every workflow step generates events stored in an append-only history
2. When a worker crashes, the entire history transfers to a new worker
3. The workflow function replays from the beginning, but all side effects (activities) are skipped via recorded results
4. Local variables, loop counters, and branch decisions are fully reconstructed
5. Checkpointing is invisible -- developers write normal code, Temporal handles persistence

### Retry policies

Activities support configurable retry behavior:
- `InitialInterval` -- starting delay between attempts
- `BackoffCoefficient` -- multiplier for exponential backoff (default 2.0)
- `MaximumAttempts` -- total retry limit
- `NonRetryableErrorTypes` -- exceptions that bypass retries

### Activity timeouts (three levels)

1. **Schedule-To-Close** -- total time from scheduling to completion
2. **Start-To-Close** -- execution duration after worker picks up the task
3. **Heartbeat Timeout** -- maximum silence before presuming activity failure

### Signal handling

- `workflow.Channel` and `workflow.Selector` for coordinating concurrent activities
- Signals can modify workflow state and trigger new activities
- Queries provide read-only inspection without adding to event history
- Updates combine signal + query with validation

### Long-running workflow management

- Event history limit: 50K events (51,200) and 50MB size
- **Continue-As-New** resets history while preserving workflow identity
- Pending signals must be drained before Continue-As-New (or they're lost)
- Unawaited activities are canceled during transitions
- For large data, pass URLs (S3) instead of payloads

### Non-deterministic value capture

- `workflow.SideEffect()` captures random/timestamps once, stores in history for replay consistency
- `workflow.Now()` returns consistent timestamps across replays
- This guarantees identical behavior during recovery

---

## 2. Temporal for AI Agents

Temporal has explicitly positioned itself as an AI agent orchestration platform (blog post: "Durable Execution meets AI"). Key patterns:

### Agent loop pattern
```
while not goal_achieved(history):
    next_action = execute_activity(llm_decide, goal, history, tools)
    result = execute_activity(next_action.tool, next_action.params)
    history.append(action, result)
```

The workflow is deterministic (loop structure), but the LLM decisions within activities are non-deterministic. On replay, prior LLM decisions are read from history, not re-executed.

### Dynamic tool dispatch
LLMs determine which activity to execute at runtime. The agent dynamically selects tools based on context rather than following predetermined steps.

### Multi-step planning
Parent workflows spawn child workflows. LLM generates plans as activities; each step runs as a separate child workflow with its own event history.

### Production examples on Temporal
- **OpenAI Codex** -- AI coding agent handling millions of requests
- **Replit Agent 3** -- long-running agentic implementation

---

## 3. Relevance to Shikki / shid

### Direct mapping to shid daemon

| Temporal concept | shid equivalent |
|---|---|
| Workflow | FeatureLifecycle FSM (spec -> quick -> ship) |
| Activity | Agent dispatch (claude -p), build, test, deploy |
| Event History | ShikiDB event persistence (agent_events table) |
| Worker | shid worker process |
| Signal | shiki push / ntfy actions / MCP tool calls |
| Query | shiki status / board |
| Continue-As-New | Context compaction + session recovery |
| Heartbeat | Agent liveness checks (15s blocking budget) |

### What shid should steal

**1. Invisible checkpointing**: shid should automatically persist every FSM transition to ShikiDB without explicit developer code. Current FeatureLifecycle emits events but doesn't guarantee replay recovery. The Temporal model says: write normal procedural code, the platform handles persistence.

**2. Activity retry policies**: Agent dispatches (claude -p) need configurable retry with exponential backoff, heartbeat timeouts, and non-retryable error classification. Currently shid has no structured retry -- it either succeeds or fails.

**3. Event sourcing for replay**: Instead of storing just current state, store the full decision history. When shid recovers from crash, replay the event log to reconstruct exactly where the workflow was. This is the missing piece between "context compaction" (lossy) and true durable execution (lossless).

**4. Continue-As-New for long sessions**: When event history grows too large (context window exhaustion), create a fresh execution with summarized state -- exactly like Temporal's Continue-As-New. This maps to context compaction but with guaranteed signal draining first.

### Is Temporal overkill?

**YES for the server**. Temporal is a distributed system requiring PostgreSQL/MySQL/Cassandra + Elasticsearch, designed for multi-team microservices. shid is a single-user CLI daemon. Running a Temporal cluster for one developer is absurd.

**NO for the pattern**. The durable execution model is exactly right for shid:
- Workflows that survive crashes (FeatureLifecycle)
- Automatic retry with backoff (AgentProvider)
- Event sourcing for state recovery (ShikiDB)
- Signal-driven interaction (shiki push / ntfy)
- Long-running workflows with history compaction (Continue-As-New)

The correct approach: implement Temporal's patterns in Swift within ShikiCore, using ShikiDB (SQLite/PocketBase) as the event store. No external dependency.

---

## 4. Architecture Risks

| Risk | Mitigation |
|---|---|
| Event history bloat in ShikiDB | Implement Continue-As-New: archive old events, start fresh with summary state |
| Replay non-determinism | All LLM calls must be Activities (results stored), never inline in workflow |
| Heartbeat false positives | Use Temporal's three-timeout model (schedule-to-close, start-to-close, heartbeat) |
| Over-engineering | Start with simple checkpoint-on-transition, not full event sourcing. Evolve later. |

---

## 5. Action Items (max 3)

1. **[P0] Implement DurableWorkflow protocol in ShikiCore** -- a Swift protocol that wraps FeatureLifecycle with automatic event persistence on every state transition. Every `transition(from:to:)` call writes to ShikiDB before proceeding. On recovery, replay events to reconstruct state. This is the single highest-leverage pattern from Temporal.

2. **[P1] Add ActivityRetryPolicy to AgentProvider** -- configurable retry with `initialInterval`, `backoffCoefficient`, `maximumAttempts`, `nonRetryableErrors`, and `heartbeatTimeout`. Apply to all `claude -p` dispatches. Current fire-and-forget is fragile.

3. **[P1] Implement ContinueAsNew for context compaction** -- when event count exceeds threshold (configurable, default 1000), archive history to ShikiDB, create summary state, and restart workflow with fresh history. Drain all pending signals before transition. This replaces the current lossy compaction with a Temporal-inspired lossless approach.

---

## 6. Verdict: ADOPT (pattern)

Temporal's durable execution model is the missing architecture for shid. The server itself is overkill for a single-user CLI tool, but the patterns (event sourcing, invisible checkpointing, activity retry, Continue-As-New) map 1:1 to ShikiCore's needs. Implement in Swift, store in ShikiDB, skip the distributed infrastructure.

Key insight: Temporal proves that OpenAI Codex and Replit Agent 3 both chose durable execution for their AI agents. shid should be in the same architectural family.

---

**Sources**:
- [Temporal GitHub](https://github.com/temporalio/temporal) (19.3k stars)
- [Temporal Go SDK docs](https://docs.temporal.io/develop/go/core-application)
- [Temporal architecture docs](https://github.com/temporalio/temporal/tree/main/docs/architecture)
- [Durable Execution meets AI](https://temporal.io/blog/durable-execution-meets-ai-why-temporal-is-the-perfect-foundation-for-ai)
- [Building dynamic AI agents with Temporal](https://temporal.io/blog/of-course-you-can-build-dynamic-ai-agents-with-temporal)
- [Managing very long-running workflows](https://temporal.io/blog/very-long-running-workflows)
- [Temporal replaces state machines](https://temporal.io/blog/temporal-replaces-state-machines-for-distributed-applications)
