// MARK: - SQLiteStoreTests.swift
// ShikkiTestRunner — Tests for SQLite persistence layer

import Foundation
import Testing

@testable import ShikkiTestRunner

@Suite("SQLiteStore")
struct SQLiteStoreTests {

    // MARK: - Schema Creation

    @Test("Create in-memory database with schema")
    func createInMemoryDB() throws {
        let store = try SQLiteStore(path: ":memory:")
        // If we get here without throwing, schema was created
        #expect(store.path == ":memory:")
    }

    // MARK: - Record Run

    @Test("Record a test run and fetch it")
    func recordAndFetchRun() throws {
        let store = try SQLiteStore(path: ":memory:")
        let runID = try store.recordRun(gitHash: "abc123", branch: "feature/test")

        let run = try store.fetchRun(runID)
        #expect(run != nil)
        #expect(run?.runID == runID)
        #expect(run?.gitHash == "abc123")
        #expect(run?.branchName == "feature/test")
        #expect(run?.finishedAt == nil)
    }

    @Test("Record run with nil branch")
    func recordRunNilBranch() throws {
        let store = try SQLiteStore(path: ":memory:")
        let runID = try store.recordRun(gitHash: "def456")

        let run = try store.fetchRun(runID)
        #expect(run?.branchName == nil)
    }

    // MARK: - Record Group

    @Test("Record a group and fetch it")
    func recordAndFetchGroup() throws {
        let store = try SQLiteStore(path: ":memory:")
        let runID = try store.recordRun(gitHash: "abc123")
        let groupID = try store.recordGroup(runID: runID, scope: "nats")

        let groups = try store.groupsForRun(runID)
        #expect(groups.count == 1)
        #expect(groups[0].id == groupID)
        #expect(groups[0].scopeName == "nats")
        #expect(groups[0].runID == runID)
    }

    @Test("Record multiple groups for one run")
    func multipleGroupsPerRun() throws {
        let store = try SQLiteStore(path: ":memory:")
        let runID = try store.recordRun(gitHash: "abc123")
        _ = try store.recordGroup(runID: runID, scope: "nats")
        _ = try store.recordGroup(runID: runID, scope: "flywheel")
        _ = try store.recordGroup(runID: runID, scope: "tui")

        let groups = try store.groupsForRun(runID)
        #expect(groups.count == 3)
        let scopes = groups.map(\.scopeName)
        #expect(scopes.contains("nats"))
        #expect(scopes.contains("flywheel"))
        #expect(scopes.contains("tui"))
    }

    // MARK: - Record Result

    @Test("Record a test result and fetch it")
    func recordAndFetchResult() throws {
        let store = try SQLiteStore(path: ":memory:")
        let runID = try store.recordRun(gitHash: "abc123")
        let groupID = try store.recordGroup(runID: runID, scope: "kernel")

        _ = try store.recordResult(
            runID: runID,
            groupID: groupID,
            testFile: "KernelTests.swift",
            testName: "testBoot",
            suiteName: "KernelTests",
            status: .passed,
            durationMs: 42
        )

        let results = try store.resultsForRun(runID)
        #expect(results.count == 1)
        #expect(results[0].testName == "testBoot")
        #expect(results[0].suiteName == "KernelTests")
        #expect(results[0].status == .passed)
        #expect(results[0].durationMs == 42)
        #expect(results[0].groupID == groupID)
    }

    @Test("Record failed result with error details")
    func recordFailedResult() throws {
        let store = try SQLiteStore(path: ":memory:")
        let runID = try store.recordRun(gitHash: "abc123")

        _ = try store.recordResult(
            runID: runID,
            testFile: "SafetyTests.swift",
            testName: "testBudgetACL",
            status: .failed,
            durationMs: 1,
            error: "TOCTOU: concurrent check both passed",
            errorFile: "SafetyTests.swift:42:9"
        )

        let results = try store.resultsForRun(runID)
        #expect(results.count == 1)
        #expect(results[0].status == .failed)
        #expect(results[0].errorMessage == "TOCTOU: concurrent check both passed")
        #expect(results[0].errorFile == "SafetyTests.swift:42:9")
    }

    @Test("Record timeout result")
    func recordTimeoutResult() throws {
        let store = try SQLiteStore(path: ":memory:")
        let runID = try store.recordRun(gitHash: "abc123")

        _ = try store.recordResult(
            runID: runID,
            testFile: "HeartbeatTests.swift",
            testName: "testLoop",
            status: .timeout,
            durationMs: 5000,
            error: "Test exceeded 5s timeout"
        )

        let results = try store.resultsForRun(runID)
        #expect(results[0].status == .timeout)
    }

    @Test("Record result with raw output")
    func recordWithRawOutput() throws {
        let store = try SQLiteStore(path: ":memory:")
        let runID = try store.recordRun(gitHash: "abc123")
        let rawLog = "[INFO] Kernel booting...\n[WARN] Service timeout\n[ERROR] Connection refused"

        _ = try store.recordResult(
            runID: runID,
            testFile: "KernelTests.swift",
            testName: "testBootLog",
            status: .passed,
            rawOutput: rawLog
        )

        let results = try store.resultsForRun(runID)
        #expect(results[0].rawOutput == rawLog)
    }

    // MARK: - Finish Run

    @Test("Finish run sets summary counts")
    func finishRun() throws {
        let store = try SQLiteStore(path: ":memory:")
        let runID = try store.recordRun(gitHash: "abc123", branch: "develop")

        try store.finishRun(
            runID: runID,
            totalTests: 100,
            passed: 97,
            failed: 2,
            skipped: 1,
            durationMs: 1200
        )

        let run = try store.fetchRun(runID)
        #expect(run?.totalTests == 100)
        #expect(run?.passed == 97)
        #expect(run?.failed == 2)
        #expect(run?.skipped == 1)
        #expect(run?.durationMs == 1200)
        #expect(run?.finishedAt != nil)
    }

    // MARK: - Finish Group

    @Test("Finish group sets summary counts")
    func finishGroup() throws {
        let store = try SQLiteStore(path: ":memory:")
        let runID = try store.recordRun(gitHash: "abc123")
        let groupID = try store.recordGroup(runID: runID, scope: "nats")

        try store.finishGroup(
            groupID: groupID,
            totalTests: 57,
            passed: 55,
            failed: 2,
            skipped: 0,
            durationMs: 300
        )

        let groups = try store.groupsForRun(runID)
        #expect(groups[0].totalTests == 57)
        #expect(groups[0].passed == 55)
        #expect(groups[0].failed == 2)
        #expect(groups[0].durationMs == 300)
    }

    // MARK: - History Query

    @Test("History for test name across runs")
    func historyForTest() throws {
        let store = try SQLiteStore(path: ":memory:")

        // Run 1: test passes
        let run1 = try store.recordRun(gitHash: "aaa111", branch: "develop")
        _ = try store.recordResult(
            runID: run1,
            testFile: "CoreTests.swift",
            testName: "testAdd",
            status: .passed,
            durationMs: 5
        )

        // Run 2: test fails
        let run2 = try store.recordRun(gitHash: "bbb222", branch: "feature/x")
        _ = try store.recordResult(
            runID: run2,
            testFile: "CoreTests.swift",
            testName: "testAdd",
            status: .failed,
            durationMs: 3,
            error: "Expected 5, got 4"
        )

        let history = try store.historyForTest("testAdd")
        #expect(history.count == 2)
        // Most recent first
        #expect(history[0].status == .failed)
        #expect(history[1].status == .passed)
    }

    // MARK: - All Runs

    @Test("All runs returns most recent first with limit")
    func allRuns() throws {
        let store = try SQLiteStore(path: ":memory:")

        _ = try store.recordRun(gitHash: "aaa", branch: "main")
        _ = try store.recordRun(gitHash: "bbb", branch: "develop")
        _ = try store.recordRun(gitHash: "ccc", branch: "feature/x")

        let all = try store.allRuns(limit: 2)
        #expect(all.count == 2)
        // Most recent first
        #expect(all[0].gitHash == "ccc")
        #expect(all[1].gitHash == "bbb")
    }

    // MARK: - Merge

    @Test("Merge from temporary database into persistent store")
    func mergeFromTempDB() throws {
        // Create source (temporary) database
        let tmpPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("shikki-test-merge-\(UUID().uuidString).sqlite")
            .path
        defer { try? FileManager.default.removeItem(atPath: tmpPath) }

        let source = try SQLiteStore(path: tmpPath)
        let runID = try source.recordRun(gitHash: "merge123", branch: "agent/w2-nats")
        let groupID = try source.recordGroup(runID: runID, scope: "nats")
        _ = try source.recordResult(
            runID: runID,
            groupID: groupID,
            testFile: "NATSTests.swift",
            testName: "testPublish",
            status: .passed,
            durationMs: 10
        )
        _ = try source.recordResult(
            runID: runID,
            groupID: groupID,
            testFile: "NATSTests.swift",
            testName: "testSubscribe",
            status: .failed,
            durationMs: 5,
            error: "Connection refused"
        )

        // Create destination (persistent) database
        let dest = try SQLiteStore(path: ":memory:")

        // Merge
        try dest.mergeFrom(sourcePath: tmpPath)

        // Verify data was merged
        let run = try dest.fetchRun(runID)
        #expect(run != nil)
        #expect(run?.gitHash == "merge123")
        #expect(run?.branchName == "agent/w2-nats")

        let groups = try dest.groupsForRun(runID)
        #expect(groups.count == 1)
        #expect(groups[0].scopeName == "nats")

        let results = try dest.resultsForRun(runID)
        #expect(results.count == 2)
        let names = results.map(\.testName).sorted()
        #expect(names == ["testPublish", "testSubscribe"])
    }

    // MARK: - File-Based Database

    @Test("Create file-based database")
    func fileBasedDB() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("shikki-test-\(UUID().uuidString).sqlite")
            .path
        defer { try? FileManager.default.removeItem(atPath: path) }

        let store = try SQLiteStore(path: path)
        let runID = try store.recordRun(gitHash: "file123")
        let run = try store.fetchRun(runID)
        #expect(run != nil)

        // Verify file exists on disk
        #expect(FileManager.default.fileExists(atPath: path))
    }

    // MARK: - Empty Query

    @Test("Fetch run that does not exist returns nil")
    func fetchNonexistentRun() throws {
        let store = try SQLiteStore(path: ":memory:")
        let run = try store.fetchRun("nonexistent")
        #expect(run == nil)
    }

    @Test("Results for nonexistent run returns empty array")
    func resultsForNonexistentRun() throws {
        let store = try SQLiteStore(path: ":memory:")
        let results = try store.resultsForRun("nonexistent")
        #expect(results.isEmpty)
    }
}
