import Foundation

// MARK: - NATSMessage

/// A message received from or sent to NATS.
/// Thin struct wrapping subject, payload data, and optional reply-to for request/reply.
public struct NATSMessage: Sendable, Equatable {
    public let subject: String
    public let data: Data
    public let replyTo: String?

    public init(subject: String, data: Data, replyTo: String? = nil) {
        self.subject = subject
        self.data = data
        self.replyTo = replyTo
    }
}

// MARK: - NATSError

/// Errors produced by NATSClient operations.
public enum NATSError: Error, Sendable, Equatable {
    case notConnected
    case connectionFailed(String)
    case timeout
    case publishFailed(String)
}

// MARK: - NATSClientProtocol

/// Protocol abstracting a NATS client connection.
/// Concrete implementation wraps nats-io/nats.swift (added in a later wave).
/// Tests inject MockNATSClient — no real nats-server needed for unit tests.
public protocol NATSClientProtocol: Sendable {
    /// Connect to the NATS server.
    func connect() async throws

    /// Disconnect from the NATS server.
    func disconnect() async

    /// Publish data to a subject.
    func publish(subject: String, data: Data) async throws

    /// Subscribe to a subject and receive messages as an AsyncStream.
    func subscribe(subject: String) async -> AsyncStream<NATSMessage>

    /// Send a request and wait for a reply, with timeout.
    func request(subject: String, data: Data, timeout: Duration) async throws -> NATSMessage

    /// Whether the client is currently connected.
    var isConnected: Bool { get async }
}
