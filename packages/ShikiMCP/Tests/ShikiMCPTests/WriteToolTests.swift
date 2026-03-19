import Testing
import Foundation
@testable import ShikiMCP

@Suite("Write Tools")
struct WriteToolTests {

    @Test("save_decision validates required fields — missing category")
    func saveDecisionMissingCategory() async {
        let mock = MockDBClient()
        let params: JSONValue = .object([
            "question": .string("Which DB?"),
            "choice": .string("SQLite"),
            "rationale": .string("Fast"),
        ])
        let result = await WriteTools.execute(toolName: "shiki_save_decision", params: params, dbClient: mock)
        let text = extractText(result)
        #expect(text.contains("Missing required field: category"))
        #expect(isError(result))
    }

    @Test("save_decision accepts valid input")
    func saveDecisionValid() async {
        let mock = MockDBClient()
        let params: JSONValue = .object([
            "category": .string("architecture"),
            "question": .string("Which DB?"),
            "choice": .string("SQLite"),
            "rationale": .string("Lightweight and portable"),
        ])
        let result = await WriteTools.execute(toolName: "shiki_save_decision", params: params, dbClient: mock)
        #expect(!isError(result))
        #expect(mock.lastWriteType == "decision")
        #expect(mock.lastWriteScope == "shiki")
    }

    @Test("save_decision rejects invalid category enum")
    func saveDecisionInvalidCategory() async {
        let mock = MockDBClient()
        let params: JSONValue = .object([
            "category": .string("invalid_category"),
            "question": .string("Q"),
            "choice": .string("C"),
            "rationale": .string("R"),
        ])
        let result = await WriteTools.execute(toolName: "shiki_save_decision", params: params, dbClient: mock)
        let text = extractText(result)
        #expect(text.contains("Invalid category"))
        #expect(isError(result))
    }

    @Test("save_plan validates enum values for status")
    func savePlanInvalidStatus() async {
        let mock = MockDBClient()
        let params: JSONValue = .object([
            "title": .string("My Plan"),
            "scope": .string("shiki"),
            "status": .string("bogus"),
            "summary": .string("A plan"),
        ])
        let result = await WriteTools.execute(toolName: "shiki_save_plan", params: params, dbClient: mock)
        let text = extractText(result)
        #expect(text.contains("Invalid status"))
        #expect(isError(result))
    }

    @Test("save_event rejects empty data")
    func saveEventEmptyData() async {
        let mock = MockDBClient()
        let params: JSONValue = .object([
            "eventType": .string("test_event"),
            "data": .object([:]),
        ])
        let result = await WriteTools.execute(toolName: "shiki_save_event", params: params, dbClient: mock)
        let text = extractText(result)
        #expect(text.contains("must not be empty"))
        #expect(isError(result))
    }

    @Test("save_context requires sessionId")
    func saveContextMissingSessionId() async {
        let mock = MockDBClient()
        let params: JSONValue = .object([
            "summary": .string("Some context"),
        ])
        let result = await WriteTools.execute(toolName: "shiki_save_context", params: params, dbClient: mock)
        let text = extractText(result)
        #expect(text.contains("Missing required field: sessionId"))
        #expect(isError(result))
    }

    @Test("save_decision uses project field as scope")
    func saveDecisionWithProject() async {
        let mock = MockDBClient()
        let params: JSONValue = .object([
            "category": .string("implementation"),
            "question": .string("Q"),
            "choice": .string("C"),
            "rationale": .string("R"),
            "project": .string("maya"),
        ])
        _ = await WriteTools.execute(toolName: "shiki_save_decision", params: params, dbClient: mock)
        #expect(mock.lastWriteScope == "maya")
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
