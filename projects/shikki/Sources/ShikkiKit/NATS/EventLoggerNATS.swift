import Foundation
import Logging

// MARK: - EventLoggerNATS

/// Actor that subscribes to NATS event subjects and feeds events
/// to an EventRenderer for display.
///
/// Used by `shikki log` for real-time event streaming.
/// Supports:
/// - Wildcard subscription (`shikki.events.>`) for all events
/// - Company-filtered subscription (`shikki.events.{company}.>`)
/// - Replay: request last N events from DB before going live
/// - Significance-level filtering
public actor EventLoggerNATS {
    private let nats: NATSClientProtocol
    private let renderer: NATSEventRenderer
    private let logger: Logger
    private var task: Task<Void, Never>?
    private var eventCount: Int = 0

    /// Callback for each rendered line. Defaults to stdout.
    public var onLine: (@Sendable (String) -> Void)?

    public init(
        nats: NATSClientProtocol,
        renderer: NATSEventRenderer = NATSEventRenderer(),
        logger: Logger = Logger(label: "shikki.event-logger-nats")
    ) {
        self.nats = nats
        self.renderer = renderer
        self.logger = logger
    }

    /// Start subscribing to events.
    ///
    /// - Parameter filter: Company slug or `company.type` filter.
    ///   Empty/nil subscribes to all events.
    public func start(filter: String? = nil) async throws {
        // Ensure connected
        if !(await nats.isConnected) {
            try await nats.connect()
        }

        let subject = NATSEventTransport.channelToSubject(filter ?? "")
        let stream = nats.subscribe(subject: subject)

        task = Task { [renderer, onLine] in
            for await message in stream {
                if Task.isCancelled { break }

                guard let event = NATSEventTransport.decodeEvent(from: message) else {
                    continue
                }

                let line = renderer.render(event)
                if !line.isEmpty {
                    if let onLine {
                        onLine(line)
                    }
                }
                await self.incrementCount()
            }
        }
    }

    /// Replay historical events (from a provided array).
    /// The EventLoggerNATS itself doesn't query the DB — the LogCommand
    /// fetches replay events and passes them here for rendering.
    public func renderReplay(events: [ShikkiEvent]) -> [String] {
        events.compactMap { event in
            let line = renderer.renderReplay(event)
            return line.isEmpty ? nil : line
        }
    }

    /// Stop the subscription.
    public func stop() async {
        task?.cancel()
        task = nil
        await nats.disconnect()
    }

    /// Number of events received so far.
    public var count: Int { eventCount }

    /// Whether the logger is actively running.
    public var isRunning: Bool { task != nil && !task!.isCancelled }

    private func incrementCount() {
        eventCount += 1
    }
}

// MARK: - NATSSubjectMapper

/// Maps event types and company slugs to NATS subjects.
/// Centralizes the subject naming convention.
public enum NATSSubjectMapper {

    /// Build a NATS subject for a given event type and company.
    public static func subject(for eventType: EventType, company: String) -> String {
        let category = eventCategory(for: eventType)
        return "shikki.events.\(company).\(category)"
    }

    /// Build a wildcard subject for all events of a company.
    public static func companyWildcard(_ company: String) -> String {
        "shikki.events.\(company).>"
    }

    /// Build a wildcard subject for all events globally.
    public static var allEvents: String { "shikki.events.>" }

    /// Map an event type to its NATS subject category.
    public static func eventCategory(for eventType: EventType) -> String {
        switch eventType {
        // Lifecycle
        case .sessionStart, .sessionEnd, .sessionTransition, .contextCompaction, .contextSaved:
            return "lifecycle"
        // Orchestration
        case .heartbeat:
            return "heartbeat"
        case .companyDispatched, .companyStale, .companyRelaunched, .budgetExhausted:
            return "orchestration"
        // Decisions
        case .decisionPending, .decisionAnswered, .decisionUnblocked,
             .decisionMade, .architectureChoice, .tradeOffEvaluated:
            return "decision"
        // Code
        case .codeChange, .testRun, .buildResult:
            return "code"
        // PR
        case .prCacheBuilt, .prRiskAssessed, .prVerdictSet, .prFixSpawned, .prFixCompleted:
            return "pr"
        // Notifications
        case .notificationSent, .notificationActioned:
            return "notification"
        // Ship
        case .shipStarted, .shipGateStarted, .shipGatePassed, .shipGateFailed,
             .shipCompleted, .shipAborted:
            return "ship"
        // CodeGen
        case .codeGenStarted, .codeGenSpecParsed, .codeGenContractVerified,
             .codeGenPlanCreated, .codeGenAgentDispatched, .codeGenAgentCompleted,
             .codeGenMergeStarted, .codeGenMergeCompleted, .codeGenFixStarted,
             .codeGenFixCompleted, .codeGenPipelineCompleted, .codeGenPipelineFailed:
            return "codegen"
        // Scheduler
        case .scheduledTaskFired, .scheduledTaskCompleted, .scheduledTaskFailed, .corroborationSweep:
            return "scheduler"
        // Observatory
        case .blockerHit, .blockerResolved:
            return "blocker"
        case .milestoneReached:
            return "milestone"
        case .redFlag:
            return "alert"
        case .agentReportGenerated:
            return "report"
        // Quick Flow
        case .quickStarted, .quickStepCompleted, .quickCompleted, .quickFailed:
            return "quick"
        // Fast Pipeline
        case .fastStarted, .fastStageCompleted, .fastCompleted, .fastFailed:
            return "fast"
        // Generic
        case .custom:
            return "custom"
        }
    }

    // MARK: - Infrastructure Subjects (from W1 foundation)

    /// Discovery announce subject for node heartbeats.
    public static var discoveryAnnounce: String { "shikki.discovery.announce" }

    /// Discovery query subject for node lookup.
    public static var discoveryQuery: String { "shikki.discovery.query" }

    /// Discovery query reply subject.
    public static var discoveryQueryReply: String { "shikki.discovery.query.reply" }

    /// Commands subject for a specific node.
    public static func commands(nodeId: String) -> String {
        "shikki.commands.\(nodeId)"
    }

    /// Tasks available subject for a workspace.
    public static func tasksAvailable(workspace: String) -> String {
        "shikki.tasks.\(workspace).available"
    }

    /// Tasks claimed subject for a workspace.
    public static func tasksClaimed(workspace: String) -> String {
        "shikki.tasks.\(workspace).claimed"
    }

    /// Pending decisions subject.
    public static var decisionsPending: String { "shikki.decisions.pending" }

    /// Primary node claim subject (BR-06).
    /// Published when a node assumes the primary role via leader election.
    public static var nodePrimary: String { "shikki.node.primary" }

    /// Extract company slug from a NATS subject.
    public static func companySlug(from subject: String) -> String? {
        let parts = subject.split(separator: ".")
        guard parts.count >= 3, parts[0] == "shikki", parts[1] == "events" else { return nil }
        return String(parts[2])
    }
}
