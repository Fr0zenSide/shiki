import Foundation
import Logging

/// Unified checkpoint persistence for shikki.
/// Replaces PausedSessionManager + SessionJournal.
/// BR-19: Single CheckpointManager replaces both.
/// BR-20: Single file `checkpoint.json`, atomic write (write-to-temp + rename).
/// BR-22: save/load/exists/delete.
/// BR-28: Directory `~/.shikki/` created with mode 0700 on first run.
public struct CheckpointManager: Sendable {
    public let directory: String
    private let logger = Logger(label: "shikki.checkpoint")

    /// File name for the checkpoint JSON.
    private static let checkpointFilename = "checkpoint.json"

    public init(directory: String? = nil) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.directory = directory ?? "\(home)/.shikki"
    }

    /// Full path to the checkpoint file.
    public var checkpointPath: String {
        "\(directory)/\(Self.checkpointFilename)"
    }

    // MARK: - BR-22: CRUD API

    /// Save checkpoint to disk using atomic write (BR-57: write-to-temp + rename).
    public func save(_ checkpoint: Checkpoint) throws {
        let fm = FileManager.default

        // BR-28: Create directory with 0700 if it doesn't exist
        if !fm.fileExists(atPath: directory) {
            try fm.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: [
                .posixPermissions: 0o700
            ])
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(checkpoint)

        // BR-57: Atomic write — write to .tmp, then rename
        let tmpPath = "\(directory)/checkpoint.tmp"
        let targetURL = URL(fileURLWithPath: checkpointPath)
        let tmpURL = URL(fileURLWithPath: tmpPath)

        try data.write(to: tmpURL, options: .atomic)

        // If target exists, remove it first
        if fm.fileExists(atPath: checkpointPath) {
            try fm.removeItem(at: targetURL)
        }

        try fm.moveItem(at: tmpURL, to: targetURL)
        logger.debug("Checkpoint saved to \(checkpointPath)")
    }

    /// Load checkpoint from disk. Returns nil if no checkpoint file exists.
    public func load() throws -> Checkpoint? {
        guard FileManager.default.fileExists(atPath: checkpointPath) else {
            return nil
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: checkpointPath))
        return try JSONDecoder.shikkiDecoder.decode(Checkpoint.self, from: data)
    }

    /// Check if a checkpoint file exists on disk.
    public func exists() -> Bool {
        FileManager.default.fileExists(atPath: checkpointPath)
    }

    /// Delete the checkpoint file from disk.
    public func delete() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: checkpointPath) {
            try fm.removeItem(atPath: checkpointPath)
            logger.debug("Checkpoint deleted at \(checkpointPath)")
        }
    }

    // MARK: - BR-24: Legacy Migration

    /// Convert legacy PausedSessionManager + SessionJournal data to new Checkpoint schema.
    /// Reads most recent legacy session, converts to Checkpoint, writes to `~/.shikki/checkpoint.json`.
    /// Renames legacy dirs to `.migrated/` (idempotent — skips if `.migrated/` exists).
    public func migrateLegacy(
        legacySessionsDir: String? = nil,
        legacyJournalDir: String? = nil
    ) throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let sessionsDir = legacySessionsDir ?? "\(home)/.shiki/sessions"
        let journalDir = legacyJournalDir ?? "\(home)/.shiki/journal"
        let fm = FileManager.default

        let sessionsMigrated = sessionsDir + ".migrated"
        let journalMigrated = journalDir + ".migrated"

        // Idempotent: skip if already migrated
        let sessionsAlreadyMigrated = fm.fileExists(atPath: sessionsMigrated)
        let journalAlreadyMigrated = fm.fileExists(atPath: journalMigrated)

        var checkpoint: Checkpoint?

        // 1. Try to read most recent PausedSession
        if !sessionsAlreadyMigrated, fm.fileExists(atPath: sessionsDir) {
            checkpoint = try migratePausedSessions(from: sessionsDir)
        }

        // 2. Try to read most recent SessionJournal entry (fallback if no paused session)
        if checkpoint == nil, !journalAlreadyMigrated, fm.fileExists(atPath: journalDir) {
            checkpoint = try migrateJournalEntries(from: journalDir)
        }

        // 3. Write converted checkpoint if we got data
        if let cp = checkpoint {
            try save(cp)
            logger.info("Legacy data migrated to \(checkpointPath)")
        }

        // 4. Rename legacy dirs to .migrated (don't delete)
        if !sessionsAlreadyMigrated, fm.fileExists(atPath: sessionsDir) {
            try fm.moveItem(atPath: sessionsDir, toPath: sessionsMigrated)
        }
        if !journalAlreadyMigrated, fm.fileExists(atPath: journalDir) {
            try fm.moveItem(atPath: journalDir, toPath: journalMigrated)
        }
    }

    /// Convert the most recent PausedSession to a Checkpoint.
    private func migratePausedSessions(from dir: String) throws -> Checkpoint? {
        let fm = FileManager.default
        let files = try fm.contentsOfDirectory(atPath: dir)
            .filter { $0.hasSuffix(".json") }
            .sorted(by: >) // newest first

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for file in files {
            let path = "\(dir)/\(file)"
            guard let data = fm.contents(atPath: path) else { continue }
            guard let session = try? decoder.decode(PausedSession.self, from: data) else { continue }

            // Build context snippet from legacy fields
            var contextParts: [String] = []
            if let summary = session.summary {
                contextParts.append(summary)
            }
            if let next = session.nextAction {
                contextParts.append("Next: \(next)")
            }
            if !session.activeTasks.isEmpty {
                contextParts.append("Tasks: \(session.activeTasks.joined(separator: ", "))")
            }

            let hostname = ProcessInfo.processInfo.hostName

            return Checkpoint(
                timestamp: session.pausedAt,
                hostname: hostname,
                fsmState: .idle, // Paused = idle (not running)
                tmuxLayout: nil,
                sessionStats: SessionSnapshot(
                    startedAt: session.pausedAt,
                    branch: session.branch,
                    commitCount: 0,
                    linesChanged: 0
                ),
                contextSnippet: contextParts.isEmpty ? nil : contextParts.joined(separator: "\n"),
                dbSynced: false
            )
        }
        return nil
    }

    /// Convert the most recent journal entry to a Checkpoint.
    private func migrateJournalEntries(from dir: String) throws -> Checkpoint? {
        let fm = FileManager.default
        let files = try fm.contentsOfDirectory(atPath: dir)
            .filter { $0.hasSuffix(".jsonl") }
            .sorted(by: >) // newest first

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for file in files {
            let path = "\(dir)/\(file)"
            guard let content = fm.contents(atPath: path),
                  let text = String(data: content, encoding: .utf8) else { continue }

            // Read last line (most recent checkpoint)
            let lines = text.split(separator: "\n")
            guard let lastLine = lines.last else { continue }

            guard let entry = try? decoder.decode(SessionCheckpoint.self, from: Data(lastLine.utf8)) else { continue }

            let hostname = ProcessInfo.processInfo.hostName
            let branch = entry.metadata?["branch"] ?? "unknown"

            return Checkpoint(
                timestamp: entry.timestamp,
                hostname: hostname,
                fsmState: .idle,
                tmuxLayout: nil,
                sessionStats: SessionSnapshot(
                    startedAt: entry.timestamp,
                    branch: branch
                ),
                contextSnippet: nil,
                dbSynced: false
            )
        }
        return nil
    }
}

// MARK: - Shared JSON Decoder

public extension JSONDecoder {
    static let shikkiDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
