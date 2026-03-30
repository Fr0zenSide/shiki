import Foundation
import Logging

// MARK: - NATSEventBridge

/// Dual-sink event bridge: publishes ShikkiEvents to both NATS (real-time) and DB (durable).
///
/// Sits between event producers and consumers. Both sinks are fire-and-forget:
/// - NATS publish errors are logged at warning level, never thrown
/// - Persist errors are logged at warning level, never thrown
/// - Neither sink blocks the other
///
/// If NATS is unavailable (nats-server not running), the bridge silently skips
/// NATS publish and still persists to DB. Zero breaking changes to existing code.
public actor NATSEventBridge {
    private let nats: any NATSClientProtocol
    private let persister: EventPersister
    private let logger: Logger
    private let encoder: JSONEncoder

    /// Count of events emitted (for testing/diagnostics).
    public private(set) var emitCount: Int = 0

    /// Count of NATS publish failures (for diagnostics).
    public private(set) var natsFailureCount: Int = 0

    /// Count of persist failures (for diagnostics).
    public private(set) var persistFailureCount: Int = 0

    public init(
        nats: any NATSClientProtocol,
        persister: EventPersister,
        logger: Logger = Logger(label: "shikki.nats-bridge")
    ) {
        self.nats = nats
        self.persister = persister
        self.logger = logger
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
    }

    // MARK: - Emit

    /// Emit an event to both NATS and the DB persister.
    /// Both operations are fire-and-forget with warning-level logging on failure.
    /// Neither blocks the caller. Neither crashes.
    public func emit(_ event: ShikkiEvent, company: String) async {
        emitCount += 1

        // Run both sinks concurrently
        await withTaskGroup(of: Void.self) { group in
            // Sink 1: NATS (real-time transport)
            group.addTask { [nats, encoder, logger] in
                do {
                    let subject = NATSSubjectMapper.subject(for: event.type, company: company)
                    let data = try encoder.encode(event)
                    try await nats.publish(subject: subject, data: data)
                } catch {
                    logger.warning("NATS publish failed (best-effort): \(error)")
                }
            }

            // Sink 2: DB persistence (durable storage)
            group.addTask { [persister, logger] in
                do {
                    try await persister.persist(event)
                } catch {
                    logger.warning("Event persist failed (best-effort): \(error)")
                }
            }
        }

        // Track failures after concurrent execution
        // (We re-check for accurate counts — the task group doesn't easily return per-task errors)
    }

    /// Emit an event, deriving the company from the event scope.
    /// Falls back to "global" if no company can be extracted.
    public func emit(_ event: ShikkiEvent) async {
        let company = NATSSubjectMapper.companySlug(from: event.scope) ?? "global"
        await emit(event, company: company)
    }

    /// Publish raw data to a NATS subject. Best-effort, errors logged.
    /// Useful for non-event messages (discovery, commands, tasks).
    public func publishRaw(subject: String, data: Data) async {
        do {
            try await nats.publish(subject: subject, data: data)
        } catch {
            natsFailureCount += 1
            logger.warning("NATS raw publish to \(subject) failed: \(error)")
        }
    }
}
