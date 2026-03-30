import Foundation
import Testing
@testable import ShikkiKit

@Suite("BackendClient response parsing")
struct BackendClientTests {

    @Test("Decode company from snake_case JSON")
    func decodeCompany() throws {
        let json = """
        {
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "project_id": "660e8400-e29b-41d4-a716-446655440001",
            "slug": "wabisabi",
            "display_name": "WabiSabi",
            "status": "active",
            "priority": 3,
            "budget": {"daily_usd": 8, "monthly_usd": 200, "spent_today_usd": 2.5},
            "schedule": {"active_hours": [8, 22], "timezone": "Europe/Paris", "days": [1,2,3,4,5,6,7]},
            "config": {"project_path": "wabisabi"},
            "last_heartbeat_at": "2026-03-15T10:00:00Z",
            "created_at": "2026-03-01T00:00:00Z",
            "updated_at": "2026-03-15T10:00:00Z"
        }
        """.data(using: .utf8)!

        let company = try JSONDecoder().decode(Company.self, from: json)
        #expect(company.slug == "wabisabi")
        #expect(company.displayName == "WabiSabi")
        #expect(company.status == .active)
        #expect(company.priority == 3)
        #expect(company.budget.dailyUsd == 8)
        #expect(company.budget.spentTodayUsd == 2.5)
        #expect(company.schedule.activeHours == [8, 22])
        #expect(company.schedule.timezone == "Europe/Paris")
        #expect(company.schedule.days == [1, 2, 3, 4, 5, 6, 7])
    }

    @Test("Decode company with stringified JSONB fields")
    func decodeCompanyStringifiedJSON() throws {
        let json = """
        {
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "project_id": "660e8400-e29b-41d4-a716-446655440001",
            "slug": "maya",
            "display_name": "Maya",
            "status": "paused",
            "priority": 5,
            "budget": "{\\"daily_usd\\": 5, \\"monthly_usd\\": 150, \\"spent_today_usd\\": 0}",
            "schedule": "{\\"active_hours\\": [9, 20], \\"timezone\\": \\"Europe/Paris\\", \\"days\\": [1,2,3,4,5]}",
            "config": "{}",
            "last_heartbeat_at": null,
            "created_at": "2026-03-01T00:00:00Z",
            "updated_at": "2026-03-01T00:00:00Z"
        }
        """.data(using: .utf8)!

        let company = try JSONDecoder().decode(Company.self, from: json)
        #expect(company.slug == "maya")
        #expect(company.status == .paused)
        #expect(company.budget.dailyUsd == 5)
        #expect(company.schedule.activeHours == [9, 20])
        #expect(company.lastHeartbeatAt == nil)
    }

    @Test("Decode orchestrator overview with string counts")
    func decodeOverviewStringCounts() throws {
        let json = """
        {
            "active_companies": "3",
            "total_pending_tasks": "12",
            "total_running_tasks": "2",
            "total_blocked_tasks": "1",
            "total_pending_decisions": "4",
            "t1_pending_decisions": "2",
            "today_total_spend": "15.50"
        }
        """.data(using: .utf8)!

        let overview = try JSONDecoder().decode(OrchestratorStatus.Overview.self, from: json)
        #expect(overview.activeCompanies == 3)
        #expect(overview.totalPendingTasks == 12)
        #expect(overview.totalRunningTasks == 2)
        #expect(overview.totalBlockedTasks == 1)
        #expect(overview.totalPendingDecisions == 4)
        #expect(overview.t1PendingDecisions == 2)
        #expect(overview.todayTotalSpend == 15.5)
    }

    @Test("Decode decision with joined fields")
    func decodeDecision() throws {
        let json = """
        {
            "id": "abc-123",
            "company_id": "comp-1",
            "task_id": "task-1",
            "pipeline_run_id": null,
            "tier": 1,
            "question": "Should we use actor or class for BackendClient?",
            "options": {"a": "actor (thread-safe)", "b": "class (simpler)"},
            "context": "Performance vs safety tradeoff",
            "answered": false,
            "answer": null,
            "answered_by": null,
            "answered_at": null,
            "created_at": "2026-03-15T10:00:00Z",
            "metadata": {},
            "company_slug": "wabisabi",
            "company_name": "WabiSabi"
        }
        """.data(using: .utf8)!

        let decision = try JSONDecoder().decode(Decision.self, from: json)
        #expect(decision.tier == 1)
        #expect(decision.companySlug == "wabisabi")
        #expect(decision.answered == false)
        #expect(decision.options?["a"]?.description == "actor (thread-safe)")
    }

    @Test("Decode daily report")
    func decodeDailyReport() throws {
        let json = """
        {
            "date": "2026-03-15",
            "perCompany": [
                {
                    "slug": "wabisabi",
                    "display_name": "WabiSabi",
                    "tasks_completed": "3",
                    "tasks_failed": "0",
                    "decisions_asked": "2",
                    "decisions_answered": "1",
                    "spend_usd": "4.20"
                }
            ],
            "blocked": [],
            "prsCreated": []
        }
        """.data(using: .utf8)!

        let report = try JSONDecoder().decode(DailyReport.self, from: json)
        #expect(report.date == "2026-03-15")
        #expect(report.perCompany.count == 1)
        #expect(report.perCompany[0].tasksCompleted == 3)
        #expect(report.perCompany[0].spendUsd == 4.2)
    }

    @Test("Decode task with project_path")
    func decodeTask() throws {
        let json = """
        {
            "id": "task-1",
            "company_id": "comp-1",
            "parent_id": null,
            "title": "SPM migration wave 1",
            "description": "Extract shared packages",
            "source": "backlog",
            "status": "pending",
            "claimed_by": null,
            "claimed_at": null,
            "priority": 3,
            "blocking_question_ids": [],
            "result": null,
            "project_path": "wabisabi",
            "pipeline_run_id": null,
            "created_at": "2026-03-15T10:00:00Z",
            "updated_at": "2026-03-15T10:00:00Z",
            "metadata": {}
        }
        """.data(using: .utf8)!

        let task = try JSONDecoder().decode(OrchestratorTask.self, from: json)
        #expect(task.title == "SPM migration wave 1")
        #expect(task.status == .pending)
        #expect(task.source == .backlog)
        #expect(task.projectPath == "wabisabi")
    }

    @Test("Decode task without project_path (backward compat)")
    func decodeTaskNoProjectPath() throws {
        let json = """
        {
            "id": "task-2",
            "company_id": "comp-1",
            "parent_id": null,
            "title": "Old task",
            "description": null,
            "source": "manual",
            "status": "pending",
            "claimed_by": null,
            "claimed_at": null,
            "priority": 5,
            "blocking_question_ids": [],
            "result": null,
            "pipeline_run_id": null,
            "created_at": "2026-03-15T10:00:00Z",
            "updated_at": "2026-03-15T10:00:00Z",
            "metadata": {}
        }
        """.data(using: .utf8)!

        let task = try JSONDecoder().decode(OrchestratorTask.self, from: json)
        #expect(task.projectPath == nil)
    }

    @Test("Decode dispatcher task")
    func decodeDispatcherTask() throws {
        let json = """
        {
            "task_id": "t-abc",
            "title": "MayaKit public API wave 2",
            "task_priority": 3,
            "project_path": "Maya",
            "status": "pending",
            "company_id": "c-123",
            "company_slug": "maya",
            "company_priority": 3,
            "budget": {"daily_usd": 8, "monthly_usd": 200, "spent_today_usd": 0},
            "schedule": {"active_hours": [8, 22], "timezone": "Europe/Paris", "days": [1,2,3,4,5,6,7]},
            "spent_today": "2.50"
        }
        """.data(using: .utf8)!

        let task = try JSONDecoder().decode(DispatcherTask.self, from: json)
        #expect(task.taskId == "t-abc")
        #expect(task.companySlug == "maya")
        #expect(task.projectPath == "Maya")
        #expect(task.spentToday == 2.5)
        #expect(task.budget.dailyUsd == 8)
        #expect(task.sessionSlug == "maya:mayakit-public-")
    }

    @Test("Decode company with companyProjects")
    func decodeCompanyWithProjects() throws {
        let json = """
        {
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "project_id": "660e8400-e29b-41d4-a716-446655440001",
            "slug": "wabisabi",
            "display_name": "WabiSabi",
            "status": "active",
            "priority": 3,
            "budget": {"daily_usd": 8, "monthly_usd": 200, "spent_today_usd": 2.5},
            "schedule": {"active_hours": [8, 22], "timezone": "Europe/Paris", "days": [1,2,3,4,5,6,7]},
            "config": {},
            "last_heartbeat_at": null,
            "created_at": "2026-03-01T00:00:00Z",
            "updated_at": "2026-03-01T00:00:00Z",
            "company_projects": [
                {"project_id": "p-1", "project_slug": "wabisabi", "role": "primary", "config": {}},
                {"project_id": "p-2", "project_slug": "kintsugi-ds", "role": "member", "config": {}}
            ]
        }
        """.data(using: .utf8)!

        let company = try JSONDecoder().decode(Company.self, from: json)
        #expect(company.companyProjects.count == 2)
        #expect(company.companyProjects[0].role == "primary")
        #expect(company.companyProjects[1].projectSlug == "kintsugi-ds")
    }
}
