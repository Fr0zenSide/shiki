import Foundation

/// A single row from the `board_overview` SQL view.
///
/// Contains company status, task counts, budget, health, last session summary,
/// and project count — everything needed for the `shiki board` display.
public struct BoardEntry: Codable, Sendable {
    public let companyId: String
    public let companySlug: String
    public let displayName: String
    public let companyStatus: String
    public let priority: Int
    public let budget: Company.Budget
    public let schedule: Company.Schedule
    public let lastHeartbeatAt: String?

    public let pendingTasks: Int
    public let runningTasks: Int
    public let blockedTasks: Int
    public let completedTasks: Int
    public let failedTasks: Int
    public let totalTasks: Int

    public let spentToday: Double
    public let heartbeatStatus: String

    public let lastSessionSummary: String?
    public let lastSessionPhase: String?
    public let lastSessionAt: String?
    public let pendingDecisions: Int
    public let projectCount: Int

    enum CodingKeys: String, CodingKey {
        case budget, schedule, priority
        case companyId = "company_id"
        case companySlug = "company_slug"
        case displayName = "display_name"
        case companyStatus = "company_status"
        case lastHeartbeatAt = "last_heartbeat_at"
        case pendingTasks = "pending_tasks"
        case runningTasks = "running_tasks"
        case blockedTasks = "blocked_tasks"
        case completedTasks = "completed_tasks"
        case failedTasks = "failed_tasks"
        case totalTasks = "total_tasks"
        case spentToday = "spent_today"
        case heartbeatStatus = "heartbeat_status"
        case lastSessionSummary = "last_session_summary"
        case lastSessionPhase = "last_session_phase"
        case lastSessionAt = "last_session_at"
        case pendingDecisions = "pending_decisions"
        case projectCount = "project_count"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        companyId = try container.decode(String.self, forKey: .companyId)
        companySlug = try container.decode(String.self, forKey: .companySlug)
        displayName = try container.decode(String.self, forKey: .displayName)
        companyStatus = try container.decode(String.self, forKey: .companyStatus)
        priority = try container.decode(Int.self, forKey: .priority)
        budget = try Self.decodePossiblyStringified(Company.Budget.self, from: container, forKey: .budget)
        schedule = try Self.decodePossiblyStringified(Company.Schedule.self, from: container, forKey: .schedule)
        lastHeartbeatAt = try container.decodeIfPresent(String.self, forKey: .lastHeartbeatAt)

        pendingTasks = try Self.intOrString(from: container, forKey: .pendingTasks)
        runningTasks = try Self.intOrString(from: container, forKey: .runningTasks)
        blockedTasks = try Self.intOrString(from: container, forKey: .blockedTasks)
        completedTasks = try Self.intOrString(from: container, forKey: .completedTasks)
        failedTasks = try Self.intOrString(from: container, forKey: .failedTasks)
        totalTasks = try Self.intOrString(from: container, forKey: .totalTasks)

        if let d = try? container.decode(Double.self, forKey: .spentToday) {
            spentToday = d
        } else {
            spentToday = Double(try container.decode(String.self, forKey: .spentToday)) ?? 0
        }

        heartbeatStatus = try container.decode(String.self, forKey: .heartbeatStatus)
        lastSessionSummary = try container.decodeIfPresent(String.self, forKey: .lastSessionSummary)
        lastSessionPhase = try container.decodeIfPresent(String.self, forKey: .lastSessionPhase)
        lastSessionAt = try container.decodeIfPresent(String.self, forKey: .lastSessionAt)
        pendingDecisions = try Self.intOrString(from: container, forKey: .pendingDecisions)
        projectCount = try Self.intOrString(from: container, forKey: .projectCount)
    }

    private static func intOrString(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Int {
        if let v = try? container.decode(Int.self, forKey: key) { return v }
        if let s = try? container.decode(String.self, forKey: key) { return Int(s) ?? 0 }
        return 0
    }

    private static func decodePossiblyStringified<T: Decodable>(
        _ type: T.Type, from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys
    ) throws -> T {
        if let value = try? container.decode(T.self, forKey: key) { return value }
        let jsonString = try container.decode(String.self, forKey: key)
        guard let data = jsonString.data(using: .utf8) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "Invalid JSON string")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
