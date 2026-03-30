import ArgumentParser
import Foundation
import ShikkiKit

/// List all known nodes in the Shikki mesh.
///
/// Sends a `shikki.discovery.query` request via NATS and displays
/// the response as a formatted table. Requires nats-server running.
struct NodeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "nodes",
        abstract: "List all known Shikki nodes in the mesh"
    )

    @Option(name: .long, help: "NATS server URL")
    var natsUrl: String = "nats://127.0.0.1:4222"

    @Option(name: .long, help: "Filter by role (primary/shadow/watcher/draining)")
    var role: String?

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    @Option(name: .long, help: "Request timeout in seconds")
    var timeout: Int = 5

    func run() async throws {
        let nats = MockNATSClient() // TODO: replace with real NATSClient when available
        try await nats.connect()
        defer { Task { await nats.disconnect() } }

        let roleFilter: NodeRole?
        if let roleString = role {
            guard let parsed = NodeRole(rawValue: roleString) else {
                print("Unknown role: \(roleString). Valid: \(NodeRole.allCases.map(\.rawValue).joined(separator: ", "))")
                throw ExitCode.failure
            }
            roleFilter = parsed
        } else {
            roleFilter = nil
        }

        let query = DiscoveryQuery(roleFilter: roleFilter)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let queryData = try encoder.encode(query)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let reply = try await nats.request(
                subject: NATSSubjectMapper.discoveryQuery,
                data: queryData,
                timeout: .seconds(timeout)
            )

            let response = try decoder.decode(DiscoveryResponse.self, from: reply.data)

            if json {
                let jsonEncoder = JSONEncoder()
                jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                jsonEncoder.dateEncodingStrategy = .iso8601
                let output = try jsonEncoder.encode(response.nodes)
                print(String(data: output, encoding: .utf8) ?? "[]")
            } else {
                renderTable(response.nodes)
            }
        } catch let error as NATSError where error == .timeout {
            print("No response from discovery service (timeout after \(timeout)s).")
            print("Is nats-server running? Is a Shikki node active?")
            throw ExitCode.failure
        }
    }

    // MARK: - Table Rendering

    private func renderTable(_ nodes: [NodeIdentity]) {
        guard !nodes.isEmpty else {
            print("No nodes found.")
            return
        }

        let header = String(
            format: "%-20s %-10s %-8s %-20s %s",
            "NODE ID", "ROLE", "PID", "HOSTNAME", "STARTED"
        )

        print("\u{1B}[1mShikki Mesh Nodes\u{1B}[0m (\(nodes.count) node\(nodes.count == 1 ? "" : "s"))")
        print(String(repeating: "\u{2500}", count: 72))
        print("\u{1B}[2m\(header)\u{1B}[0m")
        print(String(repeating: "\u{2500}", count: 72))

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withFullTime, .withColonSeparatorInTime]

        for node in nodes.sorted(by: { $0.nodeId < $1.nodeId }) {
            let roleColor: String
            switch node.role {
            case .primary: roleColor = "\u{1B}[32m" // green
            case .shadow: roleColor = "\u{1B}[33m"  // yellow
            case .watcher: roleColor = "\u{1B}[36m" // cyan
            case .draining: roleColor = "\u{1B}[31m" // red
            }

            let started = formatter.string(from: node.startedAt)
            let idTruncated = String(node.nodeId.prefix(20))
            let hostTruncated = String(node.hostname.prefix(20))

            print(String(
                format: "%-20s %s%-10s\u{1B}[0m %-8d %-20s %s",
                idTruncated,
                roleColor, node.role.rawValue,
                node.pid,
                hostTruncated,
                started
            ))
        }

        print(String(repeating: "\u{2500}", count: 72))
    }
}
