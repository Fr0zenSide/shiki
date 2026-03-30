import Foundation
import Testing
@testable import ShikkiKit

@Suite("NodeHeartbeat")
struct NodeHeartbeatTests {

    private func makeIdentity(_ id: String = "test-node") -> NodeIdentity {
        NodeIdentity(
            nodeId: id,
            binaryVersion: "0.3.0-pre",
            role: .primary,
            pid: ProcessInfo.processInfo.processIdentifier,
            hostname: "test.local",
            startedAt: Date()
        )
    }

    // MARK: - Lifecycle

    @Test("Start connects to NATS and registers in registry")
    func startConnectsAndRegisters() async throws {
        let nats = MockNATSClient()
        let registry = NodeRegistry()
        let identity = makeIdentity()

        let heartbeat = NodeHeartbeat(
            identity: identity,
            nats: nats,
            registry: registry,
            interval: .seconds(60) // long interval so only initial heartbeat fires
        )

        try await heartbeat.start()
        // Allow initial heartbeat to publish
        try await Task.sleep(for: .milliseconds(100))

        // NATS should be connected
        let connected = await nats.isConnected
        #expect(connected == true)

        // Node should be registered
        let active = await registry.isActive("test-node")
        #expect(active == true)

        // At least one heartbeat published
        let count = await heartbeat.publishedCount
        #expect(count >= 1)

        // Should be running
        let running = await heartbeat.isRunning
        #expect(running == true)

        await heartbeat.stop()
    }

    @Test("Stop cancels tasks and deregisters")
    func stopDeregisters() async throws {
        let nats = MockNATSClient()
        let registry = NodeRegistry()
        let identity = makeIdentity()

        let heartbeat = NodeHeartbeat(
            identity: identity,
            nats: nats,
            registry: registry,
            interval: .seconds(60)
        )

        try await heartbeat.start()
        try await Task.sleep(for: .milliseconds(50))

        await heartbeat.stop()

        let running = await heartbeat.isRunning
        #expect(running == false)

        let active = await registry.isActive("test-node")
        #expect(active == false)
    }

    @Test("Double start is idempotent")
    func doubleStartIdempotent() async throws {
        let nats = MockNATSClient()
        let registry = NodeRegistry()
        let identity = makeIdentity()

        let heartbeat = NodeHeartbeat(
            identity: identity,
            nats: nats,
            registry: registry,
            interval: .seconds(60)
        )

        try await heartbeat.start()
        try await heartbeat.start() // should not crash or duplicate

        let running = await heartbeat.isRunning
        #expect(running == true)

        await heartbeat.stop()
    }

    // MARK: - Heartbeat Publishing

    @Test("Heartbeat publishes to discovery.announce subject")
    func publishesToCorrectSubject() async throws {
        let nats = MockNATSClient()
        let registry = NodeRegistry()
        let identity = makeIdentity()

        let heartbeat = NodeHeartbeat(
            identity: identity,
            nats: nats,
            registry: registry,
            interval: .seconds(60)
        )

        try await heartbeat.start()
        try await Task.sleep(for: .milliseconds(100))

        let published = await nats.publishedMessages
        #expect(published.count >= 1)
        #expect(published[0].subject == "shikki.discovery.announce")

        await heartbeat.stop()
    }

    @Test("Heartbeat payload contains node identity")
    func payloadContainsIdentity() async throws {
        let nats = MockNATSClient()
        let registry = NodeRegistry()
        let identity = makeIdentity("payload-test")

        let heartbeat = NodeHeartbeat(
            identity: identity,
            nats: nats,
            registry: registry,
            interval: .seconds(60)
        )

        try await heartbeat.start()
        try await Task.sleep(for: .milliseconds(100))

        let published = await nats.publishedMessages
        #expect(published.count >= 1)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let payload = try decoder.decode(HeartbeatPayload.self, from: published[0].data)
        #expect(payload.identity.nodeId == "payload-test")
        #expect(payload.identity.role == .primary)
        #expect(payload.uptimeSeconds >= 0)

        await heartbeat.stop()
    }

    // MARK: - Incoming Heartbeat Processing

    @Test("Incoming heartbeat from another node registers in registry")
    func incomingHeartbeatRegisters() async throws {
        let nats = MockNATSClient()
        let registry = NodeRegistry()
        let identity = makeIdentity("local-node")

        let heartbeat = NodeHeartbeat(
            identity: identity,
            nats: nats,
            registry: registry,
            interval: .seconds(60)
        )

        try await heartbeat.start()
        try await Task.sleep(for: .milliseconds(100))

        // Simulate an incoming heartbeat from a remote node
        let remoteIdentity = NodeIdentity(
            nodeId: "remote-node",
            binaryVersion: "0.3.0-pre",
            role: .shadow,
            pid: 9999,
            hostname: "remote.local",
            startedAt: Date()
        )
        let remotePayload = HeartbeatPayload(identity: remoteIdentity)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(remotePayload)

        let message = NATSMessage(
            subject: "shikki.discovery.announce",
            data: data
        )
        await nats.injectMessage(message)
        try await Task.sleep(for: .milliseconds(100))

        // Remote node should now be in the registry
        let active = await registry.isActive("remote-node")
        #expect(active == true)

        let remote = await registry.nodes(withRole: .shadow)
        #expect(remote.count == 1)
        #expect(remote[0].nodeId == "remote-node")

        await heartbeat.stop()
    }

    // MARK: - Stale Detection

    @Test("Stale node callback fires for silent nodes")
    func staleCallbackFires() async throws {
        let nats = MockNATSClient()
        let registry = NodeRegistry()
        let identity = makeIdentity("monitor-node")

        // Register a "remote" node manually, then never heartbeat
        let remoteIdentity = NodeIdentity(
            nodeId: "stale-node",
            binaryVersion: "0.3.0-pre",
            role: .watcher,
            pid: 8888,
            hostname: "stale.local",
            startedAt: Date()
        )
        await registry.register(remoteIdentity)

        let staleDetected = StaleTracker()

        let heartbeat = NodeHeartbeat(
            identity: identity,
            nats: nats,
            registry: registry,
            interval: .milliseconds(50), // fast ticking for test
            staleThreshold: .milliseconds(10) // very short threshold
        )
        await heartbeat.setOnStaleNode { node in
            staleDetected.record(node.nodeId)
        }

        try await heartbeat.start()
        // Wait for at least one monitor cycle
        try await Task.sleep(for: .milliseconds(200))

        await heartbeat.stop()

        let detected = staleDetected.detectedIds
        #expect(detected.contains("stale-node"))
    }

    @Test("NATS publish failure does not crash heartbeat")
    func publishFailureHandled() async throws {
        let nats = MockNATSClient()
        await nats.setPublishError(.publishFailed("test"))
        let registry = NodeRegistry()
        let identity = makeIdentity()

        let heartbeat = NodeHeartbeat(
            identity: identity,
            nats: nats,
            registry: registry,
            interval: .seconds(60)
        )

        // Should not throw — publish failure is logged, not thrown
        try await heartbeat.start()
        try await Task.sleep(for: .milliseconds(100))

        let running = await heartbeat.isRunning
        #expect(running == true)

        await heartbeat.stop()
    }
}

// MARK: - Test Helper

/// Thread-safe stale node tracker for test assertions.
private final class StaleTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var _ids: [String] = []

    var detectedIds: [String] {
        lock.withLock { _ids }
    }

    func record(_ id: String) {
        lock.withLock { _ids.append(id) }
    }
}

// MARK: - Helper extension

extension NodeHeartbeat {
    func setOnStaleNode(_ handler: @escaping @Sendable (NodeIdentity) -> Void) {
        self.onStaleNode = handler
    }
}
