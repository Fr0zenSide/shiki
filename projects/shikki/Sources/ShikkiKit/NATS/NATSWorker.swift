import Foundation
import Logging

// MARK: - TaskExecutor

/// Protocol for executing dispatch tasks.
/// Abstracts the agent execution layer so NATSWorker is testable
/// without spawning real processes.
public protocol TaskExecutor: Sendable {
    /// Execute a task and return the output string.
    /// Calls `onProgress` for incremental updates during execution.
    func execute(
        task: DispatchTask,
        onProgress: @Sendable (Int, String) async -> Void
    ) async throws -> String
}

// MARK: - TaskExecutorError

public enum TaskExecutorError: Error, Sendable {
    case executionFailed(String)
    case timeout
}

// MARK: - MockTaskExecutor

/// Test double for TaskExecutor.
/// Returns a configurable output and optional progress steps.
public actor MockTaskExecutor: TaskExecutor {
    public var output: String = "mock output"
    public var progressSteps: [(Int, String)] = []
    public var shouldThrow: Bool = false
    public var executedTasks: [DispatchTask] = []

    public init() {}

    public func setOutput(_ output: String) {
        self.output = output
    }

    public func setProgressSteps(_ steps: [(Int, String)]) {
        self.progressSteps = steps
    }

    public func setThrows(_ shouldThrow: Bool) {
        self.shouldThrow = shouldThrow
    }

    public nonisolated func execute(
        task: DispatchTask,
        onProgress: @Sendable (Int, String) async -> Void
    ) async throws -> String {
        let currentOutput = await self.output
        let steps = await self.progressSteps
        let shouldFail = await self.shouldThrow

        await appendTask(task)

        if shouldFail {
            throw TaskExecutorError.executionFailed("mock failure")
        }

        for (step, message) in steps {
            await onProgress(step, message)
        }

        return currentOutput
    }

    private func appendTask(_ task: DispatchTask) {
        executedTasks.append(task)
    }
}

// MARK: - NATSWorker

/// Worker node that subscribes to NATS dispatch subjects, executes tasks,
/// and publishes progress and results back.
///
/// A worker subscribes to two subjects:
/// - `shikki.dispatch.available` for tasks any node can pick up
/// - `shikki.dispatch.{ownNodeId}` for tasks targeted at this specific node
///
/// On receiving a task, the worker:
/// 1. Publishes progress events to `shikki.dispatch.progress.{taskId}`
/// 2. Executes via the injected `TaskExecutor`
/// 3. Publishes the result to `shikki.dispatch.result.{taskId}`
public actor NATSWorker {
    private let nats: any NATSClientProtocol
    private let nodeId: String
    private let executor: TaskExecutor
    private let logger: Logger
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var listenTask: Task<Void, Never>?

    /// Tasks currently being executed.
    public private(set) var activeTasks: Set<String> = []

    /// Tasks completed by this worker.
    public private(set) var completedTaskIds: [String] = []

    /// Count of tasks processed.
    public var processedCount: Int { completedTaskIds.count }

    public init(
        nats: any NATSClientProtocol,
        nodeId: String,
        executor: TaskExecutor,
        logger: Logger = Logger(label: "shikki.nats-worker")
    ) {
        self.nats = nats
        self.nodeId = nodeId
        self.executor = executor
        self.logger = logger
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Start / Stop

    /// Start listening for dispatch tasks on both the available and targeted subjects.
    public func start() {
        let availableStream = nats.subscribe(subject: NATSDispatchSubjects.available)
        let targetedStream = nats.subscribe(subject: NATSDispatchSubjects.targeted(nodeId: nodeId))

        listenTask = Task {
            await self.listenLoop(available: availableStream, targeted: targetedStream)
        }

        logger.info("NATSWorker \(nodeId) started listening")
    }

    /// Internal listen loop that consumes both streams sequentially via merge.
    private func listenLoop(
        available: AsyncStream<NATSMessage>,
        targeted: AsyncStream<NATSMessage>
    ) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [self] in
                for await message in available {
                    if Task.isCancelled { break }
                    await self.handleMessage(message)
                }
            }
            group.addTask { [self] in
                for await message in targeted {
                    if Task.isCancelled { break }
                    await self.handleMessage(message)
                }
            }
        }
    }

    /// Stop listening for tasks. In-flight tasks are allowed to complete.
    public func stop() {
        listenTask?.cancel()
        listenTask = nil
        logger.info("NATSWorker \(nodeId) stopped")
    }

    /// Whether the worker is currently listening.
    public var isRunning: Bool {
        listenTask != nil && !(listenTask?.isCancelled ?? true)
    }

    // MARK: - Message Handling

    private func handleMessage(_ message: NATSMessage) async {
        guard let task = try? decoder.decode(DispatchTask.self, from: message.data) else {
            logger.warning("Failed to decode dispatch task from \(message.subject)")
            return
        }

        // If the task is targeted at a different node, ignore it.
        // This guards against wildcard subscription overlap.
        if let target = task.targetNode, target != nodeId {
            return
        }

        await executeTask(task)
    }

    private func executeTask(_ task: DispatchTask) async {
        activeTasks.insert(task.id)
        let startTime = Date()

        logger.info("Worker \(nodeId) executing task \(task.id)")

        let result: NATSDispatchResult
        do {
            let output = try await executor.execute(task: task) { [weak self] step, message in
                await self?.publishProgress(
                    taskId: task.id,
                    step: step,
                    message: message
                )
            }

            let duration = Date().timeIntervalSince(startTime)
            result = NATSDispatchResult(
                taskId: task.id,
                nodeId: nodeId,
                status: .completed,
                output: output,
                durationSeconds: duration
            )
        } catch is CancellationError {
            let duration = Date().timeIntervalSince(startTime)
            result = NATSDispatchResult(
                taskId: task.id,
                nodeId: nodeId,
                status: .timeout,
                output: "Task cancelled",
                durationSeconds: duration
            )
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            result = NATSDispatchResult(
                taskId: task.id,
                nodeId: nodeId,
                status: .failed,
                output: String(describing: error),
                durationSeconds: duration
            )
        }

        await publishResult(result)
        activeTasks.remove(task.id)
        completedTaskIds.append(task.id)
    }

    // MARK: - Publishing

    private func publishProgress(taskId: String, step: Int, message: String) async {
        let progress = DispatchProgress(
            taskId: taskId,
            nodeId: nodeId,
            step: step,
            message: message
        )

        do {
            let data = try encoder.encode(progress)
            let subject = NATSDispatchSubjects.progress(taskId: taskId)
            try await nats.publish(subject: subject, data: data)
        } catch {
            logger.warning("Failed to publish progress for task \(taskId): \(error)")
        }
    }

    private func publishResult(_ result: NATSDispatchResult) async {
        do {
            let data = try encoder.encode(result)
            let subject = NATSDispatchSubjects.result(taskId: result.taskId)
            try await nats.publish(subject: subject, data: data)
            logger.info("Published result for task \(result.taskId): \(result.status)")
        } catch {
            logger.warning("Failed to publish result for task \(result.taskId): \(error)")
        }
    }
}
