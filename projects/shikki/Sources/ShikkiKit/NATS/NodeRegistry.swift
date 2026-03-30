import Foundation
import Logging

// MARK: - NodeEntry

/// Internal bookkeeping for a registered node.
struct NodeEntry: Sendable {
    let identity: NodeIdentity
    var lastSeen: Date
    var isStale: Bool
}

// MARK: - NodeRegistry

/// Actor maintaining the live topology map of all known Shikki nodes.
///
/// Nodes register via heartbeats on `shikki.discovery.announce`.
/// The registry tracks last-seen timestamps and marks nodes stale
/// when they exceed the silence threshold (default 90s).
///
/// Responds to `shikki.discovery.query` request/reply with the
/// current list of active nodes.
public actor NodeRegistry {
    private var nodes: [String: NodeEntry] = [:]
    private let logger: Logger
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var queryTask: Task<Void, Never>?

    public init(
        logger: Logger = Logger(label: "shikki.node-registry")
    ) {
        self.logger = logger
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Registration

    /// Register or update a node in the registry.
    /// Resets the stale flag and updates last-seen.
    public func register(_ identity: NodeIdentity) {
        let existing = nodes[identity.nodeId]
        nodes[identity.nodeId] = NodeEntry(
            identity: identity,
            lastSeen: Date(),
            isStale: false
        )
        if existing == nil {
            logger.info("Node registered: \(identity.nodeId) (\(identity.hostname), role: \(identity.role))")
        }
    }

    /// Remove a node from the registry.
    public func deregister(_ nodeId: String) {
        if nodes.removeValue(forKey: nodeId) != nil {
            logger.info("Node deregistered: \(nodeId)")
        }
    }

    /// Mark a node as stale (no heartbeat within threshold).
    public func markStale(_ nodeId: String) {
        nodes[nodeId]?.isStale = true
    }

    // MARK: - Queries

    /// All currently active (non-stale) nodes.
    public var activeNodes: [NodeIdentity] {
        nodes.values
            .filter { !$0.isStale }
            .map(\.identity)
    }

    /// All known nodes (including stale).
    public var allNodes: [NodeIdentity] {
        nodes.values.map(\.identity)
    }

    /// The current primary node, if any.
    public var primaryNode: NodeIdentity? {
        nodes.values
            .filter { !$0.isStale && $0.identity.role == .primary }
            .map(\.identity)
            .first
    }

    /// Total registered nodes (including stale).
    public var nodeCount: Int { nodes.count }

    /// Total active (non-stale) nodes.
    public var activeCount: Int {
        nodes.values.filter { !$0.isStale }.count
    }

    /// Check if a specific node is registered and active.
    public func isActive(_ nodeId: String) -> Bool {
        guard let entry = nodes[nodeId] else { return false }
        return !entry.isStale
    }

    /// Check if a specific node is stale.
    public func isStale(_ nodeId: String) -> Bool {
        nodes[nodeId]?.isStale ?? false
    }

    /// Last-seen timestamp for a node.
    public func lastSeen(_ nodeId: String) -> Date? {
        nodes[nodeId]?.lastSeen
    }

    /// Nodes that haven't sent a heartbeat within the threshold.
    public func staleNodes(threshold: Duration) -> [NodeIdentity] {
        let cutoff = Date().addingTimeInterval(
            -Double(threshold.components.seconds)
            - Double(threshold.components.attoseconds) / 1e18
        )
        return nodes.values
            .filter { !$0.isStale && $0.lastSeen < cutoff }
            .map(\.identity)
    }

    /// Nodes filtered by role.
    public func nodes(withRole role: NodeRole) -> [NodeIdentity] {
        nodes.values
            .filter { !$0.isStale && $0.identity.role == role }
            .map(\.identity)
    }

    // MARK: - Discovery Query Handler

    /// Start listening for `shikki.discovery.query` requests and replying
    /// with the current topology.
    public func startQueryResponder(nats: any NATSClientProtocol) {
        queryTask = Task { [weak self] in
            let queryDecoder = JSONDecoder()
            queryDecoder.dateDecodingStrategy = .iso8601
            let queryEncoder = JSONEncoder()
            queryEncoder.dateEncodingStrategy = .iso8601

            let stream = await nats.subscribe(subject: NATSSubjectMapper.discoveryQuery)
            for await message in stream {
                if Task.isCancelled { break }
                guard let self else { break }

                let query: DiscoveryQuery
                if message.data.isEmpty {
                    query = DiscoveryQuery()
                } else {
                    query = (try? queryDecoder.decode(DiscoveryQuery.self, from: message.data)) ?? DiscoveryQuery()
                }

                var resultNodes = await self.activeNodes
                if let roleFilter = query.roleFilter {
                    resultNodes = resultNodes.filter { $0.role == roleFilter }
                }

                let response = DiscoveryResponse(nodes: resultNodes)
                if let replyTo = message.replyTo,
                   let data = try? queryEncoder.encode(response) {
                    try? await nats.publish(subject: replyTo, data: data)
                }
            }
        }
    }

    /// Stop the query responder.
    public func stopQueryResponder() {
        queryTask?.cancel()
        queryTask = nil
    }
}
