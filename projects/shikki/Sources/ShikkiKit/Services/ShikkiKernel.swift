import Foundation
import Logging

// MARK: - ServiceEntry

/// Internal bookkeeping for a managed service.
struct ServiceEntry: Sendable {
    let service: any ManagedService
    var nextDue: Date
    var restartCount: Int = 0
    var lastFailure: Date?
}

// MARK: - ShikkiKernel

/// Root actor managing all Shikki services with adaptive timing and timer coalescing.
/// Like launchd is to macOS — it launches everything, monitors health, restarts on failure.
///
/// The kernel:
/// 1. Computes when the next service is due
/// 2. Sleeps until that time (tickless when idle)
/// 3. Collects all services due within the coalescing window
/// 4. Batch-fetches a single KernelSnapshot
/// 5. Fans out to services ordered by QoS
/// 6. Handles failures per RestartPolicy
public actor ShikkiKernel {
    private var entries: [ServiceID: ServiceEntry] = [:]
    private let snapshotProvider: KernelSnapshotProvider
    private let logger: Logger
    private var isRunning = false

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

        let now = Date()
        for service in services {
            entries[service.id] = ServiceEntry(
                service: service,
                nextDue: now
            )
        }
    }

    // MARK: - Public API

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

            // Sleep until next service is due
            if sleepDuration > .zero {
                do {
                    try await Task.sleep(for: sleepDuration)
                } catch {
                    break // Cancelled
                }
            }

            let now = Date()
            let dueServices = collectDueServices(at: now)

            guard !dueServices.isEmpty else { continue }

            // Batch-fetch snapshot once for all services in this tick
            let snapshot = await snapshotProvider.fetchSnapshot()

            // Fan out: higher QoS first
            let sorted = dueServices.sorted { $0.qos < $1.qos }

            for service in sorted {
                guard service.canRun(health: snapshot.health) else {
                    logger.debug("Service \(service.id) skipped (health: \(snapshot.health))")
                    continue
                }

                do {
                    try await service.tick(snapshot: snapshot)
                    // Reset restart count on success
                    entries[service.id]?.restartCount = 0
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
        logger.info("ShikkiKernel shutdown requested")
    }

    /// All registered service IDs.
    public var serviceIDs: [ServiceID] {
        Array(entries.keys)
    }

    /// Next due date for a given service.
    public func nextDue(for serviceId: ServiceID) -> Date? {
        entries[serviceId]?.nextDue
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
        entry.lastFailure = Date()

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
