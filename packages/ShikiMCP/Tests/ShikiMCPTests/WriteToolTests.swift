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

    @Test("save_agent_report validates required fields — missing persona")
    func saveAgentReportMissingPersona() async {
        let mock = MockDBClient()
        let params: JSONValue = .object([
            "sessionId": .string("sess-1"),
            "taskTitle": .string("Fix bug"),
            "beforeState": .string("broken"),
            "afterState": .string("fixed"),
        ])
        let result = await WriteTools.execute(toolName: "shiki_save_agent_report", params: params, dbClient: mock)
        let text = extractText(result)
        #expect(text.contains("Missing required field: persona"))
        #expect(isError(result))
    }

    @Test("save_agent_report rejects invalid persona enum")
    func saveAgentReportInvalidPersona() async {
        let mock = MockDBClient()
        let params: JSONValue = .object([
            "sessionId": .string("sess-1"),
            "persona": .string("hacker"),
            "taskTitle": .string("Fix bug"),
            "beforeState": .string("broken"),
            "afterState": .string("fixed"),
        ])
        let result = await WriteTools.execute(toolName: "shiki_save_agent_report", params: params, dbClient: mock)
        let text = extractText(result)
        #expect(text.contains("Invalid persona"))
        #expect(isError(result))
    }

    @Test("save_agent_report accepts valid input with all fields")
    func saveAgentReportValid() async {
        let mock = MockDBClient()
        let params: JSONValue = .object([
            "sessionId": .string("sess-1"),
            "persona": .string("implement"),
            "taskTitle": .string("Add MCP tools"),
            "beforeState": .string("no MCP"),
            "afterState": .string("MCP working"),
            "filesChanged": .array([.string("WriteTools.swift")]),
            "testsAdded": .int(5),
            "redFlags": .array([]),
        ])
        let result = await WriteTools.execute(toolName: "shiki_save_agent_report", params: params, dbClient: mock)
        #expect(!isError(result))
        #expect(mock.lastWriteType == "agent_report")
    }

    @Test("save_agent_report requires sessionId")
    func saveAgentReportMissingSessionId() async {
        let mock = MockDBClient()
        let params: JSONValue = .object([
            "persona": .string("review"),
            "taskTitle": .string("Review PR"),
            "beforeState": .string("pending"),
            "afterState": .string("approved"),
        ])
        let result = await WriteTools.execute(toolName: "shiki_save_agent_report", params: params, dbClient: mock)
        let text = extractText(result)
        #expect(text.contains("Missing required field: sessionId"))
        #expect(isError(result))
    }

    @Test("save_agent_report requires taskTitle")
    func saveAgentReportMissingTaskTitle() async {
        let mock = MockDBClient()
        let params: JSONValue = .object([
            "sessionId": .string("sess-1"),
            "persona": .string("investigate"),
            "beforeState": .string("unknown"),
            "afterState": .string("understood"),
        ])
        let result = await WriteTools.execute(toolName: "shiki_save_agent_report", params: params, dbClient: mock)
        let text = extractText(result)
        #expect(text.contains("Missing required field: taskTitle"))
        #expect(isError(result))
    }

    @Test("save_agent_report requires beforeState")
    func saveAgentReportMissingBeforeState() async {
        let mock = MockDBClient()
        let params: JSONValue = .object([
            "sessionId": .string("sess-1"),
            "persona": .string("fix"),
            "taskTitle": .string("Fix crash"),
            "afterState": .string("stable"),
        ])
        let result = await WriteTools.execute(toolName: "shiki_save_agent_report", params: params, dbClient: mock)
        let text = extractText(result)
        #expect(text.contains("Missing required field: beforeState"))
        #expect(isError(result))
    }

    @Test("save_agent_report requires afterState")
    func saveAgentReportMissingAfterState() async {
        let mock = MockDBClient()
        let params: JSONValue = .object([
            "sessionId": .string("sess-1"),
            "persona": .string("critique"),
            "taskTitle": .string("Review design"),
            "beforeState": .string("draft"),
        ])
        let result = await WriteTools.execute(toolName: "shiki_save_agent_report", params: params, dbClient: mock)
        let text = extractText(result)
        #expect(text.contains("Missing required field: afterState"))
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
