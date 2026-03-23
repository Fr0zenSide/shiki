# Spec: ReportAggregator, Event Logger, NATS Integration

> @Sensei implementation spec. Three tightly coupled components that form the observability layer of Shikki. NATS is the transport root — report and logger are subscribers.

**Depends on:** ShikiCore (Events, Lifecycle), ShikiCtlKit (BackendClient, models), nats.swift
**Blocked by:** Nothing — can start immediately. NATS client is the foundation; report and logger build on it.
**Branch:** `feature/shikki-observability`

---

## Architecture Overview

```
                          nats-server (localhost:4222)
                               │
              ┌────────────────┼─────────────────┐
              │                │                  │
        NATSEventBridge   EventLogger        ReportAggregator
        (ShikiCore)       (shikki log)       (shikki report)
              │                │                  │
              │           ANSI renderer      ShikiDB queries
              │           tmux pane          + git log
              │                               + NATS metrics
     ┌────────┴────────┐
     │                 │
EventPersister    InProcessEventBus
(ShikiDB HTTP)    (current, retained)
```

NATS does NOT replace `EventPersister`. NATS is real-time transport (fire-and-forget pub/sub). `EventPersister` is durable persistence (HTTP to ShikiDB). `NATSEventBridge` publishes every `LifecycleEventPayload` to both NATS AND `EventPersister`. The logger consumes from NATS. The report aggregator queries ShikiDB (persisted state) and optionally subscribes to NATS for live counters.

---

## Part 1: NATS Integration in ShikiCore

### 1.1 NATSClient Protocol

```
public protocol NATSClientProtocol: Sendable {
    func connect() async throws
    func disconnect() async
    func publish(subject: String, data: Data) async throws
    func subscribe(subject: String) -> AsyncStream<NATSMessage>
    func request(subject: String, data: Data, timeout: Duration) async throws -> NATSMessage
    var isConnected: Bool { get async }
}
```

`NATSMessage` is a thin struct: `subject: String`, `data: Data`, `replyTo: String?`.

Concrete implementation wraps `nats-io/nats.swift` (v0.4.0, Core NATS only). The protocol exists so tests inject a `MockNATSClient` — no real nats-server in unit tests.

### 1.2 NATS Topics Table

| Subject Pattern | Direction | Payload | Purpose |
|---|---|---|---|
| `shikki.events.{company}.lifecycle` | pub | `LifecycleEventPayload` (JSON) | State transitions, gate evaluations |
| `shikki.events.{company}.agent` | pub | `AgentEventPayload` | Agent dispatch/complete/fail |
| `shikki.events.{company}.ship` | pub | `ShipEventPayload` | Ship gate results |
| `shikki.events.{company}.task` | pub | `TaskEventPayload` | Task claim/complete/fail |
| `shikki.events.{company}.decision` | pub | `DecisionEventPayload` | Decision asked/answered |
| `shikki.events.{company}.git` | pub | `GitEventPayload` | PR created, commit, merge |
| `shikki.commands.{node_id}` | req/rep | `CommandPayload` | Directed commands to a specific node |
| `shikki.discovery.announce` | pub | `HeartbeatPayload` | Node heartbeat (30s interval) |
| `shikki.discovery.query` | req/rep | `DiscoveryQuery` / `DiscoveryResponse` | "Who's alive?" |
| `shikki.tasks.{workspace}.available` | pub | `TaskAvailablePayload` | Task published for claiming |
| `shikki.tasks.{workspace}.claimed` | pub | `TaskClaimedPayload` | Task claimed by a node |
| `shikki.decisions.pending` | pub | `DecisionPendingPayload` | Decisions needing @Daimyo input |

**Wildcard subscriptions used by consumers:**
- Event logger: `shikki.events.>` (all events, all companies)
- Event logger filtered: `shikki.events.maya.>` (one company)
- Report live mode: `shikki.events.>` (counters)
- Discovery monitor: `shikki.discovery.>`

### 1.3 ShikiEvent-to-NATS Subject Mapping

Every `LifecycleEventPayload` maps to a NATS subject via:

```
func subject(for event: LifecycleEventPayload, company: String) -> String {
    switch event.type {
    case .agentDispatched, .agentCompleted, .agentFailed:
        return "shikki.events.\(company).agent"
    case .lifecycleStarted, .stateTransitioned, .lifecycleCompleted, .lifecycleFailed:
        return "shikki.events.\(company).lifecycle"
    case .governorGateReached, .governorGateCleared, .gateEvaluated:
        return "shikki.events.\(company).lifecycle"
    case .checkpointSaved:
        return "shikki.events.\(company).lifecycle"
    }
}
```

The `company` slug comes from the `CompanyManager` context — it is NOT embedded in `LifecycleEventPayload` today. The `NATSEventBridge` receives the company context from whoever calls `emit()`.

### 1.4 NATSEventBridge

The bridge sits between ShikiCore's event producers and the two sinks (NATS + DB).

```
public actor NATSEventBridge {
    let nats: NATSClientProtocol
    let persister: EventPersisting

    func emit(_ event: LifecycleEventPayload, company: String) async
    func emit(_ event: ShikiEvent, company: String) async  // future: unified protocol
}
```

`emit()` does two things in parallel:
1. `persister.persist(event)` — durable to ShikiDB
2. `nats.publish(subject: ..., data: encoded)` — real-time to subscribers

Both are fire-and-forget with warning-level logging on failure. Neither blocks the caller. Neither crashes.

### 1.5 NKey Generation and Storage

Location: `~/.config/shiki/nats-key.nk`

Generated on first `shikki start` if missing. Ed25519 keypair using `nkeys.swift` (or shell out to `nk -gen user` if the Go tool is available). The `.nk` file contains the seed (private key). The public key (NKey) is registered with nats-server's `authorization` block.

For v1 (localhost only), auth is optional — use `--no-auth` or a simple token. NKeys become mandatory when leaf nodes are introduced (v2, VPS/CI).

### 1.6 nats-server Lifecycle in `shikki start`

**Responsibility:** `StartupCommand` (or a new `NATSServerManager` service in ShikiCtlKit).

**Sequence:**
1. Check if `nats-server` binary exists at `~/.config/shiki/bin/nats-server`
2. If missing: download from `https://github.com/nats-io/nats-server/releases` (platform-specific, ~20MB). Print progress. Verify SHA256.
3. Generate `~/.config/shiki/nats-server.conf` from template:
   ```
   listen: 127.0.0.1:4222
   max_payload: 1048576  # 1MB
   authorization {
       token: "<generated-token>"
   }
   ```
4. Start `nats-server -c ~/.config/shiki/nats-server.conf` as a managed child process (same pattern as Docker in `StartupCommand`)
5. Health check: connect to `localhost:4222`, verify response. Retry 3x with 500ms backoff.
6. On `shikki stop`: send SIGTERM to nats-server PID (stored in `~/.config/shiki/nats-server.pid`)

**No Docker.** nats-server is a single static binary. Production deploys are native binaries, not containers.

---

## Part 2: Event Logger (`shikki log`)

### 2.1 Purpose

Real-time ANSI event stream. Zero LLM tokens. Pure data mirroring from NATS.

### 2.2 CLI Interface

```
shikki log                          # subscribe to all events, foreground
shikki log --filter maya            # filter by company
shikki log --filter maya.agent      # filter by company + event type
shikki log --json                   # raw JSON output (pipe-friendly)
shikki log --since 5m               # replay last 5 minutes from ShikiDB, then live
```

### 2.3 LogCommand (ArgumentParser)

```
struct LogCommand: AsyncParsableCommand {
    commandName: "log"
    abstract: "Real-time event stream from NATS bus"

    @Option  var filter: String?     // company or company.type
    @Flag    var json: Bool = false   // raw JSON mode
    @Option  var since: String?      // replay window (5m, 1h, 2h)
    @Option  var natsUrl: String = "nats://127.0.0.1:4222"
}
```

### 2.4 ANSI Rendering Format

```
[14:32:01] maya:agent-a1     lifecycle    state: building → gating
[14:32:15] shiki:agent-b3    agent        dispatched: fix-heartbeat (prompt: 200 chars)
[14:32:30] wabisabi:main     ship         gate: CleanBranch PASSED
[14:32:45] maya:agent-a1     git          PR #31 created → develop
[14:33:00] shiki:discovery   heartbeat    node shikki-main alive (ctx: 42%, 2 compactions)
```

**Color scheme:**
- Timestamp: dim white
- Company: bold, unique color per company (maya=cyan, shiki=green, wabisabi=magenta — assigned by hash of slug)
- Agent ID: normal white
- Event type: dim yellow
- Payload summary: normal white, keywords highlighted (PASSED=green, FAILED=red, blocked=yellow)

**Rendering logic:** `EventRenderer` protocol with `ANSIEventRenderer` (TUI) and `JSONEventRenderer` (pipe). Selected by `--json` flag.

### 2.5 NATS Subscription

```swift
let subject = filter.map { "shikki.events.\($0)" } ?? "shikki.events.>"
for await message in nats.subscribe(subject: subject) {
    let rendered = renderer.render(message)
    print(rendered)
}
```

### 2.6 Replay from ShikiDB

When `--since` is provided, before subscribing to NATS:
1. Query ShikiDB: `GET /api/agent-events?since=<ISO8601>&limit=500`
2. Render each historical event with dim styling (to distinguish from live)
3. Print separator: `── live ──`
4. Switch to NATS subscription

This requires a new `since` query parameter on the existing `/api/agent-events` endpoint (currently supports `session_id` and `limit` only).

### 2.7 Reconnection

NATS client handles reconnection natively (configurable in `nats.swift`). The logger should:
- Print `[reconnecting...]` in dim red when disconnected
- Print `[connected]` in dim green when reconnected
- Buffer nothing during disconnect — events are fire-and-forget. Replay via `--since` if needed.

### 2.8 Tmux Pane Integration

`shikki start` spawns the logger in a tmux pane:
- Position: right column, above heartbeat pane
- Height: ~40% of right column
- Command: `shikki log` (no filter, all events)
- Pane title: `event-log` (for `shikki stop` to identify and kill)

This is a single `tmux split-window` call in `StartupCommand`, same pattern as the existing heartbeat pane.

---

## Part 3: ReportAggregator (`shikki report` / `shikki codir`)

### 3.1 Purpose

Productivity dashboard. Aggregates from ShikiDB (historical) and optionally NATS (live session counters).

### 3.2 CLI Interface

```
shikki report                       # weekly summary (default)
shikki report --daily               # today only
shikki report --weekly              # last 7 days (default)
shikki report --sprint              # current sprint (2-week window)
shikki report --since 2026-03-01    # custom start date
shikki report --company maya        # scope to one company
shikki report --project wabisabi    # scope to one project
shikki report --workspace           # all companies (default)
shikki report --md                  # markdown output
shikki report --json                # JSON output (pipe-friendly)

shikki codir                        # executive board summary (alias for report --codir)
```

### 3.3 Metrics

| Metric | Source | Query |
|---|---|---|
| LOC added/deleted (net) | `git log --numstat` per project | Shell out to `git log --since={start} --until={end} --numstat --pretty=format:""` in each project directory, sum insertions/deletions |
| PRs merged | ShikiDB `git_events` | `SELECT COUNT(*) FROM git_events WHERE event_type = 'pr_created' AND occurred_at BETWEEN $1 AND $2` (Note: "merged" requires a `pr_merged` event type — add to git_events, or query GitHub API via `gh pr list --state merged`) |
| Tasks completed | ShikiDB `task_queue` | `SELECT COUNT(*) FROM task_queue WHERE status = 'completed' AND updated_at BETWEEN $1 AND $2 AND company_id = $3` |
| Tasks failed | ShikiDB `task_queue` | Same with `status = 'failed'` |
| Budget spent | ShikiDB `company_budget_log` | `SELECT SUM(amount_usd) FROM company_budget_log WHERE occurred_at BETWEEN $1 AND $2 AND company_id = $3` |
| Agent utilization | ShikiDB `agent_events` | Context %: extract from `data_sync` events with `payload->>'context_pct'`. Compaction count: `SELECT COUNT(*) FROM agent_events WHERE event_type = 'data_sync' AND message = 'context_compaction'` |
| Time per stage | ShikiDB `agent_events` | Compute time deltas between `stateTransitioned` events per feature lifecycle. `idle→specDrafting` = spec time, `building→gating` = build time, etc. |
| Decisions asked/answered | ShikiDB `decision_queue` | Existing `getDailyReport` query already computes this |
| Session count | ShikiDB `session_transcripts` | `SELECT COUNT(*) FROM session_transcripts WHERE created_at BETWEEN $1 AND $2` |

### 3.4 ReportCommand (ArgumentParser)

```
struct ReportCommand: AsyncParsableCommand {
    commandName: "report"
    abstract: "Productivity report — metrics across companies, projects, workspace"

    // Time range (mutually exclusive group)
    @Flag    var daily: Bool = false
    @Flag    var weekly: Bool = false   // default if none specified
    @Flag    var sprint: Bool = false
    @Option  var since: String?         // ISO date
    @Option  var until: String?         // ISO date (defaults to now)

    // Scope
    @Option  var company: String?
    @Option  var project: String?
    @Flag    var workspace: Bool = false // all companies (default)

    // Output
    @Flag    var md: Bool = false
    @Flag    var json: Bool = false
    @Flag    var codir: Bool = false     // executive summary mode

    @Option  var url: String = "http://localhost:3900"
}
```

### 3.5 CodiRCommand (alias)

```
struct CodirCommand: AsyncParsableCommand {
    commandName: "codir"
    abstract: "Executive board summary — stakeholder view"

    // Delegates to ReportCommand with --codir flag
}
```

The CODIR view differs from the standard report:
- No per-agent breakdown (stakeholders don't care about agent IDs)
- Budget-first layout (spent vs. allocated, burn rate, projection)
- Milestone progress bars (features completed vs. planned)
- Risk section (blocked tasks, stale companies, budget alerts)
- One-paragraph summary per company (generated from task/decision data, NOT by LLM — pure template)

### 3.6 ReportAggregator Service

Lives in `ShikiCtlKit/Services/ReportAggregator.swift`.

```
public struct ReportAggregator {
    let client: BackendClientProtocol
    let gitRoots: [String: String]  // company slug → git root path

    func aggregate(range: DateRange, scope: ReportScope) async throws -> Report
}
```

`Report` is a struct containing all metrics. Renderers (`TUIReportRenderer`, `MarkdownReportRenderer`, `JSONReportRenderer`) format it for output.

### 3.7 ShikiDB Queries (New Backend Endpoints)

The existing `/api/orchestrator/report` endpoint (`getDailyReport`) covers per-company tasks/decisions/spend for a single day. The new report needs:

**New endpoint: `GET /api/orchestrator/report/range`**
```
Query params: start, end, company_id (optional)
Returns: {
  tasks: { completed, failed, blocked, total },
  decisions: { asked, answered, pending },
  budget: { spent, daily_avg, projected },
  prs: { created, merged },
  sessions: { count, total_duration_hours },
  agents: { dispatched, completed, failed, avg_context_pct, total_compactions },
  lifecycle: { avg_time_per_stage: { spec: "2h", build: "4h", ... } }
}
```

**New endpoint: `GET /api/orchestrator/report/loc`**
Not a DB query — the CLI computes this locally via `git log --numstat`. No backend involvement. The `ReportAggregator` shells out to git directly.

### 3.8 TUI Output Format

```
Shikki Report — 2026-03-17 → 2026-03-23 (weekly)
────────────────────────────────────────────────────────────

Company       Tasks    PRs    LOC (+/-)     Budget    Agents
────────────────────────────────────────────────────────────
maya          12/15    4      +1,240/-380   $12.40    3 (avg 68% ctx)
shiki         8/10     2      +890/-120     $8.20     2 (avg 55% ctx)
wabisabi      3/5      1      +320/-90      $4.10     1 (avg 72% ctx)
────────────────────────────────────────────────────────────
TOTAL         23/30    7      +2,450/-590   $24.70    6

Stage Timing (avg):
  spec: 1h 20m | build: 3h 10m | gate: 12m | ship: 8m

Blocked: 2 tasks (maya:auth-flow T1, shiki:tui-widget T2)
Decisions pending: 1

Compactions: 14 total (avg 3.2/day)
Sessions: 18 (avg 2.6/day)
```

### 3.9 CODIR Output Format

```
CODIR Board — Week 12, 2026
════════════════════════════

Budget: $24.70 / $50.00 weekly (49% burn)
  Projection: $26.20 by EOW (within budget)

Maya (12/15 tasks, 80%)
  ██████████████████░░░░ 80%
  4 PRs merged. Auth flow blocked (T1 decision pending).
  Sprint health: ON TRACK

Shiki (8/10 tasks, 80%)
  ██████████████████░░░░ 80%
  2 PRs merged. TUI widget decision pending (T2).
  Sprint health: ON TRACK

WabiSabi (3/5 tasks, 60%)
  ██████████████░░░░░░░░ 60%
  1 PR merged. No blockers.
  Sprint health: AT RISK (below 70% completion rate)

Risks:
  [T1] maya:auth-flow — blocks 3 downstream tasks
  [T2] shiki:tui-widget — non-blocking, can defer

Net output: +2,450 / -590 LOC (net +1,860)
```

---

## Files to Create

### ShikiCore (packages/ShikiCore/)

| File | Purpose | Est. LOC |
|---|---|---|
| `Sources/ShikiCore/NATS/NATSClientProtocol.swift` | Protocol + NATSMessage struct | ~40 |
| `Sources/ShikiCore/NATS/NATSClient.swift` | Concrete wrapper around nats.swift | ~120 |
| `Sources/ShikiCore/NATS/NATSEventBridge.swift` | Dual-sink emitter (NATS + DB) | ~80 |
| `Sources/ShikiCore/NATS/NATSSubjectMapper.swift` | Event-to-subject mapping | ~50 |
| `Tests/ShikiCoreTests/NATSClientTests.swift` | Protocol conformance, mock | ~60 |
| `Tests/ShikiCoreTests/NATSEventBridgeTests.swift` | Dual-sink, failure isolation | ~80 |
| `Tests/ShikiCoreTests/NATSSubjectMapperTests.swift` | Subject mapping correctness | ~40 |

**ShikiCore subtotal: ~470 LOC**

### ShikiCtlKit (tools/shiki-ctl/Sources/ShikiCtlKit/)

| File | Purpose | Est. LOC |
|---|---|---|
| `Services/NATSServerManager.swift` | Download, start, stop, health check nats-server | ~180 |
| `Services/ReportAggregator.swift` | Metric collection + aggregation | ~200 |
| `Services/EventRenderer.swift` | Protocol + ANSI + JSON renderers | ~150 |
| `Models/Report.swift` | Report struct, DateRange, ReportScope | ~80 |
| `Models/NATSMessage.swift` | Re-export or bridge from ShikiCore | ~20 |
| `Renderers/TUIReportRenderer.swift` | Table + progress bar formatting | ~120 |
| `Renderers/MarkdownReportRenderer.swift` | .md output | ~80 |
| `Renderers/JSONReportRenderer.swift` | .json output (trivial — Codable) | ~20 |

**ShikiCtlKit subtotal: ~850 LOC**

### CLI Commands (tools/shiki-ctl/Sources/shikki/Commands/)

| File | Purpose | Est. LOC |
|---|---|---|
| `LogCommand.swift` | NEW — `shikki log` | ~60 |
| `CodirCommand.swift` | NEW — `shikki codir` (delegates to report) | ~30 |
| `ReportCommand.swift` | REWRITE — replace current daily-only with full aggregator | ~100 |

**Commands subtotal: ~190 LOC**

### Backend (src/backend/src/)

| File | Purpose | Est. LOC |
|---|---|---|
| `routes.ts` | ADD `/api/orchestrator/report/range` endpoint | ~30 |
| `orchestrator.ts` | ADD `getRangeReport()` function | ~80 |

**Backend subtotal: ~110 LOC**

### Config Templates

| File | Purpose | Est. LOC |
|---|---|---|
| `config/nats-server.conf.template` | nats-server config template | ~15 |

---

## Tests

### Unit Tests

| Test File | Cases | What It Covers |
|---|---|---|
| `NATSClientTests.swift` | 5 | Mock connect/disconnect, publish, subscribe stream, request/reply timeout |
| `NATSEventBridgeTests.swift` | 6 | Dual-sink emit, NATS failure doesn't block persist, persist failure doesn't block NATS, company routing, concurrent emit safety |
| `NATSSubjectMapperTests.swift` | 11 | One test per `LifecycleEventType` → correct subject, plus wildcard matching |
| `ReportAggregatorTests.swift` | 8 | Date range computation (daily/weekly/sprint/custom), scope filtering (company/project/workspace), empty data handling, LOC parsing from git output |
| `EventRendererTests.swift` | 6 | ANSI format correctness, JSON format correctness, color-per-company determinism, timestamp formatting, long payload truncation, special characters |
| `TUIReportRendererTests.swift` | 4 | Table alignment, progress bar rendering, CODIR mode differences, zero-data display |
| `NATSServerManagerTests.swift` | 5 | Binary detection, config generation, PID file write/read, health check retry, cleanup on stop |
| `LogCommandTests.swift` | 3 | Filter parsing, --since flag, --json flag |
| `ReportCommandTests.swift` | 4 | Time range flag mutual exclusivity, scope defaults, output format selection, CODIR alias |

**Total test cases: ~52**
**Estimated test LOC: ~500**

### Integration Tests (require nats-server running)

| Test | What It Covers |
|---|---|
| `NATSIntegrationTests.swift` | Real publish→subscribe round-trip, reconnection after disconnect, wildcard subscription filtering |
| `EventLoggerE2ETests.swift` | Publish event → logger renders correct ANSI output (capture stdout) |

**Guarded by `SKIP_E2E` env var.** Not run in CI until nats-server is available in the CI image.

---

## LOC Summary

| Component | Source | Tests | Total |
|---|---|---|---|
| ShikiCore NATS | 290 | 180 | 470 |
| ShikiCtlKit Services | 850 | 280 | 1,130 |
| CLI Commands | 190 | 40 | 230 |
| Backend | 110 | 0 | 110 |
| Config | 15 | 0 | 15 |
| **Total** | **1,455** | **500** | **~1,955** |

---

## Implementation Order

### Wave 1: NATS Foundation (blocks everything)
1. `NATSClientProtocol` + `MockNATSClient` + tests
2. `NATSSubjectMapper` + tests
3. `NATSEventBridge` + tests
4. Add `nats-io/nats.swift` to ShikiCore `Package.swift`
5. `NATSClient` concrete implementation (wraps nats.swift)

### Wave 2: nats-server Lifecycle
6. `NATSServerManager` — download, start, stop, health
7. Wire into `StartupCommand` / `StopCommand`
8. Config template generation
9. NKey generation (optional for v1, stub with token auth)

### Wave 3: Event Logger
10. `EventRenderer` protocol + `ANSIEventRenderer` + `JSONEventRenderer`
11. `LogCommand` — subscribe + render loop
12. Tmux pane integration in `StartupCommand`
13. `--since` replay (add `since` param to `/api/agent-events`)

### Wave 4: ReportAggregator
14. `Report` model + `DateRange` + `ReportScope`
15. Backend: `getRangeReport()` + `/api/orchestrator/report/range`
16. `ReportAggregator` service — DB queries + git log parsing
17. `TUIReportRenderer` + `MarkdownReportRenderer` + `JSONReportRenderer`
18. Rewrite `ReportCommand` with full flag support
19. `CodirCommand`

### Wave 5: Bridge + Wire-Up
20. Wire `NATSEventBridge` into `FeatureLifecycle` (replace direct `EventPersister` calls)
21. Wire `NATSEventBridge` into `CompanyManager` heartbeat
22. Integration tests (gated behind `SKIP_E2E`)

---

## Dependencies

### SPM (ShikiCore Package.swift)

```swift
.package(url: "https://github.com/nats-io/nats.swift.git", from: "0.4.0"),
```

Add to ShikiCore target:
```swift
.product(name: "Nats", package: "nats.swift"),
```

### SPM (shiki-ctl Package.swift)

Already depends on ShikiCore. No new dependency needed — NATS types flow through ShikiCore.

### External Binary

`nats-server` v2.10.x — downloaded at runtime by `NATSServerManager`, NOT bundled. Stored at `~/.config/shiki/bin/nats-server`.

---

## Migration Path: EventPersister to NATSEventBridge

Today, `FeatureLifecycle` and other ShikiCore components call `EventPersister.persist()` directly. After this spec:

1. `NATSEventBridge` wraps `EventPersister` — all existing persist calls are preserved
2. `NATSEventBridge.emit()` additionally publishes to NATS
3. If NATS is unavailable (nats-server not running), the bridge silently skips NATS publish and still persists to DB
4. `EventPersister` is never removed — it remains the durable persistence layer
5. The bridge is injected where `EventPersisting` was injected before (protocol conformance preserved)

**Zero breaking changes.** Existing tests pass unchanged. New tests cover the NATS path.

---

## Open Questions (for @Daimyo)

1. **Sprint duration** — The `--sprint` flag assumes 2-week sprints. Is that correct, or should it be configurable?
2. **LOC source** — `git log --numstat` counts all commits, including merge commits and automated version bumps. Should we filter to only human/agent commits?
3. **PR merged tracking** — The backend currently tracks `pr_created` but not `pr_merged`. Add a `pr_merged` event type to `git_events`, or query GitHub via `gh` CLI?
4. **CODIR audience** — Is the CODIR view for solo use (just you reviewing weekly output) or will external stakeholders see it? Affects tone of the template.
5. **nats-server version pinning** — Pin to a specific release (e.g., 2.10.25) or latest stable?
