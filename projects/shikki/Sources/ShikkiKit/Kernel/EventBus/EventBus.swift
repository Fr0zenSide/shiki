import Foundation

// MARK: - EventFilter

/// Filter for subscribing to specific events.
public struct EventFilter: Sendable {
    public var types: Set<EventType>?
    public var scopes: Set<EventScope>?
    public var minTimestamp: Date?

    public static let all = EventFilter()

    public init(
        types: Set<EventType>? = nil,
        scopes: Set<EventScope>? = nil,
        minTimestamp: Date? = nil
    ) {
        self.types = types
        self.scopes = scopes
        self.minTimestamp = minTimestamp
    }

    public func matches(_ event: ShikkiEvent) -> Bool {
        if let types, !types.contains(event.type) { return false }
        if let scopes, !scopes.contains(event.scope) { return false }
        if let minTimestamp, event.timestamp < minTimestamp { return false }
        return true
    }
}

// MARK: - SubscriptionID

public struct SubscriptionID: Hashable, Sendable {
    public let rawValue: UUID
    public init() { rawValue = UUID() }
}

// MARK: - InProcessEventBus

/// Simple in-process event bus using AsyncStream continuations.
/// Events are fire-and-forget — publishers never block.
public actor InProcessEventBus {
    private var subscribers: [SubscriptionID: Subscriber] = [:]

    private struct Subscriber {
        let filter: EventFilter
        let continuation: AsyncStream<ShikkiEvent>.Continuation
    }

    public init() {}

    /// Publish an event to all matching subscribers.
    public func publish(_ event: ShikkiEvent) {
        for (_, sub) in subscribers {
            if sub.filter.matches(event) {
                sub.continuation.yield(event)
            }
        }
    }

    /// Subscribe with a filter. Returns an AsyncStream of matching events.
    public func subscribe(filter: EventFilter) -> AsyncStream<ShikkiEvent> {
        let (stream, _) = subscribeWithId(filter: filter)
        return stream
    }

    /// Subscribe and get the subscription ID for later unsubscribe.
    public func subscribeWithId(filter: EventFilter) -> (AsyncStream<ShikkiEvent>, SubscriptionID) {
        let id = SubscriptionID()
        let stream = AsyncStream<ShikkiEvent>(bufferingPolicy: .bufferingNewest(100)) { continuation in
            subscribers[id] = Subscriber(filter: filter, continuation: continuation)
            continuation.onTermination = { @Sendable _ in
                Task { await self.removeSubscriber(id) }
            }
        }
        return (stream, id)
    }

    /// Remove a subscription and finish its stream.
    public func unsubscribe(_ id: SubscriptionID) {
        removeSubscriber(id)
    }

    private func removeSubscriber(_ id: SubscriptionID) {
        if let sub = subscribers.removeValue(forKey: id) {
            sub.continuation.finish()
        }
    }
}
