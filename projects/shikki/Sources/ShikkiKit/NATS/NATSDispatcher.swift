import Foundation
import Logging

// MARK: - NATSDispatcherError

/// Errors from the NATS dispatch subsystem.
public enum NATSDispatcherError: Error, Sendable, Equatable {
    case notConnected
    case encodingFailed
    case taskTimeout(taskId: String)
    case resultDecodingFailed(taskId: String)
}

// MARK: - NATSDispatcher

/// Publishes dispatch tasks to NATS subjects and collects results.
///
/// The dispatcher is the orchestrator-side component:
/// 1. Encodes a `DispatchTask` as JSON
/// 2. Publishes to `shikki.dispatch.{nodeId}` (targeted) or `shikki.dispatch.available` (any node)
/// 3. Subscribes to `shikki.dispatch.progress.{taskId}` for incremental updates
/// 4. Subscribes to `shikki.dispatch.result.{taskId}` for the final result
///
/// All encoding uses ISO8601 dates for cross-node compatibility.
public actor NATSDispatcher {
    private let nats: any NATSClientProtocol
    private let logger: Logger
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Dispatched task IDs and their collected results.
    public private(set) var dispatchedTasks: [String: NATSDispatchResult?] = [:]

    /// Progress events collected per task ID.
    public private(set) var progressEvents: [String: [DispatchProgress]] = [:]

    /// Count of tasks dispatched (for diagnostics).
    public var dispatchCount: Int { dispatchedTasks.count }

    public init(
        nats: any NATSClientProtocol,
        logger: Logger = Logger(label: "shikki.nats-dispatcher")
    ) {
        self.nats = nats
        self.logger = logger
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Dispatch

    /// Dispatch a task to NATS for execution.
    ///
    /// Publishes the task to either:
    /// - `shikki.dispatch.{nodeId}` if `task.targetNode` is set
    /// - `shikki.dispatch.available` if no target is specified
    ///
    /// Does NOT wait for the result. Use `collectResult(for:timeout:)` to wait.
    public func dispatch(task: DispatchTask) async throws {
        guard await nats.isConnected else {
            throw NATSDispatcherError.notConnected
        }

        let data: Data
        do {
            data = try encoder.encode(task)
        } catch {
            throw NATSDispatcherError.encodingFailed
        }

        let subject: String
        if let targetNode = task.targetNode {
            subject = NATSDispatchSubjects.targeted(nodeId: targetNode)
        } else {
            subject = NATSDispatchSubjects.available
        }

        try await nats.publish(subject: subject, data: data)
        dispatchedTasks[task.id] = .some(nil)

        logger.info("Dispatched task \(task.id) to \(subject)")
    }

    // MARK: - Progress Listening

    /// Start listening for progress events for a specific task.
    ///
    /// Subscribes to `shikki.dispatch.progress.{taskId}` and collects
    /// progress updates into `progressEvents[taskId]`.
    /// Returns an AsyncStream that yields each progress event as it arrives.
    public func listenForProgress(taskId: String) -> AsyncStream<DispatchProgress> {
        let subject = NATSDispatchSubjects.progress(taskId: taskId)
        let stream = nats.subscribe(subject: subject)
        let decoder = self.decoder

        progressEvents[taskId] = []

        return AsyncStream { continuation in
            let task = Task { [weak self] in
                for await message in stream {
                    if Task.isCancelled { break }
                    guard let progress = try? decoder.decode(DispatchProgress.self, from: message.data) else {
                        continue
                    }
                    await self?.appendProgress(progress, for: taskId)
                    continuation.yield(progress)
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    /// Append a progress event to the internal collection.
    private func appendProgress(_ progress: DispatchProgress, for taskId: String) {
        progressEvents[taskId, default: []].append(progress)
    }

    // MARK: - Result Collection

    /// Wait for a result on `shikki.dispatch.result.{taskId}`.
    ///
    /// Subscribes to the result subject and waits for the first message
    /// within the timeout. If no result arrives, returns a timeout result.
    public func collectResult(
        for taskId: String,
        timeout: Duration = .seconds(300)
    ) async -> NATSDispatchResult {
        let subject = NATSDispatchSubjects.result(taskId: taskId)
        let stream = nats.subscribe(subject: subject)
        let decoder = self.decoder

        let result: NATSDispatchResult = await withTaskGroup(of: NATSDispatchResult.self) { group in
            // Race: result message vs timeout
            group.addTask {
                for await message in stream {
                    if Task.isCancelled { break }
                    if let result = try? decoder.decode(NATSDispatchResult.self, from: message.data) {
                        return result
                    }
                }
                // Stream ended without result
                return NATSDispatchResult(
                    taskId: taskId,
                    nodeId: "unknown",
                    status: .timeout,
                    output: "Result stream ended without result",
                    durationSeconds: 0
                )
            }

            group.addTask {
                try? await Task.sleep(for: timeout)
                return NATSDispatchResult(
                    taskId: taskId,
                    nodeId: "unknown",
                    status: .timeout,
                    output: "Task timed out after \(timeout)",
                    durationSeconds: Double(timeout.components.seconds)
                )
            }

            let first = await group.next()!
            group.cancelAll()
            return first
        }

        dispatchedTasks[taskId] = result
        return result
    }

    // MARK: - Queries

    /// Get the result for a previously dispatched task (if available).
    public func result(for taskId: String) -> NATSDispatchResult? {
        dispatchedTasks[taskId] ?? nil
    }

    /// Get all collected progress events for a task.
    public func progress(for taskId: String) -> [DispatchProgress] {
        progressEvents[taskId] ?? []
    }
}
