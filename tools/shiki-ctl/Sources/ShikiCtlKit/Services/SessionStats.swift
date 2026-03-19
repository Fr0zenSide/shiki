import Foundation
import Logging

// MARK: - Models

public struct ProjectStats: Sendable, Equatable {
    public let name: String
    public let insertions: Int
    public let deletions: Int
    public let commits: Int
    public let filesChanged: Int

    public init(name: String, insertions: Int, deletions: Int, commits: Int, filesChanged: Int) {
        self.name = name
        self.insertions = insertions
        self.deletions = deletions
        self.commits = commits
        self.filesChanged = filesChanged
    }

    /// True when insertions/deletions ratio is between 0.8 and 1.2 — indicates
    /// mature/beta stage where code is being refined rather than growing.
    public var isMatureStage: Bool {
        guard deletions > 0 else { return false }
        let ratio = Double(insertions) / Double(deletions)
        return ratio >= 0.8 && ratio <= 1.2
    }
}

public struct SessionSummary: Sendable {
    /// Stats computed since the last recorded session end.
    public let sinceSession: [ProjectStats]
    /// Aggregate stats over the last 7 days.
    public let weeklyAggregate: [ProjectStats]
    /// When the previous session ended (nil on first run).
    public let lastSessionEnd: Date?

    public init(sinceSession: [ProjectStats], weeklyAggregate: [ProjectStats], lastSessionEnd: Date?) {
        self.sinceSession = sinceSession
        self.weeklyAggregate = weeklyAggregate
        self.lastSessionEnd = lastSessionEnd
    }
}

// MARK: - Protocol

public protocol SessionStatsProviding: Sendable {
    func computeStats(workspace: String, projects: [String]) async -> SessionSummary
    func recordSessionEnd() throws
}

// MARK: - Concrete Implementation

public struct SessionStats: SessionStatsProviding, Sendable {
    private static let configDir = ".config/shiki"
    private static let timestampFile = "last-session"

    private let logger: Logger

    public init(logger: Logger = Logger(label: "shiki-ctl.session-stats")) {
        self.logger = logger
    }

    // MARK: - SessionStatsProviding

    public func computeStats(workspace: String, projects: [String]) async -> SessionSummary {
        let lastEnd = readLastSessionEnd()

        var sinceSession: [ProjectStats] = []
        var weekly: [ProjectStats] = []

        for project in projects {
            let projectPath = (workspace as NSString).appendingPathComponent(project)

            guard FileManager.default.fileExists(atPath: (projectPath as NSString).appendingPathComponent(".git")) else {
                logger.debug("Skipping \(project): not a git repo")
                continue
            }

            if let lastEnd {
                let timestamp = ISO8601DateFormatter().string(from: lastEnd)
                if let stats = await gitStats(at: projectPath, since: timestamp, projectName: project) {
                    sinceSession.append(stats)
                }
            }

            if let stats = await gitStats(at: projectPath, since: "7 days ago", projectName: project) {
                weekly.append(stats)
            }
        }

        return SessionSummary(
            sinceSession: sinceSession,
            weeklyAggregate: weekly,
            lastSessionEnd: lastEnd
        )
    }

    public func recordSessionEnd() throws {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(Self.configDir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let file = dir.appendingPathComponent(Self.timestampFile)
        let timestamp = ISO8601DateFormatter().string(from: Date())
        try timestamp.write(to: file, atomically: true, encoding: .utf8)
    }

    // MARK: - Private

    private func readLastSessionEnd() -> Date? {
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(Self.configDir)
            .appendingPathComponent(Self.timestampFile)

        guard let contents = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        return ISO8601DateFormatter().date(from: contents.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Run `git log --since=<since> --shortstat --oneline` and parse the aggregated output.
    private func gitStats(at path: String, since: String, projectName: String) async -> ProjectStats? {
        let output = runGit(args: [
            "log", "--since=\(since)", "--shortstat", "--oneline",
        ], at: path)

        guard let output, !output.isEmpty else { return nil }

        var totalInsertions = 0
        var totalDeletions = 0
        var totalFiles = 0
        var commits = 0

        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Shortstat lines look like: " 3 files changed, 45 insertions(+), 12 deletions(-)"
            if trimmed.contains("files changed") || trimmed.contains("file changed") {
                totalFiles += parseComponent(trimmed, suffix: "file")
                totalInsertions += parseComponent(trimmed, suffix: "insertion")
                totalDeletions += parseComponent(trimmed, suffix: "deletion")
            } else if !trimmed.isEmpty {
                // Oneline commit summaries count as commits
                commits += 1
            }
        }

        guard commits > 0 else { return nil }

        return ProjectStats(
            name: projectName,
            insertions: totalInsertions,
            deletions: totalDeletions,
            commits: commits,
            filesChanged: totalFiles
        )
    }

    /// Extract the integer before a keyword like "insertion" or "deletion" from a shortstat fragment.
    private func parseComponent(_ line: String, suffix: String) -> Int {
        // Split by commas, find the fragment containing the suffix, extract leading number
        let fragments = line.components(separatedBy: ",")
        guard let fragment = fragments.first(where: { $0.contains(suffix) }) else { return 0 }
        let digits = fragment.trimmingCharacters(in: .whitespaces)
            .components(separatedBy: .whitespaces)
            .first ?? ""
        return Int(digits) ?? 0
    }

    /// Synchronously run a git command and return stdout, or nil on failure.
    private func runGit(args: [String], at directory: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: directory)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe() // silence stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            logger.debug("git failed in \(directory): \(error)")
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Mock

public final class MockSessionStats: SessionStatsProviding, @unchecked Sendable {
    public var stubbedSummary: SessionSummary
    public private(set) var recordSessionEndCallCount = 0
    public private(set) var computeStatsCallCount = 0

    public init(
        stubbedSummary: SessionSummary = SessionSummary(
            sinceSession: [],
            weeklyAggregate: [],
            lastSessionEnd: nil
        )
    ) {
        self.stubbedSummary = stubbedSummary
    }

    public func computeStats(workspace: String, projects: [String]) async -> SessionSummary {
        computeStatsCallCount += 1
        return stubbedSummary
    }

    public func recordSessionEnd() throws {
        recordSessionEndCallCount += 1
    }
}
