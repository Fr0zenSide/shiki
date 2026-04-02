import Foundation
import Logging

// MARK: - ServiceEntry

/// Internal bookkeeping for a managed service.
struct ServiceEntry: Sendable {
    let service: any ManagedService
    var nextDue: Date
    var restartCount: Int = 0
    var consecutiveFailures: Int = 0
    var lastFailure: Date?
}

// MARK: - WakeReason

/// Reason the kernel woke up early from its tickless sleep.
/// Used for logging, metrics, and debugging scheduler responsiveness.
public enum WakeReason: Sendable, CustomStringConvertible {
    /// A new task was created or modified externally.
    case taskCreated(String)
    /// An agent or user requested immediate dispatch.
    case dispatchRequested
    /// A service explicitly asked for an early re-tick.
    case serviceNudge(ServiceID)
    /// External signal (e.g., from DB trigger, MCP call, shi push).
    case externalSignal(String)

    public var description: String {
        switch self {
        case .taskCreated(let name): "taskCreated(\(name))"
        case .dispatchRequested: "dispatchRequested"
        case .serviceNudge(let id): "serviceNudge(\(id))"
        case .externalSignal(let source): "externalSignal(\(source))"
        }
    }
}

// MARK: - EscalationEvent

/// Emitted when a service hits 3 consecutive failures (BR-24).
/// The kernel disables the service and records diagnostic context.
public struct EscalationEvent: Sendable {
    public let serviceId: ServiceID
    public let failureCount: Int
    public let lastError: String
    public let timestamp: Date

    public init(serviceId: ServiceID, failureCount: Int, lastError: String, timestamp: Date = Date()) {
        self.serviceId = serviceId
        self.failureCount = failureCount
        self.lastError = lastError
        self.timestamp = timestamp
    }
}

// MARK: - ShikkiKernel

/// Root actor managing all Shikki services with adaptive timing and timer coalescing.
/// Like launchd is to macOS — it launches everything, monitors health, restarts on failure.
///
/// The kernel:
/// 1. Computes when the next service is due
/// 2. Sleeps until that time (tickless when idle) — OR wakes early on external signal
/// 3. Collects all services due within the coalescing window
/// 4. Batch-fetches a single KernelSnapshot
/// 5. Fans out to services ordered by QoS
/// 6. Handles failures per RestartPolicy with 3-failure escalation
///
/// Wake-on-event: Any external producer (DB hook, MCP handler, CLI command, service)
/// can call `wake(_:)` to interrupt the sleep and force an immediate recompute of `next_due`.
public actor ShikkiKernel {
    private var entries: [ServiceID: ServiceEntry] = [:]
    private let snapshotProvider: KernelSnapshotProvider
    private let logger: Logger
    private var isRunning = false

    /// Signal channel: any producer can wake the kernel from its tickless sleep.
    private let wakeContinuation: AsyncStream<WakeReason>.Continuation
    private let wakeStream: AsyncStream<WakeReason>

    /// Escalation events emitted by the kernel. Consumers (e.g., EventBus) can read these.
    private(set) var escalations: [EscalationEvent] = []

    /// Number of consecutive failures that triggers escalation (BR-24).
    static let escalationThreshold = 3

    /// The coalescing window: services due within this tolerance of each other
    /// fire in the same tick. Per-service leeway is used for individual tolerance.
    private static let defaultCoalescingWindow: Duration = .seconds(2)

    public init(
        services: [any ManagedService],
        snapshotProvider: KernelSnapshotProvider,
        logger: Logger = Logger(label: "shikki.kernel")
    ) {
        self.snapshotProvider = snapshotProvider
        self.logger = logger

        // Initialize the wake signal channel (unbounded buffer — producers never block).
        var cont: AsyncStream<WakeReason>.Continuation!
        self.wakeStream = AsyncStream(bufferingPolicy: .unbounded) { cont = $0 }
        self.wakeContinuation = cont

        let now = Date()
        for service in services {
            entries[service.id] = ServiceEntry(
                service: service,
                nextDue: now
            )
        }
    }

    // MARK: - Public API

    /// Register a new service at runtime.
    public func register(_ service: any ManagedService) {
        entries[service.id] = ServiceEntry(
            service: service,
            nextDue: Date()
        )
        logger.info("Registered service: \(service.id)")
    }

    /// Unregister a service at runtime.
    public func unregister(_ serviceId: ServiceID) {
        entries.removeValue(forKey: serviceId)
        logger.info("Unregistered service: \(serviceId)")
    }

    /// Start the kernel loop. Runs until cancelled.
    public func run() async {
        isRunning = true
        installSignalHandlers()
        logger.info("ShikkiKernel started with \(entries.count) services")

        while !Task.isCancelled && isRunning {
            guard let sleepDuration = computeSleepDuration() else {
                // No services registered — should not happen, but guard anyway
                logger.warning("No services registered, stopping kernel")
                break
            }

            // Sleep until next service is due — OR an external event wakes us early.
            if sleepDuration > .zero {
                let reason = await raceTimerVsWake(duration: sleepDuration)
                if let reason {
                    logger.info("Kernel woke early: \(reason)")
                }
                if Task.isCancelled { break }
            }

            let now = Date()
            let dueServices = collectDueServices(at: now)

            guard !dueServices.isEmpty else { continue }

            // Batch-fetch snapshot once for all services in this tick
            let snapshot = await snapshotProvider.fetchSnapshot()

            // Fan out: higher QoS first (BR-05)
            let sorted = dueServices.sorted { $0.qos < $1.qos }

            for service in sorted {
                guard service.canRun(health: snapshot.health) else {
                    logger.debug("Service \(service.id) skipped (health: \(snapshot.health))")
                    continue
                }

                do {
                    try await service.tick(snapshot: snapshot)
                    // Reset failure tracking on success
                    entries[service.id]?.restartCount = 0
                    entries[service.id]?.consecutiveFailures = 0
                    entries[service.id]?.lastFailure = nil
                } catch {
                    logger.error("Service \(service.id) failed: \(error)")
                    await handleFailure(serviceId: service.id, error: error)
                }

                // Schedule next tick
                let interval = service.interval
                entries[service.id]?.nextDue = now.addingTimeInterval(
                    Double(interval.components.seconds)
                    + Double(interval.components.attoseconds) / 1e18
                )
            }
        }

        logger.info("ShikkiKernel stopped")
    }

    /// Graceful shutdown: checkpoint and stop.
    public func shutdown() {
        isRunning = false
        wakeContinuation.finish()
        logger.info("ShikkiKernel shutdown requested")
    }

    // MARK: - Wake Signal (Public API)

    /// Wake the kernel from its tickless sleep.
    /// Called by: DB event hooks, MCP handlers, CLI commands, services themselves.
    public func wake(_ reason: WakeReason) {
        wakeContinuation.yield(reason)
    }

    /// Non-isolated variant for signal handlers, callbacks, and non-async contexts.
    public nonisolated func wakeSync(_ reason: WakeReason) {
        wakeContinuation.yield(reason)
    }

    // MARK: - Timer vs Wake Race

    /// Race the timer sleep against the wake stream.
    /// Returns the wake reason if interrupted, nil if the timer expired naturally.
    private func raceTimerVsWake(duration: Duration) async -> WakeReason? {
        await withTaskGroup(of: WakeReason?.self) { group in
            group.addTask {
                try? await Task.sleep(for: duration)
                return nil  // Timer expired naturally
            }
            group.addTask { [wakeStream] in
                var iterator = wakeStream.makeAsyncIterator()
                return await iterator.next()  // Woke by signal
            }
            let first = await group.next() ?? nil
            group.cancelAll()  // Cancel the loser
            return first
        }
    }

    /// All registered service IDs.
    public var serviceIDs: [ServiceID] {
        Array(entries.keys)
    }

    /// Next due date for a given service.
    public func nextDue(for serviceId: ServiceID) -> Date? {
        entries[serviceId]?.nextDue
    }

    /// Consecutive failure count for a service (for testing/observability).
    public func consecutiveFailures(for serviceId: ServiceID) -> Int {
        entries[serviceId]?.consecutiveFailures ?? 0
    }

    // MARK: - Timer Coalescing

    /// Compute how long to sleep until the next service is due (BR-06).
    func computeSleepDuration() -> Duration? {
        guard !entries.isEmpty else { return nil }

        let now = Date()
        let earliest = entries.values.map(\.nextDue).min() ?? now
        let interval = earliest.timeIntervalSince(now)

        if interval <= 0 {
            return .zero
        }

        return .nanoseconds(Int64(interval * 1_000_000_000))
    }

    /// Collect all services due within the coalescing window (BR-07).
    /// A service is "due" if now >= nextDue - leeway.
    func collectDueServices(at now: Date) -> [any ManagedService] {
        var due: [any ManagedService] = []

        for (_, entry) in entries {
            let leewaySeconds = Double(entry.service.leeway.components.seconds)
                + Double(entry.service.leeway.components.attoseconds) / 1e18
            let effectiveDue = entry.nextDue.addingTimeInterval(-leewaySeconds)

            if now >= effectiveDue {
                due.append(entry.service)
            }
        }

        return due
    }

    // MARK: - Failure Handling

    private func handleFailure(serviceId: ServiceID, error: Error) async {
        guard var entry = entries[serviceId] else { return }

        entry.restartCount += 1
        entry.consecutiveFailures += 1
        entry.lastFailure = Date()

        // BR-24: 3 consecutive failures → escalate
        if entry.consecutiveFailures >= Self.escalationThreshold {
            let event = EscalationEvent(
                serviceId: serviceId,
                failureCount: entry.consecutiveFailures,
                lastError: String(describing: error)
            )
            escalations.append(event)
            logger.error(
                "ESCALATION: Service \(serviceId) hit \(entry.consecutiveFailures) consecutive failures — disabling"
            )
            // Remove from active entries to stop scheduling
            entries.removeValue(forKey: serviceId)
            return
        }

        let policy = entry.service.restartPolicy

        switch policy {
        case .always(let maxRestarts, let backoff):
            if entry.restartCount <= maxRestarts {
                let backoffSeconds = Double(backoff.components.seconds)
                    + Double(backoff.components.attoseconds) / 1e18
                entry.nextDue = Date().addingTimeInterval(backoffSeconds)
                logger.info("Service \(serviceId) restart \(entry.restartCount)/\(maxRestarts) after backoff")
            } else {
                logger.error("Service \(serviceId) exceeded max restarts (\(maxRestarts))")
            }

        case .onFailure(let maxRestarts, let backoff):
            if entry.restartCount <= maxRestarts {
                let backoffSeconds = Double(backoff.components.seconds)
                    + Double(backoff.components.attoseconds) / 1e18
                entry.nextDue = Date().addingTimeInterval(backoffSeconds)
                logger.info("Service \(serviceId) restart \(entry.restartCount)/\(maxRestarts) after backoff")
            } else {
                logger.error("Service \(serviceId) exceeded max restarts (\(maxRestarts))")
            }

        case .once:
            logger.warning("Service \(serviceId) failed with .once policy — will not restart")
            // Remove from entries so it doesn't fire again
            entries.removeValue(forKey: serviceId)
            return
        }

        entries[serviceId] = entry
    }

    // MARK: - Signal Handling

    private nonisolated func installSignalHandlers() {
        let handler: @convention(c) (Int32) -> Void = { signal in
            let manager = PausedSessionManager()
            if let checkpoint = manager.autoSave() {
                FileHandle.standardError.write(
                    Data("\nAuto-saved session: \(checkpoint.sessionId)\n".utf8)
                )
            }
            Foundation.signal(signal, SIG_DFL)
            raise(signal)
        }
        signal(SIGINT, handler)
        signal(SIGTERM, handler)
    }
}

// MARK: - KernelSnapshotProvider

/// Protocol for fetching batched backend data.
/// Abstracts the HTTP layer so the kernel is testable.
public protocol KernelSnapshotProvider: Sendable {
    func fetchSnapshot() async -> KernelSnapshot
}

// MARK: - BackendSnapshotProvider

/// Production snapshot provider that batch-fetches from the backend API.
public struct BackendSnapshotProvider: KernelSnapshotProvider {
    private let client: any BackendClientProtocol
    private let registry: SessionRegistry

    public init(client: any BackendClientProtocol, registry: SessionRegistry) {
        self.client = client
        self.registry = registry
    }

    public func fetchSnapshot() async -> KernelSnapshot {
        do {
            guard try await client.healthCheck() else {
                return .unreachable
            }

            let companies = (try? await client.getCompanies()) ?? []
            let queue = (try? await client.getDispatcherQueue()) ?? []
            let decisions = (try? await client.getPendingDecisions()) ?? []
            let slugs = await registry.runningSlugs()
            let sessions = slugs.map { slug -> SessionInfo in
                let parts = slug.split(separator: ":", maxSplits: 1)
                let companySlug = parts.first.map(String.init) ?? slug
                return SessionInfo(slug: slug, companySlug: companySlug, isRunning: true)
            }

            return KernelSnapshot(
                health: .healthy,
                companies: companies,
                dispatchQueue: queue,
                pendingDecisions: decisions,
                sessions: sessions,
                fetchedAt: Date()
            )
        } catch {
            return KernelSnapshot(health: .unreachable, fetchedAt: Date())
        }
    }
}
