import Foundation
import Logging

/// Result of the shikki entry point dispatch.
public enum ShikkiAction: Equatable, Sendable {
    case startClean                      // IDLE + no checkpoint → fresh start
    case resume(Checkpoint)              // IDLE + checkpoint → restore and start
    case attach                          // RUNNING → attach to existing session
    case blocked                         // STOPPING → wait or cancel in other terminal
}

/// Result of the shi stop flow.
public enum StopAction: Equatable, Sendable {
    case stopped                         // Full stop completed
    case cancelled                       // User pressed Esc
    case nothingRunning                  // IDLE → no-op
    case alreadyStopping                 // STOPPING → no-op
}

/// Core orchestration logic for shikki.
/// Wires together StateDetector, CheckpointManager, LockfileManager, DBSyncClient,
/// CountdownTimer, and WelcomeRenderer into testable user flows.
/// The CLI command layer (ShikkiCommand) delegates to this engine.
public struct ShikkiEngine: Sendable {
    public let detector: any StateDetecting
    public let checkpointManager: CheckpointManager
    public let lockfileManager: LockfileManager
    public let dbSync: any DBSyncing
    private let logger = Logger(label: "shikki.engine")

    public init(
        detector: any StateDetecting,
        checkpointManager: CheckpointManager,
        lockfileManager: LockfileManager,
        dbSync: any DBSyncing
    ) {
        self.detector = detector
        self.checkpointManager = checkpointManager
        self.lockfileManager = lockfileManager
        self.dbSync = dbSync
    }

    // MARK: - Entry Point (BR-08, BR-09, BR-10)

    /// Determine what action to take when `shikki` is invoked with no args.
    /// BR-08: IDLE → start/resume, RUNNING → attach, STOPPING → block.
    /// BR-09: IDLE + checkpoint → resume.
    /// BR-10: IDLE + no checkpoint → clean start.
    /// BR-11: Never prompts — deterministic dispatch.
    public func dispatch() async throws -> ShikkiAction {
        let state = await detector.detect()

        switch state {
        case .idle:
            // Check for resumable checkpoint
            if let checkpoint = try checkpointManager.load() {
                return .resume(checkpoint)
            }
            return .startClean

        case .running:
            return .attach

        case .stopping:
            return .blocked
        }
    }

    /// Render welcome message for resume action.
    /// BR-45: Shows "Welcome back" line.
    /// BR-49: Returns nil for clean start.
    public func welcomeMessage(for action: ShikkiAction, now: Date = Date()) -> String? {
        switch action {
        case .resume(let checkpoint):
            return WelcomeRenderer.renderToString(checkpoint: checkpoint, now: now)
        default:
            return nil
        }
    }

    /// After successful resume, delete the checkpoint.
    /// BR-23: Checkpoint deleted after tmux confirmed live.
    public func confirmResume() throws {
        try checkpointManager.delete()
    }

    // MARK: - Stop Flow (BR-12, BR-18, BR-25)

    /// Execute the stop flow.
    /// BR-12: RUNNING → save + countdown + cleanup. IDLE → no-op.
    /// BR-18: STOPPING → no-op.
    /// BR-25: Save order: local first (hard), DB second (soft).
    public func stop(
        checkpoint: Checkpoint,
        countdown: Int = CountdownTimer.defaultCountdown,
        timer: CountdownTimer
    ) async throws -> StopAction {
        let state = await detector.detect()

        switch state {
        case .idle:
            return .nothingRunning
        case .stopping:
            return .alreadyStopping
        case .running:
            break
        }

        // BR-25: Local first (hard error if fails)
        try checkpointManager.save(checkpoint)

        // BR-25: DB second (soft warning if fails)
        let synced = await dbSync.uploadCheckpoint(checkpoint)
        if !synced {
            logger.warning("DB sync failed — checkpoint saved locally only (dbSynced=false)")
        }

        // Countdown with Esc cancel
        let result = await timer.run(seconds: countdown)

        switch result {
        case .cancelled:
            // BR-16: Esc cancels. Checkpoint is preserved as resume point.
            return .cancelled
        case .completed, .immediate:
            // Cleanup: release lockfile
            try? lockfileManager.release()
            return .stopped
        }
    }

    // MARK: - Subcommand Routing (BR-36 to BR-40)

    /// Known shikki subcommands — retained after migration.
    public static let retainedCommands: Set<String> = [
        "stop", "pr", "board", "dashboard", "doctor", "report",
        "search", "ship", "menu", "decide", "heartbeat", "history",
        "status",
    ]

    /// Commands that were deleted — subsumed by FSM.
    public static let deletedCommands: Set<String> = [
        "start", "attach", "session",
    ]

    /// Commands requiring a RUNNING tmux session.
    public static let requiresRunning: Set<String> = [
        "board", "dashboard",
    ]

    /// Check if a subcommand is recognized.
    public static func isKnownCommand(_ command: String) -> Bool {
        retainedCommands.contains(command.lowercased())
    }

    /// Check if a subcommand requires running state.
    /// BR-39: Returns true for board, dashboard.
    /// BR-40: Returns false for pr, doctor, etc.
    public static func commandRequiresRunning(_ command: String) -> Bool {
        requiresRunning.contains(command.lowercased())
    }

    /// Validate that a command requiring RUNNING state can execute.
    /// BR-39: If not RUNNING, returns error message.
    public func validateStateForCommand(_ command: String) async -> String? {
        guard Self.commandRequiresRunning(command) else { return nil }
        let state = await detector.detect()
        if state != .running {
            return "'\(command)' requires a running session. Run `shikki` to start."
        }
        return nil
    }

    // MARK: - Hybrid Persistence (BR-25, BR-26, BR-27)

    /// Load checkpoint with hybrid persistence: local first, DB fallback.
    /// BR-26: Resume reads local first. If no local, queries DB by hostname.
    /// BR-27: If both exist and differ, local wins.
    public func loadCheckpointHybrid(hostname: String) async throws -> Checkpoint? {
        // Local first
        if let local = try checkpointManager.load() {
            return local
        }

        // DB fallback
        if let remote = await dbSync.downloadCheckpoint(hostname: hostname) {
            // Write to local for next time
            try checkpointManager.save(remote)
            return remote
        }

        return nil
    }
}
