import Foundation

/// Drives a feature through the full lifecycle pipeline.
/// Manages state transitions, gate execution, and checkpoint persistence.
public actor FeatureLifecycle {
    public let featureId: String
    public private(set) var state: LifecycleState = .idle
    private var transitions: [LifecycleTransition] = []
    private let persister: (any EventPersisting)?
    private let pipelineRunner: PipelineRunner
    private let validator = TransitionValidator()

    public init(featureId: String, persister: (any EventPersisting)? = nil) {
        self.featureId = featureId
        self.persister = persister
        self.pipelineRunner = PipelineRunner(persister: persister)
    }

    // Private init for restore — sets state and transitions directly
    private init(featureId: String, state: LifecycleState, transitions: [LifecycleTransition], persister: (any EventPersisting)?) {
        self.featureId = featureId
        self.state = state
        self.transitions = transitions
        self.persister = persister
        self.pipelineRunner = PipelineRunner(persister: persister)
    }

    /// Attempt a state transition. Throws if invalid.
    public func transition(to newState: LifecycleState, actor: TransitionActor, reason: String) throws {
        try validator.validate(from: state, to: newState)
        let t = LifecycleTransition(
            from: state, to: newState,
            timestamp: Date(), actor: actor, reason: reason
        )
        transitions.append(t)
        state = newState
    }

    /// Run a pipeline of gates and transition based on result.
    public func runGates(
        _ gates: [PipelineGate],
        context: PipelineContext,
        onSuccess: LifecycleState,
        onFail: LifecycleState
    ) async throws -> PipelineResult {
        let result = try await pipelineRunner.run(gates: gates, context: context)
        if result.success {
            try transition(to: onSuccess, actor: .system, reason: "All gates passed")
        } else {
            try transition(to: onFail, actor: .system, reason: "Gate failed: \(result.failedGate ?? "unknown")")
        }
        return result
    }

    /// Save checkpoint for crash recovery.
    public func checkpoint(to path: String) throws {
        let cp = LifecycleCheckpoint(
            featureId: featureId,
            state: state,
            timestamp: Date(),
            metadata: [:],
            transitionHistory: transitions
        )
        try cp.save(to: path)
    }

    /// Restore from checkpoint.
    public static func restore(from path: String, persister: (any EventPersisting)? = nil) throws -> FeatureLifecycle? {
        guard let cp = try LifecycleCheckpoint.load(from: path) else { return nil }
        return FeatureLifecycle(
            featureId: cp.featureId,
            state: cp.state,
            transitions: cp.transitionHistory,
            persister: persister
        )
    }
}
