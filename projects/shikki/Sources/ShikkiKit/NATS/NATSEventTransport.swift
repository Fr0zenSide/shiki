import Foundation
import Logging

// MARK: - NATSEventTransport

/// Adapts a NATSClientProtocol to the EventTransport protocol.
/// Subscribes to `shikki.events.>` (or a filtered subject) and decodes
/// NATSMessage payloads into ShikkiEvent objects.
///
/// This is the NATS replacement for WebSocketEventTransport.
/// The existing EventRenderer, LogCommand, etc. work unchanged —
/// they consume EventTransport, not a specific transport implementation.
public actor NATSEventTransport: EventTransport {
    private let nats: NATSClientProtocol
    private let logger: Logger
    private var isDisconnected = false

    /// Status callback for rendering connection state.
    public var onStatusChange: (@Sendable (ConnectionStatus) -> Void)?

    public enum ConnectionStatus: Sendable {
        case connecting
        case connected
        case reconnecting(attempt: Int)
        case disconnected
    }

    public init(
        nats: NATSClientProtocol,
        logger: Logger = Logger(label: "shikki.event-transport.nats")
    ) {
        self.nats = nats
        self.logger = logger
    }

    /// Subscribe to events.
    ///
    /// The `channel` parameter maps to a NATS subject:
    /// - Empty or `*` → `shikki.events.>` (all events)
    /// - `maya` → `shikki.events.maya.>` (one company)
    /// - `maya.agent` → `shikki.events.maya.agent` (company + type)
    public nonisolated func subscribe(to channel: String) -> AsyncStream<ShikkiEvent> {
        let subject = Self.channelToSubject(channel)

        return AsyncStream { continuation in
            let task = Task {
                // Connect if needed
                let connected = await self.nats.isConnected
                if !connected {
                    do {
                        await self.notifyStatus(.connecting)
                        try await self.nats.connect()
                        await self.notifyStatus(.connected)
                    } catch {
                        await self.notifyStatus(.disconnected)
                        continuation.finish()
                        return
                    }
                } else {
                    await self.notifyStatus(.connected)
                }

                // Subscribe to the NATS subject
                let stream = self.nats.subscribe(subject: subject)

                for await message in stream {
                    let stopped = await self.isDisconnected
                    if stopped || Task.isCancelled { break }

                    if let event = Self.decodeEvent(from: message) {
                        continuation.yield(event)
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
        await nats.disconnect()
    }

    // MARK: - Helpers

    private func notifyStatus(_ status: ConnectionStatus) {
        onStatusChange?(status)
    }

    /// Map a channel string to a NATS subject.
    nonisolated static func channelToSubject(_ channel: String) -> String {
        let trimmed = channel.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed == "*" {
            return "shikki.events.>"
        }
        // If it already contains dots (e.g. "maya.agent"), use as-is under prefix
        if trimmed.contains(".") {
            return "shikki.events.\(trimmed)"
        }
        // Single token = company filter with tail wildcard
        return "shikki.events.\(trimmed).>"
    }

    /// Decode a NATSMessage into a ShikkiEvent.
    nonisolated static func decodeEvent(from message: NATSMessage) -> ShikkiEvent? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ShikkiEvent.self, from: message.data)
    }
}
