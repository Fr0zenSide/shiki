import Foundation

/// Protocol for shikki FSM state detection.
/// BR-07: Detection runs in under 200ms. No network calls.
public protocol StateDetecting: Sendable {
    func detect() async -> ShikkiState
}

/// Detects the current shikki FSM state from tmux + checkpoint file.
/// BR-02: IDLE = no tmux session + no live session.
/// BR-03: RUNNING = tmux session exists.
/// BR-50: tmux crash (checkpoint exists, no tmux) → IDLE.
/// Note: STOPPING is transient — only set by the stop command's FSM, never detected externally.
public struct StateDetector: StateDetecting, Sendable {
    private let sessionName: String
    private let environment: any EnvironmentChecking
    private let checkpointManager: CheckpointManager

    public init(
        sessionName: String = "shikki",
        environment: any EnvironmentChecking = EnvironmentDetector(),
        checkpointManager: CheckpointManager = CheckpointManager()
    ) {
        self.sessionName = sessionName
        self.environment = environment
        self.checkpointManager = checkpointManager
    }

    /// Detect the current FSM state.
    /// Check order (BR-07): (1) tmux has-session, (2) checkpoint file.
    public func detect() async -> ShikkiState {
        // Primary signal: is tmux session alive?
        let tmuxAlive = await environment.isTmuxSessionRunning(name: sessionName)

        if tmuxAlive {
            return .running
        }

        // tmux not running → idle (regardless of checkpoint)
        // BR-50: If checkpoint exists but tmux is dead, treat as idle (crash recovery).
        // The checkpoint is preserved so `shikki` can offer resume.
        return .idle
    }
}
