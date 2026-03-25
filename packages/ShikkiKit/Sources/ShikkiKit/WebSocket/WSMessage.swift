import Foundation

/// Discriminated union for WebSocket messages (maps to WsMessageSchema).
/// Uses a tagged enum with associated values matching the Deno discriminatedUnion("type", ...).
public enum WSMessage: Codable, Equatable, Sendable {
    case subscribe(channel: String)
    case unsubscribe(channel: String)
    case chat(WSChatPayload)

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "subscribe":
            let payload = try WSSubscribePayload(from: decoder)
            self = .subscribe(channel: payload.channel)
        case "unsubscribe":
            let payload = try WSUnsubscribePayload(from: decoder)
            self = .unsubscribe(channel: payload.channel)
        case "chat":
            let payload = try WSChatPayload(from: decoder)
            self = .chat(payload)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown WebSocket message type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .subscribe(let channel):
            try WSSubscribePayload(channel: channel).encode(to: encoder)
        case .unsubscribe(let channel):
            try WSUnsubscribePayload(channel: channel).encode(to: encoder)
        case .chat(let payload):
            try payload.encode(to: encoder)
        }
    }
}

// MARK: - Payload types

/// Subscribe message payload.
struct WSSubscribePayload: Codable, Sendable {
    let type: String
    let channel: String

    init(channel: String) {
        self.type = "subscribe"
        self.channel = channel
    }
}

/// Unsubscribe message payload.
struct WSUnsubscribePayload: Codable, Sendable {
    let type: String
    let channel: String

    init(channel: String) {
        self.type = "unsubscribe"
        self.channel = channel
    }
}

/// Chat message payload within a WebSocket message (maps to WsChatSchema).
public struct WSChatPayload: Codable, Equatable, Sendable {
    public let type: String
    public let sessionId: UUID
    public let projectId: UUID
    public let agentId: UUID?
    public let role: ChatRole
    public let content: String

    public init(
        sessionId: UUID,
        projectId: UUID,
        agentId: UUID? = nil,
        role: ChatRole = .assistant,
        content: String
    ) {
        self.type = "chat"
        self.sessionId = sessionId
        self.projectId = projectId
        self.agentId = agentId
        self.role = role
        self.content = content
    }

    enum CodingKeys: String, CodingKey {
        case type, role, content
        case sessionId = "session_id"
        case projectId = "project_id"
        case agentId = "agent_id"
    }
}

// MARK: - Server broadcast messages

/// Server-sent broadcast message types (sent from server to clients).
/// These are NOT part of the WsMessageSchema but are broadcast payloads.
public enum WSBroadcast: Codable, Equatable, Sendable {
    case agentEvent(WSAgentEventBroadcast)
    case statsUpdate(WSStatsUpdateBroadcast)
    case chatMessage(WSChatBroadcast)
    case dataSync(WSDataSyncBroadcast)
    case prCreated(WSPrCreatedBroadcast)

    enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "agent_event":
            self = .agentEvent(try WSAgentEventBroadcast(from: decoder))
        case "stats_update":
            self = .statsUpdate(try WSStatsUpdateBroadcast(from: decoder))
        case "chat":
            self = .chatMessage(try WSChatBroadcast(from: decoder))
        case "data_sync":
            self = .dataSync(try WSDataSyncBroadcast(from: decoder))
        case "pr_created":
            self = .prCreated(try WSPrCreatedBroadcast(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown broadcast type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .agentEvent(let payload): try payload.encode(to: encoder)
        case .statsUpdate(let payload): try payload.encode(to: encoder)
        case .chatMessage(let payload): try payload.encode(to: encoder)
        case .dataSync(let payload): try payload.encode(to: encoder)
        case .prCreated(let payload): try payload.encode(to: encoder)
        }
    }
}

/// Agent event broadcast payload.
public struct WSAgentEventBroadcast: Codable, Equatable, Sendable {
    public let type: String
    public let event: AgentEventDTO

    public init(event: AgentEventDTO) {
        self.type = "agent_event"
        self.event = event
    }
}

/// Stats update broadcast payload.
public struct WSStatsUpdateBroadcast: Codable, Equatable, Sendable {
    public let type: String
    public let metric: PerformanceMetricInput
    public let timestamp: String

    public init(metric: PerformanceMetricInput, timestamp: String) {
        self.type = "stats_update"
        self.metric = metric
        self.timestamp = timestamp
    }
}

/// Chat broadcast payload.
public struct WSChatBroadcast: Codable, Equatable, Sendable {
    public let type: String
    public let sessionId: UUID
    public let projectId: UUID
    public let agentId: UUID?
    public let role: ChatRole
    public let content: String
    public let timestamp: String

    public init(
        sessionId: UUID,
        projectId: UUID,
        agentId: UUID? = nil,
        role: ChatRole,
        content: String,
        timestamp: String
    ) {
        self.type = "chat"
        self.sessionId = sessionId
        self.projectId = projectId
        self.agentId = agentId
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }

    enum CodingKeys: String, CodingKey {
        case type, role, content, timestamp
        case sessionId = "session_id"
        case projectId = "project_id"
        case agentId = "agent_id"
    }
}

/// Data sync broadcast payload.
public struct WSDataSyncBroadcast: Codable, Equatable, Sendable {
    public let type: String
    public let syncType: String
    public let data: [String: AnyCodable]
    public let timestamp: String

    public init(syncType: String, data: [String: AnyCodable], timestamp: String) {
        self.type = "data_sync"
        self.syncType = syncType
        self.data = data
        self.timestamp = timestamp
    }

    enum CodingKeys: String, CodingKey {
        case type, data, timestamp
        case syncType = "sync_type"
    }
}

/// PR created broadcast payload.
public struct WSPrCreatedBroadcast: Codable, Equatable, Sendable {
    public let type: String
    public let prUrl: String
    public let title: String
    public let branch: String
    public let timestamp: String

    public init(prUrl: String, title: String, branch: String, timestamp: String) {
        self.type = "pr_created"
        self.prUrl = prUrl
        self.title = title
        self.branch = branch
        self.timestamp = timestamp
    }

    enum CodingKeys: String, CodingKey {
        case type, title, branch, timestamp
        case prUrl = "pr_url"
    }
}
