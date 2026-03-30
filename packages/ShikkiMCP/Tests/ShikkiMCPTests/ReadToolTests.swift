import Foundation
import Testing
@testable import ShikkiMCP

@Suite("Read Tools")
struct ReadToolTests {

    @Test("search builds correct request body")
    func searchBuildsRequest() async {
        let mock = MockDBClient()
        mock.searchResult = .array([.object(["id": .string("1")])])

        let params: JSONValue = .object([
            "query": .string("architecture decisions"),
            "limit": .int(5),
        ])
        _ = await ReadTools.execute(toolName: "shiki_search", params: params, dbClient: mock)

        #expect(mock.lastSearchQuery == "architecture decisions")
        #expect(mock.lastSearchLimit == 5)
        #expect(mock.lastSearchProjectIds == nil)
    }

    @Test("search with filters adds projectIds")
    func searchWithProjectIds() async {
        let mock = MockDBClient()
        let params: JSONValue = .object([
            "query": .string("test"),
            "projectIds": .array([.string("proj-1"), .string("proj-2")]),
        ])
        _ = await ReadTools.execute(toolName: "shiki_search", params: params, dbClient: mock)

        #expect(mock.lastSearchProjectIds == ["proj-1", "proj-2"])
    }

    @Test("search with types filter")
    func searchWithTypes() async {
        let mock = MockDBClient()
        let params: JSONValue = .object([
            "query": .string("test"),
            "types": .array([.string("decision"), .string("plan")]),
        ])
        _ = await ReadTools.execute(toolName: "shiki_search", params: params, dbClient: mock)

        #expect(mock.lastSearchTypes == ["decision", "plan"])
    }

    @Test("search clamps limit to max 100")
    func searchClampsLimit() async {
        let mock = MockDBClient()
        let params: JSONValue = .object([
            "query": .string("test"),
            "limit": .int(500),
        ])
        _ = await ReadTools.execute(toolName: "shiki_search", params: params, dbClient: mock)

        #expect(mock.lastSearchLimit == 100)
    }

    @Test("search clamps limit to min 1")
    func searchClampsMinLimit() async {
        let mock = MockDBClient()
        let params: JSONValue = .object([
            "query": .string("test"),
            "limit": .int(-5),
        ])
        _ = await ReadTools.execute(toolName: "shiki_search", params: params, dbClient: mock)

        #expect(mock.lastSearchLimit == 1)
    }

    @Test("search uses default limit of 10")
    func searchDefaultLimit() async {
        let mock = MockDBClient()
        let params: JSONValue = .object([
            "query": .string("test"),
        ])
        _ = await ReadTools.execute(toolName: "shiki_search", params: params, dbClient: mock)

        #expect(mock.lastSearchLimit == 10)
    }

    @Test("get_decisions returns structured results with type filter")
    func getDecisionsFilter() async {
        let mock = MockDBClient()
        let params: JSONValue = .object([
            "query": .string("database choice"),
        ])
        _ = await ReadTools.execute(toolName: "shiki_get_decisions", params: params, dbClient: mock)

        #expect(mock.lastSearchTypes == ["decision"])
        #expect(mock.lastSearchQuery == "database choice")
    }

    @Test("get_decisions uses default query when none provided")
    func getDecisionsDefaultQuery() async {
        let mock = MockDBClient()
        _ = await ReadTools.execute(toolName: "shiki_get_decisions", params: .object([:]), dbClient: mock)

        #expect(mock.lastSearchQuery == "decision")
    }

    @Test("get_context filters by sessionId")
    func getContextBySession() async {
        let mock = MockDBClient()
        let params: JSONValue = .object([
            "sessionId": .string("sess-abc"),
        ])
        _ = await ReadTools.execute(toolName: "shiki_get_context", params: params, dbClient: mock)

        #expect(mock.lastSearchTypes == ["context_compaction"])
        #expect(mock.lastSearchQuery?.contains("sess-abc") == true)
    }

    @Test("get_plans filters by status")
    func getPlansByStatus() async {
        let mock = MockDBClient()
        let params: JSONValue = .object([
            "status": .string("validated"),
        ])
        _ = await ReadTools.execute(toolName: "shiki_get_plans", params: params, dbClient: mock)

        #expect(mock.lastSearchTypes == ["plan"])
        #expect(mock.lastSearchQuery?.contains("validated") == true)
    }

    @Test("get_reports uses default limit of 5")
    func getReportsDefaultLimit() async {
        let mock = MockDBClient()
        _ = await ReadTools.execute(toolName: "shiki_get_reports", params: .object([:]), dbClient: mock)

        #expect(mock.lastSearchLimit == 5)
        #expect(mock.lastSearchTypes == ["report"])
    }

    @Test("search missing query returns error")
    func searchMissingQuery() async {
        let mock = MockDBClient()
        let params: JSONValue = .object([:])
        let result = await ReadTools.execute(toolName: "shiki_search", params: params, dbClient: mock)

        let text = extractText(result)
        #expect(text.contains("Missing required field: query"))
        #expect(result["isError"] == .bool(true))
    }

    @Test("search empty query returns error")
    func searchEmptyQuery() async {
        let mock = MockDBClient()
        let params: JSONValue = .object(["query": .string("")])
        let result = await ReadTools.execute(toolName: "shiki_search", params: params, dbClient: mock)

        let text = extractText(result)
        #expect(text.contains("Missing required field: query"))
        #expect(result["isError"] == .bool(true))
    }

    @Test("search handles DB error gracefully")
    func searchDBError() async {
        let mock = MockDBClient()
        mock.shouldThrow = .httpError(statusCode: 500, body: "Internal")
        let params: JSONValue = .object(["query": .string("test")])
        let result = await ReadTools.execute(toolName: "shiki_search", params: params, dbClient: mock)

        let text = extractText(result)
        #expect(text.contains("ShikkiDB error"))
        #expect(result["isError"] == .bool(true))
    }

    @Test("unknown read tool returns error")
    func unknownReadTool() async {
        let mock = MockDBClient()
        let result = await ReadTools.execute(toolName: "shiki_unknown", params: .object([:]), dbClient: mock)
        let text = extractText(result)
        #expect(text.contains("Unknown read tool"))
        #expect(result["isError"] == .bool(true))
    }

    @Test("search with nil params uses empty args")
    func searchNilParams() async {
        let mock = MockDBClient()
        let result = await ReadTools.execute(toolName: "shiki_search", params: nil, dbClient: mock)
        #expect(result["isError"] == .bool(true))
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
}
