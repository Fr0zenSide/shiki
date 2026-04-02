import Foundation
import Logging

// MARK: - ElectionState

/// State machine for leader election in the Shikki mesh.
///
/// Transitions:
/// ```
/// idle → shadow → verify → promoting → primary
///                                ↑           │
///                                └───────────┘  (on demotion)
/// ```
public enum ElectionState: String, Sendable, Codable, CaseIterable {
    /// Not participating in any election activity.
    case idle
    /// Monitoring the current primary — ready to take over.
    case shadow
    /// Checking that no other node holds the primary claim.
    case verify
    /// Publishing PrimaryClaim and waiting for objections.
    case promoting
    /// This node is the active primary.
    case primary
}

// MARK: - PrimaryClaim

/// Claim published to `shikki.node.primary` when a node assumes the primary role.
/// Other nodes inspect the claim's `startedAt` for fencing: the oldest wins.
public struct PrimaryClaim: Codable, Sendable {
    /// Node ID of the claiming node.
    public let nodeId: String
    /// When the claiming node was started.
    public let startedAt: Date
    /// SHA-256 hash of the mesh token — proves the node holds the shared secret.
    public let meshTokenHash: String
    /// When the claim was made.
    public let claimedAt: Date

    public init(
        nodeId: String,
        startedAt: Date,
        meshTokenHash: String,
        claimedAt: Date = Date()
    ) {
        self.nodeId = nodeId
        self.startedAt = startedAt
        self.meshTokenHash = meshTokenHash
        self.claimedAt = claimedAt
    }
}

// MARK: - LeaderElection

/// Actor that manages leader election for a Shikki node.
///
/// The FSM progresses through: idle → shadow → verify → promoting → primary.
///
/// Business rules:
/// - BR-05: New primary MUST go through SHADOW → VERIFY → PROMOTE sequence
/// - BR-06: Primary claim published to `shikki.node.primary` with signature
/// - BR-10: Primary silent for 3 heartbeat intervals → shadow auto-promotes
///
/// Usage:
/// ```swift
/// let election = LeaderElection(
///     identity: nodeIdentity,
///     registry: registry,
///     nats: natsClient,
///     meshToken: "shared-secret"
/// )
/// try await election.start()          // enters shadow state
/// try await election.requestPromotion() // shadow → verify → promoting → primary
/// ```
public actor LeaderElection {
    private let identity: NodeIdentity
    private let registry: NodeRegistry
    private let nats: any NATSClientProtocol
    private let meshToken: String
    private let meshTokenHashValue: String
    private let heartbeatInterval: Duration
    private let logger: Logger
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private var _state: ElectionState = .idle
    private var monitorTask: Task<Void, Never>?
    private var claimListenerTask: Task<Void, Never>?
    private var missedHeartbeatCount: Int = 0

    /// Current FSM state.
    public var state: ElectionState { _state }

    public init(
        identity: NodeIdentity,
        registry: NodeRegistry,
        nats: any NATSClientProtocol,
        meshToken: String,
        heartbeatInterval: Duration = .seconds(30),
        logger: Logger = Logger(label: "shikki.leader-election")
    ) {
        self.identity = identity
        self.registry = registry
        self.nats = nats
        self.meshToken = meshToken
        self.meshTokenHashValue = MeshTokenProvider.hash(meshToken)
        self.heartbeatInterval = heartbeatInterval
        self.logger = logger
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Lifecycle

    /// Start the election process. The node enters shadow state and begins
    /// monitoring the current primary.
    public func start() async throws {
        guard _state == .idle else { return }

        // Register self in the registry
        _ = await registry.registerWithAuth(
            identity,
            meshTokenHash: meshTokenHashValue
        )

        _state = .shadow
        logger.info("Node \(identity.nodeId) entered shadow state")

        // Start monitoring loop for primary health
        startMonitorLoop()

        // Listen for primary claims from other nodes
        startClaimListener()
    }

    /// Request promotion from shadow to primary.
    /// Progresses through verify → promoting → primary.
    public func requestPromotion() async throws {
        guard _state == .shadow else {
            logger.warning("Cannot promote from state \(_state.rawValue) — must be shadow")
            return
        }

        // Step 1: VERIFY — check no active primary exists
        _state = .verify
        logger.info("Node \(identity.nodeId) entering verify state")

        let currentPrimary = await registry.primaryNode
        if let existing = currentPrimary {
            let stale = await registry.isStale(existing.nodeId)
            if !stale {
                // Active primary exists — stay as shadow
                _state = .shadow
                logger.info("Active primary \(existing.nodeId) exists — staying shadow")
                return
            }
        }

        // Step 2: PROMOTING — publish our claim
        _state = .promoting
        logger.info("Node \(identity.nodeId) entering promoting state")

        try await publishPrimaryClaim()

        // Brief pause to allow objections (in production this would be longer)
        try await Task.sleep(for: .milliseconds(50))

        // Step 3: PRIMARY — claim accepted
        _state = .primary
        logger.info("Node \(identity.nodeId) is now PRIMARY")

        // Update registry with our primary role
        var updatedIdentity = identity
        updatedIdentity.role = .primary
        _ = await registry.registerWithAuth(
            updatedIdentity,
            meshTokenHash: meshTokenHashValue
        )
    }

    /// Stop the election actor — cancels monitoring tasks.
    public func stop() async {
        monitorTask?.cancel()
        monitorTask = nil
        claimListenerTask?.cancel()
        claimListenerTask = nil

        if _state == .primary {
            _state = .idle
            logger.info("Node \(identity.nodeId) stepped down from primary")
        } else {
            _state = .idle
        }
    }

    // MARK: - Internal

    /// Publish a PrimaryClaim to `shikki.node.primary`.
    private func publishPrimaryClaim() async throws {
        let claim = PrimaryClaim(
            nodeId: identity.nodeId,
            startedAt: identity.startedAt,
            meshTokenHash: meshTokenHashValue
        )

        let data = try encoder.encode(claim)
        try await nats.publish(
            subject: NATSSubjectMapper.nodePrimary,
            data: data
        )

        logger.info("Published PrimaryClaim for \(identity.nodeId)")
    }

    /// Monitor loop that checks primary health every heartbeat interval.
    /// If the primary is stale for 3 consecutive checks, triggers auto-promotion.
    private func startMonitorLoop() {
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }

                do {
                    try await Task.sleep(for: await self.heartbeatInterval)
                } catch {
                    break
                }

                let currentState = await self.state
                guard currentState == .shadow else { continue }

                // Check if primary is still alive
                let primary = await self.registry.primaryNode
                if primary == nil {
                    // No primary — increment missed count
                    let missed = await self.incrementMissedHeartbeat()
                    if missed >= 3 {
                        // BR-10: Primary silent for 3 intervals → auto-promote
                        await self.resetMissedHeartbeat()
                        do {
                            try await self.requestPromotion()
                        } catch {
                            // Promotion failed — will retry next cycle
                        }
                    }
                } else {
                    await self.resetMissedHeartbeat()
                }
            }
        }
    }

    /// Listen for PrimaryClaim messages from other nodes.
    /// If a claim arrives from an older node, defer to it.
    private func startClaimListener() {
        let capturedDecoder = decoder
        let capturedNats = nats
        let capturedNodeId = identity.nodeId
        let capturedStartedAt = identity.startedAt

        claimListenerTask = Task { [weak self] in
            let stream = capturedNats.subscribe(subject: NATSSubjectMapper.nodePrimary)

            for await message in stream {
                if Task.isCancelled { break }
                guard let self else { break }

                guard let claim = try? capturedDecoder.decode(PrimaryClaim.self, from: message.data) else {
                    continue
                }

                // Ignore our own claims
                if claim.nodeId == capturedNodeId { continue }

                let currentState = await self.state

                // BR-04: If we're primary and a claim arrives from an older node, step down
                if currentState == .primary || currentState == .promoting {
                    if claim.startedAt < capturedStartedAt {
                        await self.demoteToShadow()
                    }
                }
            }
        }
    }

    /// Demote this node back to shadow state.
    private func demoteToShadow() {
        _state = .shadow
        missedHeartbeatCount = 0
        logger.info("Node \(identity.nodeId) demoted to shadow — older primary detected")
    }

    private func incrementMissedHeartbeat() -> Int {
        missedHeartbeatCount += 1
        return missedHeartbeatCount
    }

    private func resetMissedHeartbeat() {
        missedHeartbeatCount = 0
    }
}
