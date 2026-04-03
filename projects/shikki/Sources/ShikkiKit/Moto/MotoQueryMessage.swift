import Foundation

// MARK: - MotoQueryRequest

/// Request payload for remote Moto cache queries over NATS.
///
/// Sent by `MotoRemoteResolver` to a remote node's `MotoQueryHandler`.
/// The `tool` field maps to MCP tool names (e.g. `moto_get_type`),
/// and `args` carries the tool parameters as string key-value pairs.
public struct MotoQueryRequest: Codable, Sendable {
    /// MCP tool name to invoke (e.g. "moto_get_type", "moto_get_protocol").
    public let tool: String

    /// Tool arguments as string key-value pairs.
    public let args: [String: String]

    public init(tool: String, args: [String: String] = [:]) {
        self.tool = tool
        self.args = args
    }
}

// MARK: - MotoQueryResponse

/// Response payload from a remote Moto cache query over NATS.
///
/// Returned by `MotoQueryHandler` after delegating to the local `MotoMCPInterface`.
/// Contains either the tool result in `data` (when `ok == true`) or an error message.
public struct MotoQueryResponse: Codable, Sendable {
    /// Whether the query succeeded.
    public let ok: Bool

    /// JSON payload from the MCP tool (nil on error).
    public let data: Data?

    /// Error message (nil on success).
    public let error: String?

    /// Node ID that produced this response.
    public let nodeId: String

    /// Cache version from the .moto dotfile.
    public let cacheVersion: String

    public init(
        ok: Bool,
        data: Data? = nil,
        error: String? = nil,
        nodeId: String,
        cacheVersion: String
    ) {
        self.ok = ok
        self.data = data
        self.error = error
        self.nodeId = nodeId
        self.cacheVersion = cacheVersion
    }
}

// MARK: - MotoQuerySubjects

/// Centralizes NATS subject naming for the Moto query subsystem.
public enum MotoQuerySubjects {
    /// Subject for querying a specific node's Moto cache.
    public static func targeted(nodeId: String) -> String {
        "shikki.moto.query.\(nodeId)"
    }

    /// Broadcast subject for querying any available node's Moto cache.
    public static var available: String {
        "shikki.moto.query.available"
    }
}

// MARK: - MotoQueryError

/// Errors from the Moto remote query subsystem.
public enum MotoQueryError: Error, Sendable, Equatable {
    case timeout
    case encodingFailed
    case decodingFailed(String)
    case remoteError(String)
    case unknownTool(String)
}
