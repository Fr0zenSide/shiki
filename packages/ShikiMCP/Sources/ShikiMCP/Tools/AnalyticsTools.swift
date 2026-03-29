import Foundation

enum AnalyticsTools: Sendable {

    // MARK: - Tool Definitions

    static let dailySummary = MCPToolDefinition(
        name: "shiki_daily_summary",
        description: "Get a daily summary of agent activity — decisions made, plans validated, agents completed, red flags, test counts",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "date": .object([
                    "type": .string("string"),
                    "description": .string("ISO8601 date (YYYY-MM-DD). Defaults to today."),
                ]),
                "projectIds": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")]),
                    "description": .string("Filter by project IDs"),
                ]),
            ]),
        ])
    )

    static let decisionChain = MCPToolDefinition(
        name: "shiki_decision_chain",
        description: "Get the full decision chain from a root decision — traces parent-child decision relationships",
        inputSchema: .object([
            "type": .string("object"),
            "required": .array([.string("decisionId")]),
            "properties": .object([
                "decisionId": .object([
                    "type": .string("string"),
                    "description": .string("Root decision ID to trace the chain from"),
                ]),
            ]),
        ])
    )

    static let agentEffectiveness = MCPToolDefinition(
        name: "shiki_agent_effectiveness",
        description: "Get per-persona success rates, average duration, and context resets",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "since": .object([
                    "type": .string("string"),
                    "description": .string("ISO8601 date to filter from (e.g. 2026-03-01)"),
                ]),
                "projectIds": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")]),
                    "description": .string("Filter by project IDs"),
                ]),
            ]),
        ])
    )

    static let allDefinitions: [MCPToolDefinition] = [dailySummary, decisionChain, agentEffectiveness]

    // MARK: - Execution

    static func execute(toolName: String, params: JSONValue?, dbClient: ShikiDBClientProtocol) async -> JSONValue {
        let args = params?.objectValue ?? [:]

        switch toolName {
        case "shiki_daily_summary":
            return await executeDailySummary(args: args, dbClient: dbClient)
        case "shiki_decision_chain":
            return await executeDecisionChain(args: args, dbClient: dbClient)
        case "shiki_agent_effectiveness":
            return await executeAgentEffectiveness(args: args, dbClient: dbClient)
        default:
            return WriteTools.errorResult("Unknown analytics tool: \(toolName)")
        }
    }

    // MARK: - Individual handlers

    private static func executeDailySummary(args: [String: JSONValue], dbClient: ShikiDBClientProtocol) async -> JSONValue {
        let dateString = args["date"]?.stringValue ?? todayISO8601()
        let projectIds = args["projectIds"]?.arrayValue?.compactMap(\.stringValue)

        // Validate date format
        guard isValidDateString(dateString) else {
            return WriteTools.errorResult("Invalid date format '\(dateString)'. Expected YYYY-MM-DD.")
        }

        // Fetch decisions, plans, reports, and events for the day
        var sections: [String] = []
        sections.append("Daily Summary for \(dateString)")
        sections.append("=" + String(repeating: "=", count: 39))

        // Decisions
        let decisionsResult = await fetchForDay(
            query: "decision \(dateString)",
            types: ["decision"],
            projectIds: projectIds,
            dbClient: dbClient
        )
        sections.append(formatSection("Decisions", result: decisionsResult))

        // Plans
        let plansResult = await fetchForDay(
            query: "plan \(dateString)",
            types: ["plan"],
            projectIds: projectIds,
            dbClient: dbClient
        )
        sections.append(formatSection("Plans", result: plansResult))

        // Agent reports
        let reportsResult = await fetchForDay(
            query: "report \(dateString)",
            types: ["agent_report", "report"],
            projectIds: projectIds,
            dbClient: dbClient
        )
        sections.append(formatSection("Agent Reports", result: reportsResult))

        // Events
        let eventsResult = await fetchForDay(
            query: "event \(dateString)",
            types: ["agent_event"],
            projectIds: projectIds,
            dbClient: dbClient
        )
        sections.append(formatSection("Events", result: eventsResult))

        let summary = sections.joined(separator: "\n\n")
        return WriteTools.successResult(summary)
    }

    private static func executeDecisionChain(args: [String: JSONValue], dbClient: ShikiDBClientProtocol) async -> JSONValue {
        guard let decisionId = args["decisionId"]?.stringValue, !decisionId.isEmpty else {
            return WriteTools.errorResult("Missing required field: decisionId")
        }

        // Search for the root decision and any linked decisions
        do {
            let rootResult = try await dbClient.memoriesSearch(
                query: "decisionId:\(decisionId)",
                projectIds: nil,
                types: ["decision"],
                limit: 1
            )

            // Search for children referencing this as parentDecisionId
            let childrenResult = try await dbClient.memoriesSearch(
                query: "parentDecisionId:\(decisionId)",
                projectIds: nil,
                types: ["decision"],
                limit: 50
            )

            let chain: JSONValue = .object([
                "rootDecisionId": .string(decisionId),
                "root": rootResult,
                "children": childrenResult,
            ])

            return WriteTools.successResult("Decision chain for \(decisionId)", data: chain)
        } catch let error as ShikiDBError {
            return WriteTools.errorResult("ShikiDB error: \(error.description)")
        } catch {
            return WriteTools.errorResult("Unexpected error: \(error)")
        }
    }

    private static func executeAgentEffectiveness(args: [String: JSONValue], dbClient: ShikiDBClientProtocol) async -> JSONValue {
        let since = args["since"]?.stringValue
        let projectIds = args["projectIds"]?.arrayValue?.compactMap(\.stringValue)

        if let since = since, !isValidDateString(since) {
            return WriteTools.errorResult("Invalid date format '\(since)'. Expected YYYY-MM-DD.")
        }

        var query = "agent report effectiveness"
        if let since = since {
            query += " since:\(since)"
        }

        do {
            let result = try await dbClient.memoriesSearch(
                query: query,
                projectIds: projectIds,
                types: ["agent_report", "report"],
                limit: 100
            )
            return WriteTools.successResult("Agent effectiveness data", data: result)
        } catch let error as ShikiDBError {
            return WriteTools.errorResult("ShikiDB error: \(error.description)")
        } catch {
            return WriteTools.errorResult("Unexpected error: \(error)")
        }
    }

    // MARK: - Helpers

    private static func todayISO8601() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: Date())
    }

    static func isValidDateString(_ dateString: String) -> Bool {
        // Strict regex check for YYYY-MM-DD format
        let pattern = #"^\d{4}-\d{2}-\d{2}$"#
        guard dateString.range(of: pattern, options: .regularExpression) != nil else {
            return false
        }
        // Also verify it parses to a real date
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: dateString) != nil
    }

    private static func fetchForDay(
        query: String,
        types: [String],
        projectIds: [String]?,
        dbClient: ShikiDBClientProtocol
    ) async -> Result<JSONValue, ShikiDBError> {
        do {
            let result = try await dbClient.memoriesSearch(
                query: query,
                projectIds: projectIds,
                types: types,
                limit: 50
            )
            return .success(result)
        } catch let error as ShikiDBError {
            return .failure(error)
        } catch {
            return .failure(.unexpectedError("\(error)"))
        }
    }

    private static func formatSection(_ title: String, result: Result<JSONValue, ShikiDBError>) -> String {
        switch result {
        case .success(let value):
            let count: Int
            if let arr = value.arrayValue {
                count = arr.count
            } else if let obj = value.objectValue, let arr = obj["results"]?.arrayValue {
                count = arr.count
            } else {
                count = 0
            }
            return "\(title): \(count) found"
        case .failure(let error):
            return "\(title): error — \(error.description)"
        }
    }
}
