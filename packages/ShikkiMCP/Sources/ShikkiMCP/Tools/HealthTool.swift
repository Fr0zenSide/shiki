import Foundation

enum HealthTool: Sendable {
    static let definition = MCPToolDefinition(
        name: "shiki_health",
        description: "Check if the ShikkiDB backend is reachable and healthy",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([:]),
        ])
    )

    static func execute(params: JSONValue?, dbClient: ShikkiDBClientProtocol) async -> JSONValue {
        do {
            let healthy = try await dbClient.healthCheck()
            return .object([
                "content": .array([
                    .object([
                        "type": .string("text"),
                        "text": .string(healthy ? "ShikkiDB is healthy" : "ShikkiDB is not responding"),
                    ])
                ]),
                "isError": .bool(!healthy),
            ])
        } catch {
            return .object([
                "content": .array([
                    .object([
                        "type": .string("text"),
                        "text": .string("Health check failed: \(error)"),
                    ])
                ]),
                "isError": .bool(true),
            ])
        }
    }
}
