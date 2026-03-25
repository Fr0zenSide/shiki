import Foundation

// TODO: Extract to ShikkiKit — this should conform to ShikkiEvent protocol once that package exists

public enum LifecycleEventType: String, Codable, Sendable {
    case lifecycleStarted
    case stateTransitioned
    case governorGateReached
    case governorGateCleared
    case agentDispatched
    case agentCompleted
    case agentFailed
    case checkpointSaved
    case lifecycleCompleted
    case lifecycleFailed
    case gateEvaluated
}
