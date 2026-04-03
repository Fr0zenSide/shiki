import Foundation
import Logging

// MARK: - ScheduledTaskService

/// Checks the task queue and marks overdue tasks.
///
/// Lightweight ``ManagedService`` designed for scheduled (secondary) daemon mode.
/// Unlike ``TaskSchedulerService`` which does full claim/dispatch, this only
/// scans the dispatch queue for overdue tasks and logs warnings.
public actor ScheduledTaskService: ManagedService {
    public nonisolated let id: ServiceID = .taskScheduler
    public nonisolated let qos: ServiceQoS = .default
    public nonisolated let interval: Duration = .seconds(30)
    public nonisolated let restartPolicy: RestartPolicy = .once

    private let logger: Logger

    /// Number of overdue tasks found in the last tick (for testing/observability).
    private(set) var lastOverdueCount: Int = 0

    /// Total ticks performed.
    private(set) var tickCount: Int = 0

    public init(logger: Logger = Logger(label: "shikki.scheduled-tasks")) {
        self.logger = logger
    }

    public func tick(snapshot: KernelSnapshot) async throws {
        tickCount += 1

        guard snapshot.health == .healthy else {
            logger.debug("Skipping task check — backend not healthy")
            return
        }

        // Count pending tasks that have no active session — these are potentially stalled
        let runningSlugs = Set(snapshot.sessions.filter(\.isRunning).map(\.companySlug))
        var overdueCount = 0

        for task in snapshot.dispatchQueue {
            guard task.status == "pending" else { continue }
            // A pending task whose company has no running session is overdue
            if !runningSlugs.contains(task.companySlug) {
                overdueCount += 1
                logger.warning("Overdue task: \(task.companySlug)/\(task.title) — no active session")
            }
        }

        lastOverdueCount = overdueCount

        if overdueCount > 0 {
            logger.info("Found \(overdueCount) overdue task(s)")
        }
    }
}
