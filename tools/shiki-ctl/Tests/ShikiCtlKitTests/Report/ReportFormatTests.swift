import Foundation
import Testing
@testable import ShikiCtlKit

@Suite("Report renderers — BR-R-05")
struct ReportFormatTests {

    // Shared test report
    static let testReport = Report(
        timeRange: ReportDateRange(start: "2026-03-17T00:00:00Z", end: "2026-03-23T23:59:59Z", label: "weekly"),
        scope: "workspace",
        companies: [
            CompanyMetrics(
                slug: "maya", displayName: "Maya",
                tasksCompleted: 12, tasksTotal: 15, tasksFailed: 1,
                prsMerged: 4, locAdded: 1240, locDeleted: 380,
                budgetSpent: 12.40, agentCount: 3, avgContextPct: 68
            ),
            CompanyMetrics(
                slug: "shiki", displayName: "Shiki",
                tasksCompleted: 8, tasksTotal: 10, tasksFailed: 0,
                prsMerged: 2, locAdded: 890, locDeleted: 120,
                budgetSpent: 8.20, agentCount: 2, avgContextPct: 55
            ),
        ],
        totals: Totals(
            tasksCompleted: 20, tasksTotal: 25, tasksFailed: 1,
            prsMerged: 6, locAdded: 2130, locDeleted: 500,
            budgetSpent: 20.60, agentCount: 5
        ),
        blocked: [
            BlockedItem(companySlug: "maya", title: "auth-flow", taskId: "T1", reason: "decision pending"),
        ],
        pendingDecisions: 1,
        sessions: SessionMetrics(count: 18, totalDurationMinutes: 540),
        compactions: 14
    )

    @Test("TUI renderer produces ANSI table with company rows")
    func tuiRendererOutput() {
        let renderer = TUIReportRenderer()
        let output = renderer.render(Self.testReport)

        #expect(output.contains("Shikki Report"))
        #expect(output.contains("maya"))
        #expect(output.contains("shiki"))
        #expect(output.contains("TOTAL"))
        #expect(output.contains("12/15"))
        #expect(output.contains("Sessions: 18"))
    }

    @Test("Markdown renderer produces valid markdown table")
    func markdownRendererOutput() {
        let renderer = MarkdownReportRenderer()
        let output = renderer.render(Self.testReport)

        #expect(output.contains("# Shikki Report"))
        #expect(output.contains("| maya |"))
        #expect(output.contains("| **TOTAL** |"))
        #expect(output.contains("## Blocked"))
        #expect(output.contains("**Sessions:** 18"))
    }

    @Test("JSON renderer produces valid decodable JSON")
    func jsonRendererOutput() throws {
        let renderer = JSONReportRenderer()
        let output = renderer.render(Self.testReport)

        let data = output.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Report.self, from: data)
        #expect(decoded.companies.count == 2)
        #expect(decoded.totals.tasksCompleted == 20)
        #expect(decoded.scope == "workspace")
    }
}
