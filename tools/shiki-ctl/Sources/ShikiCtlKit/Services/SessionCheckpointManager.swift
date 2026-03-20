import Foundation
import Logging

/// Manages session checkpoints for pause/resume functionality.
/// Stores session state as JSON files in ~/.shiki/sessions/.
public struct PausedSessionManager: Sendable {
    private let sessionsDir: String
    private let logger = Logger(label: "shiki.session-checkpoint")

    public init(sessionsDir: String = "~/.shiki/sessions") {
        self.sessionsDir = (sessionsDir as NSString).expandingTildeInPath
    }

    // MARK: - Pause (save checkpoint)

    public func pause(checkpoint: PausedSession) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: sessionsDir) {
            try fm.createDirectory(atPath: sessionsDir, withIntermediateDirectories: true)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(checkpoint)

        let path = "\(sessionsDir)/\(checkpoint.sessionId).json"
        try data.write(to: URL(fileURLWithPath: path))
        logger.info("Session paused: \(checkpoint.sessionId) at \(path)")
    }

    // MARK: - Resume (load checkpoint)

    public func resume(sessionId: String? = nil) throws -> PausedSession? {
        if let id = sessionId {
            return try load(sessionId: id)
        }
        // No ID: return most recent
        return try listCheckpoints().first
    }

    // MARK: - List available sessions

    public func listCheckpoints() throws -> [PausedSession] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sessionsDir) else { return [] }

        let files = try fm.contentsOfDirectory(atPath: sessionsDir)
            .filter { $0.hasSuffix(".json") }
            .sorted(by: >) // newest first by filename (ISO timestamp prefix)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return files.compactMap { file in
            let path = "\(sessionsDir)/\(file)"
            guard let data = fm.contents(atPath: path) else { return nil }
            return try? decoder.decode(PausedSession.self, from: data)
        }.sorted { $0.pausedAt > $1.pausedAt }
    }

    // MARK: - Clean old sessions (keep last N)

    public func cleanup(keep: Int = 10) throws {
        let checkpoints = try listCheckpoints()
        guard checkpoints.count > keep else { return }

        let toRemove = checkpoints.dropFirst(keep)
        for cp in toRemove {
            let path = "\(sessionsDir)/\(cp.sessionId).json"
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    // MARK: - Build context injection for Claude

    public func buildResumeContext(checkpoint: PausedSession) -> String {
        var lines: [String] = []
        lines.append("# Session Resume — \(checkpoint.sessionId)")
        lines.append("Paused: \(ISO8601DateFormatter().string(from: checkpoint.pausedAt))")
        lines.append("Branch: \(checkpoint.branch)")
        lines.append("")

        if let summary = checkpoint.summary {
            lines.append("## Last Session Summary")
            lines.append(summary)
            lines.append("")
        }

        if !checkpoint.activeTasks.isEmpty {
            lines.append("## Active Tasks")
            for task in checkpoint.activeTasks {
                lines.append("- \(task)")
            }
            lines.append("")
        }

        if !checkpoint.pendingPRs.isEmpty {
            lines.append("## Pending PRs")
            for pr in checkpoint.pendingPRs {
                lines.append("- #\(pr)")
            }
            lines.append("")
        }

        if !checkpoint.decisions.isEmpty {
            lines.append("## Recent Decisions")
            for decision in checkpoint.decisions.prefix(5) {
                lines.append("- \(decision)")
            }
            lines.append("")
        }

        if let nextAction = checkpoint.nextAction {
            lines.append("## Next Action")
            lines.append(nextAction)
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Private

    private func load(sessionId: String) throws -> PausedSession? {
        let path = "\(sessionsDir)/\(sessionId).json"
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PausedSession.self, from: data)
    }
}

// MARK: - PausedSession Model

public struct PausedSession: Codable, Sendable {
    public let sessionId: String
    public let pausedAt: Date
    public let branch: String
    public let summary: String?
    public let activeTasks: [String]
    public let pendingPRs: [Int]
    public let decisions: [String]
    public let nextAction: String?
    public let workspaceRoot: String
    public let personality: [String]  // behavioral observations

    public init(
        sessionId: String = UUID().uuidString.prefix(8).lowercased() + "-" + ISO8601DateFormatter().string(from: Date()).prefix(10),
        pausedAt: Date = Date(),
        branch: String,
        summary: String? = nil,
        activeTasks: [String] = [],
        pendingPRs: [Int] = [],
        decisions: [String] = [],
        nextAction: String? = nil,
        workspaceRoot: String = FileManager.default.currentDirectoryPath,
        personality: [String] = []
    ) {
        self.sessionId = String(sessionId)
        self.pausedAt = pausedAt
        self.branch = branch
        self.summary = summary
        self.activeTasks = activeTasks
        self.pendingPRs = pendingPRs
        self.decisions = decisions
        self.nextAction = nextAction
        self.workspaceRoot = workspaceRoot
        self.personality = personality
    }
}
