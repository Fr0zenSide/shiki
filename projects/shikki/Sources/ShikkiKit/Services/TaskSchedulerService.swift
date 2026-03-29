import Foundation

// MARK: - TaskSchedulerService

/// Evaluates scheduled tasks, claims ready ones, dispatches them, and handles failures.
/// Standalone service with its own tick() method (Wave 1 ManagedService not yet merged).
///
/// Responsibilities:
/// - Find tasks whose nextRunAt <= now and are enabled
/// - Atomic claim: only claim if claimedBy IS NULL (BR-19)
/// - After execution: update lastRunAt, compute nextRunAt, clear claim
/// - Failed execution: increment retryCount, disable if >= maxRetries (BR-24)
/// - Stuck claim detection: claimed > 2x estimatedDuration → clear (BR-20)
public actor TaskSchedulerService {

    private var tasks: [UUID: ScheduledTask]
    private let nodeId: String
    private let cronParser: CronParser

    /// Weak reference to the kernel for wake-on-create signaling.
    private weak var _kernel: ShikkiKernel?

    public init(
        initialTasks: [ScheduledTask] = [],
        nodeId: String = ProcessInfo.processInfo.hostName
    ) {
        var taskMap: [UUID: ScheduledTask] = [:]
        for task in initialTasks {
            taskMap[task.id] = task
        }
        self.tasks = taskMap
        self.nodeId = nodeId
        self.cronParser = CronParser()
    }

    /// Link this service to its managing kernel for wake signaling.
    /// Called once during kernel boot, after both are initialized.
    public func setKernel(_ kernel: ShikkiKernel) {
        self._kernel = kernel
    }

    // MARK: - Task Management

    /// Add a new task to the scheduler.
    /// Wakes the kernel so it picks up the new task immediately
    /// instead of waiting for the next scheduled tick.
    public func addTask(_ task: ScheduledTask) async {
        tasks[task.id] = task
        await _kernel?.wake(.taskCreated(task.name))
    }

    /// Remove a task. Built-in tasks cannot be removed (BR-37), only disabled.
    /// Returns true if the task was disabled (builtin) or removed.
    @discardableResult
    public func removeTask(id: UUID) -> Bool {
        guard var task = tasks[id] else { return false }
        if task.isBuiltin {
            // BR-37: Cannot delete builtin tasks, only disable
            task.enabled = false
            tasks[id] = task
            return true
        }
        tasks.removeValue(forKey: id)
        return true
    }

    /// Get all tasks.
    public func allTasks() -> [ScheduledTask] {
        Array(tasks.values).sorted { $0.name < $1.name }
    }

    /// Get a task by ID.
    public func task(for id: UUID) -> ScheduledTask? {
        tasks[id]
    }

    /// Update a task in-place.
    public func updateTask(_ task: ScheduledTask) {
        tasks[task.id] = task
    }

    // MARK: - Tick (main evaluation loop)

    /// Evaluate all tasks and dispatch ready ones.
    /// Returns the tasks that were dispatched this tick.
    public func tick(now: Date = .now) -> [ScheduledTask] {
        // First: clear stuck claims (BR-20)
        clearStuckClaims(now: now)

        // Find ready tasks
        let ready = findReadyTasks(now: now)

        // Claim and prepare for dispatch
        var dispatched: [ScheduledTask] = []
        for task in ready {
            if claim(taskId: task.id, now: now) {
                dispatched.append(tasks[task.id]!)
            }
        }

        return dispatched
    }

    /// Mark a task execution as completed successfully.
    public func markCompleted(taskId: UUID, durationMs: Int, now: Date = .now) {
        guard var task = tasks[taskId] else { return }

        // Update avg duration (BR-21)
        task.updateAvgDuration(actual: durationMs)

        // Update timestamps
        task.lastRunAt = now

        // Compute next run
        task.nextRunAt = task.computeNextRun(after: now)

        // Clear claim
        task.claimedBy = nil
        task.claimedAt = nil

        // Reset retry count on success
        task.retryCount = 0

        tasks[taskId] = task
    }

    /// Mark a task execution as failed (BR-24).
    public func markFailed(taskId: UUID, now: Date = .now) {
        guard var task = tasks[taskId] else { return }

        task.retryCount += 1

        // BR-24: Disable after maxRetries consecutive failures
        if task.retryCount >= task.maxRetries {
            task.enabled = false
        }

        // Clear claim
        task.claimedBy = nil
        task.claimedAt = nil

        // Still compute next run (if not disabled)
        task.lastRunAt = now
        task.nextRunAt = task.computeNextRun(after: now)

        tasks[taskId] = task
    }

    // MARK: - Internal

    /// Find tasks that are ready to fire (enabled, not claimed, nextRunAt <= now).
    func findReadyTasks(now: Date) -> [ScheduledTask] {
        tasks.values.filter { task in
            task.enabled
                && task.claimedBy == nil
                && (task.nextRunAt ?? .distantPast) <= now
        }
    }

    /// Atomic claim: set claimedBy if still NULL (BR-19).
    /// Returns true if this node claimed it.
    func claim(taskId: UUID, now: Date) -> Bool {
        guard var task = tasks[taskId], task.claimedBy == nil else {
            return false
        }
        task.claimedBy = nodeId
        task.claimedAt = now
        tasks[taskId] = task
        return true
    }

    /// Clear stuck claims: claimed for > 2x estimatedDuration (BR-20).
    func clearStuckClaims(now: Date) {
        for (id, task) in tasks {
            guard let claimedAt = task.claimedAt, task.claimedBy != nil else { continue }
            let maxClaimDuration = TimeInterval(task.estimatedDurationMs * 2) / 1000.0
            if now.timeIntervalSince(claimedAt) > maxClaimDuration {
                var updated = task
                updated.claimedBy = nil
                updated.claimedAt = nil
                tasks[id] = updated
            }
        }
    }

    /// Seed built-in tasks if they don't exist yet (BR-36).
    public func seedBuiltinTasks(now: Date = .now) {
        for builtinTask in ScheduledTask.builtinTasks {
            if tasks[builtinTask.id] == nil {
                var task = builtinTask
                task.nextRunAt = task.computeNextRun(after: now)
                tasks[task.id] = task
            }
        }
    }
}
