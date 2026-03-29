import Foundation

// MARK: - Provenance

/// Where a recovered item came from.
/// BR-03: Each recovered item carries a provenance field.
/// K1: Provenance is the "gold in the cracks" — makes recovery trustworthy.
public enum Provenance: String, Sendable, Codable, Equatable {
    case db
    case checkpoint
    case git
    case inferred
}

// MARK: - ItemKind

/// What kind of recovered item this is.
public enum ItemKind: String, Sendable, Codable, Equatable {
    case event
    case commit
    case checkpoint
    case decision
    case file
}

// MARK: - Staleness

/// BR-20: Staleness indicator based on time since last event.
public enum Staleness: String, Sendable, Codable, Equatable {
    case fresh    // < 1h
    case recent   // 1-6h
    case stale    // 6-24h
    case ancient  // > 24h

    /// Compute staleness from a date relative to now.
    public static func from(lastActivity: Date, now: Date = Date()) -> Staleness {
        let elapsed = now.timeIntervalSince(lastActivity)
        let hours = elapsed / 3600

        switch hours {
        case ..<1:
            return .fresh
        case 1..<6:
            return .recent
        case 6..<24:
            return .stale
        default:
            return .ancient
        }
    }
}

// MARK: - RecoveredItem

/// A single item recovered from any source with provenance tracking.
/// BR-03: provenance field on every item.
public struct RecoveredItem: Sendable, Codable, Equatable {
    public let id: String
    public let timestamp: Date
    public let provenance: Provenance
    public let kind: ItemKind
    public let summary: String
    public let detail: String?

    public init(
        id: String = UUID().uuidString,
        timestamp: Date,
        provenance: Provenance,
        kind: ItemKind,
        summary: String,
        detail: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.provenance = provenance
        self.kind = kind
        self.summary = summary
        self.detail = detail
    }
}

// MARK: - SourceStatus

/// Status of a single recovery source.
public enum SourceStatus: String, Sendable, Codable, Equatable {
    case available
    case partial
    case corrupted
    case unavailable
}

// MARK: - SourceResult

/// Result from a single recovery source (DB, checkpoint, or git).
public struct SourceResult: Sendable, Codable, Equatable {
    public let name: String
    public let status: SourceStatus
    public let itemCount: Int
    public let score: Int
    public let error: String?

    public init(
        name: String,
        status: SourceStatus,
        itemCount: Int,
        score: Int,
        error: String? = nil
    ) {
        self.name = name
        self.status = status
        self.itemCount = itemCount
        self.score = score
        self.error = error
    }
}

// MARK: - WorkspaceSnapshot

/// Git workspace state snapshot for recovery context.
/// BR-24: Never reads file contents, diffs, or .env files.
public struct WorkspaceSnapshot: Sendable, Codable, Equatable {
    public let branch: String?
    public let recentCommits: [CommitInfo]
    public let modifiedFiles: [String]
    public let untrackedFiles: [String]
    public let worktrees: [WorktreeInfo]
    public let aheadBehind: AheadBehind?

    public init(
        branch: String? = nil,
        recentCommits: [CommitInfo] = [],
        modifiedFiles: [String] = [],
        untrackedFiles: [String] = [],
        worktrees: [WorktreeInfo] = [],
        aheadBehind: AheadBehind? = nil
    ) {
        self.branch = branch
        self.recentCommits = recentCommits
        self.modifiedFiles = modifiedFiles
        self.untrackedFiles = untrackedFiles
        self.worktrees = worktrees
        self.aheadBehind = aheadBehind
    }
}

/// A single commit's metadata (no diffs, no file contents).
public struct CommitInfo: Sendable, Codable, Equatable {
    public let hash: String
    public let message: String
    public let author: String
    public let timestamp: Date

    public init(hash: String, message: String, author: String, timestamp: Date) {
        self.hash = hash
        self.message = message
        self.author = author
        self.timestamp = timestamp
    }
}

/// Worktree metadata.
public struct WorktreeInfo: Sendable, Codable, Equatable {
    public let path: String
    public let branch: String?

    public init(path: String, branch: String?) {
        self.path = path
        self.branch = branch
    }
}

/// Ahead/behind tracking info.
public struct AheadBehind: Sendable, Codable, Equatable {
    public let ahead: Int
    public let behind: Int

    public init(ahead: Int, behind: Int) {
        self.ahead = ahead
        self.behind = behind
    }
}

// MARK: - TimeWindow

/// Time window for context recovery queries.
/// BR-01: Default 2h, max 7d.
public struct TimeWindow: Sendable, Codable, Equatable {
    public let since: Date
    public let until: Date

    public init(since: Date, until: Date = Date()) {
        self.since = since
        self.until = until
    }

    /// Create a time window from a duration (looking back from now).
    public static func lookback(seconds: TimeInterval, from now: Date = Date()) -> TimeWindow {
        TimeWindow(since: now.addingTimeInterval(-seconds), until: now)
    }

    /// Duration in seconds.
    public var duration: TimeInterval {
        until.timeIntervalSince(since)
    }
}

// MARK: - ConfidenceScore

/// Weighted confidence calculation for recovery context.
/// BR-16: Percentage (0-100), weighted: DB 50%, checkpoint 30%, git 20%.
/// BR-17: DB score: 100 if >10 events, 70 if 1-10, 0 if empty/unreachable.
/// BR-18: Checkpoint: 100 if fresh, 50 if stale, 0 if none.
/// BR-19: Git: 100 if commits in window, 50 if dirty, 0 if clean.
public struct ConfidenceScore: Sendable, Codable, Equatable {
    public let dbScore: Int
    public let checkpointScore: Int
    public let gitScore: Int
    public let overall: Int

    public static let dbWeight: Double = 0.50
    public static let checkpointWeight: Double = 0.30
    public static let gitWeight: Double = 0.20

    public init(dbScore: Int, checkpointScore: Int, gitScore: Int) {
        self.dbScore = dbScore
        self.checkpointScore = checkpointScore
        self.gitScore = gitScore
        self.overall = Self.computeOverall(
            dbScore: dbScore,
            checkpointScore: checkpointScore,
            gitScore: gitScore
        )
    }

    /// Compute weighted average.
    public static func computeOverall(dbScore: Int, checkpointScore: Int, gitScore: Int) -> Int {
        let weighted = Double(dbScore) * dbWeight
            + Double(checkpointScore) * checkpointWeight
            + Double(gitScore) * gitWeight
        return Int(weighted.rounded())
    }

    /// Compute DB source score based on event count.
    /// BR-17: 100 if >10 events, 70 if 1-10, 0 if unreachable/empty.
    public static func dbSourceScore(eventCount: Int, available: Bool) -> Int {
        guard available else { return 0 }
        if eventCount > 10 { return 100 }
        if eventCount >= 1 { return 70 }
        return 0
    }

    /// Compute checkpoint source score.
    /// BR-18: 100 if fresh (within window), 50 if stale, 0 if none.
    public static func checkpointSourceScore(exists: Bool, withinWindow: Bool) -> Int {
        guard exists else { return 0 }
        return withinWindow ? 100 : 50
    }

    /// Compute git source score.
    /// BR-19: 100 if commits in window, 50 if dirty, 0 if clean/no commits.
    public static func gitSourceScore(hasCommits: Bool, isDirty: Bool) -> Int {
        if hasCommits { return 100 }
        if isDirty { return 50 }
        return 0
    }
}

// MARK: - RecoveryContext

/// Unified recovery result from all sources.
/// The main output of ContextRecoveryService.
public struct RecoveryContext: Sendable, Codable, Equatable {
    public let recoveredAt: Date
    public let timeWindow: TimeWindow
    public let confidence: ConfidenceScore
    public let staleness: Staleness
    public let sources: [SourceResult]
    public let timeline: [RecoveredItem]
    public let workspace: WorkspaceSnapshot
    public let errors: [String]
    public let pendingDecisions: [String]

    public init(
        recoveredAt: Date = Date(),
        timeWindow: TimeWindow,
        confidence: ConfidenceScore,
        staleness: Staleness,
        sources: [SourceResult],
        timeline: [RecoveredItem],
        workspace: WorkspaceSnapshot,
        errors: [String] = [],
        pendingDecisions: [String] = []
    ) {
        self.recoveredAt = recoveredAt
        self.timeWindow = timeWindow
        self.confidence = confidence
        self.staleness = staleness
        self.sources = sources
        self.timeline = timeline
        self.workspace = workspace
        self.errors = errors
        self.pendingDecisions = pendingDecisions
    }
}
