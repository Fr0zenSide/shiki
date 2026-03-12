import Foundation

/// Input for posting a PR creation event (maps to PrCreatedSchema in schemas.ts).
public struct PrCreatedInput: Codable, Equatable, Sendable, Validatable {
    public let projectId: UUID
    public let sessionId: UUID?
    public let agentId: UUID?
    public let prUrl: String
    public let title: String
    public let branch: String
    public let baseBranch: String
    public let metadata: [String: AnyCodable]

    public init(
        projectId: UUID,
        sessionId: UUID? = nil,
        agentId: UUID? = nil,
        prUrl: String,
        title: String,
        branch: String,
        baseBranch: String = "main",
        metadata: [String: AnyCodable] = [:]
    ) {
        self.projectId = projectId
        self.sessionId = sessionId
        self.agentId = agentId
        self.prUrl = prUrl
        self.title = title
        self.branch = branch
        self.baseBranch = baseBranch
        self.metadata = metadata
    }

    public func validate() throws {
        try Validators.requireNonEmpty(prUrl, field: "prUrl")
        try Validators.requireNonEmpty(title, field: "title")
        try Validators.requireNonEmpty(branch, field: "branch")
        try Validators.requireNonEmpty(baseBranch, field: "baseBranch")
    }

    enum CodingKeys: String, CodingKey {
        case title, branch, metadata
        case projectId = "project_id"
        case sessionId = "session_id"
        case agentId = "agent_id"
        case prUrl = "pr_url"
        case baseBranch = "base_branch"
    }
}

/// Git event as stored in the git_events hypertable.
public struct GitEventDTO: Codable, Equatable, Sendable {
    public let occurredAt: Date
    public let projectId: UUID
    public let sessionId: UUID?
    public let agentId: UUID?
    public let eventType: String
    public let ref: String?
    public let commitMsg: String?
    public let metadata: [String: AnyCodable]

    public init(
        occurredAt: Date = Date(),
        projectId: UUID,
        sessionId: UUID? = nil,
        agentId: UUID? = nil,
        eventType: String,
        ref: String? = nil,
        commitMsg: String? = nil,
        metadata: [String: AnyCodable] = [:]
    ) {
        self.occurredAt = occurredAt
        self.projectId = projectId
        self.sessionId = sessionId
        self.agentId = agentId
        self.eventType = eventType
        self.ref = ref
        self.commitMsg = commitMsg
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case ref, metadata
        case occurredAt = "occurred_at"
        case projectId = "project_id"
        case sessionId = "session_id"
        case agentId = "agent_id"
        case eventType = "event_type"
        case commitMsg = "commit_msg"
    }
}
