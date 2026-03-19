import Foundation

// MARK: - States

public enum LifecycleState: String, Codable, Sendable, CaseIterable {
    case idle
    case specDrafting
    case specPendingApproval  // governor gate
    case decisionsNeeded      // governor gate
    case building
    case gating
    case shipping
    case done
    case failed
    case blocked
}

// MARK: - Transition

public struct LifecycleTransition: Codable, Sendable {
    public let from: LifecycleState
    public let to: LifecycleState
    public let timestamp: Date
    public let actor: TransitionActor
    public let reason: String

    public init(from: LifecycleState, to: LifecycleState, timestamp: Date, actor: TransitionActor, reason: String) {
        self.from = from
        self.to = to
        self.timestamp = timestamp
        self.actor = actor
        self.reason = reason
    }
}

// MARK: - Actor

public enum TransitionActor: Codable, Sendable {
    case agent(id: String)
    case user(id: String)
    case system
}

// MARK: - Transition Validation

public enum TransitionError: Error, Sendable {
    case invalidTransition(from: LifecycleState, to: LifecycleState)
}

public struct TransitionValidator: Sendable {

    /// Valid transitions from each state (excluding universal transitions to blocked/failed).
    private static let validTransitions: [LifecycleState: Set<LifecycleState>] = [
        .idle: [.specDrafting],
        .specDrafting: [.specPendingApproval],
        .specPendingApproval: [.decisionsNeeded, .building],
        .decisionsNeeded: [.building],
        .building: [.gating],
        .gating: [.shipping, .failed],
        .shipping: [.done, .failed],
        .done: [],
        .failed: [],
        // blocked can resume to any active state
        .blocked: [.idle, .specDrafting, .specPendingApproval, .decisionsNeeded, .building, .gating, .shipping],
    ]

    public init() {}

    public func isValid(from: LifecycleState, to: LifecycleState) -> Bool {
        // Any state can go to blocked (except blocked itself)
        if to == .blocked && from != .blocked {
            return true
        }

        // Any state (except done/failed) can go to failed
        if to == .failed && from != .done && from != .failed {
            return true
        }

        guard let validTargets = Self.validTransitions[from] else {
            return false
        }

        return validTargets.contains(to)
    }

    public func validate(from: LifecycleState, to: LifecycleState) throws {
        guard isValid(from: from, to: to) else {
            throw TransitionError.invalidTransition(from: from, to: to)
        }
    }
}
