import Foundation
import Logging

/// Protocol for persisting events to external storage.
public protocol EventPersister: Sendable {
    func persist(_ event: ShikkiEvent) async throws
}

/// Subscribes to all events and persists them via an EventPersister.
/// Best-effort: if persistence fails, events still flow to local subscribers.
public actor ShikkiDBEventLogger {
    private let persister: EventPersister
    private let logger: Logger
    private var task: Task<Void, Never>?

    public init(
        persister: EventPersister,
        logger: Logger = Logger(label: "shikki.event-logger")
    ) {
        self.persister = persister
        self.logger = logger
    }

    /// Start consuming events from the bus and persisting them.
    public func start(bus: InProcessEventBus) async {
        let stream = await bus.subscribe(filter: .all)
        task = Task {
            for await event in stream {
                do {
                    try await persister.persist(event)
                } catch {
                    logger.debug("Event persist failed (best-effort): \(error.localizedDescription)")
                }
            }
        }
    }

    /// Stop the logger.
    public func stop() {
        task?.cancel()
        task = nil
    }
}
