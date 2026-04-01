import Testing
import Foundation
@testable import ShikkiKit

@Suite("TaskSchedulerService")
struct TaskSchedulerTests {

    let nodeId = "test-node-1"

    // MARK: - Task Creation

    @Test func scheduledTask_creation() {
        let task = ScheduledTask(
            name: "test-task",
            cronExpression: "0 5 * * *",
            command: "echo hello"
        )
        #expect(task.name == "test-task")
        #expect(task.cronExpression == "0 5 * * *")
        #expect(task.command == "echo hello")
        #expect(task.enabled == true)
        #expect(task.retryCount == 0)
        #expect(task.maxRetries == 3)
        #expect(task.isBuiltin == false)
        #expect(task.speculative == false)
        #expect(task.claimedBy == nil)
    }

    @Test func computeNextRun() {
        let task = ScheduledTask(
            name: "daily-5am",
            cronExpression: "0 5 * * *",
            command: "scan"
        )
        let next = task.computeNextRun(after: Date.now)
        #expect(next != nil)
    }

    // MARK: - Evaluator

    @Test func evaluator_finds_ready_tasks() async {
        let pastDate = Date.now.addingTimeInterval(-3600)
        let task = ScheduledTask(
            name: "ready-task",
            cronExpression: "0 5 * * *",
            command: "run",
            nextRunAt: pastDate
        )

        let service = TaskSchedulerService(initialTasks: [task], nodeId: nodeId)
        let dispatched = await service.tick(now: .now)
        #expect(dispatched.count == 1)
        #expect(dispatched.first?.name == "ready-task")
    }

    @Test func evaluator_skips_future_tasks() async {
        let futureDate = Date.now.addingTimeInterval(3600)
        let task = ScheduledTask(
            name: "future-task",
            cronExpression: "0 5 * * *",
            command: "run",
            nextRunAt: futureDate
        )

        let service = TaskSchedulerService(initialTasks: [task], nodeId: nodeId)
        let dispatched = await service.tick(now: .now)
        #expect(dispatched.isEmpty)
    }

    @Test func evaluator_skips_disabled_tasks() async {
        let pastDate = Date.now.addingTimeInterval(-3600)
        let task = ScheduledTask(
            name: "disabled-task",
            cronExpression: "0 5 * * *",
            command: "run",
            enabled: false,
            nextRunAt: pastDate
        )

        let service = TaskSchedulerService(initialTasks: [task], nodeId: nodeId)
        let dispatched = await service.tick(now: .now)
        #expect(dispatched.isEmpty)
    }

    // MARK: - Atomic Claim (BR-19)

    @Test func atomicClaim_prevents_double_dispatch() async {
        let pastDate = Date.now.addingTimeInterval(-3600)
        let task = ScheduledTask(
            name: "claim-test",
            cronExpression: "0 5 * * *",
            command: "run",
            nextRunAt: pastDate,
            claimedBy: "other-node",
            claimedAt: Date.now
        )

        let service = TaskSchedulerService(initialTasks: [task], nodeId: nodeId)
        let dispatched = await service.tick(now: .now)
        // Already claimed by another node → should not dispatch
        #expect(dispatched.isEmpty)
    }

    // MARK: - Execution Results

    @Test func execution_clears_claim_updates_nextRun() async {
        let pastDate = Date.now.addingTimeInterval(-3600)
        let task = ScheduledTask(
            name: "completed-task",
            cronExpression: "0 5 * * *",
            command: "run",
            nextRunAt: pastDate
        )

        let service = TaskSchedulerService(initialTasks: [task], nodeId: nodeId)
        let dispatched = await service.tick(now: .now)
        #expect(dispatched.count == 1)

        let taskId = dispatched[0].id
        await service.markCompleted(taskId: taskId, durationMs: 5000)

        let updated = await service.task(for: taskId)
        #expect(updated?.claimedBy == nil)
        #expect(updated?.claimedAt == nil)
        #expect(updated?.lastRunAt != nil)
        #expect(updated?.nextRunAt != nil)
        #expect(updated?.retryCount == 0)
    }

    @Test func failedExecution_increments_retryCount() async {
        let pastDate = Date.now.addingTimeInterval(-3600)
        let task = ScheduledTask(
            name: "fail-task",
            cronExpression: "0 5 * * *",
            command: "run",
            nextRunAt: pastDate,
            maxRetries: 3
        )

        let service = TaskSchedulerService(initialTasks: [task], nodeId: nodeId)
        let dispatched = await service.tick(now: .now)
        let taskId = dispatched[0].id

        await service.markFailed(taskId: taskId)

        let updated = await service.task(for: taskId)
        #expect(updated?.retryCount == 1)
        #expect(updated?.enabled == true)
        #expect(updated?.claimedBy == nil)
    }

    @Test func maxRetries_disables_task() async {
        let pastDate = Date.now.addingTimeInterval(-3600)
        var task = ScheduledTask(
            name: "disable-task",
            cronExpression: "0 5 * * *",
            command: "run",
            nextRunAt: pastDate,
            retryCount: 2,
            maxRetries: 3
        )

        let service = TaskSchedulerService(initialTasks: [task], nodeId: nodeId)

        // First tick: claim and dispatch
        _ = await service.tick(now: .now)

        // Mark failed → retryCount goes to 3, which >= maxRetries
        await service.markFailed(taskId: task.id)

        let updated = await service.task(for: task.id)
        #expect(updated?.retryCount == 3)
        #expect(updated?.enabled == false)
    }

    // MARK: - Stuck Claims (BR-20)

    @Test func stuckClaim_expires() async {
        // Task claimed 10 minutes ago, estimated duration is 60s → 2x = 120s, well past
        let claimedAt = Date.now.addingTimeInterval(-600)
        let task = ScheduledTask(
            name: "stuck-task",
            cronExpression: "0 5 * * *",
            command: "run",
            estimatedDurationMs: 60_000,
            nextRunAt: Date.now.addingTimeInterval(-3600),
            claimedBy: "dead-node",
            claimedAt: claimedAt
        )

        let service = TaskSchedulerService(initialTasks: [task], nodeId: nodeId)

        // Tick should clear the stuck claim and then dispatch
        let dispatched = await service.tick(now: .now)
        #expect(dispatched.count == 1)
        #expect(dispatched.first?.claimedBy == nodeId)
    }

    // MARK: - Built-in Tasks (BR-36, BR-37)

    @Test func builtinTasks_seeded() async {
        let service = TaskSchedulerService(nodeId: nodeId)
        await service.seedBuiltinTasks()

        let tasks = await service.allTasks()
        let names = tasks.map(\.name)
        #expect(names.contains("corroboration-sweep"))
        #expect(names.contains("radar-scan"))

        let corroboration = tasks.first { $0.name == "corroboration-sweep" }
        #expect(corroboration?.isBuiltin == true)
        #expect(corroboration?.cronExpression == "0 3 * * *")
        #expect(corroboration?.nextRunAt != nil)
    }

    @Test func addTask_wakes_kernel() async {
        let service = TaskSchedulerService(nodeId: nodeId)

        // Create a kernel with this service
        let kernel = ShikkiKernel(
            services: [],
            snapshotProvider: MockSnapshotProvider()
        )
        await service.setKernel(kernel)

        let newTask = ScheduledTask(
            name: "urgent-task",
            cronExpression: "0 * * * *",
            command: "urgent-run"
        )

        // addTask is now async and wakes the kernel
        await service.addTask(newTask)

        let retrieved = await service.task(for: newTask.id)
        #expect(retrieved?.name == "urgent-task")
    }

    @Test func builtinTasks_cannot_be_deleted() async {
        let service = TaskSchedulerService(nodeId: nodeId)
        await service.seedBuiltinTasks()

        let tasks = await service.allTasks()
        let corroboration = tasks.first { $0.name == "corroboration-sweep" }!

        // Attempt to remove → should disable, not delete
        let result = await service.removeTask(id: corroboration.id)
        #expect(result == true)

        // Task still exists but is disabled
        let updated = await service.task(for: corroboration.id)
        #expect(updated != nil)
        #expect(updated?.enabled == false)
        #expect(updated?.isBuiltin == true)
    }
}
