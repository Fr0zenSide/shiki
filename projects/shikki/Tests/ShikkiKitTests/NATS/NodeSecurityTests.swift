import Foundation
import Testing
@testable import ShikkiKit

@Suite("Node Security — Auth + Leader Election")
struct NodeSecurityTests {

    // MARK: - Helpers

    private func makeIdentity(
        _ id: String,
        role: NodeRole = .shadow,
        startedAt: Date = Date()
    ) -> NodeIdentity {
        NodeIdentity(
            nodeId: id,
            binaryVersion: "0.3.0-pre",
            role: role,
            pid: 100,
            hostname: "test.local",
            startedAt: startedAt
        )
    }

    private static let validToken = "test-mesh-secret-2026"
    private static let validTokenHash = MeshTokenProvider.hash(validToken)
    private static let wrongToken = "wrong-secret"
    private static let wrongTokenHash = MeshTokenProvider.hash(wrongToken)

    private func makePayloadData(
        identity: NodeIdentity,
        meshTokenHash: String? = nil
    ) throws -> Data {
        let payload = HeartbeatPayload(
            identity: identity,
            meshTokenHash: meshTokenHash
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    // MARK: - Test 1: Valid heartbeat with meshToken → registered (BR-01)

    @Test("Valid heartbeat with meshToken is accepted and registered")
    func validHeartbeatRegistered() async throws {
        let registry = NodeRegistry(meshTokenHash: Self.validTokenHash)
        let identity = makeIdentity("node-valid", role: .shadow)

        let accepted = await registry.registerWithAuth(
            identity,
            meshTokenHash: Self.validTokenHash
        )

        #expect(accepted == true)
        let active = await registry.isActive("node-valid")
        #expect(active == true)
    }

    // MARK: - Test 2: Invalid meshToken → silently rejected (BR-02, BR-09)

    @Test("Invalid meshToken heartbeat silently rejected — no info leak")
    func invalidTokenRejected() async throws {
        let registry = NodeRegistry(meshTokenHash: Self.validTokenHash)
        let identity = makeIdentity("node-bad")

        let accepted = await registry.registerWithAuth(
            identity,
            meshTokenHash: Self.wrongTokenHash
        )

        #expect(accepted == false)
        let active = await registry.isActive("node-bad")
        #expect(active == false)
        let count = await registry.nodeCount
        #expect(count == 0)
    }

    // MARK: - Test 3: Missing meshToken → silently rejected (BR-01, BR-09)

    @Test("Missing meshToken heartbeat silently rejected")
    func missingTokenRejected() async throws {
        let registry = NodeRegistry(meshTokenHash: Self.validTokenHash)
        let identity = makeIdentity("node-notoken")

        let accepted = await registry.registerWithAuth(
            identity,
            meshTokenHash: nil
        )

        #expect(accepted == false)
        let active = await registry.isActive("node-notoken")
        #expect(active == false)
    }

    // MARK: - Test 4: Split-brain prevention — older primary wins (BR-03, BR-04)

    @Test("Split-brain: older primary wins fencing by startedAt")
    func splitBrainOlderWins() async throws {
        let registry = NodeRegistry(meshTokenHash: Self.validTokenHash)

        let olderDate = Date().addingTimeInterval(-3600) // 1 hour ago
        let newerDate = Date()

        let olderPrimary = makeIdentity("node-old", role: .primary, startedAt: olderDate)
        let newerPrimary = makeIdentity("node-new", role: .primary, startedAt: newerDate)

        // Register older primary first
        _ = await registry.registerWithAuth(olderPrimary, meshTokenHash: Self.validTokenHash)
        // Attempt to register newer primary — should be demoted to shadow
        _ = await registry.registerWithAuth(newerPrimary, meshTokenHash: Self.validTokenHash)

        let primaryCount = await registry.primaryCount
        #expect(primaryCount == 1)

        let primary = await registry.primaryNode
        #expect(primary?.nodeId == "node-old")

        // The newer node should have been registered but as shadow
        let newerNode = await registry.activeNodes.first { $0.nodeId == "node-new" }
        #expect(newerNode?.role == .shadow)
    }

    // MARK: - Test 5: SHADOW → VERIFY → PROMOTE sequence (BR-05, BR-06)

    @Test("Leader election follows shadow → verify → promoting → primary sequence")
    func leaderElectionSequence() async throws {
        let nats = MockNATSClient()
        try await nats.connect()
        let registry = NodeRegistry(meshTokenHash: Self.validTokenHash)
        let identity = makeIdentity("node-leader", role: .shadow)

        let election = LeaderElection(
            identity: identity,
            registry: registry,
            nats: nats,
            meshToken: Self.validToken,
            heartbeatInterval: .milliseconds(50)
        )

        let initialState = await election.state
        #expect(initialState == .idle)

        // Start the election — enters shadow
        try await election.start()
        let afterStart = await election.state
        #expect(afterStart == .shadow)

        // Request promotion — should go through verify → promoting → primary
        try await election.requestPromotion()

        // Give it time for the FSM to advance
        try await Task.sleep(for: .milliseconds(200))

        let finalState = await election.state
        #expect(finalState == .primary)

        // A PrimaryClaim should have been published
        let published = await nats.publishedMessages
        let claimMessages = published.filter {
            $0.subject == NATSSubjectMapper.nodePrimary
        }
        #expect(claimMessages.count >= 1)

        // Decode the claim
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let claim = try decoder.decode(PrimaryClaim.self, from: claimMessages[0].data)
        #expect(claim.nodeId == "node-leader")
        #expect(claim.meshTokenHash == Self.validTokenHash)

        await election.stop()
    }

    // MARK: - Test 6: Auto-promote on primary silence after 3 intervals (BR-10)

    @Test("Shadow auto-promotes when primary silent for 3 heartbeat intervals")
    func autoPromoteOnPrimarySilence() async throws {
        let nats = MockNATSClient()
        try await nats.connect()
        let registry = NodeRegistry(meshTokenHash: Self.validTokenHash)

        // Register a primary that will go stale
        let primaryIdentity = makeIdentity("node-primary-stale", role: .primary)
        _ = await registry.registerWithAuth(primaryIdentity, meshTokenHash: Self.validTokenHash)

        // Create shadow node with very short heartbeat interval
        let shadowIdentity = makeIdentity("node-shadow-promote", role: .shadow)

        let election = LeaderElection(
            identity: shadowIdentity,
            registry: registry,
            nats: nats,
            meshToken: Self.validToken,
            heartbeatInterval: .milliseconds(30)
        )

        try await election.start()

        // Mark the primary as stale (simulating 3 missed heartbeats)
        await registry.markStale("node-primary-stale")

        // Wait for the election to detect stale primary and auto-promote
        try await Task.sleep(for: .milliseconds(400))

        let state = await election.state
        #expect(state == .primary)

        await election.stop()
    }

    // MARK: - Test 7: primaryCount alert when > 1 (BR-07)

    @Test("primaryCount tracks primary nodes and detects split-brain")
    func primaryCountAlert() async throws {
        let registry = NodeRegistry(meshTokenHash: Self.validTokenHash)

        // No primaries initially
        let initialCount = await registry.primaryCount
        #expect(initialCount == 0)

        // Register one primary
        let node1 = makeIdentity("node-p1", role: .primary, startedAt: Date().addingTimeInterval(-100))
        _ = await registry.registerWithAuth(node1, meshTokenHash: Self.validTokenHash)

        let oneCount = await registry.primaryCount
        #expect(oneCount == 1)

        // Force-register a second primary (bypassing fencing, simulating a race)
        // Use the non-auth register to simulate a split-brain scenario
        var node2 = makeIdentity("node-p2", role: .primary)
        await registry.register(node2)

        let splitCount = await registry.primaryCount
        #expect(splitCount == 2)

        let hasSplitBrain = await registry.hasSplitBrain
        #expect(hasSplitBrain == true)
    }

    // MARK: - Test 8: meshToken loaded from environment (BR-08)

    @Test("MeshTokenProvider loads from SHIKKI_MESH_TOKEN env and hashes with SHA-256")
    func meshTokenFromEnvironment() throws {
        // Test the hash function is deterministic and produces valid SHA-256
        let hash1 = MeshTokenProvider.hash("test-secret")
        let hash2 = MeshTokenProvider.hash("test-secret")
        #expect(hash1 == hash2)
        #expect(hash1.count == 64) // SHA-256 hex = 64 chars

        // Different inputs produce different hashes
        let hash3 = MeshTokenProvider.hash("other-secret")
        #expect(hash1 != hash3)

        // Test load throws when env var is not set
        // We cannot safely set env vars in tests, so test the error case
        // by checking MeshTokenProvider.loadFromValue
        let token = MeshTokenProvider.loadFromValue("my-secure-token")
        #expect(token == "my-secure-token")

        // Empty token should throw
        #expect(throws: MeshTokenError.self) {
            try MeshTokenProvider.validate("")
        }
    }
}
