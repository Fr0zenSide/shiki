import Foundation

/// Three-state FSM for the shikki unified command.
/// State is derived from tmux `has-session` + checkpoint file — no explicit state file.
/// BR-01: Exactly three states. BR-05/06: Valid/invalid transitions.
public enum ShikkiState: String, Sendable, Codable, Equatable {
    case idle
    case running
    case stopping

    /// BR-05: Valid transitions per state.
    public var allowedTransitions: Set<ShikkiState> {
        switch self {
        case .idle:
            // IDLE → RUNNING (start or resume)
            return [.running]
        case .running:
            // RUNNING → STOPPING (stop invoked), RUNNING → IDLE (crash/external kill)
            return [.stopping, .idle]
        case .stopping:
            // STOPPING → IDLE (countdown completes), STOPPING → RUNNING (Esc cancel)
            return [.idle, .running]
        }
    }

    /// Check if a transition to the target state is valid.
    public func canTransition(to target: ShikkiState) -> Bool {
        allowedTransitions.contains(target)
    }
}
