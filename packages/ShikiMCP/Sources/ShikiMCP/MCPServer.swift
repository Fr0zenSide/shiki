import Foundation
import Logging

actor MCPServer {
    private let dbClient: ShikiDBClientProtocol
    private let logger = Logger(label: "shiki.mcp.server")

    private let allTools: [MCPToolDefinition]
    private let writeToolNames: Set<String>
    private let readToolNames: Set<String>
    private let analyticsToolNames: Set<String>

    init(dbClient: ShikiDBClientProtocol) {
        self.dbClient = dbClient
        self.allTools = WriteTools.allDefinitions + ReadTools.allDefinitions + AnalyticsTools.allDefinitions + [HealthTool.definition]
        self.writeToolNames = Set(WriteTools.allDefinitions.map(\.name))
        self.readToolNames = Set(ReadTools.allDefinitions.map(\.name))
        self.analyticsToolNames = Set(AnalyticsTools.allDefinitions.map(\.name))
    }

    // MARK: - Main loop

    func run() async {
        logger.info("ShikiMCP server starting")

        let stdout = FileHandle.standardOutput

        while let line = readLine() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let responseJSON = await handleMessage(trimmed)

            if let data = responseJSON.data(using: .utf8) {
                stdout.write(data)
                stdout.write(Data("\n".utf8))
            }
        }

        logger.info("ShikiMCP server shutting down")
    }

    // MARK: - Message handling (also used by tests)

    func handleMessage(_ message: String) async -> String {
        guard let data = message.data(using: .utf8) else {
            return encodeResponse(JSONRPCResponse(id: nil, error: MCPError(code: MCPError.parseError, message: "Invalid UTF-8")))
        }

        let request: JSONRPCRequest
        do {
            request = try JSONDecoder().decode(JSONRPCRequest.self, from: data)
        } catch {
            return encodeResponse(JSONRPCResponse(id: nil, error: MCPError(code: MCPError.parseError, message: "Parse error: \(error.localizedDescription)")))
        }

        let response = await dispatch(request)
        return encodeResponse(response)
    }

    // MARK: - Dispatch

    private func dispatch(_ request: JSONRPCRequest) async -> JSONRPCResponse {
        switch request.method {
        case "initialize":
            return handleInitialize(request)
        case "initialized":
            // Notification, no response needed — but we return ack for safety
            return JSONRPCResponse(id: request.id, result: .object([:]))
        case "tools/list":
            return handleToolsList(request)
        case "tools/call":
            return await handleToolsCall(request)
        default:
            return JSONRPCResponse(
                id: request.id,
                error: MCPError(code: MCPError.methodNotFound, message: "Unknown method: \(request.method)")
            )
        }
    }

    // MARK: - Handlers

    private func handleInitialize(_ request: JSONRPCRequest) -> JSONRPCResponse {
        let result: JSONValue = .object([
            "protocolVersion": .string("2024-11-05"),
            "capabilities": .object([
                "tools": .object([:]),
            ]),
            "serverInfo": .object([
                "name": .string("shiki-mcp"),
                "version": .string("1.0.0"),
            ]),
        ])
        return JSONRPCResponse(id: request.id, result: result)
    }

    private func handleToolsList(_ request: JSONRPCRequest) -> JSONRPCResponse {
        let tools: [JSONValue] = allTools.map { tool in
            .object([
                "name": .string(tool.name),
                "description": .string(tool.description),
                "inputSchema": tool.inputSchema,
            ])
        }
        return JSONRPCResponse(id: request.id, result: .object(["tools": .array(tools)]))
    }

    private func handleToolsCall(_ request: JSONRPCRequest) async -> JSONRPCResponse {
        guard let params = request.params?.objectValue,
              let toolName = params["name"]?.stringValue else {
            return JSONRPCResponse(
                id: request.id,
                error: MCPError(code: MCPError.invalidParams, message: "Missing tool name in params")
            )
        }

        let arguments = params["arguments"]

        let result: JSONValue
        if writeToolNames.contains(toolName) {
            result = await WriteTools.execute(toolName: toolName, params: arguments, dbClient: dbClient)
        } else if readToolNames.contains(toolName) {
            result = await ReadTools.execute(toolName: toolName, params: arguments, dbClient: dbClient)
        } else if analyticsToolNames.contains(toolName) {
            result = await AnalyticsTools.execute(toolName: toolName, params: arguments, dbClient: dbClient)
        } else if toolName == "shiki_health" {
            result = await HealthTool.execute(params: arguments, dbClient: dbClient)
        } else {
            return JSONRPCResponse(
                id: request.id,
                error: MCPError(code: MCPError.invalidParams, message: "Unknown tool: \(toolName)")
            )
        }

        return JSONRPCResponse(id: request.id, result: result)
    }

    // MARK: - Encoding

    private func encodeResponse(_ response: JSONRPCResponse) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(response),
              let str = String(data: data, encoding: .utf8) else {
            return #"{"jsonrpc":"2.0","id":null,"error":{"code":-32603,"message":"Internal encoding error"}}"#
        }
        return str
    }
}
