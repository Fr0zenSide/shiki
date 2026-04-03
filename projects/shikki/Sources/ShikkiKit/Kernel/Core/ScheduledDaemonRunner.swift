import Foundation
import Logging

// MARK: - ScheduledDaemonError

/// Errors specific to the scheduled (secondary) daemon runner.
public enum ScheduledDaemonError: Error, CustomStringConvertible {
    case primaryNotRunning
    case primaryPIDDead(pid: Int32)

    public var description: String {
        switch self {
        case .primaryNotRunning:
            "Primary daemon not running — no PID file found"
        case .primaryPIDDead(let pid):
            "Primary daemon PID \(pid) is dead"
        }
    }
}

// MARK: - TickResult

/// Result of a single scheduled tick cycle.
public struct TickResult: Sendable {
    public let servicesExecuted: Int
    public let duration: TimeInterval
    public let errors: [String]

    public init(servicesExecuted: Int, duration: TimeInterval, errors: [String]) {
        self.servicesExecuted = servicesExecuted
        self.duration = duration
        self.errors = errors
    }
}

// MARK: - ScheduledDaemonRunner

/// Runs a single tick cycle then exits. Designed for launchd/systemd interval scheduling.
///
/// Unlike ``ShikkiKernel`` which runs an infinite loop, this actor:
/// 1. Verifies the primary daemon is running (via PID file)
/// 2. Fetches a ``KernelSnapshot`` from the snapshot provider
/// 3. Ticks all registered services once (ordered by QoS)
/// 4. Collects results/errors
/// 5. Returns a ``TickResult``
///
/// Total runtime should be < 5 seconds. Intended to run every 30s via launchd/systemd.
public actor ScheduledDaemonRunner {
    private let services: [any ManagedService]
    private let snapshotProvider: KernelSnapshotProvider
    private let pidManager: DaemonPIDManager
    private let logger: Logger

    public init(
        services: [any ManagedService],
        snapshotProvider: KernelSnapshotProvider,
        pidManager: DaemonPIDManager = DaemonPIDManager(),
        logger: Logger = Logger(label: "shikki.scheduled-daemon")
    ) {
        self.services = services
        self.snapshotProvider = snapshotProvider
        self.pidManager = pidManager
        self.logger = logger
    }

    /// Run a single tick: verify primary → fetch snapshot → tick all due services → return.
    /// Total runtime should be < 5 seconds.
    public func runOnce() async throws -> TickResult {
        let start = ContinuousClock.now

        // Step 1: Verify primary daemon is running
        try verifyPrimaryDaemon()

        // Step 2: Fetch snapshot
        let snapshot = await snapshotProvider.fetchSnapshot()

        // Step 3: Tick all services ordered by QoS (higher QoS first)
        let sorted = services.sorted { $0.qos < $1.qos }
        var executed = 0
        var errors: [String] = []

        for service in sorted {
            guard service.canRun(health: snapshot.health) else {
                logger.debug("Service \(service.id) skipped (health: \(snapshot.health))")
                continue
            }

            do {
                try await service.tick(snapshot: snapshot)
                executed += 1
                logger.info("Service \(service.id) ticked successfully")
            } catch {
                let message = "Service \(service.id) failed: \(error)"
                errors.append(message)
                logger.error("\(message)")
                // Continue ticking other services — don't let one failure stop the rest
            }
        }

        let elapsed = ContinuousClock.now - start
        let duration = elapsed.totalSeconds

        logger.info(
            "Scheduled tick complete: \(executed) services, \(errors.count) errors, \(String(format: "%.3f", duration))s"
        )

        return TickResult(
            servicesExecuted: executed,
            duration: duration,
            errors: errors
        )
    }

    // MARK: - Private

    /// Verify the primary daemon is alive via its PID file.
    private func verifyPrimaryDaemon() throws {
        guard let pid = pidManager.readPID() else {
            throw ScheduledDaemonError.primaryNotRunning
        }

        guard pidManager.isRunning() else {
            throw ScheduledDaemonError.primaryPIDDead(pid: pid)
        }
    }
}

// MARK: - Default Scheduled Services

extension ScheduledDaemonRunner {
    /// The default service set for scheduled mode: lightweight, read-only checks only.
    /// - ``ScheduledTaskService``: checks task queue, marks overdue tasks
    /// - ``StaleCompanyDetectorService``: checks for idle companies with pending work
    public static func defaultServices(
        client: any BackendClientProtocol
    ) -> [any ManagedService] {
        [
            ScheduledTaskService(),
            StaleCompanyDetectorService(client: client),
        ]
    }
}
