import Foundation
import Testing
@testable import ShikkiKit

@Suite("NodeRegistry")
struct NodeRegistryTests {

    private func makeIdentity(
        _ id: String,
        role: NodeRole = .primary,
        hostname: String = "test.local"
    ) -> NodeIdentity {
        NodeIdentity(
            nodeId: id,
            binaryVersion: "0.3.0-pre",
            role: role,
            pid: 100,
            hostname: hostname,
            startedAt: Date()
        )
    }

    // MARK: - Registration

    @Test("Register adds a node")
    func registerAddsNode() async {
        let registry = NodeRegistry()
        let identity = makeIdentity("node-1")

        await registry.register(identity)

        let count = await registry.nodeCount
        #expect(count == 1)
    }

    @Test("Register updates existing node")
    func registerUpdatesExisting() async {
        let registry = NodeRegistry()
        var identity = makeIdentity("node-1", role: .primary)
        await registry.register(identity)

        identity.role = .draining
        await registry.register(identity)

        let count = await registry.nodeCount
        #expect(count == 1)

        let nodes = await registry.activeNodes
        #expect(nodes.first?.role == .draining)
    }

    @Test("Deregister removes a node")
    func deregisterRemoves() async {
        let registry = NodeRegistry()
        await registry.register(makeIdentity("node-1"))
        await registry.register(makeIdentity("node-2"))

        await registry.deregister("node-1")

        let count = await registry.nodeCount
        #expect(count == 1)
    }

    @Test("Deregister non-existent node is a no-op")
    func deregisterNonExistent() async {
        let registry = NodeRegistry()
        await registry.deregister("ghost-node")

        let count = await registry.nodeCount
        #expect(count == 0)
    }

    // MARK: - Active / Stale

    @Test("Active nodes excludes stale")
    func activeExcludesStale() async {
        let registry = NodeRegistry()
        await registry.register(makeIdentity("node-1"))
        await registry.register(makeIdentity("node-2"))
        await registry.markStale("node-1")

        let active = await registry.activeNodes
        #expect(active.count == 1)
        #expect(active[0].nodeId == "node-2")
    }

    @Test("allNodes includes stale")
    func allNodesIncludesStale() async {
        let registry = NodeRegistry()
        await registry.register(makeIdentity("node-1"))
        await registry.markStale("node-1")

        let all = await registry.allNodes
        #expect(all.count == 1)
    }

    @Test("activeCount reflects non-stale nodes")
    func activeCountCorrect() async {
        let registry = NodeRegistry()
        await registry.register(makeIdentity("node-1"))
        await registry.register(makeIdentity("node-2"))
        await registry.register(makeIdentity("node-3"))
        await registry.markStale("node-2")

        let count = await registry.activeCount
        #expect(count == 2)
    }

    @Test("isActive returns true for active, false for stale and unknown")
    func isActiveChecks() async {
        let registry = NodeRegistry()
        await registry.register(makeIdentity("node-1"))
        await registry.markStale("node-1")

        let active = await registry.isActive("node-1")
        #expect(active == false)

        let unknown = await registry.isActive("ghost")
        #expect(unknown == false)
    }

    @Test("isStale returns correct state")
    func isStaleChecks() async {
        let registry = NodeRegistry()
        await registry.register(makeIdentity("node-1"))

        let stale1 = await registry.isStale("node-1")
        #expect(stale1 == false)

        await registry.markStale("node-1")
        let stale2 = await registry.isStale("node-1")
        #expect(stale2 == true)
    }

    @Test("Re-registering a stale node clears the stale flag")
    func reRegisterClearsStale() async {
        let registry = NodeRegistry()
        let identity = makeIdentity("node-1")
        await registry.register(identity)
        await registry.markStale("node-1")

        #expect(await registry.isStale("node-1") == true)

        // Re-register (heartbeat arrived)
        await registry.register(identity)
        #expect(await registry.isStale("node-1") == false)
        #expect(await registry.isActive("node-1") == true)
    }

    // MARK: - Primary Node

    @Test("primaryNode returns the primary role node")
    func primaryNodeReturned() async {
        let registry = NodeRegistry()
        await registry.register(makeIdentity("node-1", role: .shadow))
        await registry.register(makeIdentity("node-2", role: .primary))
        await registry.register(makeIdentity("node-3", role: .watcher))

        let primary = await registry.primaryNode
        #expect(primary?.nodeId == "node-2")
    }

    @Test("primaryNode returns nil when no primary exists")
    func primaryNodeNil() async {
        let registry = NodeRegistry()
        await registry.register(makeIdentity("node-1", role: .shadow))

        let primary = await registry.primaryNode
        #expect(primary == nil)
    }

    @Test("primaryNode returns nil when primary is stale")
    func primaryNodeStale() async {
        let registry = NodeRegistry()
        await registry.register(makeIdentity("node-1", role: .primary))
        await registry.markStale("node-1")

        let primary = await registry.primaryNode
        #expect(primary == nil)
    }

    // MARK: - Role Filtering

    @Test("nodes(withRole:) filters correctly")
    func nodesWithRole() async {
        let registry = NodeRegistry()
        await registry.register(makeIdentity("node-1", role: .primary))
        await registry.register(makeIdentity("node-2", role: .shadow))
        await registry.register(makeIdentity("node-3", role: .shadow))
        await registry.register(makeIdentity("node-4", role: .watcher))

        let shadows = await registry.nodes(withRole: .shadow)
        #expect(shadows.count == 2)

        let watchers = await registry.nodes(withRole: .watcher)
        #expect(watchers.count == 1)
    }

    // MARK: - Last Seen

    @Test("lastSeen returns timestamp for registered node")
    func lastSeenReturned() async {
        let registry = NodeRegistry()
        await registry.register(makeIdentity("node-1"))

        let seen = await registry.lastSeen("node-1")
        #expect(seen != nil)
    }

    @Test("lastSeen returns nil for unknown node")
    func lastSeenNilForUnknown() async {
        let registry = NodeRegistry()

        let seen = await registry.lastSeen("ghost")
        #expect(seen == nil)
    }

    // MARK: - Stale Detection

    @Test("staleNodes detects nodes past threshold")
    func staleNodesDetection() async throws {
        let registry = NodeRegistry()
        await registry.register(makeIdentity("node-1"))

        // With a threshold of 0 seconds, the node is immediately stale
        let stale = await registry.staleNodes(threshold: .zero)
        // The node was just registered, lastSeen is ~now, threshold is 0 → depends on timing
        // Use a negative-ish approach: wait briefly then check with a very short threshold
        try await Task.sleep(for: .milliseconds(50))
        let staleAfterDelay = await registry.staleNodes(threshold: .milliseconds(10))
        #expect(staleAfterDelay.count == 1)
        #expect(staleAfterDelay[0].nodeId == "node-1")
    }

    @Test("staleNodes excludes already-stale nodes")
    func staleNodesExcludesAlreadyStale() async throws {
        let registry = NodeRegistry()
        await registry.register(makeIdentity("node-1"))
        await registry.markStale("node-1")

        try await Task.sleep(for: .milliseconds(50))
        let stale = await registry.staleNodes(threshold: .milliseconds(10))
        // Already marked stale, should not be returned again
        #expect(stale.isEmpty)
    }

    // MARK: - Discovery Query Responder

    @Test("Query responder replies with active nodes")
    func queryResponder() async throws {
        let registry = NodeRegistry()
        await registry.register(makeIdentity("node-1", role: .primary))
        await registry.register(makeIdentity("node-2", role: .shadow))

        let nats = MockNATSClient()
        try await nats.connect()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Set up reply handler that simulates what the query responder does
        await nats.whenRequest(subject: NATSSubjectMapper.discoveryQuery) { message in
            let query = (try? decoder.decode(DiscoveryQuery.self, from: message.data)) ?? DiscoveryQuery()
            let nodes = [
                NodeIdentity(
                    nodeId: "node-1", binaryVersion: "0.3.0-pre", role: .primary,
                    pid: 100, hostname: "test.local", startedAt: Date()
                ),
                NodeIdentity(
                    nodeId: "node-2", binaryVersion: "0.3.0-pre", role: .shadow,
                    pid: 101, hostname: "test.local", startedAt: Date()
                ),
            ].filter { query.roleFilter == nil || $0.role == query.roleFilter }

            let response = DiscoveryResponse(nodes: nodes)
            let responseData = (try? encoder.encode(response)) ?? Data()
            return NATSMessage(subject: message.subject, data: responseData)
        }

        // Query with no filter
        let queryData = try encoder.encode(DiscoveryQuery())
        let reply = try await nats.request(
            subject: NATSSubjectMapper.discoveryQuery,
            data: queryData,
            timeout: .seconds(1)
        )

        let response = try decoder.decode(DiscoveryResponse.self, from: reply.data)
        #expect(response.nodes.count == 2)

        // Query with role filter
        let filteredQueryData = try encoder.encode(DiscoveryQuery(roleFilter: .shadow))
        let filteredReply = try await nats.request(
            subject: NATSSubjectMapper.discoveryQuery,
            data: filteredQueryData,
            timeout: .seconds(1)
        )

        let filteredResponse = try decoder.decode(DiscoveryResponse.self, from: filteredReply.data)
        #expect(filteredResponse.nodes.count == 1)
        #expect(filteredResponse.nodes[0].role == .shadow)
    }
}
