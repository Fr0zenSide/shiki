# Feature: Shiki Event Router — Intelligent Middleware Layer

> **Type**: /md-feature
> **Priority**: P0.5 — after MCP Server, before Observatory TUI
> **Status**: Spec (validated by @Daimyo + @Shi team 2026-03-18)
> **Depends on**: Event Bus (Wave 2A — DONE), MCP Server (P0 — spec'd), Session Foundation (DONE)
> **Runtime**: SwiftNIO persistent process (not Deno — this is the Swift entry point into the backend stack)
> **Branch**: `feature/event-router` from `develop`

---

## 1. Problem

The event bus is pub/sub but dumb — events flow from producer to consumer with no interpretation. Every consumer must independently decide what matters, how to display it, and what context to add. This creates:

1. **Duplicate logic** — Watchdog, RecoveryManager, Observatory TUI all independently classify "is this important?"
2. **Missing context** — events arrive bare. Consumer must query journal, registry, DB to understand what the event means.
3. **No pattern detection** — "3 heartbeats with no progress" is a pattern, not an event. Nobody detects it.
4. **Routing by convention** — each consumer subscribes with filters they maintain. No central routing policy.

## 2. Solution — Event Router as Intelligence Layer

A SwiftNIO persistent process that sits between event producers and consumers. It doesn't replace the EventBus — it wraps it with 4 capabilities:

```
CLASSIFY → ENRICH → ROUTE → INTERPRET
```

Every event passes through all 4 stages. Raw events go in, smart events come out.

---

## 3. The Four Stages

### 3.1 CLASSIFY — What type of moment is this?

Not just `EventType` (which is the raw type). Classification adds **semantic weight**:

```swift
public enum EventSignificance: Int, Codable, Sendable, Comparable {
    case noise = 0        // heartbeat tick, routine check — never show
    case background = 1   // file read, test started — show in verbose mode
    case progress = 2     // test passed, file committed — show in timeline
    case milestone = 3    // all tests green, PR created — highlight
    case decision = 4     // architecture choice, scope change — always show
    case alert = 5        // test failure, blocker, budget exhausted — urgent
    case critical = 6     // agent terminated, data loss, security issue — interrupt

    public static func < (lhs: EventSignificance, rhs: EventSignificance) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
```

Classification rules:

| Raw EventType | Default Significance | Upgrade condition |
|---------------|---------------------|-------------------|
| `.heartbeat` | `.noise` | Upgrade to `.alert` if 3 consecutive with no progress |
| `.sessionStart` | `.progress` | — |
| `.sessionEnd` | `.milestone` | — |
| `.codeChange` | `.background` | Upgrade to `.progress` if > 100 LOC |
| `.testRun` | `.progress` | Upgrade to `.alert` if failures > 0 |
| `.decisionPending` | `.decision` | Upgrade to `.critical` if tier 1 + > 10min |
| `.prVerdictSet` | `.milestone` | — |
| `.budgetExhausted` | `.alert` | — |
| `.custom("redFlag")` | `.critical` | — |

### 3.2 ENRICH — Add smart metadata

Every event gets a `RouterEnvelope` wrapping the raw event with context:

```swift
public struct RouterEnvelope: Codable, Sendable {
    public let event: ShikiEvent              // original event
    public let significance: EventSignificance
    public let displayHint: DisplayHint
    public let context: EnrichmentContext
    public let patterns: [DetectedPattern]    // from INTERPRET stage
}

public struct EnrichmentContext: Codable, Sendable {
    public let sessionState: SessionState?       // from registry
    public let attentionZone: AttentionZone?     // from lifecycle
    public let companySlug: String?              // resolved from scope
    public let taskTitle: String?                // from registry context
    public let parentDecisionId: String?         // from decision chain
    public let journalCheckpointCount: Int?      // how many checkpoints exist
    public let elapsedSinceLastMilestone: TimeInterval? // time context
}

public enum DisplayHint: String, Codable, Sendable {
    case timeline     // show in Observatory timeline (left panel)
    case detail       // show in Observatory detail (right panel on selection)
    case question     // show in Questions tab with answer input
    case report       // aggregate into Agent Report Card
    case notification // push via ntfy
    case background   // persist to DB only, don't display
    case suppress     // don't persist, don't display (pure noise)
}
```

Enrichment sources:

| Context field | Source | Lookup |
|---------------|--------|--------|
| `sessionState` | SessionRegistry | `registry.allSessions` by sessionId |
| `attentionZone` | SessionState extension | `state.attentionZone` |
| `companySlug` | Event scope or registry | extract from scope or context |
| `taskTitle` | Registry TaskContext | `session.context?.taskId` |
| `parentDecisionId` | Shiki DB | last decision for this session |
| `journalCheckpointCount` | SessionJournal | count checkpoints for sessionId |
| `elapsedSinceLastMilestone` | In-memory tracker | time since last `.milestone` event |

### 3.3 ROUTE — Who needs this enriched event?

Routing table based on `DisplayHint`:

```swift
public struct RoutingRule: Sendable {
    let hint: DisplayHint
    let destinations: [EventDestination]
}

public enum EventDestination: Sendable {
    case database          // Shiki DB via data-sync
    case observatoryTUI    // live TUI subscription
    case ntfy              // push notification
    case journalFile       // .shiki/journal/ JSONL
    case reportAggregator  // collects events for Agent Report Card
    case agentInbox        // inject into agent's prompt context
}
```

Default routing table:

| DisplayHint | Destinations |
|-------------|-------------|
| `.timeline` | database, observatoryTUI |
| `.detail` | database |
| `.question` | database, observatoryTUI, ntfy |
| `.report` | database, reportAggregator |
| `.notification` | database, ntfy |
| `.background` | database |
| `.suppress` | (nothing) |

### 3.4 INTERPRET — Detect patterns across events

The interpreter maintains a sliding window of recent events and detects cross-event patterns:

```swift
public struct DetectedPattern: Codable, Sendable {
    public let name: String
    public let description: String
    public let severity: EventSignificance
    public let relatedEvents: [UUID]    // event IDs that form the pattern
}
```

Pattern detectors:

| Pattern | Trigger | Output |
|---------|---------|--------|
| **Stuck agent** | 3+ heartbeats, no `.codeChange` or `.testRun` | Upgrade next heartbeat to `.alert` |
| **Repeat failure** | Same test fails 3x | Emit `.critical` red flag |
| **Decision cascade** | 3+ decisions in 5 minutes | Emit `.milestone` "decision burst — review needed" |
| **Budget burn** | Spend rate > 2x daily average | Emit `.alert` budget warning |
| **Context pressure** | 2+ compaction events in 1 hour | Emit `.alert` context thrashing |
| **Idle after question** | Question pending + no activity 10min | Upgrade to `.critical` |
| **Success chain** | 5+ consecutive green tests + PR created | Emit `.milestone` "clean run" |

---

## 4. Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                    SwiftNIO Event Router                       │
│                    (persistent process)                        │
│                                                               │
│  ┌─────────┐   ┌─────────┐   ┌─────────┐   ┌────────────┐  │
│  │CLASSIFY │ → │ ENRICH  │ → │  ROUTE  │ → │ INTERPRET  │  │
│  │         │   │         │   │         │   │            │  │
│  │EventType│   │+context │   │→ DB     │   │ pattern    │  │
│  │→ signif.│   │+session │   │→ TUI    │   │ detection  │  │
│  │         │   │+chain   │   │→ ntfy   │   │ window     │  │
│  └─────────┘   └─────────┘   └─────────┘   └────────────┘  │
│                                                               │
│  Inputs:                     Outputs:                         │
│  ├─ MCP Server (agent tools) ├─ PostgreSQL (via Deno API)     │
│  ├─ InProcessEventBus        ├─ Observatory TUI (WebSocket)   │
│  ├─ HeartbeatLoop            ├─ ntfy (push notifications)     │
│  └─ Pipeline events          ├─ .shiki/journal/ (JSONL)       │
│                              ├─ .shiki/reports/ (markdown)    │
│                              └─ Agent inbox (prompt inject)   │
└──────────────────────────────────────────────────────────────┘
```

### Process lifecycle

- Started by `shiki start` alongside HeartbeatLoop
- Listens on Unix domain socket for local events (SwiftNIO)
- Connects to Deno backend via HTTP for DB persistence
- Subscribes to InProcessEventBus for CLI events
- Runs pattern detection every 30 seconds
- Graceful shutdown: flush pending events, write final checkpoint

### Why SwiftNIO (not Deno)

1. **Type safety** — Event classification and enrichment benefit from Swift's type system
2. **Performance** — Pattern detection on sliding window needs low-latency processing
3. **Unified with CLI** — same Package.swift, shares `ShikiCtlKit` types (ShikiEvent, SessionState, AttentionZone)
4. **Persistent WebSocket** — SwiftNIO WebSocket for Observatory TUI connection
5. **Future backend migration path** — this process grows into the full backend over time

---

## 5. What Gets Consolidated

The Event Router absorbs logic currently scattered across multiple types:

| Current | Absorbed into Router |
|---------|---------------------|
| `ShikiDBEventLogger` | Route stage → `.database` destination |
| `Watchdog.evaluate()` | Interpret stage → "stuck agent" pattern |
| `RecoveryManager.findRecoverableSessions()` | Interpret stage → "crashed session" pattern |
| ntfy notification logic in HeartbeatLoop | Route stage → `.notification` destination |
| Decision chain tracking | Enrich stage → `parentDecisionId` |
| Agent Report generation trigger | Interpret stage → "session complete" pattern triggers report |

**These types don't disappear** — their logic moves into router stages. The types become thinner (data models only, no logic).

---

## 6. Event Flow Diagram — Full Process

```
Agent starts task
  │
  ├─ sessionStart ──→ CLASSIFY: progress ──→ ENRICH: +company, +task
  │                    ROUTE: timeline, DB
  │
  ├─ codeChange ───→ CLASSIFY: background ──→ ENRICH: +file, +LOC
  │   (repeat)        ROUTE: DB only
  │
  ├─ testRun ──────→ CLASSIFY: progress ──→ ENRICH: +pass/fail count
  │   (green)         ROUTE: timeline, DB
  │
  ├─ testRun ──────→ CLASSIFY: alert ──→ ENRICH: +failure details
  │   (red)           ROUTE: timeline, DB, ntfy
  │                   INTERPRET: "repeat failure" if 3x same test
  │
  ├─ decisionMade ─→ CLASSIFY: decision ──→ ENRICH: +parent chain
  │                   ROUTE: timeline, DB, detail
  │
  ├─ decisionGate ─→ CLASSIFY: decision ──→ ENRICH: +session context
  │   (needs human)   ROUTE: question tab, ntfy, DB
  │                   INTERPRET: "idle after question" if no response 10min
  │
  ├─ heartbeat ────→ CLASSIFY: noise ──→ ENRICH: +progress check
  │   (normal)        ROUTE: suppress
  │
  ├─ heartbeat ────→ CLASSIFY: alert ──→ ENRICH: +idle duration
  │   (3x no progress) ROUTE: timeline, ntfy
  │                   INTERPRET: "stuck agent" pattern
  │
  ├─ prVerdictSet ─→ CLASSIFY: milestone ──→ ENRICH: +PR number
  │                   ROUTE: timeline, DB, report
  │
  └─ sessionEnd ───→ CLASSIFY: milestone ──→ ENRICH: +duration, +summary
                      ROUTE: timeline, DB, report
                      INTERPRET: trigger Agent Report Card generation
```

---

## 7. Deliverables

### Phase 1: Router Core (~300 LOC)
- `EventRouter` actor (SwiftNIO event loop)
- `EventClassifier` — significance assignment
- `EventEnricher` — context lookup and attachment
- `RouterEnvelope` — enriched event wrapper

### Phase 2: Routing + Destinations (~200 LOC)
- `RoutingTable` — rule-based destination mapping
- `EventDestination` implementations (DB, file, ntfy proxy)
- `DisplayHint` assignment logic

### Phase 3: Pattern Interpreter (~200 LOC)
- `PatternDetector` protocol
- Built-in detectors: stuck agent, repeat failure, decision cascade, budget burn, context pressure
- Sliding window (last 100 events + 30s tick)

### Phase 4: Integration (~150 LOC)
- Wire into `shiki start` (launch router process)
- Wire HeartbeatLoop → router (publish through router, not raw bus)
- Wire MCP Server → router (MCP write tools go through router)
- Observatory TUI subscribes to router output (WebSocket)

**Total**: ~850 LOC, ~30 tests

---

## 8. Dependency Chain (updated full roadmap)

```
MCP Server (P0)
  ↓
Event Router (P0.5)          ← THIS SPEC
  ↓
Observatory TUI (P1)
  ↓
Community Flywheel (P2)
```

Each layer is independently useful:
- MCP alone kills curl -sf errors
- Router alone adds smart classification + pattern detection
- Observatory alone gives you the timeline TUI
- Flywheel alone starts the self-improving engine

But each layer is dramatically better with the one below it.

---

## 9. Success Criteria

1. Every event classified with significance level
2. Enrichment adds session context automatically (no manual lookup)
3. "Stuck agent" pattern detected within 3 heartbeat cycles
4. Observatory TUI receives only significant events (no noise)
5. Agent Report Card generated automatically on session end
6. Decision chain queryable from any decision to root
7. Zero duplicate classification logic across consumers

---

## 10. What this means for the backend migration

The Event Router is the **first SwiftNIO process in the Shiki stack**. It shares `ShikiCtlKit` types, runs alongside the CLI, and handles the intelligent middleware layer. Over time:

1. Today: Deno backend (HTTP API + PostgreSQL) + SwiftNIO router (event processing)
2. 6 months: Router grows to handle more backend logic (search, analytics)
3. 12 months: Evaluate if Deno backend should be absorbed into SwiftNIO process
4. Decision point: if Deno is just proxying to PostgreSQL with no logic, absorb it

The migration is organic, not a rewrite. The router grows; the backend shrinks.
