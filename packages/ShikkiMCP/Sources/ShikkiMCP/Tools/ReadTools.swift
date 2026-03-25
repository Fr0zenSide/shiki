import Foundation

enum ReadTools: Sendable {

    // MARK: - Tool Definitions

    static let search = MCPToolDefinition(
        name: "shiki_search",
        description: "Search ShikkiDB memories by query. Returns ranked results across all types.",
        inputSchema: .object([
            "type": .string("object"),
            "required": .array([.string("query")]),
            "properties": .object([
                "query": .object([
                    "type": .string("string"),
                    "description": .string("Search query text"),
                ]),
                "projectIds": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")]),
                    "description": .string("Filter by project IDs"),
                ]),
                "types": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")]),
                    "description": .string("Filter by memory types (e.g. decision, plan, context_compaction)"),
                ]),
                "limit": .object([
                    "type": .string("integer"),
                    "description": .string("Maximum results to return (default 10)"),
                ]),
            ]),
        ])
    )

    static let getDecisions = MCPToolDefinition(
        name: "shiki_get_decisions",
        description: "Get architecture/implementation decisions from ShikkiDB",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "query": .object([
                    "type": .string("string"),
                    "description": .string("Search query to filter decisions"),
                ]),
                "projectIds": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")]),
                    "description": .string("Filter by project IDs"),
                ]),
                "limit": .object([
                    "type": .string("integer"),
                    "description": .string("Maximum results (default 10)"),
                ]),
            ]),
        ])
    )

    static let getReports = MCPToolDefinition(
        name: "shiki_get_reports",
        description: "Get weekly/session reports from ShikkiDB",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "query": .object([
                    "type": .string("string"),
                    "description": .string("Search query to filter reports"),
                ]),
                "limit": .object([
                    "type": .string("integer"),
                    "description": .string("Maximum results (default 5)"),
                ]),
            ]),
        ])
    )

    static let getContext = MCPToolDefinition(
        name: "shiki_get_context",
        description: "Get context/compaction snapshots for session recovery",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "sessionId": .object([
                    "type": .string("string"),
                    "description": .string("Filter by session ID"),
                ]),
                "query": .object([
                    "type": .string("string"),
                    "description": .string("Search query"),
                ]),
                "limit": .object([
                    "type": .string("integer"),
                    "description": .string("Maximum results (default 5)"),
                ]),
            ]),
        ])
    )

    static let getPlans = MCPToolDefinition(
        name: "shiki_get_plans",
        description: "Get saved plans from ShikkiDB",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "query": .object([
                    "type": .string("string"),
                    "description": .string("Search query to filter plans"),
                ]),
                "status": .object([
                    "type": .string("string"),
                    "enum": .array([.string("draft"), .string("validated"), .string("in_progress"), .string("completed"), .string("abandoned")]),
                    "description": .string("Filter by plan status"),
                ]),
                "limit": .object([
                    "type": .string("integer"),
                    "description": .string("Maximum results (default 10)"),
                ]),
            ]),
        ])
    )

    static let allDefinitions: [MCPToolDefinition] = [search, getDecisions, getReports, getContext, getPlans]

    // MARK: - Execution

    static func execute(toolName: String, params: JSONValue?, dbClient: ShikkiDBClientProtocol) async -> JSONValue {
        let args = params?.objectValue ?? [:]

        switch toolName {
        case "shiki_search":
            return await executeSearch(args: args, dbClient: dbClient)
        case "shiki_get_decisions":
            return await executeGetDecisions(args: args, dbClient: dbClient)
        case "shiki_get_reports":
            return await executeGetReports(args: args, dbClient: dbClient)
        case "shiki_get_context":
            return await executeGetContext(args: args, dbClient: dbClient)
        case "shiki_get_plans":
            return await executeGetPlans(args: args, dbClient: dbClient)
        default:
            return WriteTools.errorResult("Unknown read tool: \(toolName)")
        }
    }

    // MARK: - Individual handlers

    private static func executeSearch(args: [String: JSONValue], dbClient: ShikkiDBClientProtocol) async -> JSONValue {
        guard let query = args["query"]?.stringValue, !query.isEmpty else {
            return WriteTools.errorResult("Missing required field: query")
        }

        let projectIds = args["projectIds"]?.arrayValue?.compactMap(\.stringValue)
        let types = args["types"]?.arrayValue?.compactMap(\.stringValue)
        let limit = args["limit"]?.intValue ?? 10

        return await searchDB(query: query, projectIds: projectIds, types: types, limit: limit, dbClient: dbClient)
    }

    private static func executeGetDecisions(args: [String: JSONValue], dbClient: ShikkiDBClientProtocol) async -> JSONValue {
        let query = args["query"]?.stringValue ?? "decision"
        let projectIds = args["projectIds"]?.arrayValue?.compactMap(\.stringValue)
        let limit = args["limit"]?.intValue ?? 10

        return await searchDB(query: query, projectIds: projectIds, types: ["decision"], limit: limit, dbClient: dbClient)
    }

    private static func executeGetReports(args: [String: JSONValue], dbClient: ShikkiDBClientProtocol) async -> JSONValue {
        let query = args["query"]?.stringValue ?? "report"
        let limit = args["limit"]?.intValue ?? 5

        return await searchDB(query: query, projectIds: nil, types: ["report"], limit: limit, dbClient: dbClient)
    }

    private static func executeGetContext(args: [String: JSONValue], dbClient: ShikkiDBClientProtocol) async -> JSONValue {
        var query = args["query"]?.stringValue ?? "context"
        if let sessionId = args["sessionId"]?.stringValue {
            query = "sessionId:\(sessionId) \(query)"
        }
        let limit = args["limit"]?.intValue ?? 5

        return await searchDB(query: query, projectIds: nil, types: ["context_compaction"], limit: limit, dbClient: dbClient)
    }

    private static func executeGetPlans(args: [String: JSONValue], dbClient: ShikkiDBClientProtocol) async -> JSONValue {
        var query = args["query"]?.stringValue ?? "plan"
        if let status = args["status"]?.stringValue {
            query = "status:\(status) \(query)"
        }
        let limit = args["limit"]?.intValue ?? 10

        return await searchDB(query: query, projectIds: nil, types: ["plan"], limit: limit, dbClient: dbClient)
    }

    // MARK: - Helpers

    private static func searchDB(query: String, projectIds: [String]?, types: [String]?, limit: Int, dbClient: ShikkiDBClientProtocol) async -> JSONValue {
        do {
            let result = try await dbClient.memoriesSearch(query: query, projectIds: projectIds, types: types, limit: limit)
            return WriteTools.successResult("Search results", data: result)
        } catch let error as ShikkiDBError {
            return WriteTools.errorResult("ShikkiDB error: \(error.description)")
        } catch {
            return WriteTools.errorResult("Unexpected error: \(error)")
        }
    }
}
