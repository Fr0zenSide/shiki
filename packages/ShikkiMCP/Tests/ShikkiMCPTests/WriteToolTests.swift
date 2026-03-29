import Foundation
import Testing
@testable import ShikkiMCP

@Suite("Write Tools")
struct WriteToolTests {

    // MARK: - save_decision

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

    @Test("save_decision validates required fields — missing question")
    func saveDecisionMissingQuestion() async {
        let mock = MockDBClient()
        let params: JSONValue = .object([
            "category": .string("architecture"),
            "choice": .string("SQLite"),
            "rationale": .string("Fast"),
        ])
        let result = await WriteTools.execute(toolName: "shiki_save_decision", params: params, dbClient: mock)
        let text = extractText(result)
        #expect(text.contains("Missing required field: question"))
        #expect(isError(result))
    }

    @Test("save_decision validates required fields — missing choice")
    func saveDecisionMissingChoice() async {
        let mock = MockDBClient()
        let params: JSONValue = .object([
            "category": .string("architecture"),
            "question": .string("Which DB?"),
            "rationale": .string("Fast"),
        ])
        let result = await WriteTools.execute(toolName: "shiki_save_decision", params: params, dbClient: mock)
        let text = extractText(result)
        #expect(text.contains("Missing required field: choice"))
        #expect(isError(result))
    }

    @Test("save_decision validates required fields — missing rationale")
    func saveDecisionMissingRationale() async {
        let mock = MockDBClient()
        let params: JSONValue = .object([
            "category": .string("architecture"),
            "question": .string("Which DB?"),
            "choice": .string("SQLite"),
        ])
        let result = await WriteTools.execute(toolName: "shiki_save_decision", params: params, dbClient: mock)
        let text = extractText(result)
        #expect(text.contains("Missing required field: rationale"))
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
        #expect(mock.lastWriteScope == "shikki")
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

    // MARK: - save_plan

    @Test("save_plan validates enum values for status")
    func savePlanInvalidStatus() async {
        let mock = MockDBClient()
        let params: JSONValue = .object([
            "title": .string("My Plan"),
            "scope": .string("shikki"),
            "status": .string("bogus"),
            "summary": .string("A plan"),
        ])
        let result = await WriteTools.execute(toolName: "shiki_save_plan", params: params, dbClient: mock)
        let text = extractText(result)
        #expect(text.contains("Invalid status"))
        #expect(isError(result))
    }

    @Test("save_plan validates missing title")
    func savePlanMissingTitle() async {
        let mock = MockDBClient()
        let params: JSONValue = .object([
            "scope": .string("shikki"),
            "status": .string("draft"),
            "summary": .string("A plan"),
        ])
        let result = await WriteTools.execute(toolName: "shiki_save_plan", params: params, dbClient: mock)
        let text = extractText(result)
        #expect(text.contains("Missing required field: title"))
        #expect(isError(result))
    }

    @Test("save_plan validates missing scope")
    func savePlanMissingScope() async {
        let mock = MockDBClient()
        let params: JSONValue = .object([
            "title": .string("Plan"),
            "status": .string("draft"),
            "summary": .string("A plan"),
        ])
        let result = await WriteTools.execute(toolName: "shiki_save_plan", params: params, dbClient: mock)
        let text = extractText(result)
        #expect(text.contains("Missing required field: scope"))
        #expect(isError(result))
    }

    @Test("save_plan accepts valid input")
    func savePlanValid() async {
        let mock = MockDBClient()
        let params: JSONValue = .object([
            "title": .string("My Plan"),
            "scope": .string("shikki"),
            "status": .string("validated"),
            "summary": .string("A good plan"),
        ])
        let result = await WriteTools.execute(toolName: "shiki_save_plan", params: params, dbClient: mock)
        #expect(!isError(result))
        #expect(mock.lastWriteType == "plan")
        #expect(mock.lastWriteScope == "shikki")
    }

    // MARK: - save_event

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

    @Test("save_event rejects missing eventType")
    func saveEventMissingType() async {
        let mock = MockDBClient()
        let params: JSONValue = .object([
            "data": .object(["key": .string("val")]),
        ])
        let result = await WriteTools.execute(toolName: "shiki_save_event", params: params, dbClient: mock)
        let text = extractText(result)
        #expect(text.contains("Missing required field: eventType"))
        #expect(isError(result))
    }

    @Test("save_event rejects non-object data")
    func saveEventNonObjectData() async {
        let mock = MockDBClient()
        let params: JSONValue = .object([
            "eventType": .string("test"),
            "data": .string("not an object"),
        ])
        let result = await WriteTools.execute(toolName: "shiki_save_event", params: params, dbClient: mock)
        let text = extractText(result)
        #expect(text.contains("must be an object"))
        #expect(isError(result))
    }

    @Test("save_event accepts valid input")
    func saveEventValid() async {
        let mock = MockDBClient()
        let params: JSONValue = .object([
            "eventType": .string("context_session_start"),
            "data": .object(["branch": .string("main")]),
        ])
        let result = await WriteTools.execute(toolName: "shiki_save_event", params: params, dbClient: mock)
        #expect(!isError(result))
        #expect(mock.lastWriteType == "agent_event")
    }

    // MARK: - save_context

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

    @Test("save_context requires summary")
    func saveContextMissingSummary() async {
        let mock = MockDBClient()
        let params: JSONValue = .object([
            "sessionId": .string("sess-1"),
        ])
        let result = await WriteTools.execute(toolName: "shiki_save_context", params: params, dbClient: mock)
        let text = extractText(result)
        #expect(text.contains("Missing required field: summary"))
        #expect(isError(result))
    }

    @Test("save_context accepts valid input")
    func saveContextValid() async {
        let mock = MockDBClient()
        let params: JSONValue = .object([
            "sessionId": .string("sess-1"),
            "summary": .string("Working on MCP"),
            "branch": .string("feature/mcp"),
        ])
        let result = await WriteTools.execute(toolName: "shiki_save_context", params: params, dbClient: mock)
        #expect(!isError(result))
        #expect(mock.lastWriteType == "context_compaction")
    }

    // MARK: - save_agent_report

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

    // MARK: - save_batch

    @Test("save_batch saves multiple items")
    func saveBatchMultipleItems() async {
        let mock = MockDBClient()
        let params: JSONValue = .object([
            "items": .array([
                .object([
                    "type": .string("decision"),
                    "data": .object(["question": .string("Q1")]),
                ]),
                .object([
                    "type": .string("plan"),
                    "scope": .string("maya"),
                    "data": .object(["title": .string("P1")]),
                ]),
            ]),
        ])
        let result = await WriteTools.execute(toolName: "shiki_save_batch", params: params, dbClient: mock)
        let text = extractText(result)
        #expect(text.contains("2/2 saved"))
        #expect(!isError(result))
        #expect(mock.writeCallCount == 2)
    }

    @Test("save_batch rejects empty items")
    func saveBatchEmptyItems() async {
        let mock = MockDBClient()
        let params: JSONValue = .object([
            "items": .array([]),
        ])
        let result = await WriteTools.execute(toolName: "shiki_save_batch", params: params, dbClient: mock)
        let text = extractText(result)
        #expect(text.contains("Missing or empty"))
        #expect(isError(result))
    }

    @Test("save_batch rejects missing items")
    func saveBatchMissingItems() async {
        let mock = MockDBClient()
        let params: JSONValue = .object([:])
        let result = await WriteTools.execute(toolName: "shiki_save_batch", params: params, dbClient: mock)
        let text = extractText(result)
        #expect(text.contains("Missing or empty"))
        #expect(isError(result))
    }

    @Test("save_batch rejects oversized batch")
    func saveBatchTooLarge() async {
        let mock = MockDBClient()
        let items = (0..<51).map { i in
            JSONValue.object([
                "type": .string("event"),
                "data": .object(["i": .int(i)]),
            ])
        }
        let params: JSONValue = .object(["items": .array(items)])
        let result = await WriteTools.execute(toolName: "shiki_save_batch", params: params, dbClient: mock)
        let text = extractText(result)
        #expect(text.contains("Batch too large"))
        #expect(isError(result))
    }

    @Test("save_batch reports partial failures")
    func saveBatchPartialFailure() async {
        let mock = MockDBClient()
        let params: JSONValue = .object([
            "items": .array([
                .object([
                    "type": .string("decision"),
                    "data": .object(["q": .string("Q")]),
                ]),
                .object([
                    "type": .string(""),
                    "data": .object(["q": .string("Q")]),
                ]),
                .object([
                    "type": .string("plan"),
                    "data": .object(["t": .string("T")]),
                ]),
            ]),
        ])
        let result = await WriteTools.execute(toolName: "shiki_save_batch", params: params, dbClient: mock)
        let text = extractText(result)
        #expect(text.contains("2/3 saved"))
        #expect(text.contains("1 failed"))
    }

    @Test("save_batch handles invalid item structure")
    func saveBatchInvalidItem() async {
        let mock = MockDBClient()
        let params: JSONValue = .object([
            "items": .array([
                .string("not an object"),
            ]),
        ])
        let result = await WriteTools.execute(toolName: "shiki_save_batch", params: params, dbClient: mock)
        let text = extractText(result)
        #expect(text.contains("not an object"))
        #expect(isError(result))
    }

    @Test("save_batch handles missing data field")
    func saveBatchMissingData() async {
        let mock = MockDBClient()
        let params: JSONValue = .object([
            "items": .array([
                .object([
                    "type": .string("decision"),
                ]),
            ]),
        ])
        let result = await WriteTools.execute(toolName: "shiki_save_batch", params: params, dbClient: mock)
        let text = extractText(result)
        #expect(text.contains("missing or invalid 'data'"))
        #expect(isError(result))
    }

    @Test("save_batch uses default scope of shikki")
    func saveBatchDefaultScope() async {
        let mock = MockDBClient()
        let params: JSONValue = .object([
            "items": .array([
                .object([
                    "type": .string("event"),
                    "data": .object(["x": .int(1)]),
                ]),
            ]),
        ])
        _ = await WriteTools.execute(toolName: "shiki_save_batch", params: params, dbClient: mock)
        #expect(mock.lastWriteScope == "shikki")
    }

    // MARK: - Edge cases

    @Test("write with invalid params returns error")
    func writeInvalidParams() async {
        let mock = MockDBClient()
        let result = await WriteTools.execute(toolName: "shiki_save_decision", params: .string("bad"), dbClient: mock)
        let text = extractText(result)
        #expect(text.contains("Invalid parameters"))
        #expect(isError(result))
    }

    @Test("write with nil params returns error")
    func writeNilParams() async {
        let mock = MockDBClient()
        let result = await WriteTools.execute(toolName: "shiki_save_decision", params: nil, dbClient: mock)
        let text = extractText(result)
        #expect(text.contains("Invalid parameters"))
        #expect(isError(result))
    }

    @Test("unknown write tool returns error")
    func unknownWriteTool() async {
        let mock = MockDBClient()
        let result = await WriteTools.execute(toolName: "shiki_unknown", params: .object([:]), dbClient: mock)
        let text = extractText(result)
        #expect(text.contains("Unknown write tool"))
        #expect(isError(result))
    }

    @Test("write handles DB connection error")
    func writeDBConnectionError() async {
        let mock = MockDBClient()
        mock.shouldThrow = .connectionRefused(underlying: "refused")
        let params: JSONValue = .object([
            "category": .string("architecture"),
            "question": .string("Q"),
            "choice": .string("C"),
            "rationale": .string("R"),
        ])
        let result = await WriteTools.execute(toolName: "shiki_save_decision", params: params, dbClient: mock)
        let text = extractText(result)
        #expect(text.contains("Connection refused"))
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
