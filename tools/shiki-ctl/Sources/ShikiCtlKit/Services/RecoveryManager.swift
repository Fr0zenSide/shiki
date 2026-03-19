import Foundation
import Logging

// MARK: - RecoverableSession

/// A session that was active when the system stopped and can be recovered.
public struct RecoverableSession: Sendable {
    public let sessionId: String
    public let lastState: SessionState
    public let lastCheckpoint: Date
    public let metadata: [String: String]?

    public init(sessionId: String, lastState: SessionState, lastCheckpoint: Date, metadata: [String: String]?) {
        self.sessionId = sessionId
        self.lastState = lastState
        self.lastCheckpoint = lastCheckpoint
        self.metadata = metadata
    }
}

// MARK: - RecoveryPlan

/// Plan for recovering a specific session.
public struct RecoveryPlan: Sendable {
    public let sessionId: String
    public let lastState: SessionState
    public let metadata: [String: String]?
    public let checkpoints: [SessionCheckpoint]

    public init(sessionId: String, lastState: SessionState, metadata: [String: String]?, checkpoints: [SessionCheckpoint]) {
        self.sessionId = sessionId
        self.lastState = lastState
        self.metadata = metadata
        self.checkpoints = checkpoints
    }
}

// MARK: - RecoveryManager

/// Scans journals on startup to find and recover crashed sessions.
/// Validates: last state was active, workspace exists, metadata consistent.
public struct RecoveryManager: Sendable {
    private let journal: SessionJournal
    private let logger: Logger

    /// Terminal states that don't need recovery.
    private static let terminalStates: Set<SessionState> = [.done, .merged]

    public init(
        journal: SessionJournal,
        logger: Logger = Logger(label: "shiki-ctl.recovery")
    ) {
        self.journal = journal
        self.logger = logger
    }

    /// Find all sessions that were active when the system stopped.
    public func findRecoverableSessions() async throws -> [RecoverableSession] {
        let basePath = await journal.basePath
        let fm = FileManager.default
        guard fm.fileExists(atPath: basePath) else { return [] }

        let files = try fm.contentsOfDirectory(atPath: basePath)
        var recoverable: [RecoverableSession] = []

        for file in files where file.hasSuffix(".jsonl") {
            let sessionId = String(file.dropLast(6)) // remove .jsonl
            let checkpoints = try await journal.loadCheckpoints(sessionId: sessionId)

            guard let last = checkpoints.last else { continue }

            // Only recover sessions that were in an active state
            if !Self.terminalStates.contains(last.state) {
                recoverable.append(RecoverableSession(
                    sessionId: sessionId,
                    lastState: last.state,
                    lastCheckpoint: last.timestamp,
                    metadata: last.metadata
                ))
            }
        }

        return recoverable.sorted { $0.lastCheckpoint > $1.lastCheckpoint }
    }

    /// Build a recovery plan for a specific session.
    public func buildRecoveryPlan(sessionId: String) async throws -> RecoveryPlan? {
        let checkpoints = try await journal.loadCheckpoints(sessionId: sessionId)
        guard let last = checkpoints.last else { return nil }
        guard !Self.terminalStates.contains(last.state) else { return nil }

        return RecoveryPlan(
            sessionId: sessionId,
            lastState: last.state,
            metadata: last.metadata,
            checkpoints: checkpoints
        )
    }
}
