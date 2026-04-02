import Foundation

// MARK: - Time Range

/// Time range for report queries.
public enum ReportTimeRange: Sendable {
    case daily
    case weekly
    case sprint
    case custom(start: Date, end: Date)

    /// Compute the date range (start, end) relative to the current moment.
    public func resolve(now: Date = Date()) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        switch self {
        case .daily:
            let start = calendar.startOfDay(for: now)
            return (start, now)
        case .weekly:
            let start = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now))!
            return (start, now)
        case .sprint:
            let start = calendar.date(byAdding: .day, value: -14, to: calendar.startOfDay(for: now))!
            return (start, now)
        case .custom(let start, let end):
            return (start, end)
        }
    }
}

// MARK: - Scope

/// Scoping for report data. Company data stays in company scope (BR-P-03).
public enum ReportScope: Sendable, Equatable {
    case workspace      // all companies
    case company(String)  // single company slug
    case project(String)  // single project slug
}

// MARK: - Report

/// Aggregated report data. This is the output of ReportAggregator.
public struct Report: Codable, Sendable, Equatable {
    public let timeRange: ReportDateRange
    public let scope: String  // "workspace", "company:maya", "project:wabisabi"
    public let companies: [CompanyMetrics]
    public let totals: Totals
    public let blocked: [BlockedItem]
    public let pendingDecisions: Int
    public let sessions: SessionMetrics
    public let compactions: Int

    public init(
        timeRange: ReportDateRange,
        scope: String,
        companies: [CompanyMetrics],
        totals: Totals,
        blocked: [BlockedItem],
        pendingDecisions: Int,
        sessions: SessionMetrics,
        compactions: Int
    ) {
        self.timeRange = timeRange
        self.scope = scope
        self.companies = companies
        self.totals = totals
        self.blocked = blocked
        self.pendingDecisions = pendingDecisions
        self.sessions = sessions
        self.compactions = compactions
    }
}

// MARK: - Sub-models

public struct ReportDateRange: Codable, Sendable, Equatable {
    public let start: String  // ISO 8601
    public let end: String
    public let label: String  // "daily", "weekly", "sprint", "custom"

    public init(start: String, end: String, label: String) {
        self.start = start
        self.end = end
        self.label = label
    }
}

public struct CompanyMetrics: Codable, Sendable, Equatable {
    public let slug: String
    public let displayName: String
    public let tasksCompleted: Int
    public let tasksTotal: Int
    public let tasksFailed: Int
    public let prsMerged: Int
    public let locAdded: Int
    public let locDeleted: Int
    public let budgetSpent: Double
    public let agentCount: Int
    public let avgContextPct: Int

    public init(
        slug: String, displayName: String,
        tasksCompleted: Int, tasksTotal: Int, tasksFailed: Int,
        prsMerged: Int, locAdded: Int, locDeleted: Int,
        budgetSpent: Double, agentCount: Int, avgContextPct: Int
    ) {
        self.slug = slug
        self.displayName = displayName
        self.tasksCompleted = tasksCompleted
        self.tasksTotal = tasksTotal
        self.tasksFailed = tasksFailed
        self.prsMerged = prsMerged
        self.locAdded = locAdded
        self.locDeleted = locDeleted
        self.budgetSpent = budgetSpent
        self.agentCount = agentCount
        self.avgContextPct = avgContextPct
    }
}

public struct Totals: Codable, Sendable, Equatable {
    public let tasksCompleted: Int
    public let tasksTotal: Int
    public let tasksFailed: Int
    public let prsMerged: Int
    public let locAdded: Int
    public let locDeleted: Int
    public let budgetSpent: Double
    public let agentCount: Int

    public init(
        tasksCompleted: Int, tasksTotal: Int, tasksFailed: Int,
        prsMerged: Int, locAdded: Int, locDeleted: Int,
        budgetSpent: Double, agentCount: Int
    ) {
        self.tasksCompleted = tasksCompleted
        self.tasksTotal = tasksTotal
        self.tasksFailed = tasksFailed
        self.prsMerged = prsMerged
        self.locAdded = locAdded
        self.locDeleted = locDeleted
        self.budgetSpent = budgetSpent
        self.agentCount = agentCount
    }
}

public struct BlockedItem: Codable, Sendable, Equatable {
    public let companySlug: String
    public let title: String
    public let taskId: String
    public let reason: String?

    public init(companySlug: String, title: String, taskId: String, reason: String?) {
        self.companySlug = companySlug
        self.title = title
        self.taskId = taskId
        self.reason = reason
    }
}

public struct SessionMetrics: Codable, Sendable, Equatable {
    public let count: Int
    public let totalDurationMinutes: Int

    public init(count: Int, totalDurationMinutes: Int) {
        self.count = count
        self.totalDurationMinutes = totalDurationMinutes
    }
}

// MARK: - Backend Range Report Response

/// Response from `/api/orchestrator/report/range` endpoint.
public struct RangeReportResponse: Codable, Sendable {
    public let tasks: TaskStats
    public let decisions: DecisionStats
    public let budget: BudgetStats
    public let prs: PRStats
    public let sessions: SessionStats
    public let agents: AgentStats

    public struct TaskStats: Codable, Sendable {
        public let completed: Int
        public let failed: Int
        public let blocked: Int
        public let total: Int
    }

    public struct DecisionStats: Codable, Sendable {
        public let asked: Int
        public let answered: Int
        public let pending: Int
    }

    public struct BudgetStats: Codable, Sendable {
        public let spent: Double
        public let dailyAvg: Double

        enum CodingKeys: String, CodingKey {
            case spent
            case dailyAvg = "daily_avg"
        }
    }

    public struct PRStats: Codable, Sendable {
        public let created: Int
        public let merged: Int
    }

    public struct SessionStats: Codable, Sendable {
        public let count: Int
        public let totalDurationMinutes: Int

        enum CodingKeys: String, CodingKey {
            case count
            case totalDurationMinutes = "total_duration_minutes"
        }
    }

    public struct AgentStats: Codable, Sendable {
        public let dispatched: Int
        public let completed: Int
        public let failed: Int
        public let avgContextPct: Int
        public let totalCompactions: Int

        enum CodingKeys: String, CodingKey {
            case dispatched, completed, failed
            case avgContextPct = "avg_context_pct"
            case totalCompactions = "total_compactions"
        }
    }
}
