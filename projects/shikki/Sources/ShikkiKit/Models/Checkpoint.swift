import Foundation

/// Unified checkpoint for shikki session persistence.
/// Replaces both PausedSessionManager and SessionJournal.
/// BR-20: Single file `~/.shikki/checkpoint.json`, atomic JSON overwrite.
/// BR-21: Schema with version, timestamp, hostname, fsmState, tmuxLayout, sessionStats, contextSnippet (≤4KB), dbSynced.
public struct Checkpoint: Sendable, Codable, Equatable {
    public static let currentVersion = 1
    public static let maxContextBytes = 4096

    public let version: Int
    public let timestamp: Date
    public let hostname: String
    public let fsmState: ShikkiState
    public let tmuxLayout: TmuxLayout?
    public let sessionStats: SessionSnapshot?
    public let contextSnippet: String?
    public let dbSynced: Bool

    public init(
        version: Int = Checkpoint.currentVersion,
        timestamp: Date = Date(),
        hostname: String,
        fsmState: ShikkiState,
        tmuxLayout: TmuxLayout? = nil,
        sessionStats: SessionSnapshot? = nil,
        contextSnippet: String? = nil,
        dbSynced: Bool = false
    ) {
        self.version = version
        self.timestamp = timestamp
        self.hostname = hostname
        self.fsmState = fsmState
        self.tmuxLayout = tmuxLayout
        self.sessionStats = sessionStats
        self.dbSynced = dbSynced

        // BR-21: Truncate context snippet to 4KB max
        if let snippet = contextSnippet, snippet.utf8.count > Checkpoint.maxContextBytes {
            let data = Data(snippet.utf8.prefix(Checkpoint.maxContextBytes))
            self.contextSnippet = String(data: data, encoding: .utf8)
        } else {
            self.contextSnippet = contextSnippet
        }
    }
}

/// Tmux pane layout snapshot.
public struct TmuxLayout: Sendable, Codable, Equatable {
    public let paneCount: Int
    public let layoutString: String
    public let paneLabels: [String]

    public init(paneCount: Int, layoutString: String, paneLabels: [String] = []) {
        self.paneCount = paneCount
        self.layoutString = layoutString
        self.paneLabels = paneLabels
    }
}

/// Session statistics snapshot.
public struct SessionSnapshot: Sendable, Codable, Equatable {
    public let startedAt: Date
    public let branch: String
    public let commitCount: Int
    public let linesChanged: Int

    public init(startedAt: Date, branch: String, commitCount: Int = 0, linesChanged: Int = 0) {
        self.startedAt = startedAt
        self.branch = branch
        self.commitCount = commitCount
        self.linesChanged = linesChanged
    }
}
