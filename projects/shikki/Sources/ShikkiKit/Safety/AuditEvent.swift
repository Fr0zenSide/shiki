import Foundation

// MARK: - AuditEvent

/// Every MCP tool call logged with 5W1H for SOC 2 / ISO 27001 readiness.
///
/// | Field | Source |
/// |-------|--------|
/// | **Who** | User ID from auth token / API key |
/// | **What** | Tool name + parameters |
/// | **Where** | Project scope, workspace |
/// | **When** | Timestamp (ISO 8601) |
/// | **Why** | Inferred from context (search query, task in progress) |
/// | **How** | MCP tool call chain, session ID |
public struct AuditEvent: Codable, Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date

    // Who
    public let userId: String

    // What
    public let toolName: String
    public let parameters: [String: String]

    // Where
    public let projectSlug: String?
    public let workspaceId: String?

    // Why
    public let context: String?

    // How
    public let sessionId: String?
    public let parentEventId: UUID?

    // Result
    public let outcome: AuditOutcome

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        userId: String,
        toolName: String,
        parameters: [String: String] = [:],
        projectSlug: String? = nil,
        workspaceId: String? = nil,
        context: String? = nil,
        sessionId: String? = nil,
        parentEventId: UUID? = nil,
        outcome: AuditOutcome = .success
    ) {
        self.id = id
        self.timestamp = timestamp
        self.userId = userId
        self.toolName = toolName
        self.parameters = parameters
        self.projectSlug = projectSlug
        self.workspaceId = workspaceId
        self.context = context
        self.sessionId = sessionId
        self.parentEventId = parentEventId
        self.outcome = outcome
    }
}

// MARK: - AuditOutcome

/// The result of an audited tool call.
public enum AuditOutcome: Codable, Sendable, Hashable {
    case success
    case failure(reason: String)
    case blocked(reason: String)
}

// MARK: - AuditQuery

/// Query parameters for searching the audit trail.
public struct AuditQuery: Sendable {
    public let userId: String?
    public let projectSlug: String?
    public let workspaceId: String?
    public let toolName: String?
    public let since: Date?
    public let until: Date?
    public let limit: Int

    public init(
        userId: String? = nil,
        projectSlug: String? = nil,
        workspaceId: String? = nil,
        toolName: String? = nil,
        since: Date? = nil,
        until: Date? = nil,
        limit: Int = 100
    ) {
        self.userId = userId
        self.projectSlug = projectSlug
        self.workspaceId = workspaceId
        self.toolName = toolName
        self.since = since
        self.until = until
        self.limit = limit
    }

    /// Filter a collection of audit events by this query.
    public func matches(_ event: AuditEvent) -> Bool {
        if let userId, event.userId != userId { return false }
        if let projectSlug, event.projectSlug != projectSlug { return false }
        if let workspaceId, event.workspaceId != workspaceId { return false }
        if let toolName, event.toolName != toolName { return false }
        if let since, event.timestamp < since { return false }
        if let until, event.timestamp > until { return false }
        return true
    }
}

// MARK: - AuditReport

/// Aggregated audit report for compliance export.
public struct AuditReport: Sendable {
    public let query: AuditQuery
    public let events: [AuditEvent]
    public let generatedAt: Date
    public let totalCount: Int

    public init(query: AuditQuery, events: [AuditEvent], generatedAt: Date = Date()) {
        self.query = query
        self.events = events
        self.generatedAt = generatedAt
        self.totalCount = events.count
    }

    /// Unique users in this report.
    public var uniqueUsers: Set<String> {
        Set(events.map(\.userId))
    }

    /// Unique tools in this report.
    public var uniqueTools: Set<String> {
        Set(events.map(\.toolName))
    }

    /// Count of events grouped by outcome.
    public var outcomeCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for event in events {
            let key: String
            switch event.outcome {
            case .success: key = "success"
            case .failure: key = "failure"
            case .blocked: key = "blocked"
            }
            counts[key, default: 0] += 1
        }
        return counts
    }
}
