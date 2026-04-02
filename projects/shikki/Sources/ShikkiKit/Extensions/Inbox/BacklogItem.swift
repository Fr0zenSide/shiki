import Foundation

/// A backlog item in the Shikki curation pipeline.
///
/// Backlog items track ideas from raw input through enrichment to readiness.
/// State machine: raw -> enriched -> ready -> (task_queue via promotion)
/// Kill and defer are available from any non-terminal state.
public struct BacklogItem: Codable, Sendable, Identifiable {
    public let id: String
    public let companyId: String?
    public let title: String
    public let description: String?
    public let sourceType: SourceType
    public let sourceRef: String?
    public let status: Status
    public let priority: Int
    public let sortOrder: Int
    public let enrichmentNotes: String?
    public let killReason: String?
    public let tags: [String]
    public let parentId: String?
    public let promotedToTaskId: String?
    public let createdAt: String
    public let updatedAt: String
    public let metadata: [String: AnyCodable]

    // MARK: - Enums

    public enum Status: String, Codable, Sendable, CaseIterable {
        case raw, enriched, ready, deferred, killed
    }

    public enum SourceType: String, Codable, Sendable {
        case manual, push, flsh, conversation, agent
    }

    // MARK: - CodingKeys (snake_case mapping)

    enum CodingKeys: String, CodingKey {
        case id, title, description, status, priority, tags, metadata
        case companyId = "company_id"
        case sourceType = "source_type"
        case sourceRef = "source_ref"
        case sortOrder = "sort_order"
        case enrichmentNotes = "enrichment_notes"
        case killReason = "kill_reason"
        case parentId = "parent_id"
        case promotedToTaskId = "promoted_to_task_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    // MARK: - Custom Decoding

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        companyId = try container.decodeIfPresent(String.self, forKey: .companyId)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        sourceType = try container.decode(SourceType.self, forKey: .sourceType)
        sourceRef = try container.decodeIfPresent(String.self, forKey: .sourceRef)
        status = try container.decode(Status.self, forKey: .status)
        priority = try container.decode(Int.self, forKey: .priority)
        sortOrder = try container.decode(Int.self, forKey: .sortOrder)
        enrichmentNotes = try container.decodeIfPresent(String.self, forKey: .enrichmentNotes)
        killReason = try container.decodeIfPresent(String.self, forKey: .killReason)
        tags = (try? container.decode([String].self, forKey: .tags)) ?? []
        parentId = try container.decodeIfPresent(String.self, forKey: .parentId)
        promotedToTaskId = try container.decodeIfPresent(String.self, forKey: .promotedToTaskId)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
        metadata = (try? Self.decodePossiblyStringified([String: AnyCodable].self, from: container, forKey: .metadata)) ?? [:]
    }

    // MARK: - Memberwise init (for testing)

    public init(
        id: String,
        companyId: String? = nil,
        title: String,
        description: String? = nil,
        sourceType: SourceType = .manual,
        sourceRef: String? = nil,
        status: Status = .raw,
        priority: Int = 50,
        sortOrder: Int = 0,
        enrichmentNotes: String? = nil,
        killReason: String? = nil,
        tags: [String] = [],
        parentId: String? = nil,
        promotedToTaskId: String? = nil,
        createdAt: String = "2026-01-01T00:00:00Z",
        updatedAt: String = "2026-01-01T00:00:00Z",
        metadata: [String: AnyCodable] = [:]
    ) {
        self.id = id
        self.companyId = companyId
        self.title = title
        self.description = description
        self.sourceType = sourceType
        self.sourceRef = sourceRef
        self.status = status
        self.priority = priority
        self.sortOrder = sortOrder
        self.enrichmentNotes = enrichmentNotes
        self.killReason = killReason
        self.tags = tags
        self.parentId = parentId
        self.promotedToTaskId = promotedToTaskId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.metadata = metadata
    }

    // MARK: - JSON Helpers

    private static func decodePossiblyStringified<T: Decodable>(
        _ type: T.Type,
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> T {
        if let value = try? container.decode(T.self, forKey: key) {
            return value
        }
        let jsonString = try container.decode(String.self, forKey: key)
        guard let data = jsonString.data(using: .utf8) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "Invalid JSON string")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Sort

public enum BacklogSort: String, Sendable {
    case priority, age, manual
}

// MARK: - State Machine Validation

public extension BacklogItem.Status {
    /// Valid forward transitions per the curation lifecycle.
    var validTransitions: Set<BacklogItem.Status> {
        switch self {
        case .raw:
            return [.enriched, .ready, .deferred, .killed]
        case .enriched:
            return [.ready, .deferred, .killed]
        case .ready:
            return [.deferred, .killed]
        case .deferred:
            return [.enriched, .raw, .deferred, .killed]
        case .killed:
            return [] // Terminal state
        }
    }

    /// Whether a transition to the given status is allowed.
    func canTransition(to target: BacklogItem.Status) -> Bool {
        validTransitions.contains(target)
    }
}
