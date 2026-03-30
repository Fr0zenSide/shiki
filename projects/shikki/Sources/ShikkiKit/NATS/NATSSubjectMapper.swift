import Foundation

// MARK: - NATSSubjectMapper

/// Maps ShikkiEvent types to NATS subject strings per the NATS topics table.
///
/// Subject hierarchy:
/// - `shikki.events.{company}.{category}` — event streams
/// - `shikki.commands.{node_id}` — directed commands (req/rep)
/// - `shikki.discovery.announce` / `shikki.discovery.query` — node discovery
/// - `shikki.tasks.{workspace}.available` / `.claimed` — task distribution
/// - `shikki.decisions.pending` — decisions needing human input
public enum NATSSubjectMapper {

    // MARK: - Event Category

    /// The NATS subject category for event routing.
    public enum EventCategory: String, Sendable {
        case lifecycle
        case agent
        case ship
        case task
        case decision
        case git
        case codegen
        case scheduler
        case observatory
        case system
    }

    // MARK: - Event Subject Mapping

    /// Map a ShikkiEvent type to its NATS subject for a given company.
    public static func subject(for eventType: EventType, company: String) -> String {
        let category = Self.category(for: eventType)
        return "shikki.events.\(company).\(category.rawValue)"
    }

    /// Map a ShikkiEvent to its full NATS subject, extracting company from scope.
    public static func subject(for event: ShikkiEvent, defaultCompany: String = "global") -> String {
        let company = companySlug(from: event.scope) ?? defaultCompany
        return subject(for: event.type, company: company)
    }

    /// Determine the event category for a given event type.
    public static func category(for eventType: EventType) -> EventCategory {
        switch eventType {
        // Lifecycle
        case .sessionStart, .sessionEnd, .sessionTransition, .contextCompaction:
            return .lifecycle

        // Orchestration (lifecycle-level)
        case .heartbeat, .companyDispatched, .companyStale, .companyRelaunched, .budgetExhausted:
            return .lifecycle

        // Decisions
        case .decisionPending, .decisionAnswered, .decisionUnblocked:
            return .decision

        // Code / Git
        case .codeChange:
            return .git
        case .testRun, .buildResult:
            return .lifecycle

        // PR (agent-level workflow)
        case .prCacheBuilt, .prRiskAssessed, .prVerdictSet, .prFixSpawned, .prFixCompleted:
            return .agent

        // Notifications (system-level)
        case .notificationSent, .notificationActioned:
            return .system

        // Ship
        case .shipStarted, .shipGateStarted, .shipGatePassed, .shipGateFailed,
             .shipCompleted, .shipAborted:
            return .ship

        // CodeGen
        case .codeGenStarted, .codeGenSpecParsed, .codeGenContractVerified,
             .codeGenPlanCreated, .codeGenAgentDispatched, .codeGenAgentCompleted,
             .codeGenMergeStarted, .codeGenMergeCompleted, .codeGenFixStarted,
             .codeGenFixCompleted, .codeGenPipelineCompleted, .codeGenPipelineFailed:
            return .codegen

        // Scheduler
        case .scheduledTaskFired, .scheduledTaskCompleted, .scheduledTaskFailed,
             .corroborationSweep:
            return .scheduler

        // Observatory
        case .decisionMade, .architectureChoice, .tradeOffEvaluated,
             .blockerHit, .blockerResolved, .milestoneReached, .redFlag,
             .contextSaved, .agentReportGenerated:
            return .observatory

        // Custom — route to system by default
        case .custom:
            return .system
        }
    }

    // MARK: - Special Subjects

    /// Subject for directed commands to a specific node.
    public static func commandSubject(nodeId: String) -> String {
        "shikki.commands.\(nodeId)"
    }

    /// Subject for node heartbeat announcements.
    public static let discoveryAnnounce = "shikki.discovery.announce"

    /// Subject for discovery queries (req/rep).
    public static let discoveryQuery = "shikki.discovery.query"

    /// Subject for available tasks in a workspace.
    public static func tasksAvailable(workspace: String) -> String {
        "shikki.tasks.\(workspace).available"
    }

    /// Subject for claimed tasks in a workspace.
    public static func tasksClaimed(workspace: String) -> String {
        "shikki.tasks.\(workspace).claimed"
    }

    /// Subject for decisions pending human input.
    public static let decisionsPending = "shikki.decisions.pending"

    // MARK: - Wildcard Subjects (for consumers)

    /// Subscribe to all events across all companies.
    public static let allEvents = "shikki.events.>"

    /// Subscribe to all events for a specific company.
    public static func companyEvents(_ company: String) -> String {
        "shikki.events.\(company).>"
    }

    /// Subscribe to all discovery traffic.
    public static let allDiscovery = "shikki.discovery.>"

    // MARK: - Helpers

    /// Extract company slug from an EventScope.
    static func companySlug(from scope: EventScope) -> String? {
        switch scope {
        case .project(let slug):
            return slug
        case .session(let id):
            // Convention: session IDs may be prefixed with company slug (e.g. "maya:session-123")
            let parts = id.split(separator: ":")
            return parts.count > 1 ? String(parts[0]) : nil
        case .global, .pr, .file:
            return nil
        }
    }
}
