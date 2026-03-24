import Foundation
import Logging

// MARK: - EventTransport Protocol

/// Transport-agnostic event subscription.
/// WS today, NATS tomorrow — zero code change in the logger when we swap transports.
public protocol EventTransport: Sendable {
    /// Subscribe to events on a given channel/subject pattern.
    /// Returns an AsyncStream that yields decoded events until disconnected.
    func subscribe(to channel: String) -> AsyncStream<ShikiEvent>

    /// Disconnect and clean up resources.
    func disconnect() async
}

// MARK: - WebSocketEventTransport

/// WebSocket-based transport connecting to the Shiki backend WS endpoint.
/// Auto-reconnects on disconnect with exponential backoff.
public actor WebSocketEventTransport: EventTransport {
    private let url: URL
    private let logger: Logger
    private let maxReconnectDelay: Duration
    private var webSocketTask: URLSessionWebSocketTask?
    private let session: URLSession
    private var isDisconnected = false

    /// Status callback for rendering reconnection state.
    public var onStatusChange: (@Sendable (ConnectionStatus) -> Void)?

    public enum ConnectionStatus: Sendable {
        case connecting
        case connected
        case reconnecting(attempt: Int)
        case disconnected
    }

    public init(
        url: URL,
        maxReconnectDelay: Duration = .seconds(30),
        logger: Logger = Logger(label: "shikki.event-transport.ws")
    ) {
        self.url = url
        self.maxReconnectDelay = maxReconnectDelay
        self.logger = logger
        self.session = URLSession(configuration: .default)
    }

    public nonisolated func subscribe(to channel: String) -> AsyncStream<ShikiEvent> {
        AsyncStream { continuation in
            let task = Task {
                var attempt = 0
                while !Task.isCancelled {
                    let shouldStop = await self.isDisconnected
                    if shouldStop { break }

                    attempt += 1
                    await self.notifyStatus(attempt == 1 ? .connecting : .reconnecting(attempt: attempt))

                    do {
                        let wsTask = await self.connect()
                        await self.notifyStatus(.connected)
                        attempt = 0

                        while !Task.isCancelled {
                            let message = try await wsTask.receive()
                            let data: Data
                            switch message {
                            case .string(let text):
                                data = Data(text.utf8)
                            case .data(let d):
                                data = d
                            @unknown default:
                                continue
                            }

                            if let event = Self.parseEvent(from: data, channel: channel) {
                                continuation.yield(event)
                            }
                        }
                    } catch {
                        let stopped = await self.isDisconnected
                        if stopped || Task.isCancelled { break }

                        let delay = Self.backoffDelay(attempt: attempt, max: self.maxReconnectDelay)
                        await self.notifyStatus(.reconnecting(attempt: attempt))
                        try? await Task.sleep(for: delay)
                    }
                }

                await self.notifyStatus(.disconnected)
                continuation.finish()
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    public func disconnect() async {
        isDisconnected = true
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }

    // MARK: - Private

    private func connect() -> URLSessionWebSocketTask {
        let task = session.webSocketTask(with: url)
        task.resume()
        self.webSocketTask = task
        return task
    }

    private func notifyStatus(_ status: ConnectionStatus) {
        onStatusChange?(status)
    }

    /// Parse a raw JSON message into a ShikiEvent, optionally filtering by channel.
    /// The channel filter matches against the event scope's project slug or event type.
    nonisolated static func parseEvent(from data: Data, channel: String) -> ShikiEvent? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let event = try? decoder.decode(ShikiEvent.self, from: data) else {
            return nil
        }

        // Empty channel = no filter, accept all
        if channel.isEmpty || channel == "*" {
            return event
        }

        // Filter by company slug (scope) or event type string
        let parts = channel.split(separator: ".")
        if let companyFilter = parts.first {
            switch event.scope {
            case .project(let slug) where slug == String(companyFilter):
                break // matches
            case .session(let id) where id.hasPrefix(String(companyFilter)):
                break // matches
            default:
                // Check if it's a type filter instead
                if parts.count == 1 {
                    // Single-part filter: match company OR type keyword
                    let typeString = String(describing: event.type)
                    if !typeString.localizedCaseInsensitiveContains(String(companyFilter)) {
                        return nil
                    }
                } else {
                    return nil
                }
            }
        }

        // If second part present, filter by event type keyword
        if parts.count > 1 {
            let typeFilter = String(parts[1])
            let typeString = String(describing: event.type)
            if !typeString.localizedCaseInsensitiveContains(typeFilter) {
                return nil
            }
        }

        return event
    }

    /// Exponential backoff: 1s, 2s, 4s, 8s, ... capped at maxDelay.
    nonisolated static func backoffDelay(attempt: Int, max maxDelay: Duration) -> Duration {
        let base = 1.0
        let delay = base * pow(2.0, Double(min(attempt - 1, 10)))
        let capped = min(delay, Double(maxDelay.components.seconds))
        return .seconds(capped)
    }
}

// MARK: - MockEventTransport (for tests)

/// In-memory transport for testing. Yields events pushed via `emit(_:)`.
public actor MockEventTransport: EventTransport {
    private var continuations: [AsyncStream<ShikiEvent>.Continuation] = []
    public private(set) var disconnectCalled = false

    public init() {}

    public nonisolated func subscribe(to channel: String) -> AsyncStream<ShikiEvent> {
        AsyncStream { continuation in
            Task { await self.addContinuation(continuation) }
        }
    }

    public func disconnect() async {
        disconnectCalled = true
        for c in continuations {
            c.finish()
        }
        continuations.removeAll()
    }

    /// Push an event to all active subscribers.
    public func emit(_ event: ShikiEvent) {
        for c in continuations {
            c.yield(event)
        }
    }

    private func addContinuation(_ continuation: AsyncStream<ShikiEvent>.Continuation) {
        continuations.append(continuation)
    }
}
