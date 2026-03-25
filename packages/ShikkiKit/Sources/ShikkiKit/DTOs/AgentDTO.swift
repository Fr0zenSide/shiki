import Foundation

/// Agent status values matching the CHECK constraint in the schema.
public enum AgentStatus: String, Codable, Sendable {
    case spawned
    case running
    case completed
    case failed
    case cancelled
}

/// Maps to the `agents` table in the PostgreSQL schema.
public struct AgentDTO: Codable, Equatable, Sendable {
    public let id: UUID
    public let sessionId: UUID
    public let projectId: UUID
    public let handle: String
    public let role: String
    public let model: String
    public let spawnedAt: Date
    public let completedAt: Date?
    public let status: AgentStatus
    public let parentId: UUID?
    public let metadata: [String: AnyCodable]

    public init(
        id: UUID,
        sessionId: UUID,
        projectId: UUID,
        handle: String,
        role: String,
        model: String,
        spawnedAt: Date = Date(),
        completedAt: Date? = nil,
        status: AgentStatus = .spawned,
        parentId: UUID? = nil,
        metadata: [String: AnyCodable] = [:]
    ) {
        self.id = id
        self.sessionId = sessionId
        self.projectId = projectId
        self.handle = handle
        self.role = role
        self.model = model
        self.spawnedAt = spawnedAt
        self.completedAt = completedAt
        self.status = status
        self.parentId = parentId
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case id, handle, role, model, status, metadata
        case sessionId = "session_id"
        case projectId = "project_id"
        case spawnedAt = "spawned_at"
        case completedAt = "completed_at"
        case parentId = "parent_id"
    }
}

/// Input for posting agent events (maps to AgentEventSchema in schemas.ts).
public struct AgentEventInput: Codable, Equatable, Sendable {
    public let agentId: UUID
    public let sessionId: UUID
    public let projectId: UUID
    public let eventType: String
    public let payload: [String: AnyCodable]?
    public let progressPct: Int?
    public let message: String?

    public init(
        agentId: UUID,
        sessionId: UUID,
        projectId: UUID,
        eventType: String,
        payload: [String: AnyCodable]? = nil,
        progressPct: Int? = nil,
        message: String? = nil
    ) {
        self.agentId = agentId
        self.sessionId = sessionId
        self.projectId = projectId
        self.eventType = eventType
        self.payload = payload
        self.progressPct = progressPct
        self.message = message
    }

    enum CodingKeys: String, CodingKey {
        case eventType = "event_type"
        case agentId = "agent_id"
        case sessionId = "session_id"
        case projectId = "project_id"
        case payload
        case progressPct = "progress_pct"
        case message
    }
}

/// Agent event stored in agent_events hypertable.
public struct AgentEventDTO: Codable, Equatable, Sendable {
    public let occurredAt: Date
    public let agentId: UUID?
    public let sessionId: UUID?
    public let projectId: UUID
    public let eventType: String
    public let payload: [String: AnyCodable]
    public let progressPct: Int?
    public let message: String?

    public init(
        occurredAt: Date = Date(),
        agentId: UUID? = nil,
        sessionId: UUID? = nil,
        projectId: UUID,
        eventType: String,
        payload: [String: AnyCodable] = [:],
        progressPct: Int? = nil,
        message: String? = nil
    ) {
        self.occurredAt = occurredAt
        self.agentId = agentId
        self.sessionId = sessionId
        self.projectId = projectId
        self.eventType = eventType
        self.payload = payload
        self.progressPct = progressPct
        self.message = message
    }

    enum CodingKeys: String, CodingKey {
        case occurredAt = "occurred_at"
        case agentId = "agent_id"
        case sessionId = "session_id"
        case projectId = "project_id"
        case eventType = "event_type"
        case payload
        case progressPct = "progress_pct"
        case message
    }
}

/// Performance metric input (maps to PerformanceMetricSchema in schemas.ts).
public struct PerformanceMetricInput: Codable, Equatable, Sendable {
    public let agentId: UUID
    public let sessionId: UUID
    public let projectId: UUID
    public let metricType: String
    public let tokensInput: Int?
    public let tokensOutput: Int?
    public let durationMs: Int?
    public let costUsd: Double?
    public let model: String?

    public init(
        agentId: UUID,
        sessionId: UUID,
        projectId: UUID,
        metricType: String,
        tokensInput: Int? = nil,
        tokensOutput: Int? = nil,
        durationMs: Int? = nil,
        costUsd: Double? = nil,
        model: String? = nil
    ) {
        self.agentId = agentId
        self.sessionId = sessionId
        self.projectId = projectId
        self.metricType = metricType
        self.tokensInput = tokensInput
        self.tokensOutput = tokensOutput
        self.durationMs = durationMs
        self.costUsd = costUsd
        self.model = model
    }

    enum CodingKeys: String, CodingKey {
        case agentId = "agent_id"
        case sessionId = "session_id"
        case projectId = "project_id"
        case metricType = "metric_type"
        case tokensInput = "tokens_input"
        case tokensOutput = "tokens_output"
        case durationMs = "duration_ms"
        case costUsd = "cost_usd"
        case model
    }
}
