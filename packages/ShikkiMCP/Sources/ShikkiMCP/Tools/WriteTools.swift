import Foundation

enum WriteTools: Sendable {

    // MARK: - Tool Definitions

    static let saveDecision = MCPToolDefinition(
        name: "shiki_save_decision",
        description: "Save an architecture/implementation decision to ShikkiDB",
        inputSchema: .object([
            "type": .string("object"),
            "required": .array([.string("category"), .string("question"), .string("choice"), .string("rationale")]),
            "properties": .object([
                "category": .object([
                    "type": .string("string"),
                    "enum": .array([.string("architecture"), .string("implementation"), .string("process"), .string("tradeOff"), .string("scope")]),
                    "description": .string("Decision category"),
                ]),
                "question": .object([
                    "type": .string("string"),
                    "description": .string("The decision question"),
                ]),
                "choice": .object([
                    "type": .string("string"),
                    "description": .string("What was decided"),
                ]),
                "rationale": .object([
                    "type": .string("string"),
                    "description": .string("Why this choice"),
                ]),
                "alternatives": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")]),
                    "description": .string("Alternatives considered"),
                ]),
                "project": .object([
                    "type": .string("string"),
                    "description": .string("Project name (e.g. shikki, maya)"),
                ]),
                "branch": .object([
                    "type": .string("string"),
                    "description": .string("Git branch where decision was made"),
                ]),
            ]),
        ])
    )

    static let savePlan = MCPToolDefinition(
        name: "shiki_save_plan",
        description: "Save a validated plan to ShikkiDB",
        inputSchema: .object([
            "type": .string("object"),
            "required": .array([.string("title"), .string("scope"), .string("status"), .string("summary")]),
            "properties": .object([
                "title": .object([
                    "type": .string("string"),
                    "description": .string("Plan title"),
                ]),
                "scope": .object([
                    "type": .string("string"),
                    "description": .string("Project scope (e.g. shikki, maya, wabisabi)"),
                ]),
                "status": .object([
                    "type": .string("string"),
                    "enum": .array([.string("draft"), .string("validated"), .string("in_progress"), .string("completed"), .string("abandoned")]),
                    "description": .string("Plan status"),
                ]),
                "summary": .object([
                    "type": .string("string"),
                    "description": .string("Plan summary"),
                ]),
                "waves": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("object")]),
                    "description": .string("Plan waves/phases"),
                ]),
                "branch": .object([
                    "type": .string("string"),
                    "description": .string("Git branch for this plan"),
                ]),
            ]),
        ])
    )

    static let saveEvent = MCPToolDefinition(
        name: "shiki_save_event",
        description: "Save an agent event to ShikkiDB (session start, compaction, etc.)",
        inputSchema: .object([
            "type": .string("object"),
            "required": .array([.string("eventType"), .string("data")]),
            "properties": .object([
                "eventType": .object([
                    "type": .string("string"),
                    "description": .string("Event type (e.g. context_session_start, context_compaction)"),
                ]),
                "data": .object([
                    "type": .string("object"),
                    "description": .string("Event data payload"),
                ]),
                "sessionId": .object([
                    "type": .string("string"),
                    "description": .string("Session identifier"),
                ]),
            ]),
        ])
    )

    static let saveContext = MCPToolDefinition(
        name: "shiki_save_context",
        description: "Save context/compaction state to ShikkiDB for session recovery",
        inputSchema: .object([
            "type": .string("object"),
            "required": .array([.string("sessionId"), .string("summary")]),
            "properties": .object([
                "sessionId": .object([
                    "type": .string("string"),
                    "description": .string("Session identifier"),
                ]),
                "summary": .object([
                    "type": .string("string"),
                    "description": .string("Context summary for recovery"),
                ]),
                "wipState": .object([
                    "type": .string("object"),
                    "description": .string("Work-in-progress state snapshot"),
                ]),
                "branch": .object([
                    "type": .string("string"),
                    "description": .string("Current git branch"),
                ]),
            ]),
        ])
    )

    static let saveAgentReport = MCPToolDefinition(
        name: "shiki_save_agent_report",
        description: "Save an agent report card to ShikkiDB — captures task outcome, files changed, red flags",
        inputSchema: .object([
            "type": .string("object"),
            "required": .array([.string("sessionId"), .string("persona"), .string("taskTitle"), .string("beforeState"), .string("afterState")]),
            "properties": .object([
                "sessionId": .object([
                    "type": .string("string"),
                    "description": .string("Session identifier"),
                ]),
                "persona": .object([
                    "type": .string("string"),
                    "enum": .array([
                        .string("investigate"), .string("implement"), .string("verify"),
                        .string("critique"), .string("review"), .string("fix"),
                    ]),
                    "description": .string("Agent persona that performed the task"),
                ]),
                "taskTitle": .object([
                    "type": .string("string"),
                    "description": .string("Short description of the task"),
                ]),
                "beforeState": .object([
                    "type": .string("string"),
                    "description": .string("State before the task started"),
                ]),
                "afterState": .object([
                    "type": .string("string"),
                    "description": .string("State after the task completed"),
                ]),
                "keyDecisions": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("object")]),
                    "description": .string("Key decisions made during the task"),
                ]),
                "filesChanged": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")]),
                    "description": .string("Files modified during the task"),
                ]),
                "testsAdded": .object([
                    "type": .string("integer"),
                    "description": .string("Number of tests added"),
                ]),
                "redFlags": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")]),
                    "description": .string("Issues or concerns discovered"),
                ]),
            ]),
        ])
    )

    static let saveBatch = MCPToolDefinition(
        name: "shiki_save_batch",
        description: "Save multiple items to ShikkiDB in a single call. Each item needs a type and data.",
        inputSchema: .object([
            "type": .string("object"),
            "required": .array([.string("items")]),
            "properties": .object([
                "items": .object([
                    "type": .string("array"),
                    "description": .string("Array of items to save. Each item must have 'type' (string) and 'data' (object). Optional: 'scope' (string, default 'shikki')."),
                    "items": .object([
                        "type": .string("object"),
                        "required": .array([.string("type"), .string("data")]),
                        "properties": .object([
                            "type": .object([
                                "type": .string("string"),
                                "description": .string("Data type (e.g. decision, plan, agent_event)"),
                            ]),
                            "scope": .object([
                                "type": .string("string"),
                                "description": .string("Project scope (default: shikki)"),
                            ]),
                            "data": .object([
                                "type": .string("object"),
                                "description": .string("Data payload"),
                            ]),
                        ]),
                    ]),
                ]),
            ]),
        ])
    )

    static let allDefinitions: [MCPToolDefinition] = [saveDecision, savePlan, saveEvent, saveContext, saveAgentReport, saveBatch]

    // MARK: - Execution

    static func execute(toolName: String, params: JSONValue?, dbClient: ShikkiDBClientProtocol) async -> JSONValue {
        guard let args = params?.objectValue else {
            return ToolResult.error("Invalid parameters: expected object")
        }

        switch toolName {
        case "shiki_save_decision":
            return await executeSaveDecision(args: args, dbClient: dbClient)
        case "shiki_save_plan":
            return await executeSavePlan(args: args, dbClient: dbClient)
        case "shiki_save_event":
            return await executeSaveEvent(args: args, dbClient: dbClient)
        case "shiki_save_context":
            return await executeSaveContext(args: args, dbClient: dbClient)
        case "shiki_save_agent_report":
            return await executeSaveAgentReport(args: args, dbClient: dbClient)
        case "shiki_save_batch":
            return await executeSaveBatch(args: args, dbClient: dbClient)
        default:
            return ToolResult.error("Unknown write tool: \(toolName)")
        }
    }

    // MARK: - Individual handlers

    private static func executeSaveDecision(args: [String: JSONValue], dbClient: ShikkiDBClientProtocol) async -> JSONValue {
        // Validate required fields
        guard let category = args["category"]?.stringValue else {
            return ToolResult.error("Missing required field: category")
        }
        guard args["question"]?.stringValue != nil else {
            return ToolResult.error("Missing required field: question")
        }
        guard args["choice"]?.stringValue != nil else {
            return ToolResult.error("Missing required field: choice")
        }
        guard args["rationale"]?.stringValue != nil else {
            return ToolResult.error("Missing required field: rationale")
        }

        // Validate enum
        let validCategories = ["architecture", "implementation", "process", "tradeOff", "scope"]
        guard validCategories.contains(category) else {
            return ToolResult.error("Invalid category '\(category)'. Must be one of: \(validCategories.joined(separator: ", "))")
        }

        let scope = args["project"]?.stringValue ?? "shikki"
        return await writeToDB(type: "decision", scope: scope, data: args, dbClient: dbClient)
    }

    private static func executeSavePlan(args: [String: JSONValue], dbClient: ShikkiDBClientProtocol) async -> JSONValue {
        guard args["title"]?.stringValue != nil else {
            return ToolResult.error("Missing required field: title")
        }
        guard let scope = args["scope"]?.stringValue else {
            return ToolResult.error("Missing required field: scope")
        }
        guard let status = args["status"]?.stringValue else {
            return ToolResult.error("Missing required field: status")
        }
        guard args["summary"]?.stringValue != nil else {
            return ToolResult.error("Missing required field: summary")
        }

        let validStatuses = ["draft", "validated", "in_progress", "completed", "abandoned"]
        guard validStatuses.contains(status) else {
            return ToolResult.error("Invalid status '\(status)'. Must be one of: \(validStatuses.joined(separator: ", "))")
        }

        return await writeToDB(type: "plan", scope: scope, data: args, dbClient: dbClient)
    }

    private static func executeSaveEvent(args: [String: JSONValue], dbClient: ShikkiDBClientProtocol) async -> JSONValue {
        guard let eventType = args["eventType"]?.stringValue, !eventType.isEmpty else {
            return ToolResult.error("Missing required field: eventType")
        }
        guard let data = args["data"], data.objectValue != nil else {
            return ToolResult.error("Missing required field: data (must be an object)")
        }

        // Check data is not empty
        if let obj = data.objectValue, obj.isEmpty {
            return ToolResult.error("data must not be empty")
        }

        var writeData = args
        writeData["eventType"] = .string(eventType)

        return await writeToDB(type: "agent_event", scope: "shikki", data: writeData, dbClient: dbClient)
    }

    private static func executeSaveContext(args: [String: JSONValue], dbClient: ShikkiDBClientProtocol) async -> JSONValue {
        guard args["sessionId"]?.stringValue != nil else {
            return ToolResult.error("Missing required field: sessionId")
        }
        guard args["summary"]?.stringValue != nil else {
            return ToolResult.error("Missing required field: summary")
        }

        return await writeToDB(type: "context_compaction", scope: "shikki", data: args, dbClient: dbClient)
    }

    private static func executeSaveAgentReport(args: [String: JSONValue], dbClient: ShikkiDBClientProtocol) async -> JSONValue {
        guard args["sessionId"]?.stringValue != nil else {
            return ToolResult.error("Missing required field: sessionId")
        }
        guard let persona = args["persona"]?.stringValue else {
            return ToolResult.error("Missing required field: persona")
        }
        guard args["taskTitle"]?.stringValue != nil else {
            return ToolResult.error("Missing required field: taskTitle")
        }
        guard args["beforeState"]?.stringValue != nil else {
            return ToolResult.error("Missing required field: beforeState")
        }
        guard args["afterState"]?.stringValue != nil else {
            return ToolResult.error("Missing required field: afterState")
        }

        let validPersonas = ["investigate", "implement", "verify", "critique", "review", "fix"]
        guard validPersonas.contains(persona) else {
            return ToolResult.error("Invalid persona '\(persona)'. Must be one of: \(validPersonas.joined(separator: ", "))")
        }

        return await writeToDB(type: "agent_report", scope: "shikki", data: args, dbClient: dbClient)
    }

    private static func executeSaveBatch(args: [String: JSONValue], dbClient: ShikkiDBClientProtocol) async -> JSONValue {
        guard let items = args["items"]?.arrayValue, !items.isEmpty else {
            return ToolResult.error("Missing or empty required field: items")
        }

        guard items.count <= 50 else {
            return ToolResult.error("Batch too large: \(items.count) items (max 50)")
        }

        var successes = 0
        var failures: [String] = []

        for (index, item) in items.enumerated() {
            guard let itemObj = item.objectValue else {
                failures.append("Item \(index): not an object")
                continue
            }
            guard let type = itemObj["type"]?.stringValue, !type.isEmpty else {
                failures.append("Item \(index): missing 'type'")
                continue
            }
            guard let data = itemObj["data"]?.objectValue else {
                failures.append("Item \(index): missing or invalid 'data'")
                continue
            }

            let scope = itemObj["scope"]?.stringValue ?? "shikki"
            let projectId = ShikkiDBClient.resolveProjectId(scope)

            do {
                _ = try await dbClient.dataSyncWrite(type: type, scope: scope, data: data, projectId: projectId)
                successes += 1
            } catch let error as ShikkiDBError {
                failures.append("Item \(index) (\(type)): \(error.description)")
            } catch {
                failures.append("Item \(index) (\(type)): \(error)")
            }
        }

        if failures.isEmpty {
            return ToolResult.success("Batch complete: \(successes)/\(items.count) saved")
        } else {
            let summary = "Batch partial: \(successes)/\(items.count) saved, \(failures.count) failed\n" + failures.joined(separator: "\n")
            if successes > 0 {
                return ToolResult.success(summary)
            } else {
                return ToolResult.error(summary)
            }
        }
    }

    // MARK: - Helpers

    private static func writeToDB(type: String, scope: String, data: [String: JSONValue], dbClient: ShikkiDBClientProtocol) async -> JSONValue {
        do {
            let projectId = ShikkiDBClient.resolveProjectId(scope)
            let result = try await dbClient.dataSyncWrite(type: type, scope: scope, data: data, projectId: projectId)
            return ToolResult.success("Saved \(type) to ShikkiDB", data: result)
        } catch let error as ShikkiDBError {
            return ToolResult.error("ShikkiDB error: \(error.description)")
        } catch {
            return ToolResult.error("Unexpected error: \(error)")
        }
    }
}
