import Testing
import Foundation
@testable import ShikiMCP

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

    @Test("search missing query returns error")
    func searchMissingQuery() async {
        let mock = MockDBClient()
        let params: JSONValue = .object([:])
        let result = await ReadTools.execute(toolName: "shiki_search", params: params, dbClient: mock)

        guard let content = result["content"]?.arrayValue,
              let first = content.first,
              let text = first["text"]?.stringValue else {
            Issue.record("Expected text content")
            return
        }
        #expect(text.contains("Missing required field: query"))
        #expect(result["isError"] == .bool(true))
    }
}
