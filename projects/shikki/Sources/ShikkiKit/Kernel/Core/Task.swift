import Foundation

public struct OrchestratorTask: Codable, Sendable {
    public let id: String
    public let companyId: String
    public let parentId: String?
    public let title: String
    public let description: String?
    public let source: TaskSource
    public let status: TaskStatus
    public let claimedBy: String?
    public let claimedAt: String?
    public let priority: Int
    public let blockingQuestionIds: [String]
    public let result: [String: AnyCodable]?
    public let projectPath: String?
    public let pipelineRunId: String?
    public let createdAt: String
    public let updatedAt: String
    public let metadata: [String: AnyCodable]

    public enum TaskSource: String, Codable, Sendable {
        case backlog, autopilot, manual
        case crossCompany = "cross_company"
    }

    public enum TaskStatus: String, Codable, Sendable {
        case pending, claimed, running, blocked, completed, failed, cancelled
    }

    enum CodingKeys: String, CodingKey {
        case id, title, description, source, status, priority, result, metadata
        case companyId = "company_id"
        case parentId = "parent_id"
        case claimedBy = "claimed_by"
        case claimedAt = "claimed_at"
        case blockingQuestionIds = "blocking_question_ids"
        case projectPath = "project_path"
        case pipelineRunId = "pipeline_run_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        companyId = try container.decode(String.self, forKey: .companyId)
        parentId = try container.decodeIfPresent(String.self, forKey: .parentId)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        source = try container.decode(TaskSource.self, forKey: .source)
        status = try container.decode(TaskStatus.self, forKey: .status)
        claimedBy = try container.decodeIfPresent(String.self, forKey: .claimedBy)
        claimedAt = try container.decodeIfPresent(String.self, forKey: .claimedAt)
        priority = try container.decode(Int.self, forKey: .priority)
        blockingQuestionIds = (try? container.decode([String].self, forKey: .blockingQuestionIds)) ?? []
        result = try? Self.decodePossiblyStringified([String: AnyCodable]?.self, from: container, forKey: .result)
        projectPath = try container.decodeIfPresent(String.self, forKey: .projectPath)
        pipelineRunId = try container.decodeIfPresent(String.self, forKey: .pipelineRunId)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
        metadata = (try? Self.decodePossiblyStringified([String: AnyCodable].self, from: container, forKey: .metadata)) ?? [:]
    }

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
