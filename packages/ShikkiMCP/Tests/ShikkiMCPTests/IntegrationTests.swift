import Foundation
import Testing
@testable import ShikkiMCP

@Suite("Integration — stdin/stdout round-trip")
struct IntegrationTests {

    @Test("Initialize returns server info")
    func initializeRoundTrip() async throws {
        let mock = MockDBClient()
        let server = MCPServer(dbClient: mock)

        let request = """
        {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}
        """
        let responseStr = await server.handleMessage(request)
        let response = try JSONDecoder().decode(JSONRPCResponse.self, from: Data(responseStr.utf8))

        #expect(response.id == .int(1))
        #expect(response.error == nil)
        #expect(response.result?["protocolVersion"]?.stringValue == "2024-11-05")
        #expect(response.result?["serverInfo"]?["name"]?.stringValue == "shikki-mcp")
        #expect(response.result?["serverInfo"]?["version"]?.stringValue == "1.1.0")
    }

    @Test("tools/list returns all tool definitions")
    func toolsList() async throws {
        let mock = MockDBClient()
        let server = MCPServer(dbClient: mock)

        let request = """
        {"jsonrpc":"2.0","id":2,"method":"tools/list"}
        """
        let responseStr = await server.handleMessage(request)
        let response = try JSONDecoder().decode(JSONRPCResponse.self, from: Data(responseStr.utf8))

        #expect(response.error == nil)
        let tools = response.result?["tools"]?.arrayValue
        #expect(tools != nil)

        // Should have all write + read + analytics + health tools
        let expectedCount = WriteTools.allDefinitions.count + ReadTools.allDefinitions.count + AnalyticsTools.allDefinitions.count + 1
        #expect(tools?.count == expectedCount)

        // Check tool names are present
        let names = tools?.compactMap { $0["name"]?.stringValue } ?? []
        #expect(names.contains("shiki_save_decision"))
        #expect(names.contains("shiki_save_batch"))
        #expect(names.contains("shiki_search"))
        #expect(names.contains("shiki_health"))
        #expect(names.contains("shiki_daily_summary"))
    }

    @Test("tools/call with valid input returns success")
    func toolsCallValid() async throws {
        let mock = MockDBClient()
        mock.dataSyncResult = .object(["id": .string("new-id")])
        let server = MCPServer(dbClient: mock)

        let request = """
        {"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"shiki_save_decision","arguments":{"category":"architecture","question":"DB?","choice":"SQLite","rationale":"Fast"}}}
        """
        let responseStr = await server.handleMessage(request)
        let response = try JSONDecoder().decode(JSONRPCResponse.self, from: Data(responseStr.utf8))

        #expect(response.error == nil)
        #expect(response.result?["isError"] == nil)

        let content = response.result?["content"]?.arrayValue
        #expect(content != nil)
        #expect(content?.first?["type"]?.stringValue == "text")
    }

    @Test("tools/call with invalid input returns validation error")
    func toolsCallInvalid() async throws {
        let mock = MockDBClient()
        let server = MCPServer(dbClient: mock)

        let request = """
        {"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"shiki_save_decision","arguments":{"category":"architecture"}}}
        """
        let responseStr = await server.handleMessage(request)
        let response = try JSONDecoder().decode(JSONRPCResponse.self, from: Data(responseStr.utf8))

        // Should return tool-level error in result, not JSON-RPC error
        #expect(response.error == nil)
        #expect(response.result?["isError"] == .bool(true))
    }

    @Test("tools/call with DB down returns graceful error")
    func toolsCallDBDown() async throws {
        let mock = MockDBClient()
        mock.shouldThrow = .connectionRefused(underlying: "Connection refused")
        let server = MCPServer(dbClient: mock)

        let request = """
        {"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"shiki_search","arguments":{"query":"test"}}}
        """
        let responseStr = await server.handleMessage(request)
        let response = try JSONDecoder().decode(JSONRPCResponse.self, from: Data(responseStr.utf8))

        // Should return graceful error, not crash
        #expect(response.error == nil)
        #expect(response.result?["isError"] == .bool(true))
        let text = response.result?["content"]?.arrayValue?.first?["text"]?.stringValue ?? ""
        #expect(text.contains("Connection refused"))
    }

    @Test("Unknown method returns method not found error")
    func unknownMethod() async throws {
        let mock = MockDBClient()
        let server = MCPServer(dbClient: mock)

        let request = """
        {"jsonrpc":"2.0","id":6,"method":"unknown/method"}
        """
        let responseStr = await server.handleMessage(request)
        let response = try JSONDecoder().decode(JSONRPCResponse.self, from: Data(responseStr.utf8))

        #expect(response.error?.code == MCPError.methodNotFound)
    }

    @Test("Invalid JSON returns parse error")
    func invalidJSON() async throws {
        let mock = MockDBClient()
        let server = MCPServer(dbClient: mock)

        let responseStr = await server.handleMessage("not json at all")
        let response = try JSONDecoder().decode(JSONRPCResponse.self, from: Data(responseStr.utf8))

        #expect(response.error?.code == MCPError.parseError)
    }

    @Test("tools/call with missing tool name returns error")
    func toolsCallMissingName() async throws {
        let mock = MockDBClient()
        let server = MCPServer(dbClient: mock)

        let request = """
        {"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"arguments":{}}}
        """
        let responseStr = await server.handleMessage(request)
        let response = try JSONDecoder().decode(JSONRPCResponse.self, from: Data(responseStr.utf8))

        #expect(response.error?.code == MCPError.invalidParams)
        #expect(response.error?.message.contains("Missing tool name") == true)
    }

    @Test("tools/call with unknown tool returns error")
    func toolsCallUnknownTool() async throws {
        let mock = MockDBClient()
        let server = MCPServer(dbClient: mock)

        let request = """
        {"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"nonexistent_tool","arguments":{}}}
        """
        let responseStr = await server.handleMessage(request)
        let response = try JSONDecoder().decode(JSONRPCResponse.self, from: Data(responseStr.utf8))

        #expect(response.error?.code == MCPError.invalidParams)
        #expect(response.error?.message.contains("Unknown tool") == true)
    }

    @Test("initialized notification returns ack")
    func initializedNotification() async throws {
        let mock = MockDBClient()
        let server = MCPServer(dbClient: mock)

        let request = """
        {"jsonrpc":"2.0","id":9,"method":"initialized"}
        """
        let responseStr = await server.handleMessage(request)
        let response = try JSONDecoder().decode(JSONRPCResponse.self, from: Data(responseStr.utf8))

        #expect(response.error == nil)
        #expect(response.result == .object([:]))
    }

    @Test("Request counter increments")
    func requestCounter() async throws {
        let mock = MockDBClient()
        let server = MCPServer(dbClient: mock)

        let count0 = await server.processedRequestCount
        #expect(count0 == 0)

        _ = await server.handleMessage("""
        {"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}
        """)

        let count1 = await server.processedRequestCount
        #expect(count1 == 1)

        _ = await server.handleMessage("""
        {"jsonrpc":"2.0","id":2,"method":"tools/list"}
        """)

        let count2 = await server.processedRequestCount
        #expect(count2 == 2)
    }
}
