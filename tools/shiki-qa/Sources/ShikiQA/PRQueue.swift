import Foundation

// MARK: - PRQueueEntry

/// A PR in the review queue with precomputed metadata.
public struct PRQueueEntry: Sendable {
    public let number: Int
    public let title: String
    public let branch: String
    public let baseBranch: String
    public let additions: Int
    public let deletions: Int
    public let fileCount: Int
    public let risk: PRRiskLevel
    public let hasPrecomputedReview: Bool
    public let hasReviewState: Bool

    public init(
        number: Int, title: String, branch: String, baseBranch: String,
        additions: Int, deletions: Int, fileCount: Int,
        risk: PRRiskLevel, hasPrecomputedReview: Bool, hasReviewState: Bool
    ) {
        self.number = number
        self.title = title
        self.branch = branch
        self.baseBranch = baseBranch
        self.additions = additions
        self.deletions = deletions
        self.fileCount = fileCount
        self.risk = risk
        self.hasPrecomputedReview = hasPrecomputedReview
        self.hasReviewState = hasReviewState
    }
}

/// Risk level for a PR in the queue.
public enum PRRiskLevel: String, Sendable, Comparable {
    case low = "LOW"
    case medium = "MED"
    case high = "HIGH"
    case critical = "CRIT"

    public static func < (lhs: PRRiskLevel, rhs: PRRiskLevel) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    var sortOrder: Int {
        switch self {
        case .critical: 0
        case .high: 1
        case .medium: 2
        case .low: 3
        }
    }

    /// Heuristic risk from PR size.
    public static func fromSize(additions: Int, deletions: Int, files: Int) -> PRRiskLevel {
        let totalChange = additions + deletions
        if totalChange > 5000 || files > 50 { return .critical }
        if totalChange > 2000 || files > 20 { return .high }
        if totalChange > 500 || files > 10 { return .medium }
        return .low
    }
}

// MARK: - PRQueue

/// Manages the review queue for all open PRs.
public struct PRQueue: Sendable {
    let workspacePath: String

    public init(workspacePath: String) {
        self.workspacePath = workspacePath
    }

    /// Check if a precomputed review exists for a PR.
    public func hasPrecomputedReview(prNumber: Int) -> Bool {
        let path = "\(workspacePath)/docs/pr\(prNumber)-precomputed-review.md"
        return FileManager.default.fileExists(atPath: path)
    }

    /// Check if a review state (in-progress review) exists for a PR.
    public func hasReviewState(prNumber: Int) -> Bool {
        let path = "\(workspacePath)/docs/pr\(prNumber)-review-state.json"
        return FileManager.default.fileExists(atPath: path)
    }

    /// Sort entries by priority: risk (desc), then size (desc).
    public func sorted(_ entries: [PRQueueEntry]) -> [PRQueueEntry] {
        entries.sorted { a, b in
            if a.risk != b.risk { return a.risk < b.risk } // higher risk first
            return (a.additions + a.deletions) > (b.additions + b.deletions)
        }
    }
}
