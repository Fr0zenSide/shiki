import Foundation

/// Shared MCP tool result builders
enum ToolResult: Sendable {

    static func success(_ message: String, data: JSONValue? = nil) -> JSONValue {
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
                ]),
            ]),
        ])
    }

    static func error(_ message: String) -> JSONValue {
        .object([
            "content": .array([
                .object([
                    "type": .string("text"),
                    "text": .string(message),
                ]),
            ]),
            "isError": .bool(true),
        ])
    }
}
