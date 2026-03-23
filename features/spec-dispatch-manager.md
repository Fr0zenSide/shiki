# DispatchManager — Implementation Spec

> The brain of `shikki run`. Owns task classification, agent spawning, worktree lifecycle, build isolation, failure handling, concurrency control, and NATS-based progress tracking.
>
> Author: @Sensei | Date: 2026-03-23 | Status: Draft

---

## Architecture Diagram

```
                          shikki run [--spec X] [--dry-run]
                                     │
                                     ▼
                            ┌─────────────────┐
                            │   RunCommand     │  (CLI entry point)
                            │   parse flags    │
                            │   load specs     │
                            └────────┬─────────┘
                                     │
                                     ▼
                ┌────────────────────────────────────────┐
                │           DispatchManager               │
                │                                        │
                │  ┌──────────────┐  ┌────────────────┐  │
                │  │ TaskClassi-  │  │ Concurrency-   │  │
                │  │ fier         │  │ Gate           │  │
                │  └──────┬───────┘  └───────┬────────┘  │
                │         │                  │           │
                │  ┌──────▼───────┐  ┌───────▼────────┐  │
                │  │ Worktree-    │  │ Budget-        │  │
                │  │ Manager      │  │ Enforcer       │  │
                │  └──────┬───────┘  └───────┬────────┘  │
                │         │                  │           │
                │  ┌──────▼──────────────────▼────────┐  │
                │  │        AgentSpawner              │  │
                │  │  (worktree + scratch-path +      │  │
                │  │   claude -p / Process spawn)     │  │
                │  └──────────────┬───────────────────┘  │
                │                 │                      │
                └─────────────────┼──────────────────────┘
                                  │
                    ┌─────────────┼─────────────┐
                    ▼             ▼              ▼
              ┌──────────┐ ┌──────────┐  ┌──────────┐
              │ Agent A   │ │ Agent B   │  │ Agent C   │
              │ worktree/ │ │ worktree/ │  │ worktree/ │
              │ scratch/  │ │ scratch/  │  │ scratch/  │
              └─────┬─────┘ └─────┬─────┘  └─────┬─────┘
                    │             │              │
                    └─────────────┼──────────────┘
                                  │ NATS publish
                                  ▼
                    ┌─────────────────────────────┐
                    │  shikki.dispatch.*           │
                    │  shikki.agents.{id}.*       │
                    │  shikki.tasks.{ws}.*        │
                    └──────────┬──────────────────┘
                               │ subscribe
                    ┌──────────▼──────────────────┐
                    │  Event Logger Pane           │
                    │  DispatchManager (progress)  │
                    │  Inbox (completion)          │
                    └─────────────────────────────┘
```

---

## 1. Task Classification

### Problem

A spec file (`features/*.md`) describes work that may touch Swift, TypeScript, markdown, config, or mixed toolchains. The DispatchManager must detect the toolchain to enforce correct build isolation rules and set agent environment variables.

### Design

```
TaskClassifier.classify(spec: SpecDocument) -> TaskToolchain
```

**Enum: `TaskToolchain`**

| Case | Detection signal | Build isolation | Env vars |
|------|-----------------|-----------------|----------|
| `.swift` | `*.swift` in file list, `Package.swift` in project, `swift build/test` in spec | `--scratch-path` per agent | `SKIP_E2E=1` |
| `.typescript` | `*.ts` in file list, `package.json` in project, `deno`/`npm` in spec | None (no shared lock) | `DENO_DIR` per agent if Deno |
| `.markdown` | Only `*.md` files in spec | None | None |
| `.config` | Only config files (`.yml`, `.json`, `.toml`, `Caddyfile`) | None | None |
| `.mixed(Set<TaskToolchain>)` | Multiple toolchains in same spec | Union of all rules | Union |

**Detection algorithm (priority order):**

1. **Explicit annotation** — spec frontmatter `toolchain: swift` (author override, highest priority)
2. **File list scan** — if spec has a "Files to create/modify" section, scan extensions
3. **Project heuristic** — check project root for `Package.swift` (Swift), `package.json`/`deno.json` (TS), etc.
4. **Default** — `.mixed([.swift, .typescript])` (safest: apply all isolation)

**Edge case:** A spec that modifies both `ShikiCtlKit/*.swift` and `src/backend/*.ts` is `.mixed`. The DispatchManager applies Swift isolation rules to any agent touching Swift files, even if other agents in the same dispatch are TS-only.

---

## 2. Swift Build Isolation

### The Problem (observed 2026-03-22/23)

Multiple `swift build`/`swift test` processes contend on:
- `.build/.lock` (SPM build lock) -> exit 144
- `~/.swiftpm/` (shared package cache) -> resolution hangs
- E2E tests waiting on stdin -> zombie processes hold lock forever

### Rules (non-negotiable)

Every Swift agent MUST run with:

```bash
AGENT_ID="agent-$(uuidgen | head -c 8)"
SCRATCH="/tmp/shiki-builds/${AGENT_ID}/.build"
CACHE="/tmp/shiki-builds/${AGENT_ID}/cache"

swift build  --scratch-path "$SCRATCH" --cache-path "$CACHE"
swift test   --scratch-path "$SCRATCH" --cache-path "$CACHE"
```

**Enforcement points:**

1. **AgentSpawner** — injects `SHIKKI_SCRATCH_PATH` and `SHIKKI_CACHE_PATH` env vars into agent process
2. **Agent prompt** — autopilot prompt includes explicit instruction: "ALWAYS use `--scratch-path $SHIKKI_SCRATCH_PATH` for swift build/test"
3. **Claude Code hook** (future) — `.claude/hooks/pre-command` that rewrites `swift build/test` to include the flag
4. **Cleanup** — `WorktreeManager.cleanup()` removes `/tmp/shiki-builds/${AGENT_ID}/` after merge

**Additional:**
- `SKIP_E2E=1` always set for worktree agents (E2E tests hang on stdin in non-interactive context)
- Max 3 concurrent Swift build processes (CPU/memory safety on M-series, see Concurrency Control)

---

## 3. Worktree Lifecycle

### State Machine

```
            create
  [none] ──────────→ [active]
                        │
              ┌─────────┼──────────┐
              │         │          │
           merge     abandon    orphan
              │         │     (crash/timeout)
              ▼         ▼          │
          [merged]  [abandoned]    │
              │         │          │
              └─────────┼──────────┘
                        │ cleanup
                        ▼
                     [deleted]
```

**WorktreeManager API:**

```swift
actor WorktreeManager {
    /// Create a worktree from develop for this agent's task
    func create(agentId: String, baseBranch: String, featureBranch: String) async throws -> WorktreeInfo

    /// List all active Shikki-managed worktrees
    func listActive() async -> [WorktreeInfo]

    /// Cleanup a worktree after merge/abandon
    func cleanup(agentId: String) async throws

    /// Reap orphaned worktrees (no running agent, older than TTL)
    func reapOrphans(ttl: Duration) async throws -> [String]
}
```

**WorktreeInfo model:**

```swift
struct WorktreeInfo: Codable, Sendable {
    let agentId: String
    let path: String                // .claude/worktrees/{agent-id}
    let baseBranch: String          // typically "develop"
    let featureBranch: String       // "dispatch/{spec-slug}/{agent-id}"
    let scratchPath: String         // /tmp/shiki-builds/{agent-id}/.build
    let cachePath: String           // /tmp/shiki-builds/{agent-id}/cache
    let createdAt: Date
    let toolchain: TaskToolchain
    var status: WorktreeStatus      // .active, .merged, .abandoned, .orphan
}
```

**Worktree creation flow:**

1. `git worktree add .claude/worktrees/{agent-id} -b dispatch/{spec-slug}/{agent-id} develop`
2. Run `scripts/worktree-setup.sh` (fixes local SPM paths — see `memory/feedback_worktree-spm-setup.md`)
3. Create scratch/cache dirs under `/tmp/shiki-builds/{agent-id}/`
4. Register in `~/.config/shiki/worktrees.json` (local tracking, not DB)
5. Publish `shikki.dispatch.worktree.created` to NATS

**Branch naming:** `dispatch/{spec-slug}/{agent-id}` — e.g., `dispatch/spec-dispatch-manager/a3f2b1c0`

**Cleanup triggers:**
- Agent completes task and PR is merged -> `cleanup(agentId:)`
- Agent crashes/times out -> marked `.orphan`, reaped after 4h TTL
- `shikki run --cleanup` manual command
- Heartbeat loop calls `reapOrphans()` every 10 minutes

**Cleanup actions:**
1. `git worktree remove .claude/worktrees/{agent-id}`
2. `git branch -d dispatch/{spec-slug}/{agent-id}` (only if merged)
3. `rm -rf /tmp/shiki-builds/{agent-id}/`
4. Remove entry from `worktrees.json`
5. Publish `shikki.dispatch.worktree.deleted` to NATS

---

## 4. Agent Spawning

### How Agents Are Launched

**v1 (current capability):** `claude -p` as a subprocess in the worktree directory.

```swift
actor AgentSpawner {
    /// Spawn a Claude agent in a worktree with full isolation
    func spawn(config: AgentSpawnConfig) async throws -> AgentHandle

    /// Send SIGTERM to agent process, wait for graceful shutdown
    func terminate(agentId: String) async throws

    /// List running agent processes
    func listRunning() async -> [AgentHandle]
}
```

**AgentSpawnConfig:**

```swift
struct AgentSpawnConfig: Sendable {
    let agentId: String
    let specPath: String            // features/spec-*.md
    let worktree: WorktreeInfo
    let toolchain: TaskToolchain
    let prompt: String              // autopilot prompt with task instructions
    let timeout: Duration           // max runtime before forced kill
    let environment: [String: String]  // SHIKKI_SCRATCH_PATH, SKIP_E2E, etc.
}
```

**Spawn sequence:**

1. WorktreeManager creates worktree
2. TaskClassifier determines toolchain
3. AgentSpawner builds environment vars:
   - `SHIKKI_AGENT_ID` = agent UUID
   - `SHIKKI_SCRATCH_PATH` = `/tmp/shiki-builds/{agent-id}/.build`
   - `SHIKKI_CACHE_PATH` = `/tmp/shiki-builds/{agent-id}/cache`
   - `SKIP_E2E` = `1` (always for dispatch agents)
   - `SHIKKI_NATS_URL` = `nats://localhost:4222`
   - `SHIKKI_SPEC` = path to spec file
4. Launch: `claude -p "{autopilot_prompt}"` as `Process` in worktree CWD
5. Monitor: stdout/stderr piped to log file at `.claude/worktrees/{agent-id}/agent.log`
6. Publish `shikki.agents.{agent-id}.spawned` to NATS

**v2 (future — NATS command):** Instead of `claude -p`, the DispatchManager publishes a `shikki.commands.{node-id}` message. A remote node picks it up and spawns the agent locally. This enables multi-machine dispatch without changing DispatchManager logic — only `AgentSpawner` gets a new implementation.

### How Agents Report Progress

Agents report via two channels:

1. **ShikiDB API** (existing) — `POST /api/task-queue/{id}` status updates, `POST /api/orchestrator/heartbeat`
2. **NATS publish** (new) — `shikki.agents.{agent-id}.progress` with structured events

The autopilot prompt instructs agents to publish progress at key moments:
- Tests written (count)
- Tests passing (count/total)
- Build succeeded/failed
- PR created (number)
- Task completed
- Blocker hit (decision needed)

---

## 5. Failure Handling

### Failure Types and Responses

| Failure | Detection | Response | Retry? | Escalation |
|---------|-----------|----------|--------|------------|
| Agent crash (SIGKILL, exit != 0) | Process termination handler | Log event, mark worktree orphan | 1 retry with fresh worktree | Inbox item: "Agent {id} crashed on {spec}" |
| Build failure (swift build fails) | Agent reports via NATS / heartbeat goes silent | Wait for agent self-recovery (TDD loop) | Agent handles internally | After 3 consecutive build failures in same agent: terminate, inbox alert |
| Test failure | Agent reports test count regression | Agent handles internally (TDD) | N/A | No escalation unless agent gives up |
| Timeout (exceeds config duration) | Timer in AgentSpawner | SIGTERM -> wait 30s -> SIGKILL | No retry (likely scope issue) | Inbox item: "Agent {id} timed out on {spec} after {duration}" |
| Budget exhausted | BudgetEnforcer check before spawn + periodic | Block new spawns for company | No | Inbox item: "Company {slug} budget exhausted" |
| NATS disconnect | Heartbeat silence > 3 intervals | Mark agent suspect, check process alive | Reconnect automatically | If process dead: treat as crash |
| Worktree conflict | `git worktree add` fails | Use alternative branch name | 1 retry with suffix | Inbox item if still fails |

### Retry Policy

```swift
struct RetryPolicy: Sendable {
    let maxRetries: Int           // default: 1
    let backoff: Duration         // default: 30s
    let freshWorktree: Bool       // default: true (don't reuse crashed worktree)
}
```

- Crash retry: 1 attempt, fresh worktree, 30s backoff
- Timeout: no retry (scope problem, not transient)
- Build contention (exit 144): 1 retry with new scratch-path UUID suffix
- All retries publish `shikki.dispatch.retry` event

### Escalation Path

Failed tasks that exhaust retries:
1. Task status set to `failed` in DB
2. `ShikiEvent(.dispatchFailed)` published to event bus
3. Inbox item created with failure context (agent log tail, exit code, last NATS message)
4. ntfy push notification: "Task failed: {title} ({reason})"

---

## 6. Concurrency Control

### Limits

```swift
struct ConcurrencyConfig: Codable, Sendable {
    /// Max total agents running on this machine
    let maxAgentsPerMachine: Int      // default: 6

    /// Max agents per company (prevents one company from hogging all slots)
    let maxAgentsPerCompany: Int      // default: 2

    /// Max concurrent Swift build processes (CPU/memory bound)
    let maxSwiftBuilds: Int           // default: 3

    /// Global budget ceiling per day (all companies combined)
    let globalDailyBudgetUsd: Double  // default: 50.0
}
```

**ConcurrencyGate:**

```swift
actor ConcurrencyGate {
    /// Check if a new agent can be spawned given current limits
    func canSpawn(company: String, toolchain: TaskToolchain) async -> SpawnDecision

    /// Register a spawned agent (occupies a slot)
    func register(agentId: String, company: String, toolchain: TaskToolchain) async

    /// Release a slot when agent completes/crashes
    func release(agentId: String) async

    /// Current utilization snapshot
    func snapshot() async -> ConcurrencySnapshot
}

enum SpawnDecision: Sendable {
    case allowed
    case blocked(reason: BlockReason)
}

enum BlockReason: Sendable {
    case machineCapacity(running: Int, max: Int)
    case companyCapacity(company: String, running: Int, max: Int)
    case swiftBuildLimit(running: Int, max: Int)
    case budgetExhausted(company: String, spent: Double, limit: Double)
    case globalBudgetExhausted(spent: Double, limit: Double)
}
```

**Budget enforcement:**

- Before spawn: check `company.spentToday < company.budget.dailyUsd`
- Before spawn: check `sum(all companies spentToday) < globalDailyBudgetUsd`
- During run: HeartbeatLoop continues periodic budget checks; if exhausted mid-run, do NOT kill running agents (let them finish current task), but block new spawns

**Swift build serialization:**

- ConcurrencyGate tracks `.swift` toolchain agents separately
- If `maxSwiftBuilds` reached, queue Swift tasks and dispatch when a slot opens
- Non-Swift agents are unaffected by Swift build limits

---

## 7. NATS Integration

### Topic Hierarchy (dispatch-specific)

```
shikki.dispatch.started              — DispatchManager began a run cycle
shikki.dispatch.plan                 — dry-run plan published (what would dispatch)
shikki.dispatch.task.queued          — task accepted into dispatch queue
shikki.dispatch.task.spawned         — agent spawned for task
shikki.dispatch.task.completed       — agent finished task successfully
shikki.dispatch.task.failed          — agent failed (with reason)
shikki.dispatch.task.retrying        — retrying after failure
shikki.dispatch.task.timeout         — agent exceeded time limit
shikki.dispatch.worktree.created     — worktree created for agent
shikki.dispatch.worktree.deleted     — worktree cleaned up
shikki.dispatch.budget.exhausted     — company or global budget hit
shikki.dispatch.concurrency.blocked  — spawn blocked (with reason)
shikki.dispatch.cycle.complete       — all tasks in this run cycle done

shikki.agents.{agent-id}.spawned    — agent process started
shikki.agents.{agent-id}.progress   — agent reports progress (tests, builds, PRs)
shikki.agents.{agent-id}.heartbeat  — agent alive signal (30s interval)
shikki.agents.{agent-id}.completed  — agent finished all work
shikki.agents.{agent-id}.failed     — agent crashed or gave up
shikki.agents.{agent-id}.decision   — agent needs human input

shikki.tasks.{workspace}.available  — (existing) task posted for claim
shikki.tasks.{workspace}.claimed    — (existing) agent claimed task
shikki.tasks.{workspace}.done       — (existing) task completed
```

### Message Format

All NATS messages are JSON-encoded `ShikiEvent` structs:

```json
{
  "id": "uuid",
  "timestamp": "2026-03-23T14:32:01Z",
  "source": {"orchestrator": {}},
  "type": {"custom": "dispatch.task.spawned"},
  "scope": {"project": {"slug": "maya"}},
  "payload": {
    "agentId": {"string": "a3f2b1c0"},
    "specPath": {"string": "features/spec-dispatch-manager.md"},
    "toolchain": {"string": "swift"},
    "worktreePath": {"string": ".claude/worktrees/a3f2b1c0"}
  }
}
```

### Task Claim/Complete Protocol

**Claim (request/reply on `shikki.tasks.{workspace}.available`):**

1. DispatchManager publishes task to `shikki.tasks.{workspace}.available`
2. Agent subscribes, replies with claim request
3. DispatchManager validates (agent exists, budget OK, no duplicate claim)
4. Publishes `shikki.tasks.{workspace}.claimed` with agent assignment

For v1 (single machine), this is simplified: DispatchManager directly assigns tasks to agents it spawns. The NATS claim protocol exists for v2 multi-machine where remote nodes compete for tasks.

**Complete:**

1. Agent publishes `shikki.agents.{agent-id}.completed` with result summary
2. DispatchManager receives, updates task status in DB
3. Triggers worktree cleanup
4. Creates inbox item if PR was created
5. Publishes `shikki.dispatch.task.completed`

### NATSBridge

```swift
actor NATSBridge {
    /// Connect to NATS server
    func connect(url: String) async throws

    /// Publish a ShikiEvent to a topic
    func publish(topic: String, event: ShikiEvent) async throws

    /// Subscribe to a topic pattern, receive events via AsyncStream
    func subscribe(pattern: String) async throws -> AsyncStream<(String, ShikiEvent)>

    /// Request/reply (for task claims, discovery)
    func request(topic: String, event: ShikiEvent, timeout: Duration) async throws -> ShikiEvent
}
```

---

## 8. RunCommand (CLI)

### Usage

```
shikki run                              # dispatch all approved specs
shikki run --spec spec-dispatch-manager # dispatch specific spec by slug
shikki run --spec p1-group-a,p1-group-b # dispatch multiple specs
shikki run --dry-run                    # show plan without side effects
shikki run --dry-run --json             # machine-readable plan
shikki run --max-agents 4              # override max concurrent agents
shikki run --company maya              # only dispatch for one company
shikki run --cleanup                   # reap orphaned worktrees, no dispatch
shikki run --status                    # show current dispatch status
```

### RunCommand Implementation

```swift
struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Dispatch approved specs to execution agents"
    )

    @Option(name: .long, help: "Spec slug(s) to dispatch (comma-separated)")
    var spec: String?

    @Flag(name: .long, help: "Show dispatch plan without executing")
    var dryRun = false

    @Flag(name: .long, help: "JSON output for dry-run")
    var json = false

    @Option(name: .long, help: "Override max concurrent agents")
    var maxAgents: Int?

    @Option(name: .long, help: "Only dispatch for this company")
    var company: String?

    @Flag(name: .long, help: "Cleanup orphaned worktrees")
    var cleanup = false

    @Flag(name: .long, help: "Show current dispatch status")
    var status = false
}
```

### Execution Flow

1. **Load specs** — scan `features/spec-*.md` for approved specs (frontmatter `status: approved`)
2. **Filter** — apply `--spec` and `--company` filters
3. **Classify** — `TaskClassifier.classify()` each spec
4. **Plan** — build dispatch plan: which agents, which worktrees, which order, estimated duration
5. **Gate check** — `ConcurrencyGate.canSpawn()` for each planned agent
6. **Budget check** — `BudgetEnforcer` validates all companies have budget remaining
7. **Dry-run exit** — if `--dry-run`, print plan and exit
8. **Dispatch** — for each task in plan:
   a. `WorktreeManager.create()`
   b. `AgentSpawner.spawn()`
   c. Publish NATS events
9. **Monitor** — DispatchManager enters monitoring loop (feeds event logger, watches for completions/failures)
10. **Complete** — when all agents done, publish `shikki.dispatch.cycle.complete`, update inbox

### Dry-Run Output

```
Dispatch Plan — 3 specs, 5 agents, est. 45min
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

spec-dispatch-manager (swift)
  Agent A  →  DispatchManager + WorktreeManager    [maya]   ~180 LOC
  Agent B  →  AgentSpawner + ConcurrencyGate       [maya]   ~150 LOC

spec-inbox-command (swift)
  Agent C  →  InboxCommand + ListReviewer          [shiki]  ~220 LOC

spec-event-logger (typescript)
  Agent D  →  NATS subscriber pane                 [shiki]  ~80 LOC
  Agent E  →  Event format + filter                [shiki]  ~60 LOC

Concurrency: 5 agents / 6 max  |  Swift: 3 / 3 max
Budget: maya $4.20 remaining  |  shiki $12.50 remaining
```

---

## 9. Progress Tracking

### Event Logger Pane

The right-side tmux pane subscribes to `shikki.>` via NATS and formats events as a live stream:

```
[14:32:01] DISPATCH  run started — 3 specs, 5 agents
[14:32:02] DISPATCH  worktree created: agent-a3f2b1c0 → maya
[14:32:02] DISPATCH  worktree created: agent-7e1d4a90 → maya
[14:32:03] AGENT     a3f2b1c0  spawned → spec-dispatch-manager
[14:32:03] AGENT     7e1d4a90  spawned → spec-dispatch-manager
[14:32:30] AGENT     a3f2b1c0  tests: 4 written, 0 passing
[14:33:15] AGENT     a3f2b1c0  build: succeeded (incremental, 3.2s)
[14:33:45] AGENT     a3f2b1c0  tests: 4/4 passing
[14:34:00] AGENT     a3f2b1c0  PR #42 created → dispatch/spec-dispatch-manager/a3f2b1c0
[14:34:01] DISPATCH  task completed: a3f2b1c0 (4min)
[14:34:02] DISPATCH  worktree deleted: a3f2b1c0
[14:34:02] INBOX     PR #42 ready for review [maya:spec-dispatch-manager]
```

**Zero LLM tokens** — pure data mirroring from NATS to terminal.

### How Inbox Knows Agents Are Done

1. Agent publishes `shikki.agents.{id}.completed` with `{"prNumber": 42, "summary": "..."}`
2. DispatchManager receives event, updates task status in ShikiDB
3. DispatchManager creates inbox item: `{type: "pr", title: "PR #42 — DispatchManager", status: "pending", source: "dispatch"}`
4. When ALL agents for a spec complete, DispatchManager publishes `shikki.dispatch.cycle.complete`
5. ntfy push: "Dispatch complete: 3 specs, 5 PRs ready for review"

### DispatchManager Monitoring Loop

After spawning agents, DispatchManager enters a monitoring state:

```swift
func monitorUntilComplete() async {
    let events = try await nats.subscribe(pattern: "shikki.agents.>")

    for await (topic, event) in events {
        switch event.type {
        case .custom("agent.completed"):
            handleAgentCompleted(event)
        case .custom("agent.failed"):
            handleAgentFailed(event)
        case .custom("agent.decision"):
            handleAgentDecision(event)
        default:
            // Forward to event logger (already subscribed via NATS)
            break
        }

        if allAgentsDone() {
            publishCycleComplete()
            break
        }
    }
}
```

---

## DispatchManager State Machine

```
                   run command
     [idle] ─────────────────→ [planning]
                                   │
                          classify + gate check
                                   │
                    ┌───── dry-run? ┼──────────┐
                    │  yes          │ no        │
                    ▼               ▼           │
               [reported]    [dispatching]      │
               (exit)             │              │
                           spawn agents         │
                                  │              │
                                  ▼              │
                           [monitoring]          │
                                  │              │
                    ┌─────────────┼─────────┐   │
                    │             │         │   │
                 agent         agent      agent │
                 done          failed     timeout
                    │             │         │   │
                    └─────────────┼─────────┘   │
                                  │              │
                           all done?             │
                             yes │               │
                                 ▼               │
                           [completing]          │
                           inbox items           │
                           cleanup               │
                           ntfy push             │
                                  │              │
                                  ▼              │
                              [idle] ◄───────────┘
```

**States:**

| State | Description | Duration |
|-------|-------------|----------|
| `idle` | No active dispatch cycle | Indefinite |
| `planning` | Loading specs, classifying, checking gates | < 2s |
| `reported` | Dry-run output shown, no side effects | Terminal (exit) |
| `dispatching` | Creating worktrees, spawning agents | < 30s |
| `monitoring` | Watching agent progress via NATS | Minutes to hours |
| `completing` | All agents done, creating inbox items, cleanup | < 10s |

---

## Files to Create

### New Files

| File | Location | Purpose | LOC est. |
|------|----------|---------|----------|
| `DispatchManager.swift` | `Services/` | Core orchestrator — plan, dispatch, monitor, complete | ~280 |
| `TaskClassifier.swift` | `Services/` | Detect toolchain from spec + project | ~90 |
| `WorktreeManager.swift` | `Services/` | Create, track, cleanup git worktrees | ~180 |
| `AgentSpawner.swift` | `Services/` | Launch `claude -p` processes with isolation | ~160 |
| `ConcurrencyGate.swift` | `Services/` | Enforce agent limits, Swift build limits, budget | ~120 |
| `NATSBridge.swift` | `Services/` | NATS client wrapper (publish, subscribe, request/reply) | ~140 |
| `BudgetEnforcer.swift` | `Services/` | Budget checks per company and global | ~70 |
| `RunCommand.swift` | `Commands/` | CLI entry point for `shikki run` | ~110 |
| `DispatchPlan.swift` | `Models/` | Plan model (specs, agents, estimates) | ~60 |
| `WorktreeInfo.swift` | `Models/` | Worktree tracking model | ~40 |
| `AgentHandle.swift` | `Models/` | Running agent reference (pid, worktree, config) | ~35 |
| `AgentSpawnConfig.swift` | `Models/` | Agent spawn parameters | ~30 |
| `TaskToolchain.swift` | `Models/` | Toolchain enum + detection config | ~25 |
| `ConcurrencyConfig.swift` | `Models/` | Concurrency limits model | ~20 |

**Total new code: ~1,360 LOC**

### Modified Files

| File | Change |
|------|--------|
| `ShikiEvent.swift` | Add dispatch-related `EventType` cases (`.dispatchStarted`, `.dispatchCompleted`, `.agentSpawned`, `.agentCompleted`, `.agentFailed`, `.worktreeCreated`, `.worktreeDeleted`) |
| `ProcessLauncher.swift` | No change — `AgentSpawner` uses `Process` directly, not `ProcessLauncher` (different abstraction: process-level, not tmux-pane-level) |
| `HeartbeatLoop.swift` | Add `WorktreeManager.reapOrphans()` call in heartbeat cycle (orphan reaping every 10 min) |
| `ShikkiCommand.swift` | Register `RunCommand` as subcommand |
| `Package.swift` | Add `swift-nio` (for NATS client process management), `nats-swift` dependency |

---

## Tests

### Unit Tests (~45 tests)

| Test file | Tests | What it covers |
|-----------|-------|----------------|
| `TaskClassifierTests.swift` | 8 | Swift detection, TS detection, mixed, frontmatter override, fallback, markdown-only, config-only, empty spec |
| `WorktreeManagerTests.swift` | 7 | Create, cleanup, reap orphans, branch naming, duplicate prevention, TTL enforcement, status transitions |
| `AgentSpawnerTests.swift` | 6 | Env var injection, scratch-path set, SKIP_E2E set, process launch, timeout kill, log file creation |
| `ConcurrencyGateTests.swift` | 8 | Machine limit, company limit, Swift limit, budget block, global budget, slot release, snapshot accuracy, concurrent registration |
| `BudgetEnforcerTests.swift` | 4 | Company budget check, global budget check, mid-run exhaustion (no kill), zero budget |
| `DispatchManagerTests.swift` | 8 | Full plan cycle, dry-run output, spec filtering, company filtering, failure escalation, retry policy, all-done detection, concurrent dispatch ordering |
| `RunCommandTests.swift` | 4 | Flag parsing, dry-run JSON, status output, cleanup mode |

### Integration Tests (~8 tests)

| Test file | Tests | What it covers |
|-----------|-------|----------------|
| `DispatchIntegrationTests.swift` | 4 | End-to-end: spec -> classify -> worktree -> spawn -> monitor -> complete (with mock agent) |
| `NATSBridgeTests.swift` | 4 | Connect, publish/subscribe round-trip, request/reply, reconnect on disconnect |

**Total tests: ~53**

---

## Dependencies

| Dependency | Version | Purpose |
|------------|---------|---------|
| `nats-io/nats.swift` | 0.4.0 | NATS Core client (pub/sub, request/reply) |
| `apple/swift-argument-parser` | (existing) | CLI flag parsing for RunCommand |
| `apple/swift-log` | (existing) | Logging |

No new heavyweight dependencies. `nats.swift` is the only addition, and it's already decided (see `project_distributed-protocol-decision.md`).

---

## Implementation Order

| Wave | Components | Depends on | Est. effort |
|------|-----------|------------|-------------|
| 1 | `TaskToolchain`, `TaskClassifier`, `WorktreeInfo`, `WorktreeManager` | Nothing (pure logic) | ~335 LOC, 15 tests |
| 2 | `AgentSpawnConfig`, `AgentHandle`, `AgentSpawner`, `ConcurrencyConfig`, `ConcurrencyGate`, `BudgetEnforcer` | Wave 1 (WorktreeInfo) | ~435 LOC, 18 tests |
| 3 | `NATSBridge`, `DispatchPlan`, `DispatchManager`, `RunCommand` | Waves 1+2, nats.swift | ~590 LOC, 20 tests |

**Total: ~1,360 LOC, ~53 tests, 3 waves**

---

## Open Questions (for @Daimyo)

1. **Agent timeout default** — 30 minutes? 60 minutes? Per-spec configurable?
2. **Worktree location** — `.claude/worktrees/` (current convention) or `/tmp/shiki-worktrees/` (avoids polluting repo)?
3. **NATS server lifecycle** — should `shikki run` auto-start `nats-server` if not running, or require it as a prerequisite (like Docker)?
4. **Spec approval mechanism** — where is `status: approved` set? In the spec frontmatter? In ShikiDB? Both?
5. **Multi-machine dispatch (v2 timeline)** — build the NATS claim protocol now (dead code until v2) or defer?
