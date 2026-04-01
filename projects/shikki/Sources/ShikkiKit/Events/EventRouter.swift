import Foundation

// MARK: - EventSignificance

/// Semantic weight of an event. Higher = more important to the human.
public enum EventSignificance: Int, Codable, Sendable, Comparable, Equatable {
    case noise = 0        // heartbeat tick, routine check
    case background = 1   // file read, test started
    case progress = 2     // test passed, file committed
    case milestone = 3    // all tests green, PR created
    case decision = 4     // architecture choice, scope change
    case alert = 5        // test failure, blocker, budget exhausted
    case critical = 6     // agent terminated, data loss, security issue

    public static func < (lhs: EventSignificance, rhs: EventSignificance) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - DisplayHint

/// Where this event should be shown.
public enum DisplayHint: String, Codable, Sendable, Equatable {
    case timeline       // Observatory timeline (left panel)
    case detail         // Observatory detail (right panel on selection)
    case question       // Questions tab with answer input
    case report         // Aggregate into Agent Report Card
    case notification   // Push via ntfy
    case background     // Persist to DB only
    case suppress       // Don't persist, don't display
}

// MARK: - EventDestination

/// Where to send an enriched event.
public enum EventDestination: String, Sendable, Equatable {
    case database
    case observatoryTUI
    case ntfy
    case journalFile
    case reportAggregator
    case agentInbox
}

// MARK: - EnrichmentContext

/// Smart metadata added by the enrichment stage.
public struct EnrichmentContext: Codable, Sendable {
    public var sessionState: SessionState?
    public var attentionZone: AttentionZone?
    public var companySlug: String?
    public var taskTitle: String?
    public var parentDecisionId: String?
    public var journalCheckpointCount: Int?
    public var elapsedSinceLastMilestone: TimeInterval?

    public init() {}
}

// MARK: - DetectedPattern

/// A pattern detected across multiple events.
public struct DetectedPattern: Codable, Sendable {
    public let name: String
    public let description: String
    public let severity: EventSignificance
    public let relatedEventIds: [UUID]

    public init(name: String, description: String, severity: EventSignificance, relatedEventIds: [UUID] = []) {
        self.name = name
        self.description = description
        self.severity = severity
        self.relatedEventIds = relatedEventIds
    }
}

// MARK: - RouterEnvelope

/// The enriched output of the router — a raw event wrapped with intelligence.
public struct RouterEnvelope: Sendable {
    public let event: ShikkiEvent
    public let significance: EventSignificance
    public let displayHint: DisplayHint
    public let context: EnrichmentContext
    public let patterns: [DetectedPattern]

    public init(event: ShikkiEvent, significance: EventSignificance, displayHint: DisplayHint, context: EnrichmentContext, patterns: [DetectedPattern] = []) {
        self.event = event
        self.significance = significance
        self.displayHint = displayHint
        self.context = context
        self.patterns = patterns
    }
}

// MARK: - EventClassifier

/// Stage 1: Assign significance to raw events.
public enum EventClassifier {

    public static func classify(_ event: ShikkiEvent) -> EventSignificance {
        switch event.type {
        // Noise
        case .heartbeat:
            return .noise

        // Background
        case .codeChange:
            return .background

        // Progress
        case .sessionStart, .sessionEnd, .sessionTransition:
            return .progress
        case .testRun:
            if event.payload["passed"] == .bool(false) { return .alert }
            return .progress
        case .buildResult:
            return .progress
        case .prVerdictSet:
            return .milestone

        // Decisions
        case .decisionPending, .decisionAnswered, .decisionUnblocked:
            return .decision

        // Alerts
        case .budgetExhausted, .companyStale:
            return .alert
        case .notificationSent, .notificationActioned:
            return .background

        // Orchestration
        case .companyDispatched, .companyRelaunched:
            return .progress

        // PR
        case .prCacheBuilt, .prRiskAssessed:
            return .background
        case .prFixSpawned:
            return .progress
        case .prFixCompleted:
            return .milestone

        // Context
        case .contextCompaction:
            return .alert

        // Ship
        case .shipStarted, .shipCompleted:
            return .milestone
        case .shipGateStarted, .shipGatePassed:
            return .progress
        case .shipGateFailed, .shipAborted:
            return .alert

        // CodeGen
        case .codeGenStarted, .codeGenPipelineCompleted:
            return .milestone
        case .codeGenSpecParsed, .codeGenContractVerified, .codeGenPlanCreated:
            return .progress
        case .codeGenAgentDispatched, .codeGenAgentCompleted:
            return .progress
        case .codeGenMergeStarted, .codeGenMergeCompleted:
            return .progress
        case .codeGenFixStarted, .codeGenFixCompleted:
            return .progress
        case .codeGenPipelineFailed:
            return .alert

        // Scheduler
        case .scheduledTaskFired:
            return .progress
        case .scheduledTaskCompleted:
            return .progress
        case .scheduledTaskFailed:
            return .alert
        case .corroborationSweep:
            return .background

        // Observatory
        case .decisionMade, .architectureChoice, .tradeOffEvaluated:
            return .decision
        case .blockerHit:
            return .alert
        case .blockerResolved:
            return .milestone
        case .milestoneReached:
            return .milestone
        case .redFlag:
            return .critical
        case .contextSaved:
            return .alert
        case .agentReportGenerated:
            return .progress

        // Quick Flow
        case .quickStarted, .quickStepCompleted:
            return .progress
        case .quickCompleted:
            return .milestone
        case .quickFailed:
            return .alert

        // Fast Pipeline
        case .fastStarted, .fastStageCompleted:
            return .progress
        case .fastCompleted:
            return .milestone
        case .fastFailed:
            return .alert

        // Custom
        case .custom(let name):
            if name == "redFlag" { return .critical }
            if name == "agentHandoff" { return .milestone }
            if name == "agentBroadcast" { return .decision }
            if name == "decisionGate" { return .decision }
            return .background
        }
    }
}

// MARK: - EventEnricher

/// Stage 2: Add smart metadata from registry, journal, etc.
public struct EventEnricher: Sendable {
    let registry: SessionRegistry?

    public init(registry: SessionRegistry?) {
        self.registry = registry
    }

    public func enrich(_ event: ShikkiEvent) async -> EnrichmentContext {
        var ctx = EnrichmentContext()

        // Extract company slug from scope
        switch event.scope {
        case .project(let slug):
            ctx.companySlug = slug
        case .session(let id):
            ctx.companySlug = id.split(separator: ":").first.map(String.init)
        default:
            break
        }

        // Lookup session state from registry
        if let registry {
            let sessions = await registry.allSessions
            let sessionId: String?
            switch event.scope {
            case .session(let id): sessionId = id
            default: sessionId = nil
            }

            if let sid = sessionId, let session = sessions.first(where: { $0.windowName == sid }) {
                ctx.sessionState = session.state
                ctx.attentionZone = session.attentionZone
                ctx.taskTitle = session.context?.taskId
            }
        }

        return ctx
    }
}

// MARK: - RoutingTable

/// Stage 3: Map significance → display hint → destinations.
public enum RoutingTable {

    public static func displayHint(for significance: EventSignificance) -> DisplayHint {
        switch significance {
        case .noise: .suppress
        case .background: .background
        case .progress: .timeline
        case .milestone: .timeline
        case .decision: .timeline
        case .alert: .notification
        case .critical: .notification
        }
    }

    public static func destinations(for hint: DisplayHint) -> Set<EventDestination> {
        switch hint {
        case .timeline: [.database, .observatoryTUI]
        case .detail: [.database]
        case .question: [.database, .observatoryTUI, .ntfy]
        case .report: [.database, .reportAggregator]
        case .notification: [.database, .observatoryTUI, .ntfy]
        case .background: [.database]
        case .suppress: []
        }
    }
}

// MARK: - PatternDetector

/// Stage 4: Detect patterns across events in a sliding window.
public actor PatternDetector {
    private var window: [(event: ShikkiEvent, timestamp: Date)] = []
    private let maxWindowSize = 100

    public init() {}

    public func record(_ event: ShikkiEvent) {
        window.append((event: event, timestamp: Date()))
        if window.count > maxWindowSize {
            window.removeFirst()
        }
    }

    public func detect() -> [DetectedPattern] {
        var patterns: [DetectedPattern] = []

        // Pattern: stuck agent (3+ heartbeats with no code changes for a session)
        patterns.append(contentsOf: detectStuckAgent())

        // Pattern: repeat failure (same test fails 3+)
        patterns.append(contentsOf: detectRepeatFailure())

        return patterns
    }

    private func detectStuckAgent() -> [DetectedPattern] {
        // Group heartbeats by session scope
        var sessionHeartbeats: [String: [UUID]] = [:]
        var sessionHasProgress: Set<String> = []

        for entry in window {
            let sessionId: String
            switch entry.event.scope {
            case .session(let id): sessionId = id
            default: continue
            }

            if entry.event.type == .heartbeat {
                sessionHeartbeats[sessionId, default: []].append(entry.event.id)
            }
            if entry.event.type == .codeChange || entry.event.type == .testRun {
                sessionHasProgress.insert(sessionId)
            }
        }

        var patterns: [DetectedPattern] = []
        for (sessionId, heartbeatIds) in sessionHeartbeats {
            if heartbeatIds.count >= 3 && !sessionHasProgress.contains(sessionId) {
                patterns.append(DetectedPattern(
                    name: "stuck_agent",
                    description: "Session \(sessionId): \(heartbeatIds.count) heartbeats with no code changes",
                    severity: .alert,
                    relatedEventIds: heartbeatIds
                ))
            }
        }
        return patterns
    }

    private func detectRepeatFailure() -> [DetectedPattern] {
        // Count test failures by test name
        var failuresByTest: [String: [UUID]] = [:]

        for entry in window {
            if entry.event.type == .testRun && entry.event.payload["passed"] == .bool(false) {
                let testName = entry.event.payload["testName"]?.stringValue ?? "unknown"
                failuresByTest[testName, default: []].append(entry.event.id)
            }
        }

        var patterns: [DetectedPattern] = []
        for (testName, ids) in failuresByTest where ids.count >= 3 {
            patterns.append(DetectedPattern(
                name: "repeat_failure",
                description: "Test '\(testName)' failed \(ids.count) times",
                severity: .critical,
                relatedEventIds: ids
            ))
        }
        return patterns
    }
}

// MARK: - EventValue helpers

extension EventValue {
    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }
    public var intValue: Int? {
        if case .int(let i) = self { return i }
        return nil
    }
    public var doubleValue: Double? {
        if case .double(let d) = self { return d }
        return nil
    }
    public var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }
}

// MARK: - EventRouter

/// The full 4-stage pipeline: classify → enrich → route → interpret.
public struct EventRouter: Sendable {
    let enricher: EventEnricher
    let detector: PatternDetector

    public init(registry: SessionRegistry? = nil) {
        self.enricher = EventEnricher(registry: registry)
        self.detector = PatternDetector()
    }

    /// Process a raw event through all 4 stages.
    public func process(_ event: ShikkiEvent) async -> RouterEnvelope {
        // 1. Classify
        let significance = EventClassifier.classify(event)

        // 2. Enrich
        let context = await enricher.enrich(event)

        // 3. Route
        let displayHint = RoutingTable.displayHint(for: significance)

        // 4. Interpret (record + detect patterns)
        await detector.record(event)
        let patterns = await detector.detect()

        return RouterEnvelope(
            event: event,
            significance: significance,
            displayHint: displayHint,
            context: context,
            patterns: patterns
        )
    }
}
