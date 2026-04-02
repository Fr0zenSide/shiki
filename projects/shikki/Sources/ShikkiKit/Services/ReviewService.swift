import Foundation
import Logging

// MARK: - ReviewAnalysisProvider

/// Protocol for LLM-backed review analysis (AI-provider agnostic).
/// BR-CA-08: Swift code is the authoritative definition; the skill is the LLM instruction.
///
/// NOTE: Named ReviewAnalysisProvider to avoid conflict with ReviewProvider (PrePRGates).
/// ReviewProvider is for pre-PR gate operations (CTO review, slop scan).
/// ReviewAnalysisProvider is for PR-level code review analysis.
public protocol ReviewAnalysisProvider: Sendable {
    /// Run a review analysis prompt and return structured findings.
    func analyze(prompt: String, timeout: TimeInterval) async throws -> String
}

// MARK: - ReviewTarget

/// What the review command is operating on.
public enum ReviewTarget: Sendable, Equatable {
    /// Single PR review: `shikki review 42`
    case single(Int)
    /// Batch range: `shikki review --batch 14..18`
    case batch([Int])
    /// Pre-PR quality gates: `shikki review --pre-pr`
    case prePR
}

// MARK: - PRReviewFinding

/// A single finding from a PR review analysis.
///
/// NOTE: Named PRReviewFinding to avoid conflict with ReviewFinding (ReviewProvider.swift).
/// ReviewFinding is for pre-PR gate findings (severity: critical/warning/info).
/// PRReviewFinding is for PR review findings (severity: critical/important/minor, has reviewer).
public struct PRReviewFinding: Codable, Sendable, Equatable {
    public enum Severity: String, Codable, Sendable, Equatable {
        case critical
        case important
        case minor
    }

    public let severity: Severity
    public let reviewer: String
    public let file: String?
    public let line: Int?
    public let message: String

    public init(severity: Severity, reviewer: String, file: String? = nil, line: Int? = nil, message: String) {
        self.severity = severity
        self.reviewer = reviewer
        self.file = file
        self.line = line
        self.message = message
    }
}

// MARK: - ReviewVerdict

/// The recommendation from a review analysis.
public enum ReviewVerdict: String, Codable, Sendable, Equatable {
    case approve = "APPROVE"
    case changesRequested = "CHANGES_REQUESTED"
    case needsDiscussion = "NEEDS_DISCUSSION"

    /// Derive verdict from findings per pr-review.md recommendation logic.
    public static func from(findings: [PRReviewFinding]) -> ReviewVerdict {
        let criticalCount = findings.filter { $0.severity == .critical }.count
        let importantCount = findings.filter { $0.severity == .important }.count

        if criticalCount > 0 { return .changesRequested }
        if importantCount >= 3 { return .changesRequested }
        if importantCount >= 1 { return .needsDiscussion }
        return .approve
    }
}

// MARK: - PRMetadata

/// Metadata about a PR, loaded from `gh pr view`.
public struct PRMetadata: Codable, Sendable, Equatable {
    public let number: Int
    public let title: String
    public let author: String
    public let branch: String
    public let baseBranch: String
    public let additions: Int
    public let deletions: Int
    public let changedFiles: Int
    public let isDraft: Bool

    public init(
        number: Int, title: String, author: String,
        branch: String, baseBranch: String,
        additions: Int, deletions: Int, changedFiles: Int,
        isDraft: Bool
    ) {
        self.number = number
        self.title = title
        self.author = author
        self.branch = branch
        self.baseBranch = baseBranch
        self.additions = additions
        self.deletions = deletions
        self.changedFiles = changedFiles
        self.isDraft = isDraft
    }

    /// Total lines changed.
    public var totalLines: Int { additions + deletions }

    /// Size label for display.
    public var sizeLabel: String {
        "+\(additions)/-\(deletions) (\(changedFiles) files)"
    }
}

// MARK: - PRReviewResult

/// Outcome of a single PR review.
///
/// NOTE: Named PRReviewResult to avoid conflict with ReviewResult (ReviewProvider.swift).
/// ReviewResult is for CTO review gate output (passed/findings/summary).
/// PRReviewResult is for PR review output (prNumber/findings/verdict/filesReviewed).
public struct PRReviewResult: Codable, Sendable, Equatable {
    public let prNumber: Int
    public let findings: [PRReviewFinding]
    public let verdict: ReviewVerdict
    public let filesReviewed: Int
    public let totalFiles: Int
    public let reviewedAt: Date

    public init(
        prNumber: Int, findings: [PRReviewFinding], verdict: ReviewVerdict,
        filesReviewed: Int, totalFiles: Int, reviewedAt: Date = Date()
    ) {
        self.prNumber = prNumber
        self.findings = findings
        self.verdict = verdict
        self.filesReviewed = filesReviewed
        self.totalFiles = totalFiles
        self.reviewedAt = reviewedAt
    }
}

// MARK: - ReviewError

public enum ReviewError: Error, Sendable, Equatable {
    case invalidPRNumber(Int)
    case invalidRange(String)
    case ghNotAvailable
    case prNotFound(Int)
    case analysisFailure(String)
    case persistenceFailure(String)
}

// MARK: - PRRangeParser

/// Parses batch range notation (e.g. "14..18", "pr14..pr18").
public enum PRRangeParser {
    /// Parse a range string into an array of PR numbers.
    /// Accepts: "14..18", "pr14..pr18", "14..14" (single).
    /// Rejects: reversed ranges, non-numeric, missing dots.
    public static func parse(_ input: String) throws -> [Int] {
        let cleaned = input
            .replacingOccurrences(of: "pr", with: "")
            .replacingOccurrences(of: "PR", with: "")
            .replacingOccurrences(of: "#", with: "")

        let parts = cleaned.split(separator: ".", omittingEmptySubsequences: true)
        guard parts.count == 2 else {
            throw ReviewError.invalidRange("Expected format: N..M, got '\(input)'")
        }

        guard let start = Int(parts[0]), let end = Int(parts[1]) else {
            throw ReviewError.invalidRange("Non-numeric range: '\(input)'")
        }

        guard start > 0, end > 0 else {
            throw ReviewError.invalidRange("PR numbers must be positive: '\(input)'")
        }

        guard start <= end else {
            throw ReviewError.invalidRange("Reversed range: \(start)..\(end)")
        }

        return Array(start...end)
    }
}

// MARK: - ReviewProgress

/// Tracks review progress for persistence to `.shikki/reviews/`.
public struct ReviewProgress: Codable, Sendable, Equatable {
    public let prNumber: Int
    public var filesReviewed: Set<String>
    public var totalFiles: Int
    public var findings: [PRReviewFinding]
    public var startedAt: Date
    public var lastUpdatedAt: Date

    public init(prNumber: Int, totalFiles: Int) {
        self.prNumber = prNumber
        self.filesReviewed = []
        self.totalFiles = totalFiles
        self.findings = []
        self.startedAt = Date()
        self.lastUpdatedAt = Date()
    }

    /// Fraction of files reviewed (0.0 to 1.0).
    public var progress: Double {
        guard totalFiles > 0 else { return 0 }
        return Double(filesReviewed.count) / Double(totalFiles)
    }

    /// Whether all files have been reviewed.
    public var isComplete: Bool {
        filesReviewed.count >= totalFiles
    }
}

// MARK: - ReviewPersistence

/// Handles saving/loading review state to `.shikki/reviews/`.
public struct ReviewPersistence: Sendable {
    private let baseDirectory: String

    public init(baseDirectory: String? = nil) {
        self.baseDirectory = baseDirectory ?? Self.resolveBaseDirectory()
    }

    private static func resolveBaseDirectory() -> String {
        var dir = FileManager.default.currentDirectoryPath
        while dir != "/" {
            let shikkiDir = "\(dir)/.shikki"
            if FileManager.default.fileExists(atPath: shikkiDir) {
                return "\(shikkiDir)/reviews"
            }
            dir = (dir as NSString).deletingLastPathComponent
        }
        return "\(FileManager.default.currentDirectoryPath)/.shikki/reviews"
    }

    /// Directory for a specific PR's review state.
    public func reviewDirectory(for prNumber: Int) -> String {
        "\(baseDirectory)/pr\(prNumber)"
    }

    /// Save review progress to disk.
    public func save(_ progress: ReviewProgress) throws {
        let dir = reviewDirectory(for: progress.prNumber)
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir) {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(progress)
        let path = "\(dir)/progress.json"
        try data.write(to: URL(fileURLWithPath: path))
    }

    /// Load existing review progress, if any.
    public func load(prNumber: Int) -> ReviewProgress? {
        let path = "\(reviewDirectory(for: prNumber))/progress.json"
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ReviewProgress.self, from: data)
    }

    /// Save a completed review result.
    public func saveResult(_ result: PRReviewResult) throws {
        let dir = reviewDirectory(for: result.prNumber)
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir) {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(result)
        let path = "\(dir)/result.json"
        try data.write(to: URL(fileURLWithPath: path))
    }
}

// MARK: - ReviewService

/// Orchestrates the PR review pipeline.
/// BR-CA-08: Swift is the authoritative pipeline; pr-review.md is the LLM prompt body.
/// BR-CA-02: Pre-PR gates are compiled Swift, not markdown.
public struct ReviewService: Sendable {
    private let provider: any ReviewAnalysisProvider
    private let persistence: ReviewPersistence
    private let logger: Logger

    public init(
        provider: any ReviewAnalysisProvider,
        persistence: ReviewPersistence = ReviewPersistence(),
        logger: Logger = Logger(label: "shikki.review")
    ) {
        self.provider = provider
        self.persistence = persistence
        self.logger = logger
    }

    /// Load PR metadata from GitHub via `gh pr view`.
    public func loadPRMetadata(number: Int) async throws -> PRMetadata {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "gh", "pr", "view", "\(number)",
            "--json", "number,title,author,headRefName,baseRefName,additions,deletions,changedFiles,isDraft",
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let _ = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ReviewError.prNotFound(number)
        }

        guard let json = try JSONSerialization.jsonObject(with: outputData) as? [String: Any] else {
            throw ReviewError.prNotFound(number)
        }

        let authorDict = json["author"] as? [String: Any]
        let author = authorDict?["login"] as? String ?? "unknown"

        return PRMetadata(
            number: json["number"] as? Int ?? number,
            title: json["title"] as? String ?? "Untitled",
            author: author,
            branch: json["headRefName"] as? String ?? "unknown",
            baseBranch: json["baseRefName"] as? String ?? "develop",
            additions: json["additions"] as? Int ?? 0,
            deletions: json["deletions"] as? Int ?? 0,
            changedFiles: json["changedFiles"] as? Int ?? 0,
            isDraft: json["isDraft"] as? Bool ?? false
        )
    }

    /// Run the review pipeline for a single PR.
    /// Steps: load metadata -> check size -> analyze -> derive verdict -> persist.
    public func review(prNumber: Int, dryRun: Bool = false) async throws -> PRReviewResult {
        guard prNumber > 0 else {
            throw ReviewError.invalidPRNumber(prNumber)
        }

        logger.info("Starting review", metadata: ["pr": "\(prNumber)"])

        // 1. Load PR metadata
        let metadata = try await loadPRMetadata(number: prNumber)

        // 2. Size check — warn if epic-sized (>400 lines or >10 files)
        let isEpicSized = metadata.totalLines > 400 || metadata.changedFiles > 10
        if isEpicSized {
            logger.warning("Large PR detected", metadata: [
                "pr": "\(prNumber)",
                "lines": "\(metadata.totalLines)",
                "files": "\(metadata.changedFiles)",
            ])
        }

        // 3. Build analysis prompt
        let prompt = ReviewPromptBuilder.build(metadata: metadata)

        // 4. Run analysis via ReviewAnalysisProvider
        let analysisOutput: String
        do {
            analysisOutput = try await provider.analyze(prompt: prompt, timeout: 300)
        } catch {
            throw ReviewError.analysisFailure("Provider failed: \(error)")
        }

        // 5. Parse findings from analysis output
        let findings = ReviewFindingsParser.parse(analysisOutput)

        // 6. Derive verdict
        let verdict = ReviewVerdict.from(findings: findings)

        // 7. Build result
        let result = PRReviewResult(
            prNumber: prNumber,
            findings: findings,
            verdict: verdict,
            filesReviewed: metadata.changedFiles,
            totalFiles: metadata.changedFiles
        )

        // 8. Persist review state
        if !dryRun {
            do {
                try persistence.saveResult(result)
            } catch {
                logger.warning("Failed to persist review", metadata: ["error": "\(error)"])
            }
        }

        return result
    }

    /// Run batch review for a range of PRs in parallel.
    public func reviewBatch(prNumbers: [Int], dryRun: Bool = false) async throws -> [PRReviewResult] {
        try await withThrowingTaskGroup(of: PRReviewResult?.self) { group in
            for number in prNumbers {
                group.addTask {
                    do {
                        return try await self.review(prNumber: number, dryRun: dryRun)
                    } catch {
                        return nil
                    }
                }
            }

            var results: [PRReviewResult] = []
            for try await result in group {
                if let result {
                    results.append(result)
                }
            }
            // Sort by PR number to maintain consistent ordering
            return results.sorted { $0.prNumber < $1.prNumber }
        }
    }
}

// MARK: - ReviewPromptBuilder

/// Builds the LLM prompt for review analysis.
/// The prompt template corresponds to pr-review.md Phase 3 analysis.
public enum ReviewPromptBuilder {
    public static func build(metadata: PRMetadata) -> String {
        var lines: [String] = []

        lines.append("You are a senior code reviewer analyzing a pull request.")
        lines.append("")
        lines.append("## PR Details")
        lines.append("- PR #\(metadata.number): \(metadata.title)")
        lines.append("- Author: @\(metadata.author)")
        lines.append("- Branch: \(metadata.branch) -> \(metadata.baseBranch)")
        lines.append("- Size: \(metadata.sizeLabel)")
        if metadata.isDraft {
            lines.append("- Status: DRAFT")
        }
        lines.append("")
        lines.append("## Instructions")
        lines.append("Analyze the PR diff for:")
        lines.append("1. Architecture compliance, concurrency, error handling, performance")
        lines.append("2. Code hygiene, documentation, testing, formatting")
        lines.append("3. Security concerns")
        lines.append("")
        lines.append("## Output Format")
        lines.append("Return findings as a structured list, one per line:")
        lines.append("[SEVERITY] [REVIEWER] [FILE:LINE] Finding description")
        lines.append("")
        lines.append("Severity: CRITICAL, IMPORTANT, or MINOR")
        lines.append("Reviewer: @Sensei (architecture), @tech-expert (code quality)")

        return lines.joined(separator: "\n")
    }
}

// MARK: - ReviewFindingsParser

/// Parses structured findings from LLM output.
public enum ReviewFindingsParser {
    /// Parse findings from a raw analysis string.
    /// Expects lines like: [CRITICAL] [@Sensei] [Foo.swift:42] Message
    public static func parse(_ output: String) -> [PRReviewFinding] {
        let lines = output.components(separatedBy: .newlines)
        var findings: [PRReviewFinding] = []

        let pattern = /\[(CRITICAL|IMPORTANT|MINOR)\]\s*\[(@\w+)\]\s*(?:\[([^\]]*)\])?\s*(.*)/

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let match = trimmed.firstMatch(of: pattern) else { continue }

            let severityStr = String(match.1)
            let reviewer = String(match.2)
            let fileRef = match.3.map(String.init)
            let message = String(match.4).trimmingCharacters(in: .whitespaces)

            let severity: PRReviewFinding.Severity
            switch severityStr {
            case "CRITICAL": severity = .critical
            case "IMPORTANT": severity = .important
            default: severity = .minor
            }

            // Parse file:line from fileRef
            var file: String?
            var lineNumber: Int?
            if let ref = fileRef, !ref.isEmpty {
                let parts = ref.split(separator: ":", maxSplits: 1)
                file = String(parts[0])
                if parts.count > 1 {
                    lineNumber = Int(parts[1])
                }
            }

            findings.append(PRReviewFinding(
                severity: severity,
                reviewer: reviewer,
                file: file,
                line: lineNumber,
                message: message
            ))
        }

        return findings
    }
}
