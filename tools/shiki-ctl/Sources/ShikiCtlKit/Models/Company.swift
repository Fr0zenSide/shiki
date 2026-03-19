import Foundation

public struct Company: Codable, Sendable {
    public let id: String
    public let projectId: String
    public let slug: String
    public let displayName: String
    public let status: CompanyStatus
    public let priority: Int
    public let budget: Budget
    public let schedule: Schedule
    public let config: [String: AnyCodable]
    public let lastHeartbeatAt: String?
    public let createdAt: String
    public let updatedAt: String

    // Joined fields (from views)
    public let projectSlug: String?
    public let pendingTasks: Int?
    public let runningTasks: Int?
    public let blockedTasks: Int?
    public let completedTasks: Int?
    public let pendingDecisions: Int?
    public let heartbeatStatus: String?
    public let pendingCount: Int?
    public let companyProjects: [CompanyProject]

    public enum CompanyStatus: String, Codable, Sendable {
        case active, paused, archived
    }

    public struct Budget: Codable, Sendable {
        public let dailyUsd: Double
        public let monthlyUsd: Double
        public let spentTodayUsd: Double

        enum CodingKeys: String, CodingKey {
            case dailyUsd = "daily_usd"
            case monthlyUsd = "monthly_usd"
            case spentTodayUsd = "spent_today_usd"
        }
    }

    public struct Schedule: Codable, Sendable {
        public let activeHours: [Int]
        public let timezone: String
        public let days: [Int]

        enum CodingKeys: String, CodingKey {
            case activeHours = "active_hours"
            case timezone
            case days
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, slug, status, priority, budget, schedule, config
        case projectId = "project_id"
        case displayName = "display_name"
        case lastHeartbeatAt = "last_heartbeat_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case projectSlug = "project_slug"
        case pendingTasks = "pending_tasks"
        case runningTasks = "running_tasks"
        case blockedTasks = "blocked_tasks"
        case completedTasks = "completed_tasks"
        case pendingDecisions = "pending_decisions"
        case heartbeatStatus = "heartbeat_status"
        case pendingCount = "pending_count"
        case companyProjects = "company_projects"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        projectId = try container.decode(String.self, forKey: .projectId)
        slug = try container.decode(String.self, forKey: .slug)
        displayName = try container.decode(String.self, forKey: .displayName)
        status = try container.decode(CompanyStatus.self, forKey: .status)
        priority = try container.decode(Int.self, forKey: .priority)
        budget = try Company.decodePossiblyStringified(Budget.self, from: container, forKey: .budget)
        schedule = try Company.decodePossiblyStringified(Schedule.self, from: container, forKey: .schedule)
        config = (try? Company.decodePossiblyStringified([String: AnyCodable].self, from: container, forKey: .config)) ?? [:]
        lastHeartbeatAt = try container.decodeIfPresent(String.self, forKey: .lastHeartbeatAt)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
        projectSlug = try container.decodeIfPresent(String.self, forKey: .projectSlug)
        pendingTasks = try Self.decodeIntOrString(from: container, forKey: .pendingTasks)
        runningTasks = try Self.decodeIntOrString(from: container, forKey: .runningTasks)
        blockedTasks = try Self.decodeIntOrString(from: container, forKey: .blockedTasks)
        completedTasks = try Self.decodeIntOrString(from: container, forKey: .completedTasks)
        pendingDecisions = try Self.decodeIntOrString(from: container, forKey: .pendingDecisions)
        heartbeatStatus = try container.decodeIfPresent(String.self, forKey: .heartbeatStatus)
        pendingCount = try Self.decodeIntOrString(from: container, forKey: .pendingCount)
        companyProjects = (try? Self.decodePossiblyStringified([CompanyProject].self, from: container, forKey: .companyProjects)) ?? []
    }

    /// Postgres COUNT returns string in some drivers — handle both Int and String.
    private static func decodeIntOrString(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> Int? {
        if let v = try? container.decode(Int.self, forKey: key) { return v }
        if let s = try? container.decode(String.self, forKey: key) { return Int(s) }
        return nil
    }

    /// Postgres JSONB fields may come as objects or as stringified JSON — handle both.
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
