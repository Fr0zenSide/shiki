import Foundation

enum HealthTool: Sendable {
    static let definition = MCPToolDefinition(
        name: "shiki_health",
        description: "Check if the ShikiDB backend is reachable and healthy",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([:]),
        ])
    )

    static func execute(params: JSONValue?, dbClient: ShikiDBClientProtocol) async -> JSONValue {
        do {
            let healthy = try await dbClient.healthCheck()
            return .object([
                "content": .array([
                    .object([
                        "type": .string("text"),
                        "text": .string(healthy ? "ShikiDB is healthy" : "ShikiDB is not responding"),
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
