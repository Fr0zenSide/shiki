import Foundation

/// Kind of radar watch item (maps to RadarWatchItemSchema.kind).
public enum RadarWatchKind: String, Codable, Sendable {
    case repo
    case dependency
    case technology
}

/// Input for adding a radar watchlist item (maps to RadarWatchItemSchema).
public struct RadarWatchItemInput: Codable, Equatable, Sendable, Validatable {
    public let slug: String
    public let kind: RadarWatchKind
    public let name: String
    public let sourceUrl: String?
    public let relevance: String?
    public let tags: [String]
    public let metadata: [String: AnyCodable]

    public init(
        slug: String,
        kind: RadarWatchKind,
        name: String,
        sourceUrl: String? = nil,
        relevance: String? = nil,
        tags: [String] = [],
        metadata: [String: AnyCodable] = [:]
    ) {
        self.slug = slug
        self.kind = kind
        self.name = name
        self.sourceUrl = sourceUrl
        self.relevance = relevance
        self.tags = tags
        self.metadata = metadata
    }

    public func validate() throws {
        try Validators.requireNonEmpty(slug, field: "slug")
        try Validators.requireNonEmpty(name, field: "name")
    }

    enum CodingKeys: String, CodingKey {
        case slug, kind, name, relevance, tags, metadata
        case sourceUrl = "source_url"
    }
}

/// Radar watchlist item as stored in the database.
public struct RadarWatchItemDTO: Codable, Equatable, Sendable {
    public let id: UUID
    public let slug: String
    public let kind: RadarWatchKind
    public let name: String
    public let sourceUrl: String?
    public let relevance: String?
    public let tags: [String]
    public let enabled: Bool
    public let metadata: [String: AnyCodable]
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: UUID,
        slug: String,
        kind: RadarWatchKind,
        name: String,
        sourceUrl: String? = nil,
        relevance: String? = nil,
        tags: [String] = [],
        enabled: Bool = true,
        metadata: [String: AnyCodable] = [:],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.slug = slug
        self.kind = kind
        self.name = name
        self.sourceUrl = sourceUrl
        self.relevance = relevance
        self.tags = tags
        self.enabled = enabled
        self.metadata = metadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, slug, kind, name, relevance, tags, enabled, metadata
        case sourceUrl = "source_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Input for triggering a radar scan (maps to RadarScanTriggerSchema).
public struct RadarScanTriggerInput: Codable, Equatable, Sendable, Validatable {
    public let itemIds: [UUID]?
    public let sinceDays: Int

    public init(itemIds: [UUID]? = nil, sinceDays: Int = 30) {
        self.itemIds = itemIds
        self.sinceDays = sinceDays
    }

    public func validate() throws {
        if sinceDays < 1 || sinceDays > 365 {
            throw ShikkiValidationError.fieldOutOfRange("sinceDays", min: 1, max: 365)
        }
    }

    enum CodingKeys: String, CodingKey {
        case itemIds = "item_ids"
        case sinceDays = "since_days"
    }
}

/// Input for ingesting radar digest into memories.
public struct RadarIngestInput: Codable, Equatable, Sendable {
    public let scanRunId: UUID
    public let projectId: UUID

    public init(scanRunId: UUID, projectId: UUID) {
        self.scanRunId = scanRunId
        self.projectId = projectId
    }

    enum CodingKeys: String, CodingKey {
        case scanRunId = "scan_run_id"
        case projectId = "project_id"
    }
}

/// Response from POST /api/radar/scan.
public struct RadarScanResponse: Codable, Equatable, Sendable {
    public let scanRunId: UUID
    public let status: String

    public init(scanRunId: UUID, status: String = "started") {
        self.scanRunId = scanRunId
        self.status = status
    }

    enum CodingKeys: String, CodingKey {
        case status
        case scanRunId = "scan_run_id"
    }
}

/// Response from POST /api/radar/ingest.
public struct RadarIngestResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let memoriesCreated: Int

    public init(ok: Bool = true, memoriesCreated: Int) {
        self.ok = ok
        self.memoriesCreated = memoriesCreated
    }

    enum CodingKeys: String, CodingKey {
        case ok
        case memoriesCreated = "memories_created"
    }
}
