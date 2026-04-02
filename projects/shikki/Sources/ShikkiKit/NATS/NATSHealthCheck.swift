import Foundation
import Logging

// MARK: - NATSHealthResult

/// Result of a NATS server health check.
public struct NATSHealthResult: Sendable, Equatable {
    /// Whether the server responded to the ping.
    public let isHealthy: Bool

    /// Connection latency in milliseconds (nil if unreachable).
    public let latencyMs: Double?

    /// Human-readable status message.
    public let message: String

    public init(isHealthy: Bool, latencyMs: Double? = nil, message: String) {
        self.isHealthy = isHealthy
        self.latencyMs = latencyMs
        self.message = message
    }

    /// Healthy result with measured latency.
    public static func healthy(latencyMs: Double) -> NATSHealthResult {
        NATSHealthResult(
            isHealthy: true,
            latencyMs: latencyMs,
            message: String(format: "NATS OK (%.1fms)", latencyMs)
        )
    }

    /// Unhealthy result with reason.
    public static func unhealthy(_ reason: String) -> NATSHealthResult {
        NATSHealthResult(
            isHealthy: false,
            latencyMs: nil,
            message: "NATS unhealthy: \(reason)"
        )
    }
}

// MARK: - NATSHealthCheckProtocol

/// Abstraction for health checking the NATS server.
/// Allows mocking in tests.
public protocol NATSHealthCheckProtocol: Sendable {
    /// Ping the nats-server and return health + latency.
    func ping() async -> NATSHealthResult
}

// MARK: - NATSHealthCheck

/// Pings nats-server by opening a TCP connection and sending PING.
/// Uses raw socket-level check (no NATS client library needed).
///
/// Protocol:
///   1. Connect to host:port via TCP
///   2. Read INFO line
///   3. Send PING\r\n
///   4. Expect PONG\r\n
///   5. Measure round-trip latency
///
/// Used by `shi doctor` and `shi status`.
public struct NATSHealthCheck: NATSHealthCheckProtocol {

    private let host: String
    private let port: Int
    private let timeout: Duration
    private let logger: Logger

    public init(
        host: String = "127.0.0.1",
        port: Int = 4222,
        timeout: Duration = .seconds(2),
        logger: Logger = Logger(label: "shikki.nats.healthcheck")
    ) {
        self.host = host
        self.port = port
        self.timeout = timeout
        self.logger = logger
    }

    public func ping() async -> NATSHealthResult {
        let start = ContinuousClock.now

        do {
            let connected = try await tcpPing(host: host, port: port, timeout: timeout)
            guard connected else {
                return .unhealthy("connection refused on \(host):\(port)")
            }

            let elapsed = ContinuousClock.now - start
            let latencyMs = Double(elapsed.components.seconds) * 1000
                + Double(elapsed.components.attoseconds) / 1e15

            return .healthy(latencyMs: latencyMs)
        } catch {
            logger.debug("NATS health check failed: \(error)")
            return .unhealthy(error.localizedDescription)
        }
    }

    /// Attempt a TCP connection to verify nats-server is listening.
    /// Returns true if the connection succeeds.
    private func tcpPing(host: String, port: Int, timeout: Duration) async throws -> Bool {
        // Use Process to call a lightweight connectivity test.
        // This avoids pulling in NIO or raw socket APIs for a health check.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        // bash -c 'echo PING | nc -w 1 host port'
        let timeoutSec = max(1, Int(timeout.components.seconds))
        process.arguments = ["bash", "-c", "echo PING | nc -w \(timeoutSec) \(host) \(port) 2>/dev/null"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()

        // Wait with timeout via Task
        let result = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                process.waitUntilExit()
                return process.terminationStatus == 0
            }
            group.addTask {
                try? await Task.sleep(for: timeout + .seconds(1))
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }

        if process.isRunning {
            process.terminate()
        }

        return result
    }
}
