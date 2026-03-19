import Foundation

// TODO: Extract to ShikiKit — this should conform to ShikiEvent protocol once that package exists

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
}
