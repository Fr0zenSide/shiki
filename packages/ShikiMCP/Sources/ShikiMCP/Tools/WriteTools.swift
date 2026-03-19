import Foundation

enum WriteTools: Sendable {

    // MARK: - Tool Definitions

    static let saveDecision = MCPToolDefinition(
        name: "shiki_save_decision",
        description: "Save an architecture/implementation decision to ShikiDB",
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
                    "description": .string("Project name (e.g. shiki, maya)"),
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
        description: "Save a validated plan to ShikiDB",
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
                    "description": .string("Project scope (e.g. shiki, maya, wabisabi)"),
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
        description: "Save an agent event to ShikiDB (session start, compaction, etc.)",
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
        description: "Save context/compaction state to ShikiDB for session recovery",
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

    static let allDefinitions: [MCPToolDefinition] = [saveDecision, savePlan, saveEvent, saveContext]

    // MARK: - Execution

    static func execute(toolName: String, params: JSONValue?, dbClient: ShikiDBClientProtocol) async -> JSONValue {
        guard let args = params?.objectValue else {
            return errorResult("Invalid parameters: expected object")
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
        default:
            return errorResult("Unknown write tool: \(toolName)")
        }
    }

    // MARK: - Individual handlers

    private static func executeSaveDecision(args: [String: JSONValue], dbClient: ShikiDBClientProtocol) async -> JSONValue {
        // Validate required fields
        guard let category = args["category"]?.stringValue else {
            return errorResult("Missing required field: category")
        }
        guard args["question"]?.stringValue != nil else {
            return errorResult("Missing required field: question")
        }
        guard args["choice"]?.stringValue != nil else {
            return errorResult("Missing required field: choice")
        }
        guard args["rationale"]?.stringValue != nil else {
            return errorResult("Missing required field: rationale")
        }

        // Validate enum
        let validCategories = ["architecture", "implementation", "process", "tradeOff", "scope"]
        guard validCategories.contains(category) else {
            return errorResult("Invalid category '\(category)'. Must be one of: \(validCategories.joined(separator: ", "))")
        }

        let scope = args["project"]?.stringValue ?? "shiki"
        return await writeToDB(type: "decision", scope: scope, data: args, dbClient: dbClient)
    }

    private static func executeSavePlan(args: [String: JSONValue], dbClient: ShikiDBClientProtocol) async -> JSONValue {
        guard args["title"]?.stringValue != nil else {
            return errorResult("Missing required field: title")
        }
        guard let scope = args["scope"]?.stringValue else {
            return errorResult("Missing required field: scope")
        }
        guard let status = args["status"]?.stringValue else {
            return errorResult("Missing required field: status")
        }
        guard args["summary"]?.stringValue != nil else {
            return errorResult("Missing required field: summary")
        }

        let validStatuses = ["draft", "validated", "in_progress", "completed", "abandoned"]
        guard validStatuses.contains(status) else {
            return errorResult("Invalid status '\(status)'. Must be one of: \(validStatuses.joined(separator: ", "))")
        }

        return await writeToDB(type: "plan", scope: scope, data: args, dbClient: dbClient)
    }

    private static func executeSaveEvent(args: [String: JSONValue], dbClient: ShikiDBClientProtocol) async -> JSONValue {
        guard let eventType = args["eventType"]?.stringValue, !eventType.isEmpty else {
            return errorResult("Missing required field: eventType")
        }
        guard let data = args["data"], data.objectValue != nil else {
            return errorResult("Missing required field: data (must be an object)")
        }

        // Check data is not empty
        if let obj = data.objectValue, obj.isEmpty {
            return errorResult("data must not be empty")
        }

        var writeData = args
        writeData["eventType"] = .string(eventType)

        return await writeToDB(type: "agent_event", scope: "shiki", data: writeData, dbClient: dbClient)
    }

    private static func executeSaveContext(args: [String: JSONValue], dbClient: ShikiDBClientProtocol) async -> JSONValue {
        guard args["sessionId"]?.stringValue != nil else {
            return errorResult("Missing required field: sessionId")
        }
        guard args["summary"]?.stringValue != nil else {
            return errorResult("Missing required field: summary")
        }

        return await writeToDB(type: "context_compaction", scope: "shiki", data: args, dbClient: dbClient)
    }

    // MARK: - Helpers

    private static func writeToDB(type: String, scope: String, data: [String: JSONValue], dbClient: ShikiDBClientProtocol) async -> JSONValue {
        do {
            let result = try await dbClient.dataSyncWrite(type: type, scope: scope, data: data)
            return successResult("Saved \(type) to ShikiDB", data: result)
        } catch let error as ShikiDBError {
            return errorResult("ShikiDB error: \(error.description)")
        } catch {
            return errorResult("Unexpected error: \(error)")
        }
    }

    static func successResult(_ message: String, data: JSONValue? = nil) -> JSONValue {
        var text = message
        if let data = data {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            if let jsonData = try? encoder.encode(data),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                text += "\n\(jsonString)"
            }
        }
        return .object([
            "content": .array([
                .object([
                    "type": .string("text"),
                    "text": .string(text),
                ])
            ]),
        ])
    }

    static func errorResult(_ message: String) -> JSONValue {
        .object([
            "content": .array([
                .object([
                    "type": .string("text"),
                    "text": .string(message),
                ])
            ]),
            "isError": .bool(true),
        ])
    }
}
