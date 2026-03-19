import Foundation

// MARK: - Event Payload

public struct LifecycleEventPayload: Codable, Sendable {
    public let type: LifecycleEventType
    public let featureId: String
    public let timestamp: Date
    public let data: [String: String]

    public init(type: LifecycleEventType, featureId: String, timestamp: Date, data: [String: String]) {
        self.type = type
        self.featureId = featureId
        self.timestamp = timestamp
        self.data = data
    }
}

// MARK: - Event Factories

// TODO: Conform to ShikiEvent protocol once ShikiKit is available on this branch

public enum CoreEvent {

    public static func lifecycleStarted(featureId: String, branch: String) -> LifecycleEventPayload {
        LifecycleEventPayload(
            type: .lifecycleStarted,
            featureId: featureId,
            timestamp: Date(),
            data: ["branch": branch]
        )
    }

    public static func stateTransitioned(
        featureId: String,
        from: LifecycleState,
        to: LifecycleState
    ) -> LifecycleEventPayload {
        LifecycleEventPayload(
            type: .stateTransitioned,
            featureId: featureId,
            timestamp: Date(),
            data: ["from": from.rawValue, "to": to.rawValue]
        )
    }

    public static func governorGateReached(featureId: String, gate: String) -> LifecycleEventPayload {
        LifecycleEventPayload(
            type: .governorGateReached,
            featureId: featureId,
            timestamp: Date(),
            data: ["gate": gate]
        )
    }

    public static func governorGateCleared(featureId: String, gate: String) -> LifecycleEventPayload {
        LifecycleEventPayload(
            type: .governorGateCleared,
            featureId: featureId,
            timestamp: Date(),
            data: ["gate": gate]
        )
    }

    public static func agentDispatched(featureId: String, agentName: String, prompt: String) -> LifecycleEventPayload {
        LifecycleEventPayload(
            type: .agentDispatched,
            featureId: featureId,
            timestamp: Date(),
            data: ["agent": agentName, "prompt": String(prompt.prefix(200))]
        )
    }

    public static func agentCompleted(featureId: String, agentName: String, exitCode: Int32) -> LifecycleEventPayload {
        LifecycleEventPayload(
            type: .agentCompleted,
            featureId: featureId,
            timestamp: Date(),
            data: ["agent": agentName, "exitCode": String(exitCode)]
        )
    }

    public static func agentFailed(featureId: String, agentName: String, error: String) -> LifecycleEventPayload {
        LifecycleEventPayload(
            type: .agentFailed,
            featureId: featureId,
            timestamp: Date(),
            data: ["agent": agentName, "error": error]
        )
    }

    public static func checkpointSaved(featureId: String, state: LifecycleState) -> LifecycleEventPayload {
        LifecycleEventPayload(
            type: .checkpointSaved,
            featureId: featureId,
            timestamp: Date(),
            data: ["state": state.rawValue]
        )
    }

    public static func lifecycleCompleted(featureId: String) -> LifecycleEventPayload {
        LifecycleEventPayload(
            type: .lifecycleCompleted,
            featureId: featureId,
            timestamp: Date(),
            data: [:]
        )
    }

    public static func lifecycleFailed(featureId: String, error: String) -> LifecycleEventPayload {
        LifecycleEventPayload(
            type: .lifecycleFailed,
            featureId: featureId,
            timestamp: Date(),
            data: ["error": error]
        )
    }

    public static func gateEvaluated(featureId: String, gate: String, passed: Bool, detail: String) -> LifecycleEventPayload {
        LifecycleEventPayload(
            type: .gateEvaluated,
            featureId: featureId,
            timestamp: Date(),
            data: ["gate": gate, "passed": String(passed), "detail": detail]
        )
    }
}
