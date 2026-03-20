# Architecture Spec: Shiki Event Bus — Observable Data Stream

> **Status**: Spec (architecture reference)
> **Author**: @Sensei (CTO) + @Hanami (UX)
> **Date**: 2026-03-17
> **Scope**: ShikiKit (shared), ShikiCtlKit (CLI consumer), future native app + web
> **Depends on**: Nothing — this is foundational
> **Blocks**: PR review v2 (Phase 4), native app, team dashboard

---

## 1. Core Principle

**Shiki is an observable data stream pipeline.**

Every action — agent spawning, code change, PR verdict, heartbeat, human feedback, course correction — is an event in a stream. Tools subscribe at the depth they need. The transport is abstracted. The event protocol is the constant.

```
Source (agent, human, orchestrator, process)
    ↓
ShikiEvent (structured, Codable, timestamped)
    ↓
EventBus (protocol — publish/subscribe)
    ↓
Transport (protocol — how events travel)
    ↓
┌─────────────┬──────────────┬──────────────┬────────────┐
│ TUI         │ Native App   │ Shiki DB     │ Web View   │
│ (LocalPipe) │ (UnixSocket) │ (Persistent) │ (WebSocket)│
└─────────────┴──────────────┴──────────────┴────────────┘
```

## 2. Event Protocol

### 2.1 ShikiEvent

```swift
/// A single observable event in the Shiki data stream.
/// Every action in the system produces one or more of these.
public struct ShikiEvent: Codable, Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let source: EventSource
    public let type: EventType
    public let scope: EventScope
    public let payload: [String: AnyCodable]
    public let metadata: EventMetadata?

    public init(
        source: EventSource,
        type: EventType,
        scope: EventScope,
        payload: [String: AnyCodable] = [:],
        metadata: EventMetadata? = nil
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.source = source
        self.type = type
        self.scope = scope
        self.payload = payload
        self.metadata = metadata
    }
}
```

### 2.2 EventSource — Who produced the event

```swift
public enum EventSource: Codable, Sendable {
    case agent(id: String, name: String?)     // Claude agent, subagent
    case human(id: String?)                    // User action
    case orchestrator                          // Heartbeat loop, dispatcher
    case process(name: String)                 // shiki pr, shiki decide, etc.
    case system                                // Startup, shutdown, health
}
```

### 2.3 EventType — What happened

```swift
public enum EventType: String, Codable, Sendable {
    // Lifecycle
    case sessionStart
    case sessionEnd
    case contextCompaction

    // Orchestration
    case heartbeat
    case companyDispatched
    case companyStale
    case companyRelaunched
    case budgetExhausted

    // Decisions
    case decisionPending
    case decisionAnswered
    case decisionUnblocked

    // Code
    case codeChange              // file modified, +/- lines
    case testRun                 // test suite result
    case buildResult             // swift build / deno compile

    // PR Review
    case prCacheBuilt            // cache generated for PR
    case prRiskAssessed          // risk map computed
    case prSectionViewed         // human opened a section
    case prVerdictSet            // human set approve/comment/requestChanges
    case prSearchQuery           // qmd/fzf search during review
    case prFixSpawned            // fix agent started in worktree
    case prFixCompleted          // fix agent finished
    case prCourseCorrect         // human injected prompt to running agent
    case prExported              // review exported as markdown

    // Notifications
    case notificationSent
    case notificationActioned    // approve/deny from ntfy

    // Generic
    case custom(String)          // extensible without enum change
}
```

### 2.4 EventScope — What context does it belong to

```swift
public enum EventScope: Codable, Sendable {
    case global                              // system-wide
    case session(id: String)                 // Claude session
    case project(slug: String)               // company/project
    case pr(number: Int)                     // specific PR
    case file(path: String)                  // specific file
    case agent(sessionId: String)            // specific agent instance
}
```

### 2.5 EventMetadata — Optional rich context

```swift
public struct EventMetadata: Codable, Sendable {
    public var branch: String?
    public var file: String?
    public var lineRange: ClosedRange<Int>?
    public var commitHash: String?
    public var duration: TimeInterval?       // for timed events
    public var tags: [String]?               // free-form labels
}
```

## 3. EventBus Protocol

```swift
/// The central pub/sub hub. Implementations vary by context.
public protocol EventBus: Sendable {
    /// Publish an event to all matching subscribers.
    func publish(_ event: ShikiEvent)

    /// Subscribe with an optional filter. Returns an AsyncStream of matching events.
    func subscribe(
        filter: EventFilter
    ) -> AsyncStream<ShikiEvent>

    /// Remove a subscription.
    func unsubscribe(_ id: SubscriptionID)
}

public struct SubscriptionID: Hashable, Sendable {
    public let rawValue: UUID
    public init() { rawValue = UUID() }
}
```

### 3.1 EventFilter

```swift
public struct EventFilter: Sendable {
    public var types: Set<EventType>?        // nil = all types
    public var sources: Set<EventSource>?    // nil = all sources
    public var scopes: Set<EventScope>?      // nil = all scopes
    public var minTimestamp: Date?            // events after this time

    public static let all = EventFilter()

    public func matches(_ event: ShikiEvent) -> Bool {
        if let types, !types.contains(event.type) { return false }
        if let scopes, !scopes.contains(event.scope) { return false }
        if let minTimestamp, event.timestamp < minTimestamp { return false }
        // Source matching requires custom Equatable on EventSource
        return true
    }
}
```

## 4. Transport Protocol

```swift
/// Abstraction over how events travel between processes/machines.
/// The EventBus uses a Transport to deliver events to remote subscribers.
public protocol EventTransport: Sendable {
    /// Send an event to connected consumers.
    func send(_ event: ShikiEvent) async throws

    /// Receive events from connected producers.
    func receive() -> AsyncStream<ShikiEvent>

    /// Connection lifecycle.
    func connect() async throws
    func disconnect() async
}
```

### 4.1 Transport Implementations (phased)

| Transport | When | Use case | Protocol |
|-----------|------|----------|----------|
| `LocalPipeTransport` | Phase 4 (now) | In-process: TUI ↔ engine | Direct function call |
| `UnixSocketTransport` | After orchestrator v3 | Native macOS app ↔ CLI | SwiftNIO, local socket |
| `WebSocketTransport` | When team grows | Browser dashboard, remote | SwiftNIO WebSocket |
| `MoshBridgeTransport` | Future (if needed) | Optimized UDP for mobile | Custom, mosh-inspired |
| `ShikiDBTransport` | Phase 4 (now) | Persistent event log | HTTP POST to data-sync |

**Key design decision**: `LocalPipeTransport` and `ShikiDBTransport` are built first. They cover the TUI (local) and persistence (DB) use cases. Socket transports come when we have a second process that needs events.

## 5. In-Process EventBus Implementation

```swift
/// Simple in-process event bus using AsyncStream continuations.
public actor InProcessEventBus: EventBus {
    private var subscribers: [SubscriptionID: (filter: EventFilter, continuation: AsyncStream<ShikiEvent>.Continuation)] = [:]

    public func publish(_ event: ShikiEvent) {
        for (_, sub) in subscribers {
            if sub.filter.matches(event) {
                sub.continuation.yield(event)
            }
        }
    }

    public func subscribe(filter: EventFilter) -> AsyncStream<ShikiEvent> {
        let id = SubscriptionID()
        return AsyncStream { continuation in
            subscribers[id] = (filter, continuation)
            continuation.onTermination = { @Sendable _ in
                Task { await self.removeSubscriber(id) }
            }
        }
    }

    public func unsubscribe(_ id: SubscriptionID) {
        removeSubscriber(id)
    }

    private func removeSubscriber(_ id: SubscriptionID) {
        if let sub = subscribers.removeValue(forKey: id) {
            sub.continuation.finish()
        }
    }
}
```

## 6. Persistent Subscriber — Shiki DB

The Shiki DB already stores `agent_events`. The event bus formalizes this:

```swift
/// Subscribes to all events and persists them to Shiki DB.
public actor ShikiDBEventLogger {
    private let client: BackendClient
    private let projectId: String

    public func start(bus: EventBus) {
        let stream = bus.subscribe(filter: .all)
        Task {
            for await event in stream {
                try? await persist(event)
            }
        }
    }

    private func persist(_ event: ShikiEvent) async throws {
        try await client.post(
            path: "/api/data-sync",
            body: DataSyncPayload(
                type: "shiki_event",
                projectId: projectId,
                payload: event
            )
        )
    }
}
```

## 7. Observation Depth Model

```
Level 0: SLEEP    — No subscriber. Events still emitted, logged to DB.
Level 1: GLANCE   — ntfy subscriber. Only critical events (errors, decisions, completions).
Level 2: SCAN     — Dashboard subscriber. All events, aggregated by source/scope.
Level 3: WATCH    — Pinned view. All events for one agent/PR/session, real-time.
Level 4: INTERVENE — Watch + write access. Can inject course_correct events.
```

Each tool declares its observation level. The transport and filter are configured accordingly:

```swift
// TUI PR review at Level 3-4 (Watch + Intervene)
let reviewStream = bus.subscribe(filter: EventFilter(
    scopes: [.pr(number: 5)],
    types: nil  // all event types for this PR
))

// ntfy at Level 1 (Glance)
let alertStream = bus.subscribe(filter: EventFilter(
    types: [.decisionPending, .budgetExhausted, .prFixCompleted]
))
```

## 8. Integration Points

### 8.1 Existing Shiki Components → EventBus

| Component | Current behavior | With EventBus |
|-----------|-----------------|---------------|
| HeartbeatLoop | Logs to console, POSTs agent_events | `bus.publish(.heartbeat)` |
| ProcessCleanup | print() results | `bus.publish(.companyStale)` |
| DecideCommand | print() answers | `bus.publish(.decisionAnswered)` |
| NotificationService | Sends ntfy push | `bus.publish(.notificationSent)` |
| StartupCommand | Renders dashboard | Subscribes to status events |
| PRReviewEngine | State transitions | `bus.publish(.prVerdictSet)` |

### 8.2 Future Components

| Component | Subscribes to | Publishes |
|-----------|--------------|-----------|
| Native macOS app | All (Level 2-3) | course_correct, human decisions |
| Web dashboard | All (Level 2) | Read-only |
| Team member view | Filtered by assigned project | Verdicts, comments |
| AI fix agent | course_correct for its session | codeChange, fixCompleted |
| CI/CD pipeline | buildResult, testRun | Triggers from external |

## 9. Wire Format

Events are JSON-serialized for all transports except LocalPipe:

```json
{
  "id": "a1b2c3d4-...",
  "timestamp": "2026-03-17T10:30:00Z",
  "source": { "agent": { "id": "session-abc", "name": "fix-agent" } },
  "type": "codeChange",
  "scope": { "pr": { "number": 5 } },
  "payload": {
    "file": "Sources/ShikiCtlKit/Services/ProcessCleanup.swift",
    "insertions": 12,
    "deletions": 3,
    "description": "Added SIGTERM timeout configuration"
  },
  "metadata": {
    "branch": "feature/cli-core-architecture",
    "commitHash": "abc123",
    "file": "ProcessCleanup.swift",
    "lineRange": [42, 54]
  }
}
```

## 10. Implementation Order

1. **ShikiEvent + EventType + EventSource** → `packages/ShikiKit/` (shared DTO package)
2. **InProcessEventBus** → `ShikiCtlKit/Events/` (CLI-local)
3. **ShikiDBEventLogger** → `ShikiCtlKit/Events/` (persistent subscriber)
4. **Migrate HeartbeatLoop** → emit events instead of raw logs
5. **PR review engine** → emit events for all state transitions
6. **UnixSocketTransport** → when native app is ready
7. **WebSocketTransport** → when team/web dashboard is ready

## 11. Design Constraints

- **Zero external dependencies** for the protocol layer (ShikiKit is pure Swift)
- **Transport is always optional** — if no transport is configured, events are in-process only
- **Events are fire-and-forget** — publishers never block waiting for subscribers
- **DB persistence is best-effort** — if Shiki DB is down, events still flow to local subscribers
- **Back-pressure via AsyncStream** — slow subscribers get events buffered, not dropped (configurable buffer policy)
- **Thread-safe** — EventBus is an actor, all access is serialized
