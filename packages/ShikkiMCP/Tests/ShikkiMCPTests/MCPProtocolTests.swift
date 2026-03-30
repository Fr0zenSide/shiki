import Foundation
import Testing
@testable import ShikkiMCP

@Suite("MCP Protocol Types")
struct MCPProtocolTests {

    @Test("Parse valid JSON-RPC request")
    func parseValidRequest() throws {
        let json = """
        {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}
        """
        let request = try JSONDecoder().decode(JSONRPCRequest.self, from: Data(json.utf8))
        #expect(request.jsonrpc == "2.0")
        #expect(request.id == .int(1))
        #expect(request.method == "initialize")
        #expect(request.params != nil)
    }

    @Test("Parse request with string ID")
    func parseStringIdRequest() throws {
        let json = """
        {"jsonrpc":"2.0","id":"abc-123","method":"tools/list"}
        """
        let request = try JSONDecoder().decode(JSONRPCRequest.self, from: Data(json.utf8))
        #expect(request.id == .string("abc-123"))
        #expect(request.method == "tools/list")
    }

    @Test("Parse request without params")
    func parseRequestNoParams() throws {
        let json = """
        {"jsonrpc":"2.0","id":10,"method":"tools/list"}
        """
        let request = try JSONDecoder().decode(JSONRPCRequest.self, from: Data(json.utf8))
        #expect(request.params == nil)
    }

    @Test("Encode JSON-RPC response")
    func encodeResponse() throws {
        let response = JSONRPCResponse(id: .int(1), result: .object(["status": .string("ok")]))
        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(JSONRPCResponse.self, from: data)
        #expect(decoded.jsonrpc == "2.0")
        #expect(decoded.id == .int(1))
        #expect(decoded.error == nil)
        #expect(decoded.result?["status"]?.stringValue == "ok")
    }

    @Test("Tool definition encodes to valid JSON Schema")
    func toolDefinitionEncoding() throws {
        let tool = MCPToolDefinition(
            name: "test_tool",
            description: "A test tool",
            inputSchema: .object([
                "type": .string("object"),
                "required": .array([.string("name")]),
                "properties": .object([
                    "name": .object(["type": .string("string")]),
                ]),
            ])
        )
        let data = try JSONEncoder().encode(tool)
        let decoded = try JSONDecoder().decode(MCPToolDefinition.self, from: data)
        #expect(decoded.name == "test_tool")
        #expect(decoded.inputSchema["type"]?.stringValue == "object")
    }

    @Test("JSONValue round-trip encoding/decoding")
    func jsonValueRoundTrip() throws {
        let value: JSONValue = .object([
            "string": .string("hello"),
            "int": .int(42),
            "double": .double(3.14),
            "bool": .bool(true),
            "null": .null,
            "array": .array([.int(1), .string("two")]),
            "nested": .object(["key": .string("val")]),
        ])

        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded["string"]?.stringValue == "hello")
        #expect(decoded["int"]?.intValue == 42)
        #expect(decoded["bool"] == .bool(true))
        #expect(decoded["null"] == .null)
        #expect(decoded["array"]?.arrayValue?.count == 2)
    }

    @Test("JSONValue accessors return nil for wrong type")
    func jsonValueAccessorsMismatch() {
        let strVal: JSONValue = .string("hello")
        #expect(strVal.stringValue == "hello")
        #expect(strVal.intValue == nil)
        #expect(strVal.doubleValue == nil)
        #expect(strVal.boolValue == nil)
        #expect(strVal.arrayValue == nil)
        #expect(strVal.objectValue == nil)

        let intVal: JSONValue = .int(42)
        #expect(intVal.intValue == 42)
        #expect(intVal.stringValue == nil)

        let boolVal: JSONValue = .bool(false)
        #expect(boolVal.boolValue == false)
        #expect(boolVal.stringValue == nil)

        let doubleVal: JSONValue = .double(3.14)
        #expect(doubleVal.doubleValue == 3.14)
        #expect(doubleVal.intValue == nil)
    }

    @Test("JSONValue subscript returns nil for non-object")
    func jsonValueSubscriptNonObject() {
        let arr: JSONValue = .array([.string("a")])
        #expect(arr["key"] == nil)

        let str: JSONValue = .string("hello")
        #expect(str["key"] == nil)
    }

    @Test("Error response has correct code")
    func errorResponse() throws {
        let response = JSONRPCResponse(
            id: .int(5),
            error: MCPError(code: MCPError.methodNotFound, message: "Unknown method")
        )
        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(JSONRPCResponse.self, from: data)
        #expect(decoded.error?.code == -32601)
        #expect(decoded.error?.message == "Unknown method")
        #expect(decoded.result == nil)
    }

    @Test("MCPError static codes are correct")
    func errorCodes() {
        #expect(MCPError.parseError == -32700)
        #expect(MCPError.invalidRequest == -32600)
        #expect(MCPError.methodNotFound == -32601)
        #expect(MCPError.invalidParams == -32602)
        #expect(MCPError.internalError == -32603)
    }
}
