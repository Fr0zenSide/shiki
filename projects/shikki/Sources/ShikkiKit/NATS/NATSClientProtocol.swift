import Foundation

// MARK: - NATSMessage

/// Lightweight message envelope from NATS.
/// Subject identifies the topic, data carries the JSON payload.
public struct NATSMessage: Sendable {
    public let subject: String
    public let data: Data
    public let replyTo: String?

    public init(subject: String, data: Data, replyTo: String? = nil) {
        self.subject = subject
        self.data = data
        self.replyTo = replyTo
    }
}

// MARK: - NATSClientProtocol

/// Transport-agnostic NATS client interface.
/// Concrete implementation wraps `nats-io/nats.swift`.
/// Tests inject `MockNATSClient` — no real nats-server in unit tests.
public protocol NATSClientProtocol: Sendable {
    /// Connect to the NATS server.
    func connect() async throws

    /// Disconnect and clean up.
    func disconnect() async

    /// Publish data to a subject.
    func publish(subject: String, data: Data) async throws

    /// Subscribe to a subject pattern (supports NATS wildcards: `*`, `>`).
    /// Returns an AsyncStream that yields messages until unsubscribed or disconnected.
    func subscribe(subject: String) -> AsyncStream<NATSMessage>

    /// Request-reply: publish and wait for a single response within the timeout.
    func request(subject: String, data: Data, timeout: Duration) async throws -> NATSMessage

    /// Whether the client is currently connected.
    var isConnected: Bool { get async }
}

// MARK: - NATSClientError

/// Errors from the NATS client layer.
public enum NATSClientError: Error, Sendable, Equatable {
    case notConnected
    case timeout
    case encodingFailed
    case connectionFailed(String)
}
