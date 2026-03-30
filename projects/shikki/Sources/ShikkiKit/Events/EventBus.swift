import Foundation

// MARK: - EventFilter

/// Filter for subscribing to specific events.
public struct EventFilter: Sendable {
    public var types: Set<EventType>?
    public var scopes: Set<EventScope>?

    public static let all = EventFilter()

    public init(
        types: Set<EventType>? = nil,
        scopes: Set<EventScope>? = nil
    ) {
        self.types = types
        self.scopes = scopes
    }

    public func matches(_ event: ShikkiEvent) -> Bool {
        if let types, !types.contains(event.type) { return false }
        if let scopes, !scopes.contains(event.scope) { return false }
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
        let id = SubscriptionID()
        let stream = AsyncStream<ShikkiEvent>(bufferingPolicy: .bufferingNewest(100)) { continuation in
            subscribers[id] = Subscriber(filter: filter, continuation: continuation)
            continuation.onTermination = { @Sendable _ in
                Task { await self.removeSubscriber(id) }
            }
        }
        return stream
    }

    private func removeSubscriber(_ id: SubscriptionID) {
        if let sub = subscribers.removeValue(forKey: id) {
            sub.continuation.finish()
        }
    }
}
