import Foundation

// MARK: - NodeRole

/// Role a node plays in the Shikki mesh.
/// Determines scheduling priority and failover behavior.
public enum NodeRole: String, Codable, Sendable, Hashable, CaseIterable {
    /// Active orchestrator — owns the dispatch loop and kernel tick.
    case primary
    /// Hot standby — mirrors state, promotes on primary failure.
    case shadow
    /// Read-only observer — consumes events, never dispatches.
    case watcher
    /// Gracefully shutting down — finishes in-flight work, accepts no new tasks.
    case draining
}

// MARK: - NodeIdentity

/// Identity of a Shikki node in the distributed mesh.
/// Published on `shikki.discovery.announce` every heartbeat interval.
/// Used by `NodeRegistry` to maintain the live topology map.
public struct NodeIdentity: Codable, Sendable, Hashable, Identifiable {
    /// Stable unique identifier for this node (persists across restarts).
    /// Generated once and stored at `~/.config/shiki/node-id`.
    public let nodeId: String

    /// Semantic version of the shikki binary.
    public let binaryVersion: String

    /// Current role in the mesh.
    public var role: NodeRole

    /// OS process identifier.
    public let pid: Int32

    /// Machine hostname.
    public let hostname: String

    /// Timestamp when this node started.
    public let startedAt: Date

    public var id: String { nodeId }

    public init(
        nodeId: String,
        binaryVersion: String,
        role: NodeRole,
        pid: Int32,
        hostname: String,
        startedAt: Date
    ) {
        self.nodeId = nodeId
        self.binaryVersion = binaryVersion
        self.role = role
        self.pid = pid
        self.hostname = hostname
        self.startedAt = startedAt
    }

    /// Create identity for the current process.
    public static func current(
        nodeId: String,
        binaryVersion: String = "0.3.0-pre",
        role: NodeRole = .primary
    ) -> NodeIdentity {
        NodeIdentity(
            nodeId: nodeId,
            binaryVersion: binaryVersion,
            role: role,
            pid: ProcessInfo.processInfo.processIdentifier,
            hostname: ProcessInfo.processInfo.hostName,
            startedAt: Date()
        )
    }
}

// MARK: - HeartbeatPayload

/// Payload published on `shikki.discovery.announce`.
/// Embeds full identity plus runtime metrics.
public struct HeartbeatPayload: Codable, Sendable {
    public let identity: NodeIdentity
    public let timestamp: Date
    public let uptimeSeconds: TimeInterval
    public let activeAgents: Int
    public let contextUsedPct: Int
    /// SHA-256 hash of the mesh token for node authentication (BR-01).
    /// Optional for backward compatibility — unauthenticated payloads
    /// are silently dropped by registries that enforce auth.
    public let meshTokenHash: String?

    public init(
        identity: NodeIdentity,
        timestamp: Date = Date(),
        uptimeSeconds: TimeInterval = 0,
        activeAgents: Int = 0,
        contextUsedPct: Int = 0,
        meshTokenHash: String? = nil
    ) {
        self.identity = identity
        self.timestamp = timestamp
        self.uptimeSeconds = uptimeSeconds
        self.activeAgents = activeAgents
        self.contextUsedPct = contextUsedPct
        self.meshTokenHash = meshTokenHash
    }
}

// MARK: - DiscoveryQuery / DiscoveryResponse

/// Request payload for `shikki.discovery.query` (request-reply).
public struct DiscoveryQuery: Codable, Sendable {
    /// Optional filter: only return nodes with this role.
    public let roleFilter: NodeRole?

    public init(roleFilter: NodeRole? = nil) {
        self.roleFilter = roleFilter
    }
}

/// Response payload for `shikki.discovery.query`.
public struct DiscoveryResponse: Codable, Sendable {
    public let nodes: [NodeIdentity]
    public let respondedAt: Date

    public init(nodes: [NodeIdentity], respondedAt: Date = Date()) {
        self.nodes = nodes
        self.respondedAt = respondedAt
    }
}
