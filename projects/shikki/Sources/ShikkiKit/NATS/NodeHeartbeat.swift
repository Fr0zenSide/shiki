import Foundation
import Logging

// MARK: - NodeHeartbeat

/// Actor that publishes heartbeat announcements to `shikki.discovery.announce`
/// every 30 seconds (configurable). Also monitors other nodes and detects stale
/// ones (no heartbeat for 3 intervals = 90s silence by default).
///
/// Usage:
/// ```swift
/// let heartbeat = NodeHeartbeat(
///     identity: .current(nodeId: "node-abc"),
///     nats: natsClient,
///     registry: nodeRegistry
/// )
/// try await heartbeat.start()
/// // ... later
/// await heartbeat.stop()
/// ```
public actor NodeHeartbeat {
    private let identity: NodeIdentity
    private let nats: any NATSClientProtocol
    private let registry: NodeRegistry
    private let interval: Duration
    private let staleThreshold: Duration
    private let logger: Logger
    private let encoder: JSONEncoder
    /// SHA-256 hash of the mesh token, included in every heartbeat (BR-01).
    /// When nil, heartbeats are sent without authentication (backward compat).
    private let meshTokenHash: String?

    private var announceTask: Task<Void, Never>?
    private var monitorTask: Task<Void, Never>?
    private var tickCount: Int = 0

    /// Callback invoked when a stale node is detected.
    /// Receives the stale node's identity.
    public var onStaleNode: (@Sendable (NodeIdentity) -> Void)?

    public init(
        identity: NodeIdentity,
        nats: any NATSClientProtocol,
        registry: NodeRegistry,
        interval: Duration = .seconds(30),
        staleThreshold: Duration = .seconds(90),
        meshToken: String? = nil,
        logger: Logger = Logger(label: "shikki.node-heartbeat")
    ) {
        self.identity = identity
        self.nats = nats
        self.registry = registry
        self.interval = interval
        self.staleThreshold = staleThreshold
        self.meshTokenHash = meshToken.map { MeshTokenProvider.hash($0) }
        self.logger = logger
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
    }

    // MARK: - Lifecycle

    /// Start the heartbeat announce loop and the stale-node monitor.
    public func start() async throws {
        guard announceTask == nil else { return }

        // Ensure NATS is connected
        if !(await nats.isConnected) {
            try await nats.connect()
        }

        // Register self in the registry
        await registry.register(identity)

        // Publish an immediate first heartbeat
        await publishHeartbeat()

        // Start periodic announce loop
        announceTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: await self.interval)
                    await self.publishHeartbeat()
                } catch {
                    break // cancelled
                }
            }
        }

        // Start stale-node monitor loop
        monitorTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: await self.interval)
                    await self.scanForStaleNodes()
                } catch {
                    break // cancelled
                }
            }
        }

        // Subscribe to incoming heartbeats from other nodes
        let stream = await nats.subscribe(subject: NATSSubjectMapper.discoveryAnnounce)
        let capturedRegistry = registry
        Task {
            let heartbeatDecoder = JSONDecoder()
            heartbeatDecoder.dateDecodingStrategy = .iso8601
            for await message in stream {
                if Task.isCancelled { break }
                guard let payload = try? heartbeatDecoder.decode(HeartbeatPayload.self, from: message.data) else {
                    continue
                }
                // Use authenticated registration when meshTokenHash is present
                if payload.meshTokenHash != nil {
                    await capturedRegistry.registerWithAuth(
                        payload.identity,
                        meshTokenHash: payload.meshTokenHash
                    )
                } else {
                    await capturedRegistry.register(payload.identity)
                }
            }
        }
    }

    /// Stop heartbeat publishing and monitoring.
    public func stop() async {
        announceTask?.cancel()
        announceTask = nil
        monitorTask?.cancel()
        monitorTask = nil

        // Deregister self from registry
        await registry.deregister(identity.nodeId)
    }

    /// Whether the heartbeat loop is currently running.
    public var isRunning: Bool {
        announceTask != nil && !(announceTask?.isCancelled ?? true)
    }

    /// Total heartbeats published since start.
    public var publishedCount: Int { tickCount }

    // MARK: - Internal

    private func publishHeartbeat() async {
        let uptime = Date().timeIntervalSince(identity.startedAt)
        let payload = HeartbeatPayload(
            identity: identity,
            timestamp: Date(),
            uptimeSeconds: uptime,
            activeAgents: 0,
            contextUsedPct: 0,
            meshTokenHash: meshTokenHash
        )

        do {
            let data = try encoder.encode(payload)
            try await nats.publish(
                subject: NATSSubjectMapper.discoveryAnnounce,
                data: data
            )
            tickCount += 1
        } catch {
            logger.warning("Failed to publish heartbeat: \(error)")
        }
    }

    private func scanForStaleNodes() async {
        let stale = await registry.staleNodes(threshold: staleThreshold)
        for node in stale {
            await registry.markStale(node.nodeId)
            logger.warning("Node \(node.nodeId) (\(node.hostname)) is stale — no heartbeat for >\(staleThreshold)")
            onStaleNode?(node)
        }
    }
}
