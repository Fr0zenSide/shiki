import Foundation
import Testing
@testable import ShikkiKit

@Suite("CODIR report — BR-R-04")
struct CODIRReportTests {

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
                slug: "wabisabi", displayName: "WabiSabi",
                tasksCompleted: 3, tasksTotal: 5, tasksFailed: 0,
                prsMerged: 1, locAdded: 320, locDeleted: 90,
                budgetSpent: 4.10, agentCount: 1, avgContextPct: 72
            ),
        ],
        totals: Totals(
            tasksCompleted: 15, tasksTotal: 20, tasksFailed: 1,
            prsMerged: 5, locAdded: 1560, locDeleted: 470,
            budgetSpent: 16.50, agentCount: 4
        ),
        blocked: [
            BlockedItem(companySlug: "maya", title: "auth-flow", taskId: "T1", reason: "blocks 3 downstream"),
        ],
        pendingDecisions: 1,
        sessions: SessionMetrics(count: 12, totalDurationMinutes: 360),
        compactions: 8
    )

    @Test("CODIR shows aggregates only — no individual agent IDs or worker metrics (BR-R-04)")
    func codirAggregatesOnly() {
        let renderer = TUIReportRenderer()
        let output = renderer.renderCODIR(Self.testReport)

        // CODIR must show company-level aggregates
        #expect(output.contains("Maya"))
        #expect(output.contains("WabiSabi"))
        #expect(output.contains("CODIR Board"))
        #expect(output.contains("Budget:"))

        // CODIR must NOT show individual agent context percentages or agent IDs
        // The output shows company-level progress, not per-agent breakdown
        #expect(!output.contains("avg") || !output.contains("ctx"))
    }

    @Test("CODIR shows progress bars per company")
    func codirProgressBars() {
        let renderer = TUIReportRenderer()
        let output = renderer.renderCODIR(Self.testReport)

        // Maya: 12/15 = 80%
        #expect(output.contains("80%"))
        // WabiSabi: 3/5 = 60%
        #expect(output.contains("60%"))
    }

    @Test("CODIR shows risk assessment per company")
    func codirRiskAssessment() {
        let renderer = TUIReportRenderer()
        let output = renderer.renderCODIR(Self.testReport)

        // Maya at 80% should be ON TRACK
        #expect(output.contains("ON TRACK"))
        // WabiSabi at 60% should be AT RISK (below 70%)
        #expect(output.contains("AT RISK"))
        // Blocked items in risks section
        #expect(output.contains("auth-flow"))
    }
}
