// HistoryManager.swift — Git-linked test run history from SQLite
// Part of ShikkiTestRunner

import Foundation

// MARK: - GitInfoProvider

/// Protocol for retrieving git metadata. Abstracted for testing.
public protocol GitInfoProvider: Sendable {
    /// Returns the current git commit hash (short form).
    func currentGitHash() async throws -> String

    /// Returns the current branch name.
    func currentBranch() async throws -> String
}

/// Errors from git operations.
public enum GitInfoError: Error, Sendable, CustomStringConvertible {
    case commandFailed(String)
    case emptyOutput

    public var description: String {
        switch self {
        case .commandFailed(let msg): "Git command failed: \(msg)"
        case .emptyOutput: "Git command returned empty output"
        }
    }
}

/// Real git info provider that shells out to `git`.
public struct SystemGitInfoProvider: GitInfoProvider {
    private let processRunner: any ProcessRunner
    private let workingDirectory: String?

    public init(
        processRunner: any ProcessRunner = SystemProcessRunner(),
        workingDirectory: String? = nil
    ) {
        self.processRunner = processRunner
        self.workingDirectory = workingDirectory
    }

    public func currentGitHash() async throws -> String {
        let output = try await processRunner.run(
            executable: "/usr/bin/git",
            arguments: ["rev-parse", "HEAD"],
            workingDirectory: workingDirectory
        )
        let hash = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hash.isEmpty else { throw GitInfoError.emptyOutput }
        return hash
    }

    public func currentBranch() async throws -> String {
        let output = try await processRunner.run(
            executable: "/usr/bin/git",
            arguments: ["branch", "--show-current"],
            workingDirectory: workingDirectory
        )
        let branch = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branch.isEmpty else { throw GitInfoError.emptyOutput }
        return branch
    }
}

// MARK: - HistoryManager

/// Manages test run history linked to git commits and branches.
///
/// Wraps `SQLiteStore` with git-aware queries: list runs by commit,
/// filter by branch, and provide the git metadata for new runs.
public struct HistoryManager: Sendable {
    private let store: SQLiteStore
    private let gitProvider: any GitInfoProvider

    /// Initialize with a SQLite store and git info provider.
    ///
    /// - Parameters:
    ///   - store: The SQLite store for test history persistence.
    ///   - gitProvider: Provider for git hash and branch information.
    public init(
        store: SQLiteStore,
        gitProvider: any GitInfoProvider = SystemGitInfoProvider()
    ) {
        self.store = store
        self.gitProvider = gitProvider
    }

    // MARK: - Git Metadata

    /// Returns the current git commit hash.
    public func currentGitHash() async throws -> String {
        try await gitProvider.currentGitHash()
    }

    /// Returns the current git branch name.
    public func currentBranch() async throws -> String {
        try await gitProvider.currentBranch()
    }

    // MARK: - Run Management

    /// Start a new test run linked to the current git state.
    ///
    /// - Returns: The generated run ID.
    @discardableResult
    public func startRun() async throws -> String {
        let hash = try await gitProvider.currentGitHash()
        let branch = try? await gitProvider.currentBranch()
        return try store.recordRun(gitHash: hash, branch: branch)
    }

    /// Start a new test run with explicit git metadata.
    ///
    /// - Parameters:
    ///   - gitHash: The commit hash.
    ///   - branch: The branch name (optional).
    /// - Returns: The generated run ID.
    @discardableResult
    public func startRun(gitHash: String, branch: String? = nil) throws -> String {
        try store.recordRun(gitHash: gitHash, branch: branch)
    }

    // MARK: - Queries

    /// List recent test runs, most recent first.
    ///
    /// - Parameter limit: Maximum number of runs to return (default 20).
    /// - Returns: Array of test run rows ordered by start time descending.
    public func listRuns(limit: Int = 20) throws -> [TestRunRow] {
        try store.allRuns(limit: limit)
    }

    /// Fetch all test runs for a specific git commit hash.
    ///
    /// - Parameter hash: The git commit hash (full or prefix).
    /// - Returns: All runs matching the commit hash, most recent first.
    public func runsForCommit(hash: String) throws -> [TestRunRow] {
        try store.runsForGitHash(hash)
    }

    /// Fetch all test runs on a specific branch.
    ///
    /// - Parameter name: The branch name.
    /// - Returns: All runs on the branch, most recent first.
    public func runsForBranch(name: String) throws -> [TestRunRow] {
        try store.runsForBranch(name)
    }

    /// Fetch results for a specific test run.
    ///
    /// - Parameter runID: The run ID.
    /// - Returns: All test result rows for the run.
    public func resultsForRun(_ runID: String) throws -> [TestResultRow] {
        try store.resultsForRun(runID)
    }

    /// Fetch the most recent completed run (with finished_at set).
    ///
    /// - Returns: The most recent finished run, or nil if none.
    public func latestFinishedRun() throws -> TestRunRow? {
        try store.latestFinishedRun()
    }
}
