import Foundation

// MARK: - JSON-RPC Types

struct JSONRPCRequest: Codable, Sendable {
    let jsonrpc: String
    let id: JSONRPCId?
    let method: String
    let params: JSONValue?
}

struct JSONRPCResponse: Codable, Sendable {
    let jsonrpc: String
    let id: JSONRPCId?
    let result: JSONValue?
    let error: MCPError?

    init(id: JSONRPCId?, result: JSONValue) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = result
        self.error = nil
    }

    init(id: JSONRPCId?, error: MCPError) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = nil
        self.error = error
    }
}

/// JSON-RPC id can be int, string, or null
enum JSONRPCId: Codable, Sendable, Equatable {
    case int(Int)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            self = .int(intVal)
        } else if let strVal = try? container.decode(String.self) {
            self = .string(strVal)
        } else {
            throw DecodingError.typeMismatch(
                JSONRPCId.self,
                .init(codingPath: decoder.codingPath, debugDescription: "Expected int or string for JSON-RPC id")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let v): try container.encode(v)
        case .string(let v): try container.encode(v)
        }
    }
}

struct MCPError: Codable, Sendable {
    let code: Int
    let message: String
    let data: JSONValue?

    init(code: Int, message: String, data: JSONValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }

    // Standard JSON-RPC error codes
    static let parseError = -32700
    static let invalidRequest = -32600
    static let methodNotFound = -32601
    static let invalidParams = -32602
    static let internalError = -32603
}

// MARK: - MCP Tool Definition

struct MCPToolDefinition: Codable, Sendable {
    let name: String
    let description: String
    let inputSchema: JSONValue
}

// MARK: - MCP Content

struct MCPTextContent: Codable, Sendable {
    let type: String
    let text: String

    init(text: String) {
        self.type = "text"
        self.text = text
    }
}

// MARK: - JSONValue

enum JSONValue: Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])
}

extension JSONValue: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
            return
        }
        if let boolVal = try? container.decode(Bool.self) {
            self = .bool(boolVal)
            return
        }
        if let intVal = try? container.decode(Int.self) {
            self = .int(intVal)
            return
        }
        if let doubleVal = try? container.decode(Double.self) {
            self = .double(doubleVal)
            return
        }
        if let strVal = try? container.decode(String.self) {
            self = .string(strVal)
            return
        }
        if let arrVal = try? container.decode([JSONValue].self) {
            self = .array(arrVal)
            return
        }
        if let objVal = try? container.decode([String: JSONValue].self) {
            self = .object(objVal)
            return
        }

        throw DecodingError.typeMismatch(
            JSONValue.self,
            .init(codingPath: decoder.codingPath, debugDescription: "Cannot decode JSONValue")
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .null: try container.encodeNil()
        case .array(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        }
    }
}

// MARK: - JSONValue helpers

extension JSONValue {
    /// Access a string value or nil
    var stringValue: String? {
        if case .string(let v) = self { return v }
        return nil
    }

    /// Access an int value or nil
    var intValue: Int? {
        if case .int(let v) = self { return v }
        return nil
    }

    /// Access an object value or nil
    var objectValue: [String: JSONValue]? {
        if case .object(let v) = self { return v }
        return nil
    }

    /// Access an array value or nil
    var arrayValue: [JSONValue]? {
        if case .array(let v) = self { return v }
        return nil
    }

    /// Subscript for object keys
    subscript(key: String) -> JSONValue? {
        guard case .object(let dict) = self else { return nil }
        return dict[key]
    }
}
