import Foundation

/// Pipeline type (maps to PipelineRunCreateSchema.pipelineType).
public enum PipelineType: String, Codable, Sendable {
    case quick
    case mdFeature = "md-feature"
    case dispatch
    case prePr = "pre-pr"
    case review
}

/// Pipeline run status.
public enum PipelineRunStatus: String, Codable, Sendable {
    case running
    case completed
    case failed
    case cancelled
    case resuming
}

/// Checkpoint status.
public enum CheckpointStatus: String, Codable, Sendable {
    case completed
    case failed
    case skipped
}

/// Routing condition (maps to PipelineRoutingRuleSchema.condition).
public enum RoutingCondition: String, Codable, Sendable {
    case onFailure = "on_failure"
    case onSuccess = "on_success"
    case onSkip = "on_skip"
    case always
}

/// Input for creating a pipeline run (maps to PipelineRunCreateSchema).
public struct PipelineRunCreateInput: Codable, Equatable, Sendable, Validatable {
    public let pipelineType: PipelineType
    public let projectId: UUID?
    public let sessionId: UUID?
    public let config: [String: AnyCodable]
    public let initialState: [String: AnyCodable]
    public let metadata: [String: AnyCodable]

    public init(
        pipelineType: PipelineType,
        projectId: UUID? = nil,
        sessionId: UUID? = nil,
        config: [String: AnyCodable] = [:],
        initialState: [String: AnyCodable] = [:],
        metadata: [String: AnyCodable] = [:]
    ) {
        self.pipelineType = pipelineType
        self.projectId = projectId
        self.sessionId = sessionId
        self.config = config
        self.initialState = initialState
        self.metadata = metadata
    }

    public func validate() throws {
        // Pipeline type is validated by the enum itself (decode fails for invalid values)
    }

    enum CodingKeys: String, CodingKey {
        case config, metadata
        case pipelineType = "pipeline_type"
        case projectId = "project_id"
        case sessionId = "session_id"
        case initialState = "initial_state"
    }
}

/// Input for updating a pipeline run (maps to PipelineRunUpdateSchema).
public struct PipelineRunUpdateInput: Codable, Equatable, Sendable {
    public let status: PipelineRunStatus?
    public let currentPhase: String?
    public let state: [String: AnyCodable]?
    public let error: String?

    public init(
        status: PipelineRunStatus? = nil,
        currentPhase: String? = nil,
        state: [String: AnyCodable]? = nil,
        error: String? = nil
    ) {
        self.status = status
        self.currentPhase = currentPhase
        self.state = state
        self.error = error
    }

    enum CodingKeys: String, CodingKey {
        case status, state, error
        case currentPhase = "current_phase"
    }
}

/// Input for adding a pipeline checkpoint (maps to PipelineCheckpointSchema).
public struct PipelineCheckpointInput: Codable, Equatable, Sendable, Validatable {
    public let phase: String
    public let phaseIndex: Int
    public let status: CheckpointStatus
    public let stateBefore: [String: AnyCodable]
    public let stateAfter: [String: AnyCodable]
    public let output: [String: AnyCodable]
    public let error: String?
    public let durationMs: Int?
    public let metadata: [String: AnyCodable]

    public init(
        phase: String,
        phaseIndex: Int,
        status: CheckpointStatus = .completed,
        stateBefore: [String: AnyCodable] = [:],
        stateAfter: [String: AnyCodable] = [:],
        output: [String: AnyCodable] = [:],
        error: String? = nil,
        durationMs: Int? = nil,
        metadata: [String: AnyCodable] = [:]
    ) {
        self.phase = phase
        self.phaseIndex = phaseIndex
        self.status = status
        self.stateBefore = stateBefore
        self.stateAfter = stateAfter
        self.output = output
        self.error = error
        self.durationMs = durationMs
        self.metadata = metadata
    }

    public func validate() throws {
        try Validators.requireNonEmpty(phase, field: "phase")
        if phaseIndex < 0 {
            throw ShikiValidationError.fieldMustBeNonNegative("phaseIndex")
        }
        if let durationMs, durationMs < 0 {
            throw ShikiValidationError.fieldMustBeNonNegative("durationMs")
        }
    }

    enum CodingKeys: String, CodingKey {
        case phase, status, output, error, metadata
        case phaseIndex = "phase_index"
        case stateBefore = "state_before"
        case stateAfter = "state_after"
        case durationMs = "duration_ms"
    }
}

/// Input for resuming a pipeline run (maps to PipelineResumeSchema).
public struct PipelineResumeInput: Codable, Equatable, Sendable {
    public let fromPhase: String?
    public let stateOverrides: [String: AnyCodable]

    public init(fromPhase: String? = nil, stateOverrides: [String: AnyCodable] = [:]) {
        self.fromPhase = fromPhase
        self.stateOverrides = stateOverrides
    }

    enum CodingKeys: String, CodingKey {
        case fromPhase = "from_phase"
        case stateOverrides = "state_overrides"
    }
}

/// Input for creating a pipeline routing rule (maps to PipelineRoutingRuleSchema).
public struct PipelineRoutingRuleInput: Codable, Equatable, Sendable, Validatable {
    public let pipelineType: String
    public let sourcePhase: String
    public let condition: RoutingCondition
    public let targetAction: String
    public let config: [String: AnyCodable]
    public let priority: Int
    public let enabled: Bool

    public init(
        pipelineType: String,
        sourcePhase: String,
        condition: RoutingCondition,
        targetAction: String,
        config: [String: AnyCodable] = [:],
        priority: Int = 0,
        enabled: Bool = true
    ) {
        self.pipelineType = pipelineType
        self.sourcePhase = sourcePhase
        self.condition = condition
        self.targetAction = targetAction
        self.config = config
        self.priority = priority
        self.enabled = enabled
    }

    public func validate() throws {
        try Validators.requireNonEmpty(pipelineType, field: "pipelineType")
        try Validators.requireNonEmpty(sourcePhase, field: "sourcePhase")
        try Validators.requireNonEmpty(targetAction, field: "targetAction")
        if priority < 0 || priority > 100 {
            throw ShikiValidationError.fieldOutOfRange("priority", min: 0, max: 100)
        }
    }

    enum CodingKeys: String, CodingKey {
        case condition, config, priority, enabled
        case pipelineType = "pipeline_type"
        case sourcePhase = "source_phase"
        case targetAction = "target_action"
    }
}

/// Input for evaluating pipeline routing (maps to PipelineRouteEvalSchema).
public struct PipelineRouteEvalInput: Codable, Equatable, Sendable, Validatable {
    public let failedPhase: String

    public init(failedPhase: String) {
        self.failedPhase = failedPhase
    }

    public func validate() throws {
        try Validators.requireNonEmpty(failedPhase, field: "failedPhase")
    }

    enum CodingKeys: String, CodingKey {
        case failedPhase = "failed_phase"
    }
}

/// Pipeline run as stored in the database.
public struct PipelineRunDTO: Codable, Equatable, Sendable {
    public let id: UUID
    public let pipelineType: PipelineType
    public let projectId: UUID?
    public let sessionId: UUID?
    public let status: PipelineRunStatus
    public let currentPhase: String?
    public let config: [String: AnyCodable]
    public let state: [String: AnyCodable]
    public let error: String?
    public let metadata: [String: AnyCodable]
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: UUID,
        pipelineType: PipelineType,
        projectId: UUID? = nil,
        sessionId: UUID? = nil,
        status: PipelineRunStatus = .running,
        currentPhase: String? = nil,
        config: [String: AnyCodable] = [:],
        state: [String: AnyCodable] = [:],
        error: String? = nil,
        metadata: [String: AnyCodable] = [:],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.pipelineType = pipelineType
        self.projectId = projectId
        self.sessionId = sessionId
        self.status = status
        self.currentPhase = currentPhase
        self.config = config
        self.state = state
        self.error = error
        self.metadata = metadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, status, config, state, error, metadata
        case pipelineType = "pipeline_type"
        case projectId = "project_id"
        case sessionId = "session_id"
        case currentPhase = "current_phase"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Pipeline checkpoint as stored in the database.
public struct PipelineCheckpointDTO: Codable, Equatable, Sendable {
    public let id: UUID
    public let runId: UUID
    public let phase: String
    public let phaseIndex: Int
    public let status: CheckpointStatus
    public let stateBefore: [String: AnyCodable]
    public let stateAfter: [String: AnyCodable]
    public let output: [String: AnyCodable]
    public let error: String?
    public let durationMs: Int?
    public let metadata: [String: AnyCodable]
    public let createdAt: Date

    public init(
        id: UUID,
        runId: UUID,
        phase: String,
        phaseIndex: Int,
        status: CheckpointStatus = .completed,
        stateBefore: [String: AnyCodable] = [:],
        stateAfter: [String: AnyCodable] = [:],
        output: [String: AnyCodable] = [:],
        error: String? = nil,
        durationMs: Int? = nil,
        metadata: [String: AnyCodable] = [:],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.runId = runId
        self.phase = phase
        self.phaseIndex = phaseIndex
        self.status = status
        self.stateBefore = stateBefore
        self.stateAfter = stateAfter
        self.output = output
        self.error = error
        self.durationMs = durationMs
        self.metadata = metadata
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, phase, status, output, error, metadata
        case runId = "run_id"
        case phaseIndex = "phase_index"
        case stateBefore = "state_before"
        case stateAfter = "state_after"
        case durationMs = "duration_ms"
        case createdAt = "created_at"
    }
}

/// Pipeline routing rule as stored in the database.
public struct PipelineRoutingRuleDTO: Codable, Equatable, Sendable {
    public let id: UUID
    public let pipelineType: String
    public let sourcePhase: String
    public let condition: RoutingCondition
    public let targetAction: String
    public let config: [String: AnyCodable]
    public let priority: Int
    public let enabled: Bool
    public let createdAt: Date

    public init(
        id: UUID,
        pipelineType: String,
        sourcePhase: String,
        condition: RoutingCondition,
        targetAction: String,
        config: [String: AnyCodable] = [:],
        priority: Int = 0,
        enabled: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.pipelineType = pipelineType
        self.sourcePhase = sourcePhase
        self.condition = condition
        self.targetAction = targetAction
        self.config = config
        self.priority = priority
        self.enabled = enabled
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, condition, config, priority, enabled
        case pipelineType = "pipeline_type"
        case sourcePhase = "source_phase"
        case targetAction = "target_action"
        case createdAt = "created_at"
    }
}
