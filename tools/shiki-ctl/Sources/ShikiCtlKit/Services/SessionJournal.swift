import Foundation

// MARK: - Models

/// A point-in-time snapshot of session state for crash recovery.
public struct SessionCheckpoint: Sendable, Codable {
    public let sessionId: String
    public let state: SessionState
    public let timestamp: Date
    public let reason: CheckpointReason
    public let metadata: [String: String]?

    public init(
        sessionId: String, state: SessionState,
        reason: CheckpointReason, metadata: [String: String]?,
        timestamp: Date = Date()
    ) {
        self.sessionId = sessionId
        self.state = state
        self.timestamp = timestamp
        self.reason = reason
        self.metadata = metadata
    }
}

/// Why a checkpoint was recorded.
public enum CheckpointReason: String, Sendable, Codable {
    case stateTransition
    case periodic
    case costThreshold
    case userAction
    case recovery
}

// MARK: - SessionJournal Actor

/// Append-only JSONL journal for session crash recovery.
/// Each session gets its own file at `{basePath}/{sessionId}.jsonl`.
public actor SessionJournal {
    private let basePath: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var pendingCoalesced: [String: SessionCheckpoint] = [:]
    private var coalesceTasks: [String: Task<Void, Never>] = [:]

    public init(basePath: String? = nil) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.basePath = basePath ?? "\(home)/.shiki/journal"
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    /// Append a checkpoint to the session's JSONL file.
    public func checkpoint(_ checkpoint: SessionCheckpoint) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: basePath) {
            try fm.createDirectory(atPath: basePath, withIntermediateDirectories: true)
        }

        let filePath = journalPath(for: checkpoint.sessionId)
        let data = try encoder.encode(checkpoint)
        guard var line = String(data: data, encoding: .utf8) else { return }
        line += "\n"

        if fm.fileExists(atPath: filePath) {
            let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: filePath))
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
        } else {
            fm.createFile(atPath: filePath, contents: Data(line.utf8))
        }
    }

    /// Buffer rapid checkpoints and only write the latest after a debounce period.
    public func coalescedCheckpoint(_ checkpoint: SessionCheckpoint, debounce: Duration = .seconds(2)) {
        let sid = checkpoint.sessionId
        pendingCoalesced[sid] = checkpoint

        // Cancel existing debounce task
        coalesceTasks[sid]?.cancel()

        // Schedule a new flush after debounce
        coalesceTasks[sid] = Task {
            do {
                try await Task.sleep(for: debounce)
            } catch {
                return // cancelled
            }
            await self.flushCoalesced(sessionId: sid)
        }
    }

    private func flushCoalesced(sessionId: String) {
        guard let checkpoint = pendingCoalesced.removeValue(forKey: sessionId) else { return }
        coalesceTasks.removeValue(forKey: sessionId)
        try? self.checkpoint(checkpoint)
    }

    /// Load all checkpoints for a session in order.
    public func loadCheckpoints(sessionId: String) throws -> [SessionCheckpoint] {
        let filePath = journalPath(for: sessionId)
        guard FileManager.default.fileExists(atPath: filePath) else { return [] }

        let content = try String(contentsOfFile: filePath, encoding: .utf8)
        return content.split(separator: "\n").compactMap { line in
            let data = Data(line.utf8)
            return try? decoder.decode(SessionCheckpoint.self, from: data)
        }
    }

    /// Remove journal files older than the given threshold. Returns count of pruned files.
    @discardableResult
    public func prune(olderThan seconds: TimeInterval) throws -> Int {
        let fm = FileManager.default
        guard fm.fileExists(atPath: basePath) else { return 0 }

        let cutoff = Date().addingTimeInterval(-seconds)
        let files = try fm.contentsOfDirectory(atPath: basePath)
        var pruned = 0

        for file in files where file.hasSuffix(".jsonl") {
            let filePath = "\(basePath)/\(file)"
            let attrs = try fm.attributesOfItem(atPath: filePath)
            if let modified = attrs[.modificationDate] as? Date, modified < cutoff {
                try fm.removeItem(atPath: filePath)
                pruned += 1
            }
        }

        return pruned
    }

    private func journalPath(for sessionId: String) -> String {
        "\(basePath)/\(sessionId).jsonl"
    }
}
