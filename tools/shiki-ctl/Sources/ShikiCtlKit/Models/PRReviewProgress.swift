import Foundation

// MARK: - PR Review Progress Model

/// Tracks file-level review state for a PR across sessions.
/// Persisted to `docs/prN-cache/review-state.json`.
public struct PRReviewProgress: Codable, Sendable {
    public let prNumber: Int
    public var reviewedFiles: [ReviewedFile]
    public var lastReviewedAt: Date?
    public var lastReviewedCommit: String

    public init(prNumber: Int, reviewedFiles: [ReviewedFile] = [], lastReviewedAt: Date? = nil, lastReviewedCommit: String = "") {
        self.prNumber = prNumber
        self.reviewedFiles = reviewedFiles
        self.lastReviewedAt = lastReviewedAt
        self.lastReviewedCommit = lastReviewedCommit
    }

    // MARK: - ReviewedFile

    public struct ReviewedFile: Codable, Sendable {
        public let path: String
        public var status: ReviewStatus
        public var reviewedAt: Date?
        public var comment: String?          // legacy single comment (backward compat)
        public var comments: [ReviewComment] // line-targeted comments
        public var reviewedAtCommit: String?

        public init(path: String, status: ReviewStatus = .pending, reviewedAt: Date? = nil, comment: String? = nil, comments: [ReviewComment] = [], reviewedAtCommit: String? = nil) {
            self.path = path
            self.status = status
            self.reviewedAt = reviewedAt
            self.comment = comment
            self.comments = comments
            self.reviewedAtCommit = reviewedAtCommit
        }
    }

    /// A comment targeting a specific line or range in a file.
    public struct ReviewComment: Codable, Sendable {
        public let message: String
        public let line: Int?           // single line (e.g. L42)
        public let endLine: Int?        // end of range (e.g. L42-L50 → line=42, endLine=50)
        public let createdAt: Date
        public let commit: String?

        public init(message: String, line: Int? = nil, endLine: Int? = nil, createdAt: Date = Date(), commit: String? = nil) {
            self.message = message
            self.line = line
            self.endLine = endLine
            self.createdAt = createdAt
            self.commit = commit
        }

        /// Display format: "L42: message" or "L42-50: message" or "message"
        public var displayText: String {
            if let line, let endLine {
                return "L\(line)-\(endLine): \(message)"
            } else if let line {
                return "L\(line): \(message)"
            }
            return message
        }
    }

    // MARK: - ReviewStatus

    public enum ReviewStatus: String, Codable, Sendable {
        case pending    // [ ]  -- not yet reviewed
        case reviewed   // [✓]  -- marked as read
        case commented  // [✎]  -- has comment attached
        case changed    // [!]  -- was reviewed but file changed since

        /// Status indicator for display
        public var indicator: String {
            switch self {
            case .pending:   return "[ ]"
            case .reviewed:  return "[✓]"
            case .commented: return "[✎]"
            case .changed:   return "[!]"
            }
        }
    }

    // MARK: - Mutations

    /// Mark a single file as reviewed at the given commit.
    public mutating func markFileReviewed(_ path: String, at date: Date = Date(), commit: String) {
        guard let index = reviewedFiles.firstIndex(where: { $0.path == path }) else { return }
        reviewedFiles[index].status = .reviewed
        reviewedFiles[index].reviewedAt = date
        reviewedFiles[index].reviewedAtCommit = commit
        lastReviewedAt = date
        lastReviewedCommit = commit
    }

    /// Mark all files as reviewed at the given commit.
    public mutating func markAllReviewed(at date: Date = Date(), commit: String) {
        for i in reviewedFiles.indices {
            reviewedFiles[i].status = .reviewed
            reviewedFiles[i].reviewedAt = date
            reviewedFiles[i].reviewedAtCommit = commit
        }
        lastReviewedAt = date
        lastReviewedCommit = commit
    }

    /// Reset all files to pending, clear global timestamps.
    public mutating func resetAll() {
        for i in reviewedFiles.indices {
            reviewedFiles[i].status = .pending
            reviewedFiles[i].reviewedAt = nil
            reviewedFiles[i].comment = nil
            reviewedFiles[i].comments = []
            reviewedFiles[i].reviewedAtCommit = nil
        }
        lastReviewedAt = nil
        lastReviewedCommit = ""
    }

    /// Attach a comment to a file, optionally targeting a line or range.
    public mutating func addComment(to path: String, message: String, line: Int? = nil, endLine: Int? = nil, at date: Date = Date(), commit: String) {
        guard let index = reviewedFiles.firstIndex(where: { $0.path == path }) else { return }
        reviewedFiles[index].status = .commented
        reviewedFiles[index].comment = message // legacy compat
        reviewedFiles[index].comments.append(
            ReviewComment(message: message, line: line, endLine: endLine, createdAt: date, commit: commit)
        )
        reviewedFiles[index].reviewedAt = date
        reviewedFiles[index].reviewedAtCommit = commit
        lastReviewedAt = date
        lastReviewedCommit = commit
    }

    /// Apply delta detection: files changed between lastReviewedCommit and current HEAD.
    /// Only files previously `reviewed` or `commented` get reset to `changed`.
    public mutating func applyDelta(changedPaths: [String]) {
        let changedSet = Set(changedPaths)
        for i in reviewedFiles.indices {
            if changedSet.contains(reviewedFiles[i].path) {
                if reviewedFiles[i].status == .reviewed || reviewedFiles[i].status == .commented {
                    reviewedFiles[i].status = .changed
                }
            }
        }
    }

    /// Prune files no longer in the PR diff.
    public mutating func prune(currentPaths: [String]) {
        let currentSet = Set(currentPaths)
        reviewedFiles = reviewedFiles.filter { currentSet.contains($0.path) }
    }

    /// Files that need attention: pending + changed + commented.
    public var deltaFiles: [ReviewedFile] {
        reviewedFiles.filter { $0.status != .reviewed }
    }

    /// Files with comments.
    public func commentedFiles(includeResolved: Bool = false) -> [ReviewedFile] {
        if includeResolved {
            return reviewedFiles.filter { $0.comment != nil }
        }
        return reviewedFiles.filter { $0.status == .commented }
    }

    // MARK: - Progress

    public var reviewedCount: Int {
        reviewedFiles.filter { $0.status == .reviewed || $0.status == .commented }.count
    }

    public var totalCount: Int {
        reviewedFiles.count
    }

    public var progressFraction: String {
        "\(reviewedCount)/\(totalCount) reviewed (\(progressPercent)%)"
    }

    public var progressPercent: Int {
        guard totalCount > 0 else { return 0 }
        return (reviewedCount * 100) / totalCount
    }

    public var isComplete: Bool {
        totalCount > 0 && reviewedCount == totalCount && !reviewedFiles.contains(where: { $0.status == .changed })
    }

    /// 20-char progress bar
    public var progressBar: String {
        guard totalCount > 0 else { return String(repeating: "░", count: 20) }
        let filled = (reviewedCount * 20) / totalCount
        let empty = 20 - filled
        return String(repeating: "█", count: filled) + String(repeating: "░", count: empty)
    }

    // MARK: - File Matching

    /// Fuzzy file matching: basename or path suffix.
    /// Returns the matching file path, or throws with candidates on ambiguity.
    public func resolveFile(_ query: String) throws -> String {
        // Exact match first
        if let file = reviewedFiles.first(where: { $0.path == query }) {
            return file.path
        }

        // Basename match
        let candidates = reviewedFiles.filter { path in
            let basename = (path.path as NSString).lastPathComponent
            return basename.localizedCaseInsensitiveContains(query)
                || path.path.hasSuffix(query)
        }

        if candidates.count == 1 {
            return candidates[0].path
        } else if candidates.isEmpty {
            throw PRReviewError.fileNotFound(query)
        } else {
            throw PRReviewError.ambiguousMatch(query, candidates.map(\.path))
        }
    }
}

// MARK: - Errors

public enum PRReviewError: Error, CustomStringConvertible {
    case fileNotFound(String)
    case ambiguousMatch(String, [String])
    case noReviewState(Int)

    public var description: String {
        switch self {
        case .fileNotFound(let query):
            return "No file matching '\(query)' in PR"
        case .ambiguousMatch(let query, let candidates):
            return "Ambiguous match for '\(query)':\n" + candidates.map { "  - \($0)" }.joined(separator: "\n")
        case .noReviewState(let pr):
            return "No review state for PR #\(pr)"
        }
    }
}
