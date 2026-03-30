import Foundation
import Testing
@testable import ShikkiKit

@Suite("NodeIdentity")
struct NodeIdentityTests {

    // MARK: - NodeRole

    @Test("NodeRole has all expected cases")
    func roleAllCases() {
        let cases = NodeRole.allCases
        #expect(cases.count == 4)
        #expect(cases.contains(.primary))
        #expect(cases.contains(.shadow))
        #expect(cases.contains(.watcher))
        #expect(cases.contains(.draining))
    }

    @Test("NodeRole rawValues are correct strings")
    func roleRawValues() {
        #expect(NodeRole.primary.rawValue == "primary")
        #expect(NodeRole.shadow.rawValue == "shadow")
        #expect(NodeRole.watcher.rawValue == "watcher")
        #expect(NodeRole.draining.rawValue == "draining")
    }

    @Test("NodeRole round-trips through Codable")
    func roleCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for role in NodeRole.allCases {
            let data = try encoder.encode(role)
            let decoded = try decoder.decode(NodeRole.self, from: data)
            #expect(decoded == role)
        }
    }

    // MARK: - NodeIdentity

    @Test("NodeIdentity initializes with all fields")
    func identityInit() {
        let now = Date()
        let identity = NodeIdentity(
            nodeId: "node-abc",
            binaryVersion: "0.3.0-pre",
            role: .primary,
            pid: 12345,
            hostname: "macbook.local",
            startedAt: now
        )

        #expect(identity.nodeId == "node-abc")
        #expect(identity.binaryVersion == "0.3.0-pre")
        #expect(identity.role == .primary)
        #expect(identity.pid == 12345)
        #expect(identity.hostname == "macbook.local")
        #expect(identity.startedAt == now)
        #expect(identity.id == "node-abc")
    }

    @Test("NodeIdentity.current uses ProcessInfo")
    func identityCurrent() {
        let identity = NodeIdentity.current(nodeId: "test-node")
        #expect(identity.nodeId == "test-node")
        #expect(identity.binaryVersion == "0.3.0-pre")
        #expect(identity.role == .primary)
        #expect(identity.pid == ProcessInfo.processInfo.processIdentifier)
        #expect(identity.hostname == ProcessInfo.processInfo.hostName)
    }

    @Test("NodeIdentity round-trips through Codable")
    func identityCodable() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let identity = NodeIdentity(
            nodeId: "node-xyz",
            binaryVersion: "1.0.0",
            role: .shadow,
            pid: 999,
            hostname: "server.local",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let data = try encoder.encode(identity)
        let decoded = try decoder.decode(NodeIdentity.self, from: data)

        #expect(decoded.nodeId == identity.nodeId)
        #expect(decoded.binaryVersion == identity.binaryVersion)
        #expect(decoded.role == identity.role)
        #expect(decoded.pid == identity.pid)
        #expect(decoded.hostname == identity.hostname)
    }

    @Test("NodeIdentity is Hashable")
    func identityHashable() {
        let a = NodeIdentity(
            nodeId: "node-a", binaryVersion: "1.0", role: .primary,
            pid: 1, hostname: "a", startedAt: Date()
        )
        let b = NodeIdentity(
            nodeId: "node-a", binaryVersion: "1.0", role: .primary,
            pid: 1, hostname: "a", startedAt: a.startedAt
        )
        #expect(a == b)

        var set: Set<NodeIdentity> = [a, b]
        #expect(set.count == 1)
    }

    // MARK: - HeartbeatPayload

    @Test("HeartbeatPayload round-trips through Codable")
    func heartbeatPayloadCodable() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let identity = NodeIdentity.current(nodeId: "hb-test")
        let payload = HeartbeatPayload(
            identity: identity,
            uptimeSeconds: 120.5,
            activeAgents: 3,
            contextUsedPct: 45
        )

        let data = try encoder.encode(payload)
        let decoded = try decoder.decode(HeartbeatPayload.self, from: data)

        #expect(decoded.identity.nodeId == "hb-test")
        #expect(decoded.uptimeSeconds == 120.5)
        #expect(decoded.activeAgents == 3)
        #expect(decoded.contextUsedPct == 45)
    }

    // MARK: - DiscoveryQuery / DiscoveryResponse

    @Test("DiscoveryQuery with no filter round-trips")
    func discoveryQueryNoFilter() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let query = DiscoveryQuery()
        let data = try encoder.encode(query)
        let decoded = try decoder.decode(DiscoveryQuery.self, from: data)

        #expect(decoded.roleFilter == nil)
    }

    @Test("DiscoveryQuery with role filter round-trips")
    func discoveryQueryWithFilter() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let query = DiscoveryQuery(roleFilter: .shadow)
        let data = try encoder.encode(query)
        let decoded = try decoder.decode(DiscoveryQuery.self, from: data)

        #expect(decoded.roleFilter == .shadow)
    }

    @Test("DiscoveryResponse with nodes round-trips")
    func discoveryResponseCodable() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let nodes = [
            NodeIdentity.current(nodeId: "node-1"),
            NodeIdentity.current(nodeId: "node-2", role: .shadow),
        ]
        let response = DiscoveryResponse(nodes: nodes)

        let data = try encoder.encode(response)
        let decoded = try decoder.decode(DiscoveryResponse.self, from: data)

        #expect(decoded.nodes.count == 2)
        #expect(decoded.nodes[0].nodeId == "node-1")
        #expect(decoded.nodes[1].role == .shadow)
    }
}
