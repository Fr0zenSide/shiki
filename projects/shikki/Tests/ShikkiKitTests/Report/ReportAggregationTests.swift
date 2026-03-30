import Foundation
import Testing
@testable import ShikkiKit

// MARK: - Mock Backend Client for Report Tests

final class MockReportBackendClient: BackendClientProtocol, @unchecked Sendable {
    var companies: [Company] = []
    var dailyReportJSON: Data = """
    {"date":"2026-03-24","perCompany":[],"blocked":[],"prsCreated":[]}
    """.data(using: .utf8)!
    var decisions: [Decision] = []
    var transcripts: [SessionTranscript] = []

    func healthCheck() async throws -> Bool { true }
    func getStatus() async throws -> OrchestratorStatus {
        fatalError("Not used in report tests")
    }
    func getStaleCompanies(thresholdMinutes: Int) async throws -> [Company] { [] }
    func getReadyCompanies() async throws -> [Company] { [] }
    func getDispatcherQueue() async throws -> [DispatcherTask] { [] }

    func getDailyReport(date: String?) async throws -> DailyReport {
        try JSONDecoder().decode(DailyReport.self, from: dailyReportJSON)
    }

    func sendHeartbeat(companyId: String, sessionId: String) async throws -> HeartbeatResponse {
        fatalError("Not used in report tests")
    }

    func getCompanies(status: String?) async throws -> [Company] {
        companies
    }

    func getPendingDecisions() async throws -> [Decision] {
        decisions
    }

    func answerDecision(id: String, answer: String, answeredBy: String) async throws -> Decision {
        fatalError("Not used in report tests")
    }

    func createSessionTranscript(_ input: SessionTranscriptInput) async throws -> SessionTranscript {
        fatalError("Not used in report tests")
    }

    func getSessionTranscripts(companySlug: String?, taskId: String?, limit: Int) async throws -> [SessionTranscript] {
        if let slug = companySlug {
            return transcripts.filter { $0.companySlug == slug }
        }
        return transcripts
    }

    func getSessionTranscript(id: String) async throws -> SessionTranscript {
        fatalError("Not used in report tests")
    }

    func getBoardOverview() async throws -> [BoardEntry] { [] }
    func shutdown() async throws {}

    // MARK: - Backlog (stubs)
    func listBacklogItems(status: BacklogItem.Status?, companyId: String?, tags: [String]?, sort: BacklogSort?) async throws -> [BacklogItem] { [] }
    func getBacklogItem(id: String) async throws -> BacklogItem { fatalError("Not used in report tests") }
    func createBacklogItem(title: String, description: String?, companyId: String?, sourceType: BacklogItem.SourceType, sourceRef: String?, priority: Int?, tags: [String]) async throws -> BacklogItem { fatalError("Not used in report tests") }
    func updateBacklogItem(id: String, status: BacklogItem.Status?, priority: Int?, sortOrder: Int?, tags: [String]?, description: String?) async throws -> BacklogItem { fatalError("Not used in report tests") }
    func enrichBacklogItem(id: String, notes: String, tags: [String]?, description: String?) async throws -> BacklogItem { fatalError("Not used in report tests") }
    func killBacklogItem(id: String, reason: String) async throws -> BacklogItem { fatalError("Not used in report tests") }
    func reorderBacklogItems(_ items: [(id: String, sortOrder: Int)]) async throws {}
    func getBacklogCount(status: BacklogItem.Status?, companyId: String?) async throws -> Int { 0 }
}

// MARK: - Test Helpers

func makeCompany(slug: String, displayName: String, spentToday: Double = 0, pendingTasks: Int = 0, runningTasks: Int = 0, completedTasks: Int = 0, blockedTasks: Int = 0) throws -> Company {
    let json = """
    {"id":"id-\(slug)","project_id":"p-\(slug)","slug":"\(slug)","display_name":"\(displayName)","status":"active","priority":1,"budget":{"daily_usd":10,"monthly_usd":300,"spent_today_usd":\(spentToday)},"schedule":{"active_hours":[8,22],"timezone":"Europe/Paris","days":[1,2,3,4,5]},"config":{},"created_at":"2026-03-01T00:00:00Z","updated_at":"2026-03-24T10:00:00Z","pending_tasks":\(pendingTasks),"running_tasks":\(runningTasks),"completed_tasks":\(completedTasks),"blocked_tasks":\(blockedTasks)}
    """.data(using: .utf8)!
    return try JSONDecoder().decode(Company.self, from: json)
}

// MARK: - Tests

@Suite("ReportAggregator — BR-R-01, BR-R-02")
struct ReportAggregationTests {

    @Test("Daily time range resolves to start of today")
    func dailyRange() {
        let now = Date()
        let range = ReportTimeRange.daily.resolve(now: now)
        let calendar = Calendar.current
        #expect(calendar.isDate(range.start, inSameDayAs: now))
        #expect(range.end <= now.addingTimeInterval(1))
    }

    @Test("Weekly time range resolves to 7 days ago")
    func weeklyRange() {
        let now = Date()
        let range = ReportTimeRange.weekly.resolve(now: now)
        let expected = Calendar.current.date(byAdding: .day, value: -7, to: Calendar.current.startOfDay(for: now))!
        #expect(range.start == expected)
    }

    @Test("Sprint time range resolves to 14 days ago")
    func sprintRange() {
        let now = Date()
        let range = ReportTimeRange.sprint.resolve(now: now)
        let expected = Calendar.current.date(byAdding: .day, value: -14, to: Calendar.current.startOfDay(for: now))!
        #expect(range.start == expected)
    }

    @Test("Git numstat parsing computes LOC correctly — BR-R-02")
    func gitNumstatParsing() {
        let output = """
        25\t10\tsrc/main.swift
        100\t30\tsrc/routes.ts
        -\t-\tassets/image.png
        5\t2\tREADME.md
        """
        let result = ReportAggregator.parseGitNumstat(output)
        #expect(result.added == 130)
        #expect(result.deleted == 42)
    }

    @Test("Aggregator produces scoped report for a company — BR-P-03")
    func scopedCompanyReport() async throws {
        let mockClient = MockReportBackendClient()
        mockClient.companies = [
            try makeCompany(slug: "maya", displayName: "Maya", spentToday: 5.50, pendingTasks: 3, runningTasks: 1, completedTasks: 8),
            try makeCompany(slug: "shiki", displayName: "Shiki", spentToday: 3.20, pendingTasks: 2, completedTasks: 5, blockedTasks: 1),
        ]

        let aggregator = ReportAggregator(client: mockClient, gitRoots: [:])
        let report = try await aggregator.aggregate(range: .daily, scope: .company("maya"))

        // Should only include maya — no cross-company leaks
        #expect(report.companies.count == 1)
        #expect(report.companies.first?.slug == "maya")
        #expect(report.scope == "company:maya")
    }
}
