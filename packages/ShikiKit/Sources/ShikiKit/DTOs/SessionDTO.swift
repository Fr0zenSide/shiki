import Foundation

/// Session status values matching the CHECK constraint in the schema.
public enum SessionStatus: String, Codable, Sendable {
    case active
    case paused
    case completed
    case failed
}

/// Maps to the `sessions` table in the PostgreSQL schema.
public struct SessionDTO: Codable, Equatable, Sendable {
    public let id: UUID
    public let projectId: UUID
    public let name: String
    public let branch: String?
    public let status: SessionStatus
    public let startedAt: Date
    public let endedAt: Date?
    public let summary: String?
    public let metadata: [String: AnyCodable]

    public init(
        id: UUID,
        projectId: UUID,
        name: String,
        branch: String? = nil,
        status: SessionStatus = .active,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        summary: String? = nil,
        metadata: [String: AnyCodable] = [:]
    ) {
        self.id = id
        self.projectId = projectId
        self.name = name
        self.branch = branch
        self.status = status
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.summary = summary
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case id, name, branch, status, summary, metadata
        case projectId = "project_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
    }
}

/// Maps to the `active_sessions` view.
public struct ActiveSessionDTO: Codable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let branch: String?
    public let startedAt: Date
    public let projectSlug: String
    public let projectName: String
    public let hoursActive: Double

    enum CodingKeys: String, CodingKey {
        case id, name, branch
        case startedAt = "started_at"
        case projectSlug = "project_slug"
        case projectName = "project_name"
        case hoursActive = "hours_active"
    }
}
