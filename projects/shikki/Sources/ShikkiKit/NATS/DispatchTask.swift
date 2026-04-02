import Foundation

// MARK: - DispatchPriority

/// Priority level for dispatch tasks.
/// Higher priority tasks are picked up first by available workers.
public enum DispatchPriority: Int, Codable, Sendable, Comparable {
    case low = 0
    case normal = 1
    case high = 2
    case critical = 3

    public static func < (lhs: DispatchPriority, rhs: DispatchPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - DispatchTask

/// A task published to NATS for distributed execution.
///
/// The orchestrator creates a `DispatchTask` and publishes it to either:
/// - `shikki.dispatch.{nodeId}` for targeted dispatch to a specific node
/// - `shikki.dispatch.available` for any available worker to pick up
///
/// The task payload includes an optional Moto context (scoped code slice)
/// so the executing agent has architecture awareness without re-indexing.
public struct DispatchTask: Codable, Sendable, Identifiable {
    /// Unique task identifier.
    public let id: String

    /// The prompt or instruction for the agent to execute.
    public let prompt: String

    /// Target node ID. If nil, task is published to `shikki.dispatch.available`.
    public let targetNode: String?

    /// Optional scoped code context from the Moto cache.
    /// Serialized as JSON string to keep the task payload flat.
    public let motoContext: MotoDispatchContext?

    /// Task priority. Workers process higher-priority tasks first.
    public let priority: DispatchPriority

    /// Maximum execution time before the task is considered timed out.
    public let timeoutSeconds: Int

    /// Company slug this task belongs to.
    public let companySlug: String

    /// Timestamp when the task was created.
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString,
        prompt: String,
        targetNode: String? = nil,
        motoContext: MotoDispatchContext? = nil,
        priority: DispatchPriority = .normal,
        timeoutSeconds: Int = 300,
        companySlug: String = "global",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.prompt = prompt
        self.targetNode = targetNode
        self.motoContext = motoContext
        self.priority = priority
        self.timeoutSeconds = timeoutSeconds
        self.companySlug = companySlug
        self.createdAt = createdAt
    }
}

// MARK: - MotoDispatchContext

/// Scoped code context attached to a dispatch task.
/// Lightweight subset of MotoContextResponse — only what the agent needs.
public struct MotoDispatchContext: Codable, Sendable {
    /// Project identifier from the Moto cache.
    public let projectId: String

    /// Relevant protocol names for this task.
    public let protocols: [String]

    /// Relevant type names for this task.
    public let types: [String]

    /// Dependency edges relevant to this task (type -> [dependencies]).
    public let dependencies: [String: [String]]

    /// File paths the agent should focus on.
    public let focusFiles: [String]

    public init(
        projectId: String,
        protocols: [String] = [],
        types: [String] = [],
        dependencies: [String: [String]] = [:],
        focusFiles: [String] = []
    ) {
        self.projectId = projectId
        self.protocols = protocols
        self.types = types
        self.dependencies = dependencies
        self.focusFiles = focusFiles
    }
}

// MARK: - DispatchStatus

/// Status of a completed dispatch task.
public enum DispatchStatus: String, Codable, Sendable {
    case completed
    case failed
    case timeout
}

// MARK: - NATSDispatchResult

/// Result published by a worker after executing a dispatch task.
///
/// Published to `shikki.dispatch.result.{taskId}` so the orchestrator
/// can correlate results with the original task.
public struct NATSDispatchResult: Codable, Sendable {
    /// ID of the task this result belongs to.
    public let taskId: String

    /// ID of the node that executed the task.
    public let nodeId: String

    /// Execution outcome.
    public let status: DispatchStatus

    /// Output from the agent (stdout, structured response, etc.).
    public let output: String

    /// Wall-clock execution duration in seconds.
    public let durationSeconds: Double

    /// Timestamp when execution completed.
    public let completedAt: Date

    public init(
        taskId: String,
        nodeId: String,
        status: DispatchStatus,
        output: String,
        durationSeconds: Double,
        completedAt: Date = Date()
    ) {
        self.taskId = taskId
        self.nodeId = nodeId
        self.status = status
        self.output = output
        self.durationSeconds = durationSeconds
        self.completedAt = completedAt
    }
}

// MARK: - DispatchProgress

/// Progress update streamed by a worker during task execution.
///
/// Published to `shikki.dispatch.progress.{taskId}` so the orchestrator
/// can track incremental progress without waiting for the final result.
public struct DispatchProgress: Codable, Sendable {
    /// ID of the task this progress belongs to.
    public let taskId: String

    /// ID of the node executing the task.
    public let nodeId: String

    /// Step number (monotonically increasing within a task).
    public let step: Int

    /// Human-readable progress message.
    public let message: String

    /// Timestamp of this progress update.
    public let timestamp: Date

    public init(
        taskId: String,
        nodeId: String,
        step: Int,
        message: String,
        timestamp: Date = Date()
    ) {
        self.taskId = taskId
        self.nodeId = nodeId
        self.step = step
        self.message = message
        self.timestamp = timestamp
    }
}

// MARK: - NATSDispatchSubjects

/// Centralizes NATS subject naming for the dispatch subsystem.
public enum NATSDispatchSubjects {
    /// Subject for dispatching a task to a specific node.
    public static func targeted(nodeId: String) -> String {
        "shikki.dispatch.\(nodeId)"
    }

    /// Subject for dispatching a task to any available worker.
    public static var available: String {
        "shikki.dispatch.available"
    }

    /// Subject for progress updates from a task.
    public static func progress(taskId: String) -> String {
        "shikki.dispatch.progress.\(taskId)"
    }

    /// Subject for the final result of a task.
    public static func result(taskId: String) -> String {
        "shikki.dispatch.result.\(taskId)"
    }

    /// Wildcard to subscribe to all dispatch progress events.
    public static var allProgress: String {
        "shikki.dispatch.progress.>"
    }

    /// Wildcard to subscribe to all dispatch results.
    public static var allResults: String {
        "shikki.dispatch.result.>"
    }
}
