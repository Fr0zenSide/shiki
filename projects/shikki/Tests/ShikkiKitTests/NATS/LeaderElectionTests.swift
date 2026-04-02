import Foundation
import Testing
@testable import ShikkiKit

@Suite("LeaderElection — FSM demotion + edge cases")
struct LeaderElectionTests {

    // MARK: - Helpers

    private static let meshToken = "test-election-secret"
    private static let meshTokenHash = MeshTokenProvider.hash(meshToken)

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

    // MARK: - Demotion on stronger claim (BR-04)

    @Test("Primary demotes to shadow when older claim arrives")
    func primaryDemotesOnOlderClaim() async throws {
        let nats = MockNATSClient()
        try await nats.connect()
        let registry = NodeRegistry(meshTokenHash: Self.meshTokenHash)

        // This node started now
        let myStartedAt = Date()
        let identity = makeIdentity("node-newer", role: .shadow, startedAt: myStartedAt)

        let election = LeaderElection(
            identity: identity,
            registry: registry,
            nats: nats,
            meshToken: Self.meshToken,
            heartbeatInterval: .seconds(60),
            objectionWindow: .milliseconds(50)
        )

        // Start and promote to primary
        try await election.start()
        try await election.requestPromotion()
        try await Task.sleep(for: .milliseconds(100))

        let stateBeforeClaim = await election.state
        #expect(stateBeforeClaim == .primary)

        // An older node publishes a PrimaryClaim
        let olderStartedAt = myStartedAt.addingTimeInterval(-3600)
        let olderClaim = PrimaryClaim(
            nodeId: "node-older",
            startedAt: olderStartedAt,
            meshTokenHash: Self.meshTokenHash
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let claimData = try encoder.encode(olderClaim)
        let claimMsg = NATSMessage(
            subject: NATSSubjectMapper.nodePrimary,
            data: claimData
        )
        await nats.injectMessage(claimMsg)

        // Wait for the claim listener to process
        try await Task.sleep(for: .milliseconds(200))

        let stateAfterClaim = await election.state
        #expect(stateAfterClaim == .shadow)

        await election.stop()
    }

    // MARK: - Ignores own claim

    @Test("Primary ignores its own PrimaryClaim messages")
    func primaryIgnoresOwnClaim() async throws {
        let nats = MockNATSClient()
        try await nats.connect()
        let registry = NodeRegistry(meshTokenHash: Self.meshTokenHash)

        let identity = makeIdentity("node-self", role: .shadow)

        let election = LeaderElection(
            identity: identity,
            registry: registry,
            nats: nats,
            meshToken: Self.meshToken,
            heartbeatInterval: .seconds(60),
            objectionWindow: .milliseconds(50)
        )

        try await election.start()
        try await election.requestPromotion()
        try await Task.sleep(for: .milliseconds(100))

        #expect(await election.state == .primary)

        // Inject our own claim as if echoed back
        let selfClaim = PrimaryClaim(
            nodeId: "node-self",
            startedAt: identity.startedAt,
            meshTokenHash: Self.meshTokenHash
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(selfClaim)
        await nats.injectMessage(NATSMessage(
            subject: NATSSubjectMapper.nodePrimary,
            data: data
        ))

        try await Task.sleep(for: .milliseconds(100))

        // Should still be primary
        #expect(await election.state == .primary)

        await election.stop()
    }

    // MARK: - Start idempotency

    @Test("Start is idempotent when already in shadow")
    func startIdempotent() async throws {
        let nats = MockNATSClient()
        try await nats.connect()
        let registry = NodeRegistry(meshTokenHash: Self.meshTokenHash)

        let identity = makeIdentity("node-idempotent", role: .shadow)
        let election = LeaderElection(
            identity: identity,
            registry: registry,
            nats: nats,
            meshToken: Self.meshToken,
            heartbeatInterval: .seconds(60),
            objectionWindow: .milliseconds(50)
        )

        try await election.start()
        #expect(await election.state == .shadow)

        // Second start should be a no-op
        try await election.start()
        #expect(await election.state == .shadow)

        await election.stop()
    }

    // MARK: - Promotion rejected when not shadow

    @Test("requestPromotion is rejected when not in shadow state")
    func promotionRejectedWhenNotShadow() async throws {
        let nats = MockNATSClient()
        try await nats.connect()
        let registry = NodeRegistry(meshTokenHash: Self.meshTokenHash)

        let identity = makeIdentity("node-reject", role: .shadow)
        let election = LeaderElection(
            identity: identity,
            registry: registry,
            nats: nats,
            meshToken: Self.meshToken,
            heartbeatInterval: .seconds(60),
            objectionWindow: .milliseconds(50)
        )

        // Still idle — haven't called start()
        try await election.requestPromotion()
        #expect(await election.state == .idle)

        await election.stop()
    }

    // MARK: - Stop resets to idle

    @Test("Stop from primary resets to idle")
    func stopFromPrimaryResetsToIdle() async throws {
        let nats = MockNATSClient()
        try await nats.connect()
        let registry = NodeRegistry(meshTokenHash: Self.meshTokenHash)

        let identity = makeIdentity("node-stop", role: .shadow)
        let election = LeaderElection(
            identity: identity,
            registry: registry,
            nats: nats,
            meshToken: Self.meshToken,
            heartbeatInterval: .seconds(60),
            objectionWindow: .milliseconds(50)
        )

        try await election.start()
        try await election.requestPromotion()
        try await Task.sleep(for: .milliseconds(100))
        #expect(await election.state == .primary)

        await election.stop()
        #expect(await election.state == .idle)
    }

    @Test("Stop from shadow resets to idle")
    func stopFromShadowResetsToIdle() async throws {
        let nats = MockNATSClient()
        try await nats.connect()
        let registry = NodeRegistry(meshTokenHash: Self.meshTokenHash)

        let identity = makeIdentity("node-stop-shadow", role: .shadow)
        let election = LeaderElection(
            identity: identity,
            registry: registry,
            nats: nats,
            meshToken: Self.meshToken,
            heartbeatInterval: .seconds(60),
            objectionWindow: .milliseconds(50)
        )

        try await election.start()
        #expect(await election.state == .shadow)

        await election.stop()
        #expect(await election.state == .idle)
    }

    // MARK: - Promotion blocked by active primary

    @Test("Promotion stays shadow when active primary exists in registry")
    func promotionBlockedByActivePrimary() async throws {
        let nats = MockNATSClient()
        try await nats.connect()
        let registry = NodeRegistry(meshTokenHash: Self.meshTokenHash)

        // Register an existing active primary
        let existingPrimary = makeIdentity("node-existing-primary", role: .primary)
        _ = await registry.registerWithAuth(
            existingPrimary,
            meshTokenHash: Self.meshTokenHash
        )

        let identity = makeIdentity("node-blocked", role: .shadow)
        let election = LeaderElection(
            identity: identity,
            registry: registry,
            nats: nats,
            meshToken: Self.meshToken,
            heartbeatInterval: .seconds(60),
            objectionWindow: .milliseconds(50)
        )

        try await election.start()
        try await election.requestPromotion()
        try await Task.sleep(for: .milliseconds(100))

        // Should stay shadow because an active primary exists
        #expect(await election.state == .shadow)

        await election.stop()
    }
}
