import Foundation

public struct OrchestratorStatus: Codable, Sendable {
    public let overview: Overview
    public let activeCompanies: [Company]
    public let pendingDecisions: [Decision]
    public let staleCompanies: [Company]
    public let packageLocks: [PackageLock]
    public let timestamp: String

    public struct Overview: Codable, Sendable {
        public let activeCompanies: Int
        public let totalPendingTasks: Int
        public let totalRunningTasks: Int
        public let totalBlockedTasks: Int
        public let totalPendingDecisions: Int
        public let t1PendingDecisions: Int
        public let todayTotalSpend: Double

        enum CodingKeys: String, CodingKey {
            case activeCompanies = "active_companies"
            case totalPendingTasks = "total_pending_tasks"
            case totalRunningTasks = "total_running_tasks"
            case totalBlockedTasks = "total_blocked_tasks"
            case totalPendingDecisions = "total_pending_decisions"
            case t1PendingDecisions = "t1_pending_decisions"
            case todayTotalSpend = "today_total_spend"
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            activeCompanies = try Self.decodeIntLike(from: container, forKey: .activeCompanies)
            totalPendingTasks = try Self.decodeIntLike(from: container, forKey: .totalPendingTasks)
            totalRunningTasks = try Self.decodeIntLike(from: container, forKey: .totalRunningTasks)
            totalBlockedTasks = try Self.decodeIntLike(from: container, forKey: .totalBlockedTasks)
            totalPendingDecisions = try Self.decodeIntLike(from: container, forKey: .totalPendingDecisions)
            t1PendingDecisions = try Self.decodeIntLike(from: container, forKey: .t1PendingDecisions)
            // Postgres returns numeric as string
            if let doubleVal = try? container.decode(Double.self, forKey: .todayTotalSpend) {
                todayTotalSpend = doubleVal
            } else {
                let stringVal = try container.decode(String.self, forKey: .todayTotalSpend)
                todayTotalSpend = Double(stringVal) ?? 0
            }
        }

        /// Postgres COUNT returns string in some drivers — handle both Int and String.
        private static func decodeIntLike(
            from container: KeyedDecodingContainer<CodingKeys>,
            forKey key: CodingKeys
        ) throws -> Int {
            if let intVal = try? container.decode(Int.self, forKey: key) {
                return intVal
            }
            let stringVal = try container.decode(String.self, forKey: key)
            return Int(stringVal) ?? 0
        }
    }
}

public struct PackageLock: Codable, Sendable {
    public let id: String
    public let companyId: String
    public let packageName: String
    public let claimedAt: String?
    public let status: String
    public let companySlug: String

    enum CodingKeys: String, CodingKey {
        case id, status
        case companyId = "company_id"
        case packageName = "package_name"
        case claimedAt = "claimed_at"
        case companySlug = "company_slug"
    }
}

public struct HeartbeatResponse: Codable, Sendable {
    public let budgetExceeded: Bool
    public let sessionId: String
    public let timestamp: String

    // company_status view fields
    public let id: String?
    public let slug: String?
    public let status: String?

    enum CodingKeys: String, CodingKey {
        case budgetExceeded = "budgetexceeded"
        case sessionId = "sessionid"
        case timestamp, id, slug, status
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Backend spreads company_status (snake_case) + camelCase fields
        // Try both casings for budget_exceeded
        if let val = try? container.decode(Bool.self, forKey: .budgetExceeded) {
            budgetExceeded = val
        } else {
            // Fallback: try as a dynamic key
            let dynamicContainer = try decoder.container(keyedBy: DynamicCodingKey.self)
            budgetExceeded = (try? dynamicContainer.decode(Bool.self, forKey: DynamicCodingKey(stringValue: "budgetExceeded")!)) ?? false
        }
        if let val = try? container.decode(String.self, forKey: .sessionId) {
            sessionId = val
        } else {
            let dynamicContainer = try decoder.container(keyedBy: DynamicCodingKey.self)
            sessionId = (try? dynamicContainer.decode(String.self, forKey: DynamicCodingKey(stringValue: "sessionId")!)) ?? ""
        }
        timestamp = (try? container.decode(String.self, forKey: .timestamp)) ?? ""
        id = try container.decodeIfPresent(String.self, forKey: .id)
        slug = try container.decodeIfPresent(String.self, forKey: .slug)
        status = try container.decodeIfPresent(String.self, forKey: .status)
    }
}

private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { self.intValue = intValue; self.stringValue = "\(intValue)" }
}
