import Foundation
import Logging

/// Bootstrap logic for first-run detection and default state creation.
///
/// Solves CRASH 3 from the zero-to-running diagnostic: "No session state —
/// checkpoint.json missing → Shikki tries to resume but nothing to resume from."
///
/// Instead of crashing, SessionBootstrap detects first-run conditions and creates
/// a safe default state so `shikki` always has something to work with.
public struct SessionBootstrap: Sendable {
    private let sessionsDirectory: String
    private let checkpointManager: CheckpointManager
    private let hostname: String
    private let logger = Logger(label: "shikki.bootstrap")

    public init(
        sessionsDirectory: String? = nil,
        checkpointManager: CheckpointManager? = nil,
        hostname: String? = nil
    ) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.sessionsDirectory = sessionsDirectory ?? "\(home)/.shikki/sessions"
        self.checkpointManager = checkpointManager ?? CheckpointManager()
        self.hostname = hostname ?? ProcessInfo.processInfo.hostName
    }

    // MARK: - First-Run Detection

    /// Check if this is the first run (no sessions directory or it's empty,
    /// AND no checkpoint file exists).
    public func isFirstRun() -> Bool {
        let fm = FileManager.default

        // If a checkpoint already exists, this is not a first run
        if checkpointManager.exists() {
            return true == false  // false — checkpoint present means prior session
        }

        // If sessions directory doesn't exist → first run
        guard fm.fileExists(atPath: sessionsDirectory) else {
            return true
        }

        // If sessions directory exists but is empty → first run
        guard let contents = try? fm.contentsOfDirectory(atPath: sessionsDirectory) else {
            return true
        }

        // Filter out hidden files (like .DS_Store)
        let sessionFiles = contents.filter { !$0.hasPrefix(".") }
        return sessionFiles.isEmpty
    }

    // MARK: - Default State Creation

    /// Create the initial session state: sessions directory + default checkpoint.
    /// Idempotent — safe to call multiple times.
    public func createDefaultState(now: Date = Date()) throws {
        let fm = FileManager.default

        // Create sessions directory with 0700 if it doesn't exist
        if !fm.fileExists(atPath: sessionsDirectory) {
            try fm.createDirectory(
                atPath: sessionsDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            logger.info("Created sessions directory: \(sessionsDirectory)")
        }

        // Create initial checkpoint (idle state, no previous session data)
        let checkpoint = Checkpoint(
            timestamp: now,
            hostname: hostname,
            fsmState: .idle,
            tmuxLayout: nil,
            sessionStats: nil,
            contextSnippet: nil,
            dbSynced: false
        )
        try checkpointManager.save(checkpoint)
        logger.info("Created default checkpoint for first run")
    }

    // MARK: - Welcome Message

    /// Generate appropriate welcome message based on session state.
    /// First run: "Welcome to Shikki" with fire emoji.
    /// Returning: "Resuming session: ..." with checkpoint context.
    public func welcomeMessage(checkpoint: Checkpoint? = nil) -> String {
        if let cp = checkpoint, cp.sessionStats != nil || cp.contextSnippet != nil {
            return resumeMessage(for: cp)
        }
        return firstRunMessage()
    }

    /// First-run welcome message.
    private func firstRunMessage() -> String {
        "Welcome to Shikki \u{1F525}"
    }

    /// Resume message with session context.
    private func resumeMessage(for checkpoint: Checkpoint) -> String {
        var parts: [String] = ["Resuming session"]

        if let stats = checkpoint.sessionStats {
            parts.append("on branch \(stats.branch)")
            if stats.commitCount > 0 {
                parts.append("(\(stats.commitCount) commits)")
            }
        }

        if let snippet = checkpoint.contextSnippet {
            let truncated = snippet.count > 80
                ? String(snippet.prefix(77)) + "..."
                : snippet
            parts.append("- \(truncated)")
        }

        return parts.joined(separator: " ")
    }

    // MARK: - Bootstrap (Combines Detection + Creation)

    /// Full bootstrap flow: detect first run, create default state if needed,
    /// return appropriate welcome message.
    /// This is the single entry point that ShikkiEngine should call.
    public func bootstrap(now: Date = Date()) throws -> String {
        if isFirstRun() {
            try createDefaultState(now: now)
            return firstRunMessage()
        }

        // Not first run — try to load checkpoint for resume message
        let checkpoint = try checkpointManager.load()
        return welcomeMessage(checkpoint: checkpoint)
    }
}
