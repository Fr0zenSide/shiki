import Foundation

/// Input for storing a new memory (maps to MemorySchema in schemas.ts).
public struct MemoryInput: Codable, Equatable, Sendable, Validatable {
    public let projectId: UUID
    public let sessionId: UUID?
    public let agentId: UUID?
    public let content: String
    public let category: String
    public let importance: Double

    public init(
        projectId: UUID,
        sessionId: UUID? = nil,
        agentId: UUID? = nil,
        content: String,
        category: String = "general",
        importance: Double = 1.0
    ) {
        self.projectId = projectId
        self.sessionId = sessionId
        self.agentId = agentId
        self.content = content
        self.category = category
        self.importance = importance
    }

    public func validate() throws {
        try Validators.requireNonEmpty(content, field: "content")
        try Validators.requireNonEmpty(category, field: "category")
        try Validators.requireRange(importance, min: 0, max: 10, field: "importance")
    }

    enum CodingKeys: String, CodingKey {
        case content, category, importance
        case projectId = "project_id"
        case sessionId = "session_id"
        case agentId = "agent_id"
    }
}

/// Input for searching memories (maps to MemorySearchSchema in schemas.ts).
public struct MemorySearchInput: Codable, Equatable, Sendable, Validatable {
    public let query: String
    public let projectId: UUID
    public let limit: Int
    public let threshold: Double

    public init(
        query: String,
        projectId: UUID,
        limit: Int = 10,
        threshold: Double = 0.7
    ) {
        self.query = query
        self.projectId = projectId
        self.limit = limit
        self.threshold = threshold
    }

    public func validate() throws {
        try Validators.requireNonEmpty(query, field: "query")
        try Validators.requirePositive(limit, field: "limit")
        if limit > 100 {
            throw ShikiValidationError.fieldOutOfRange("limit", min: 1, max: 100)
        }
        try Validators.requireRange(threshold, min: 0, max: 1, field: "threshold")
    }

    enum CodingKeys: String, CodingKey {
        case query, limit, threshold
        case projectId = "project_id"
    }
}

/// Memory as returned from the database.
public struct MemoryDTO: Codable, Equatable, Sendable {
    public let id: UUID
    public let projectId: UUID
    public let sessionId: UUID?
    public let agentId: UUID?
    public let content: String
    public let category: String
    public let importance: Double
    public let createdAt: Date
    public let lastAccessedAt: Date?
    public let accessCount: Int
    public let metadata: [String: AnyCodable]

    public init(
        id: UUID,
        projectId: UUID,
        sessionId: UUID? = nil,
        agentId: UUID? = nil,
        content: String,
        category: String = "general",
        importance: Double = 1.0,
        createdAt: Date = Date(),
        lastAccessedAt: Date? = nil,
        accessCount: Int = 0,
        metadata: [String: AnyCodable] = [:]
    ) {
        self.id = id
        self.projectId = projectId
        self.sessionId = sessionId
        self.agentId = agentId
        self.content = content
        self.category = category
        self.importance = importance
        self.createdAt = createdAt
        self.lastAccessedAt = lastAccessedAt
        self.accessCount = accessCount
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case id, content, category, importance, metadata
        case projectId = "project_id"
        case sessionId = "session_id"
        case agentId = "agent_id"
        case createdAt = "created_at"
        case lastAccessedAt = "last_accessed_at"
        case accessCount = "access_count"
    }
}

/// Result from memory search, including similarity score.
public struct MemorySearchResult: Codable, Equatable, Sendable {
    public let id: UUID
    public let projectId: UUID
    public let content: String
    public let category: String
    public let importance: Double
    public let similarity: Double
    public let createdAt: Date
    public let metadata: [String: AnyCodable]

    public init(
        id: UUID,
        projectId: UUID,
        content: String,
        category: String,
        importance: Double,
        similarity: Double,
        createdAt: Date,
        metadata: [String: AnyCodable] = [:]
    ) {
        self.id = id
        self.projectId = projectId
        self.content = content
        self.category = category
        self.importance = importance
        self.similarity = similarity
        self.createdAt = createdAt
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case id, content, category, importance, similarity, metadata
        case projectId = "project_id"
        case createdAt = "created_at"
    }
}

/// Memory store response.
public struct MemoryStoreResponse: Codable, Equatable, Sendable {
    public let id: UUID

    public init(id: UUID) {
        self.id = id
    }
}

/// Memory source grouping from /api/memories/sources.
public struct MemorySourceDTO: Codable, Equatable, Sendable {
    public let sourceFile: String
    public let fileModifiedAt: String?
    public let lastBackedUp: Date
    public let chunkCount: Int
    public let avgImportance: Double

    enum CodingKeys: String, CodingKey {
        case sourceFile = "source_file"
        case fileModifiedAt = "file_modified_at"
        case lastBackedUp = "last_backed_up"
        case chunkCount = "chunk_count"
        case avgImportance = "avg_importance"
    }
}
