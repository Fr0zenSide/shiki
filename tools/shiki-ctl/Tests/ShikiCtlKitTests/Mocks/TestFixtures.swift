import Foundation
@testable import ShikiCtlKit

/// JSON-based test factories for models that only have `init(from decoder:)`.
enum TestFixtures {

    private static let decoder = JSONDecoder()

    // MARK: - DispatcherTask

    static func dispatcherTask(
        taskId: String = "task-1",
        title: String = "Fix tests",
        companyId: String = "company-1",
        companySlug: String = "wabisabi",
        projectPath: String? = "wabisabi",
        spentToday: Double = 0.0,
        dailyBudget: Double = 10.0,
        monthlyBudget: Double = 300.0,
        activeHours: [Int] = [0, 24],
        timezone: String = "UTC",
        days: [Int] = [1, 2, 3, 4, 5, 6, 7]
    ) -> DispatcherTask {
        let projectPathJSON = projectPath.map { "\"\($0)\"" } ?? "null"
        let json = """
        {
            "task_id": "\(taskId)",
            "title": "\(title)",
            "task_priority": 1,
            "project_path": \(projectPathJSON),
            "status": "pending",
            "company_id": "\(companyId)",
            "company_slug": "\(companySlug)",
            "company_priority": 1,
            "budget": {"daily_usd": \(dailyBudget), "monthly_usd": \(monthlyBudget), "spent_today_usd": 0},
            "schedule": {"active_hours": \(activeHours), "timezone": "\(timezone)", "days": \(days)},
            "spent_today": \(spentToday)
        }
        """
        return try! decoder.decode(DispatcherTask.self, from: json.data(using: .utf8)!)
    }

    // MARK: - Decision

    static func decision(
        id: String = "dec-1",
        companyId: String = "company-1",
        tier: Int = 1,
        question: String = "Should we add caching?",
        companySlug: String? = "wabisabi",
        answered: Bool = false
    ) -> Decision {
        let slugJSON = companySlug.map { "\"\($0)\"" } ?? "null"
        let json = """
        {
            "id": "\(id)",
            "company_id": "\(companyId)",
            "tier": \(tier),
            "question": "\(question)",
            "options": null,
            "answered": \(answered),
            "created_at": "2026-03-23T10:00:00Z",
            "metadata": {},
            "company_slug": \(slugJSON)
        }
        """
        return try! decoder.decode(Decision.self, from: json.data(using: .utf8)!)
    }

    // MARK: - Company

    static func company(
        id: String = "company-1",
        slug: String = "wabisabi",
        displayName: String = "WabiSabi",
        status: String = "active",
        projectPath: String? = nil
    ) -> Company {
        var config = "{}"
        if let path = projectPath {
            config = "{\"project_path\": \"\(path)\"}"
        }
        let json = """
        {
            "id": "\(id)",
            "project_id": "proj-1",
            "slug": "\(slug)",
            "display_name": "\(displayName)",
            "status": "\(status)",
            "priority": 1,
            "budget": {"daily_usd": 10.0, "monthly_usd": 300.0, "spent_today_usd": 0},
            "schedule": {"active_hours": [0, 24], "timezone": "UTC", "days": [1,2,3,4,5,6,7]},
            "config": \(config),
            "created_at": "2026-01-01T00:00:00Z",
            "updated_at": "2026-03-23T10:00:00Z",
            "company_projects": []
        }
        """
        return try! decoder.decode(Company.self, from: json.data(using: .utf8)!)
    }

    // MARK: - OrchestratorStatus

    static func orchestratorStatus(
        activeCompanySlugs: [String] = []
    ) -> OrchestratorStatus {
        let companiesJSON = activeCompanySlugs.map { slug in
            """
            {
                "id": "id-\(slug)",
                "project_id": "proj-1",
                "slug": "\(slug)",
                "display_name": "\(slug)",
                "status": "active",
                "priority": 1,
                "budget": {"daily_usd": 10.0, "monthly_usd": 300.0, "spent_today_usd": 0},
                "schedule": {"active_hours": [0, 24], "timezone": "UTC", "days": [1,2,3,4,5,6,7]},
                "config": {},
                "created_at": "2026-01-01T00:00:00Z",
                "updated_at": "2026-03-23T10:00:00Z",
                "company_projects": []
            }
            """
        }.joined(separator: ",")

        let json = """
        {
            "overview": {
                "active_companies": \(activeCompanySlugs.count),
                "total_pending_tasks": 0,
                "total_running_tasks": 0,
                "total_blocked_tasks": 0,
                "total_pending_decisions": 0,
                "t1_pending_decisions": 0,
                "today_total_spend": 0.0
            },
            "activeCompanies": [\(companiesJSON)],
            "pendingDecisions": [],
            "staleCompanies": [],
            "packageLocks": [],
            "timestamp": "2026-03-23T10:00:00Z"
        }
        """
        return try! decoder.decode(OrchestratorStatus.self, from: json.data(using: .utf8)!)
    }

    // MARK: - SessionTranscript

    static func sessionTranscript(
        id: String = "transcript-1",
        companyId: String = "company-1",
        sessionId: String = "sess-1",
        companySlug: String = "wabisabi"
    ) -> SessionTranscript {
        let json = """
        {
            "id": "\(id)",
            "company_id": "\(companyId)",
            "session_id": "\(sessionId)",
            "company_slug": "\(companySlug)",
            "task_title": "Test task",
            "phase": "completed",
            "compaction_count": 0,
            "created_at": "2026-03-23T10:00:00Z",
            "updated_at": "2026-03-23T10:00:00Z"
        }
        """
        return try! decoder.decode(SessionTranscript.self, from: json.data(using: .utf8)!)
    }
}
