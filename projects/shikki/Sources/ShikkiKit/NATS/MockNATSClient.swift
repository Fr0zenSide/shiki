import Foundation

// MARK: - MockNATSClient

/// In-memory NATS client for testing. No real nats-server needed.
///
/// Features:
/// - Records all published messages for assertions
/// - Delivers published messages to matching subscribers via AsyncStream
/// - Supports request/reply pattern with configurable responders
/// - Supports NATS wildcard matching (`*` for single token, `>` for tail)
public actor MockNATSClient: NATSClientProtocol {

    // MARK: - State

    private var connected = false
    private var subscriptions: [String: [AsyncStream<NATSMessage>.Continuation]] = [:]
    private var responders: [String: @Sendable (NATSMessage) async -> NATSMessage] = [:]

    /// All messages published through this client, in order.
    public private(set) var publishedMessages: [NATSMessage] = []

    /// Whether connect() was called.
    public private(set) var connectCalled = false

    /// Whether disconnect() was called.
    public private(set) var disconnectCalled = false

    /// If set, connect() will throw this error.
    private var connectError: NATSError?

    /// If set, publish() will throw this error.
    private var publishError: NATSError?

    public init() {}

    // MARK: - NATSClientProtocol

    public var isConnected: Bool {
        connected
    }

    public func connect() async throws {
        connectCalled = true
        if let error = connectError {
            throw error
        }
        connected = true
    }

    public func disconnect() async {
        disconnectCalled = true
        connected = false
        // Finish all subscription continuations
        for (_, continuations) in subscriptions {
            for continuation in continuations {
                continuation.finish()
            }
        }
        subscriptions.removeAll()
    }

    public func publish(subject: String, data: Data) async throws {
        if let error = publishError {
            throw error
        }
        guard connected else {
            throw NATSError.notConnected
        }

        let message = NATSMessage(subject: subject, data: data, replyTo: nil)
        publishedMessages.append(message)

        // Deliver to matching subscribers
        for (pattern, continuations) in subscriptions {
            if Self.subjectMatches(pattern: pattern, subject: subject) {
                for continuation in continuations {
                    continuation.yield(message)
                }
            }
        }
    }

    public func subscribe(subject: String) -> AsyncStream<NATSMessage> {
        let (stream, continuation) = AsyncStream<NATSMessage>.makeStream(
            bufferingPolicy: .bufferingNewest(100)
        )
        subscriptions[subject, default: []].append(continuation)
        return stream
    }

    public func request(
        subject: String,
        data: Data,
        timeout: Duration
    ) async throws -> NATSMessage {
        guard connected else {
            throw NATSError.notConnected
        }

        let requestMessage = NATSMessage(
            subject: subject,
            data: data,
            replyTo: "_INBOX.\(UUID().uuidString)"
        )
        publishedMessages.append(requestMessage)

        // Look for a matching responder
        if let responder = findResponder(for: subject) {
            return await responder(requestMessage)
        }

        // No responder — simulate timeout
        throw NATSError.timeout
    }

    // MARK: - Test Helpers

    /// Register a responder for request/reply on a subject pattern.
    public func whenRequest(
        subject: String,
        respond: @escaping @Sendable (NATSMessage) async -> NATSMessage
    ) {
        responders[subject] = respond
    }

    /// Inject a message into subscribers as if it arrived from the server.
    /// Useful for testing subscription consumers without publishing.
    public func injectMessage(_ message: NATSMessage) {
        for (pattern, continuations) in subscriptions {
            if Self.subjectMatches(pattern: pattern, subject: message.subject) {
                for continuation in continuations {
                    continuation.yield(message)
                }
            }
        }
    }

    /// Configure connect() to throw the given error.
    public func setConnectError(_ error: NATSError?) {
        connectError = error
    }

    /// Configure publish() to throw the given error.
    public func setPublishError(_ error: NATSError?) {
        publishError = error
    }

    /// Reset all recorded state.
    public func reset() {
        publishedMessages.removeAll()
        connectCalled = false
        disconnectCalled = false
        connectError = nil
        publishError = nil
        responders.removeAll()
    }

    // MARK: - Wildcard Matching

    /// Match a NATS subject against a pattern.
    /// - `*` matches exactly one token
    /// - `>` matches one or more tokens (must be last token)
    /// - Literal tokens must match exactly
    static func subjectMatches(pattern: String, subject: String) -> Bool {
        let patternTokens = pattern.split(separator: ".", omittingEmptySubsequences: false)
        let subjectTokens = subject.split(separator: ".", omittingEmptySubsequences: false)

        for (index, pToken) in patternTokens.enumerated() {
            if pToken == ">" {
                // `>` matches one or more remaining tokens
                return index < subjectTokens.count
            }

            guard index < subjectTokens.count else {
                return false
            }

            if pToken == "*" {
                // `*` matches exactly one token
                continue
            }

            if pToken != subjectTokens[index] {
                return false
            }
        }

        return patternTokens.count == subjectTokens.count
    }

    // MARK: - Private

    private func findResponder(
        for subject: String
    ) -> (@Sendable (NATSMessage) async -> NATSMessage)? {
        // Exact match first
        if let responder = responders[subject] {
            return responder
        }
        // Pattern match
        for (pattern, responder) in responders {
            if Self.subjectMatches(pattern: pattern, subject: subject) {
                return responder
            }
        }
        return nil
    }
}
