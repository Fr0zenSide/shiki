import Foundation
import Testing
@testable import ShikkiMCP

@Suite("Analytics Tools")
struct AnalyticsToolTests {

    // MARK: - Daily Summary

    @Test("daily_summary returns summary for today by default")
    func dailySummaryDefaultDate() async {
        let mock = MockDBClient()
        mock.searchResult = .array([.object(["id": .string("d1")])])

        let result = await AnalyticsTools.execute(toolName: "shiki_daily_summary", params: .object([:]), dbClient: mock)
        let text = extractText(result)
        #expect(text.contains("Daily Summary"))
        #expect(!isError(result))
    }

    @Test("daily_summary accepts explicit date")
    func dailySummaryExplicitDate() async {
        let mock = MockDBClient()
        mock.searchResult = .array([])

        let params: JSONValue = .object([
            "date": .string("2026-03-29"),
        ])
        let result = await AnalyticsTools.execute(toolName: "shiki_daily_summary", params: params, dbClient: mock)
        let text = extractText(result)
        #expect(text.contains("2026-03-29"))
        #expect(!isError(result))
    }

    @Test("daily_summary rejects invalid date format")
    func dailySummaryInvalidDate() async {
        let mock = MockDBClient()
        let params: JSONValue = .object([
            "date": .string("not-a-date"),
        ])
        let result = await AnalyticsTools.execute(toolName: "shiki_daily_summary", params: params, dbClient: mock)
        let text = extractText(result)
        #expect(text.contains("Invalid date format"))
        #expect(isError(result))
    }

    @Test("daily_summary handles DB error gracefully")
    func dailySummaryDBError() async {
        let mock = MockDBClient()
        mock.shouldThrow = .connectionRefused(underlying: "timeout")

        let result = await AnalyticsTools.execute(toolName: "shiki_daily_summary", params: .object([:]), dbClient: mock)
        let text = extractText(result)
        // Should still produce output (error sections), not crash
        #expect(text.contains("Daily Summary"))
        #expect(text.contains("error"))
    }

    @Test("daily_summary passes projectIds filter")
    func dailySummaryWithProjectIds() async {
        let mock = MockDBClient()
        mock.searchResult = .array([])

        let params: JSONValue = .object([
            "projectIds": .array([.string("proj-123")]),
        ])
        _ = await AnalyticsTools.execute(toolName: "shiki_daily_summary", params: params, dbClient: mock)
        #expect(mock.lastSearchProjectIds == ["proj-123"])
    }

    @Test("daily_summary shows section counts")
    func dailySummarySectionCounts() async {
        let mock = MockDBClient()
        mock.searchResult = .object(["results": .array([
            .object(["id": .string("1")]),
            .object(["id": .string("2")]),
        ])])

        let params: JSONValue = .object([
            "date": .string("2026-03-29"),
        ])
        let result = await AnalyticsTools.execute(toolName: "shiki_daily_summary", params: params, dbClient: mock)
        let text = extractText(result)
        #expect(text.contains("2 found"))
    }

    // MARK: - Decision Chain

    @Test("decision_chain requires decisionId")
    func decisionChainMissingId() async {
        let mock = MockDBClient()
        let result = await AnalyticsTools.execute(toolName: "shiki_decision_chain", params: .object([:]), dbClient: mock)
        let text = extractText(result)
        #expect(text.contains("Missing required field: decisionId"))
        #expect(isError(result))
    }

    @Test("decision_chain rejects empty decisionId")
    func decisionChainEmptyId() async {
        let mock = MockDBClient()
        let params: JSONValue = .object(["decisionId": .string("")])
        let result = await AnalyticsTools.execute(toolName: "shiki_decision_chain", params: params, dbClient: mock)
        let text = extractText(result)
        #expect(text.contains("Missing required field: decisionId"))
        #expect(isError(result))
    }

    @Test("decision_chain returns root and children")
    func decisionChainValid() async {
        let mock = MockDBClient()
        mock.searchResult = .array([.object(["id": .string("d-001"), "question": .string("Which DB?")])])

        let params: JSONValue = .object([
            "decisionId": .string("d-001"),
        ])
        let result = await AnalyticsTools.execute(toolName: "shiki_decision_chain", params: params, dbClient: mock)
        #expect(!isError(result))
        let text = extractText(result)
        #expect(text.contains("d-001"))
    }

    @Test("decision_chain handles DB error")
    func decisionChainDBError() async {
        let mock = MockDBClient()
        mock.shouldThrow = .httpError(statusCode: 500, body: "Internal error")

        let params: JSONValue = .object([
            "decisionId": .string("d-001"),
        ])
        let result = await AnalyticsTools.execute(toolName: "shiki_decision_chain", params: params, dbClient: mock)
        let text = extractText(result)
        #expect(text.contains("ShikkiDB error"))
        #expect(isError(result))
    }

    // MARK: - Agent Effectiveness

    @Test("agent_effectiveness returns data without filters")
    func agentEffectivenessNoFilters() async {
        let mock = MockDBClient()
        mock.searchResult = .array([])

        let result = await AnalyticsTools.execute(toolName: "shiki_agent_effectiveness", params: .object([:]), dbClient: mock)
        #expect(!isError(result))
        #expect(mock.lastSearchTypes == ["agent_report", "report"])
    }

    @Test("agent_effectiveness filters by since date")
    func agentEffectivenessWithSince() async {
        let mock = MockDBClient()
        mock.searchResult = .array([])

        let params: JSONValue = .object([
            "since": .string("2026-03-01"),
        ])
        let result = await AnalyticsTools.execute(toolName: "shiki_agent_effectiveness", params: params, dbClient: mock)
        #expect(!isError(result))
        #expect(mock.lastSearchQuery?.contains("since:2026-03-01") == true)
    }

    @Test("agent_effectiveness rejects invalid since date")
    func agentEffectivenessInvalidSince() async {
        let mock = MockDBClient()
        let params: JSONValue = .object([
            "since": .string("yesterday"),
        ])
        let result = await AnalyticsTools.execute(toolName: "shiki_agent_effectiveness", params: params, dbClient: mock)
        let text = extractText(result)
        #expect(text.contains("Invalid date format"))
        #expect(isError(result))
    }

    @Test("agent_effectiveness passes projectIds")
    func agentEffectivenessWithProjectIds() async {
        let mock = MockDBClient()
        mock.searchResult = .array([])

        let params: JSONValue = .object([
            "projectIds": .array([.string("proj-1")]),
        ])
        _ = await AnalyticsTools.execute(toolName: "shiki_agent_effectiveness", params: params, dbClient: mock)
        #expect(mock.lastSearchProjectIds == ["proj-1"])
    }

    @Test("agent_effectiveness handles connection refused")
    func agentEffectivenessConnectionRefused() async {
        let mock = MockDBClient()
        mock.shouldThrow = .connectionRefused(underlying: "refused")

        let result = await AnalyticsTools.execute(toolName: "shiki_agent_effectiveness", params: .object([:]), dbClient: mock)
        let text = extractText(result)
        #expect(text.contains("Connection refused"))
        #expect(isError(result))
    }

    // MARK: - Date Validation

    @Test("isValidDateString accepts valid dates")
    func validDates() {
        #expect(AnalyticsTools.isValidDateString("2026-03-29"))
        #expect(AnalyticsTools.isValidDateString("2026-01-01"))
        #expect(AnalyticsTools.isValidDateString("2025-12-31"))
    }

    @Test("isValidDateString rejects invalid dates")
    func invalidDates() {
        #expect(!AnalyticsTools.isValidDateString("not-a-date"))
        #expect(!AnalyticsTools.isValidDateString("2026/03/29"))
        #expect(!AnalyticsTools.isValidDateString(""))
        #expect(!AnalyticsTools.isValidDateString("29-03-2026"))
    }

    @Test("isValidDateString rejects impossible dates")
    func impossibleDates() {
        #expect(!AnalyticsTools.isValidDateString("2026-02-30"))
        #expect(!AnalyticsTools.isValidDateString("2026-13-01"))
    }

    // MARK: - Unknown tool

    @Test("unknown analytics tool returns error")
    func unknownTool() async {
        let mock = MockDBClient()
        let result = await AnalyticsTools.execute(toolName: "shiki_unknown", params: .object([:]), dbClient: mock)
        let text = extractText(result)
        #expect(text.contains("Unknown analytics tool"))
        #expect(isError(result))
    }

    // MARK: - Helpers

    private func extractText(_ result: JSONValue) -> String {
        guard let content = result["content"]?.arrayValue,
              let first = content.first,
              let text = first["text"]?.stringValue else {
            return ""
        }
        return text
    }

    private func isError(_ result: JSONValue) -> Bool {
        result["isError"] == .bool(true)
    }
}
