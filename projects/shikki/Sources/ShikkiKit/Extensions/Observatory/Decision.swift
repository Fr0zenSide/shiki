import Foundation

public struct Decision: Codable, Sendable {
    public let id: String
    public let companyId: String
    public let taskId: String?
    public let pipelineRunId: String?
    public let tier: Int
    public let question: String
    public let options: [String: AnyCodable]?
    public let context: String?
    public let answered: Bool
    public let answer: String?
    public let answeredBy: String?
    public let answeredAt: String?
    public let createdAt: String
    public let metadata: [String: AnyCodable]

    // Joined fields (from getPendingDecisions)
    public let companySlug: String?
    public let companyName: String?

    enum CodingKeys: String, CodingKey {
        case id, tier, question, options, context, answered, answer, metadata
        case companyId = "company_id"
        case taskId = "task_id"
        case pipelineRunId = "pipeline_run_id"
        case answeredBy = "answered_by"
        case answeredAt = "answered_at"
        case createdAt = "created_at"
        case companySlug = "company_slug"
        case companyName = "company_name"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        companyId = try container.decode(String.self, forKey: .companyId)
        taskId = try container.decodeIfPresent(String.self, forKey: .taskId)
        pipelineRunId = try container.decodeIfPresent(String.self, forKey: .pipelineRunId)
        tier = try container.decode(Int.self, forKey: .tier)
        question = try container.decode(String.self, forKey: .question)
        options = try Self.decodePossiblyStringified([String: AnyCodable]?.self, from: container, forKey: .options)
        context = try container.decodeIfPresent(String.self, forKey: .context)
        answered = try container.decode(Bool.self, forKey: .answered)
        answer = try container.decodeIfPresent(String.self, forKey: .answer)
        answeredBy = try container.decodeIfPresent(String.self, forKey: .answeredBy)
        answeredAt = try container.decodeIfPresent(String.self, forKey: .answeredAt)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        metadata = (try? Self.decodePossiblyStringified([String: AnyCodable].self, from: container, forKey: .metadata)) ?? [:]
        companySlug = try container.decodeIfPresent(String.self, forKey: .companySlug)
        companyName = try container.decodeIfPresent(String.self, forKey: .companyName)
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
