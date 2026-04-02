import Foundation

/// Lightweight model for the `dispatcher_queue` SQL view.
///
/// Each row represents a pending task joined with its company's priority, budget,
/// schedule, and today's spend. The view is ordered by `(company_priority, task_priority, created_at)`
/// so the heartbeat loop can iterate top-down and dispatch the highest-value work first.
///
/// Budget and schedule fields come from the parent company; `spentToday` is aggregated
/// from `company_budget_log` for the current UTC day.
public struct DispatcherTask: Codable, Sendable {
    /// UUID of the task in `task_queue`.
    public let taskId: String
    /// Human-readable task title (also used to derive the tmux window name).
    public let title: String
    /// Task-level priority (lower = higher priority).
    public let taskPriority: Int
    /// Relative path under `projects/` where Claude should work. `nil` falls back to company config.
    public let projectPath: String?
    /// Always `"pending"` (the view filters on this).
    public let status: String
    /// UUID of the owning company.
    public let companyId: String
    /// URL-safe company identifier used in tmux window names and logs.
    public let companySlug: String
    /// Company-level priority (lower = higher priority).
    public let companyPriority: Int
    /// Company's budget caps (daily + monthly).
    public let budget: Company.Budget
    /// Company's active-hours window and timezone.
    public let schedule: Company.Schedule
    /// Dollars already spent by this company today (aggregated from `company_budget_log`).
    public let spentToday: Double

    /// Tmux window name for this task: `"{companySlug}:{task-title-truncated}"`.
    /// Used by the launcher to check for duplicate sessions and by cleanup to match running panes.
    public var sessionSlug: String {
        let short = String(title.prefix(15))
            .replacingOccurrences(of: " ", with: "-")
            .lowercased()
        return "\(companySlug):\(short)"
    }

    enum CodingKeys: String, CodingKey {
        case title, status, budget, schedule
        case taskId = "task_id"
        case taskPriority = "task_priority"
        case projectPath = "project_path"
        case companyId = "company_id"
        case companySlug = "company_slug"
        case companyPriority = "company_priority"
        case spentToday = "spent_today"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        taskId = try container.decode(String.self, forKey: .taskId)
        title = try container.decode(String.self, forKey: .title)
        taskPriority = try container.decode(Int.self, forKey: .taskPriority)
        projectPath = try container.decodeIfPresent(String.self, forKey: .projectPath)
        status = try container.decode(String.self, forKey: .status)
        companyId = try container.decode(String.self, forKey: .companyId)
        companySlug = try container.decode(String.self, forKey: .companySlug)
        companyPriority = try container.decode(Int.self, forKey: .companyPriority)
        budget = try Self.decodePossiblyStringified(Company.Budget.self, from: container, forKey: .budget)
        schedule = try Self.decodePossiblyStringified(Company.Schedule.self, from: container, forKey: .schedule)

        // spent_today comes as numeric from Postgres — handle both Double and String
        if let doubleVal = try? container.decode(Double.self, forKey: .spentToday) {
            spentToday = doubleVal
        } else {
            let stringVal = try container.decode(String.self, forKey: .spentToday)
            spentToday = Double(stringVal) ?? 0
        }
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
