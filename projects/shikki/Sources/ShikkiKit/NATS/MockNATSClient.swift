import Foundation

// MARK: - MockNATSClient

/// In-memory NATS client for testing.
/// Records all published messages and routes them to matching subscribers.
/// No real nats-server required.
public actor MockNATSClient: NATSClientProtocol {
    public private(set) var connected = false
    public private(set) var publishedMessages: [(subject: String, data: Data)] = []
    public private(set) var subscribedSubjects: [String] = []
    private var continuations: [(subject: String, continuation: AsyncStream<NATSMessage>.Continuation)] = []

    /// Configurable: if true, connect() throws.
    public var shouldFailConnect = false

    /// Configurable: if true, publish() throws.
    public var shouldFailPublish = false

    /// Configurable reply for request-reply pattern.
    public var replyHandler: (@Sendable (String, Data) -> NATSMessage?)?

    public init() {}

    public var isConnected: Bool { connected }

    public func connect() async throws {
        if shouldFailConnect {
            throw NATSClientError.connectionFailed("mock: connect disabled")
        }
        connected = true
    }

    public func disconnect() async {
        connected = false
        for (_, cont) in continuations {
            cont.finish()
        }
        continuations.removeAll()
    }

    public func publish(subject: String, data: Data) async throws {
        guard connected else { throw NATSClientError.notConnected }
        if shouldFailPublish { throw publishError ?? NATSClientError.encodingFailed }

        publishedMessages.append((subject: subject, data: data))

        // Route to matching subscribers
        let message = NATSMessage(subject: subject, data: data)
        for (pattern, cont) in continuations {
            if Self.matches(subject: subject, pattern: pattern) {
                cont.yield(message)
            }
        }
    }

    public nonisolated func subscribe(subject: String) -> AsyncStream<NATSMessage> {
        AsyncStream { continuation in
            Task { await self.addSubscription(subject: subject, continuation: continuation) }
        }
    }

    public func request(subject: String, data: Data, timeout: Duration) async throws -> NATSMessage {
        guard connected else { throw NATSClientError.notConnected }
        if let handler = replyHandler, let reply = handler(subject, data) {
            return reply
        }
        throw NATSClientError.timeout
    }

    // MARK: - Internal

    private func addSubscription(subject: String, continuation: AsyncStream<NATSMessage>.Continuation) {
        subscribedSubjects.append(subject)
        continuations.append((subject: subject, continuation: continuation))
    }

    /// Set a publish error to simulate failure. Nil clears the error.
    public func setPublishError(_ error: NATSClientError?) {
        if let error {
            shouldFailPublish = true
            publishError = error
        } else {
            shouldFailPublish = false
            publishError = nil
        }
    }

    /// Configurable publish error (defaults to encodingFailed when shouldFailPublish is set).
    private var publishError: NATSClientError?

    /// Register a handler for request-reply on a specific subject.
    public func whenRequest(
        subject: String,
        handler: @escaping @Sendable (NATSMessage) -> NATSMessage?
    ) {
        replyHandler = { subj, data in
            guard Self.matches(subject: subj, pattern: subject) else { return nil }
            return handler(NATSMessage(subject: subj, data: data))
        }
    }

    /// Simulate injecting a message from "outside" (e.g. another publisher).
    /// Routes to all matching subscribers.
    public func injectMessage(_ message: NATSMessage) {
        for (pattern, cont) in continuations {
            if Self.matches(subject: message.subject, pattern: pattern) {
                cont.yield(message)
            }
        }
    }

    // MARK: - NATS Wildcard Matching

    /// Match a concrete subject against a NATS subscription pattern.
    /// Supports `*` (single token) and `>` (tail wildcard).
    ///
    /// Examples:
    /// - `shikki.events.maya.agent` matches `shikki.events.maya.agent` (exact)
    /// - `shikki.events.maya.agent` matches `shikki.events.>` (tail wildcard)
    /// - `shikki.events.maya.agent` matches `shikki.events.*.agent` (single wildcard)
    /// - `shikki.events.maya.agent` does NOT match `shikki.events.shiki.agent`
    nonisolated static func matches(subject: String, pattern: String) -> Bool {
        let subjectTokens = subject.split(separator: ".", omittingEmptySubsequences: false)
        let patternTokens = pattern.split(separator: ".", omittingEmptySubsequences: false)

        for (index, patternToken) in patternTokens.enumerated() {
            // `>` matches the rest of the subject
            if patternToken == ">" {
                return index <= subjectTokens.count
            }
            // Must have a subject token at this position
            guard index < subjectTokens.count else { return false }
            // `*` matches exactly one token
            if patternToken == "*" { continue }
            // Literal match
            if patternToken != subjectTokens[index] { return false }
        }

        // If pattern is shorter than subject (no `>`), lengths must match
        return subjectTokens.count == patternTokens.count
    }
}
