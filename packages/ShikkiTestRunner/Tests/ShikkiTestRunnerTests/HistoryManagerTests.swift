// HistoryManagerTests.swift — Tests for git-linked test run history
// Part of ShikkiTestRunnerTests

import Foundation
import Testing

@testable import ShikkiTestRunner

// MARK: - Mock GitInfoProvider

struct MockGitInfoProvider: GitInfoProvider {
    let hash: String
    let branch: String
    let shouldFail: Bool

    init(hash: String = "abc123def456", branch: String = "feature/test", shouldFail: Bool = false) {
        self.hash = hash
        self.branch = branch
        self.shouldFail = shouldFail
    }

    func currentGitHash() async throws -> String {
        if shouldFail { throw GitInfoError.commandFailed("mock failure") }
        return hash
    }

    func currentBranch() async throws -> String {
        if shouldFail { throw GitInfoError.commandFailed("mock failure") }
        return branch
    }
}

// MARK: - Tests

@Suite("HistoryManager")
struct HistoryManagerTests {

    // MARK: - Git Metadata

    @Test("Current git hash from provider")
    func currentGitHash() async throws {
        let store = try SQLiteStore(path: ":memory:")
        let manager = HistoryManager(
            store: store,
            gitProvider: MockGitInfoProvider(hash: "deadbeef1234")
        )

        let hash = try await manager.currentGitHash()
        #expect(hash == "deadbeef1234")
    }

    @Test("Current branch from provider")
    func currentBranch() async throws {
        let store = try SQLiteStore(path: ":memory:")
        let manager = HistoryManager(
            store: store,
            gitProvider: MockGitInfoProvider(branch: "develop")
        )

        let branch = try await manager.currentBranch()
        #expect(branch == "develop")
    }

    @Test("Git hash failure propagates error")
    func gitHashFailure() async throws {
        let store = try SQLiteStore(path: ":memory:")
        let manager = HistoryManager(
            store: store,
            gitProvider: MockGitInfoProvider(shouldFail: true)
        )

        await #expect(throws: GitInfoError.self) {
            _ = try await manager.currentGitHash()
        }
    }

    // MARK: - Run Management

    @Test("Start run links to git state")
    func startRunLinksGit() async throws {
        let store = try SQLiteStore(path: ":memory:")
        let manager = HistoryManager(
            store: store,
            gitProvider: MockGitInfoProvider(hash: "abc123", branch: "feature/w4")
        )

        let runID = try await manager.startRun()
        let run = try store.fetchRun(runID)

        #expect(run != nil)
        #expect(run?.gitHash == "abc123")
        #expect(run?.branchName == "feature/w4")
    }

    @Test("Start run with explicit git metadata")
    func startRunExplicit() throws {
        let store = try SQLiteStore(path: ":memory:")
        let manager = HistoryManager(
            store: store,
            gitProvider: MockGitInfoProvider()
        )

        let runID = try manager.startRun(gitHash: "explicit123", branch: "main")
        let run = try store.fetchRun(runID)

        #expect(run?.gitHash == "explicit123")
        #expect(run?.branchName == "main")
    }

    // MARK: - Listing

    @Test("List runs returns most recent first")
    func listRuns() throws {
        let store = try SQLiteStore(path: ":memory:")
        let manager = HistoryManager(
            store: store,
            gitProvider: MockGitInfoProvider()
        )

        _ = try manager.startRun(gitHash: "aaa111", branch: "main")
        _ = try manager.startRun(gitHash: "bbb222", branch: "develop")
        _ = try manager.startRun(gitHash: "ccc333", branch: "feature/x")

        let runs = try manager.listRuns(limit: 2)
        #expect(runs.count == 2)
        #expect(runs[0].gitHash == "ccc333")
        #expect(runs[1].gitHash == "bbb222")
    }

    // MARK: - Commit Filtering

    @Test("Runs for specific commit hash")
    func runsForCommit() throws {
        let store = try SQLiteStore(path: ":memory:")
        let manager = HistoryManager(
            store: store,
            gitProvider: MockGitInfoProvider()
        )

        _ = try manager.startRun(gitHash: "abc123", branch: "develop")
        _ = try manager.startRun(gitHash: "def456", branch: "main")
        _ = try manager.startRun(gitHash: "abc123", branch: "feature/retry")

        let runs = try manager.runsForCommit(hash: "abc123")
        #expect(runs.count == 2)
        #expect(runs.allSatisfy { $0.gitHash == "abc123" })
    }

    @Test("Runs for nonexistent commit returns empty")
    func runsForNonexistentCommit() throws {
        let store = try SQLiteStore(path: ":memory:")
        let manager = HistoryManager(
            store: store,
            gitProvider: MockGitInfoProvider()
        )

        let runs = try manager.runsForCommit(hash: "nonexistent")
        #expect(runs.isEmpty)
    }

    // MARK: - Branch Filtering

    @Test("Runs for specific branch")
    func runsForBranch() throws {
        let store = try SQLiteStore(path: ":memory:")
        let manager = HistoryManager(
            store: store,
            gitProvider: MockGitInfoProvider()
        )

        _ = try manager.startRun(gitHash: "aaa", branch: "develop")
        _ = try manager.startRun(gitHash: "bbb", branch: "main")
        _ = try manager.startRun(gitHash: "ccc", branch: "develop")

        let runs = try manager.runsForBranch(name: "develop")
        #expect(runs.count == 2)
        #expect(runs.allSatisfy { $0.branchName == "develop" })
    }

    @Test("Runs for nonexistent branch returns empty")
    func runsForNonexistentBranch() throws {
        let store = try SQLiteStore(path: ":memory:")
        let manager = HistoryManager(
            store: store,
            gitProvider: MockGitInfoProvider()
        )

        _ = try manager.startRun(gitHash: "aaa", branch: "main")
        let runs = try manager.runsForBranch(name: "feature/ghost")
        #expect(runs.isEmpty)
    }

    // MARK: - Latest Finished Run

    @Test("Latest finished run skips unfinished runs")
    func latestFinishedRun() throws {
        let store = try SQLiteStore(path: ":memory:")
        let manager = HistoryManager(
            store: store,
            gitProvider: MockGitInfoProvider()
        )

        let run1 = try manager.startRun(gitHash: "aaa", branch: "main")
        try store.finishRun(
            runID: run1,
            totalTests: 10, passed: 10, failed: 0, skipped: 0, durationMs: 100
        )

        // Run 2 is not finished
        _ = try manager.startRun(gitHash: "bbb", branch: "develop")

        let latest = try manager.latestFinishedRun()
        #expect(latest?.gitHash == "aaa")
        #expect(latest?.finishedAt != nil)
    }
}
