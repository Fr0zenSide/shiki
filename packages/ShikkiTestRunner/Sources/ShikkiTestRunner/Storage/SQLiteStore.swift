// MARK: - SQLiteStore.swift
// ShikkiTestRunner — SQLite persistence for test runs, groups, and results

#if canImport(SQLite3)
import SQLite3
#endif
import Foundation

// MARK: - Errors

/// Errors thrown by SQLiteStore operations.
public enum SQLiteStoreError: Error, Sendable, CustomStringConvertible {
    case openFailed(String)
    case queryFailed(String)
    case prepareFailed(String)
    case notFound(String)

    public var description: String {
        switch self {
        case .openFailed(let msg): "SQLite open failed: \(msg)"
        case .queryFailed(let msg): "SQLite query failed: \(msg)"
        case .prepareFailed(let msg): "SQLite prepare failed: \(msg)"
        case .notFound(let msg): "Not found: \(msg)"
        }
    }
}

// MARK: - Result Row

/// A single test result row from the database.
public struct TestResultRow: Sendable, Equatable {
    public let id: Int64
    public let runID: String
    public let groupID: Int64?
    public let testFile: String
    public let testName: String
    public let suiteName: String?
    public let status: TestStatus
    public let durationMs: Int64?
    public let errorMessage: String?
    public let errorFile: String?
    public let rawOutput: String?
}

/// A test run row from the database.
public struct TestRunRow: Sendable, Equatable {
    public let runID: String
    public let gitHash: String
    public let branchName: String?
    public let startedAt: String
    public let finishedAt: String?
    public let totalTests: Int64?
    public let passed: Int64?
    public let failed: Int64?
    public let skipped: Int64?
    public let durationMs: Int64?
}

/// A test group row from the database.
public struct TestGroupRow: Sendable, Equatable {
    public let id: Int64
    public let runID: String
    public let scopeName: String
    public let startedAt: String?
    public let finishedAt: String?
    public let totalTests: Int64?
    public let passed: Int64?
    public let failed: Int64?
    public let skipped: Int64?
    public let durationMs: Int64?
}

// MARK: - SQLiteStore

/// Thread-safe SQLite store for test run history.
///
/// Uses the C sqlite3 API directly. Each instance owns a single connection.
/// Not an actor because we want synchronous init for simplicity —
/// all mutation methods are `throws` and use a serial lock.
public final class SQLiteStore: @unchecked Sendable {

    private let db: OpaquePointer
    private let lock = NSLock()

    /// The file path of the database (":memory:" for in-memory).
    public let path: String

    // MARK: - Init / Deinit

    /// Open or create a SQLite database at the given path.
    ///
    /// - Parameter path: File path, or `:memory:` for in-memory database.
    public init(path: String = ":memory:") throws {
        self.path = path
        var dbPointer: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(path, &dbPointer, flags, nil)
        guard result == SQLITE_OK, let opened = dbPointer else {
            let msg = dbPointer.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let ptr = dbPointer { sqlite3_close(ptr) }
            throw SQLiteStoreError.openFailed(msg)
        }
        db = opened
        // Enable WAL mode for better concurrent read performance
        try execute("PRAGMA journal_mode=WAL")
        try createTables()
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Schema

    private func createTables() throws {
        let schema = """
        CREATE TABLE IF NOT EXISTS test_runs (
            run_id TEXT PRIMARY KEY,
            git_hash TEXT NOT NULL,
            branch_name TEXT,
            started_at DATETIME NOT NULL,
            finished_at DATETIME,
            total_tests INTEGER,
            passed INTEGER,
            failed INTEGER,
            skipped INTEGER,
            duration_ms INTEGER,
            moto_cache_hash TEXT
        );

        CREATE TABLE IF NOT EXISTS test_groups (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            run_id TEXT REFERENCES test_runs(run_id),
            scope_name TEXT NOT NULL,
            started_at DATETIME,
            finished_at DATETIME,
            total_tests INTEGER,
            passed INTEGER,
            failed INTEGER,
            skipped INTEGER,
            duration_ms INTEGER
        );

        CREATE TABLE IF NOT EXISTS test_results (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            run_id TEXT REFERENCES test_runs(run_id),
            group_id INTEGER REFERENCES test_groups(id),
            test_file TEXT NOT NULL,
            test_name TEXT NOT NULL,
            suite_name TEXT,
            status TEXT CHECK(status IN ('passed', 'failed', 'skipped', 'timeout')),
            duration_ms INTEGER,
            error_message TEXT,
            error_file TEXT,
            raw_output TEXT
        );

        CREATE INDEX IF NOT EXISTS idx_runs_hash ON test_runs(git_hash);
        CREATE INDEX IF NOT EXISTS idx_runs_branch ON test_runs(branch_name);
        CREATE INDEX IF NOT EXISTS idx_results_status ON test_results(status);
        CREATE INDEX IF NOT EXISTS idx_results_test ON test_results(test_name);
        CREATE INDEX IF NOT EXISTS idx_results_group ON test_results(group_id);
        """
        try execute(schema)
    }

    // MARK: - Public API

    /// Record a new test run.
    ///
    /// - Parameters:
    ///   - gitHash: The git commit hash for this run.
    ///   - branch: The branch name (optional).
    /// - Returns: The generated run_id (UUID string).
    @discardableResult
    public func recordRun(gitHash: String, branch: String? = nil) throws -> String {
        let runID = UUID().uuidString
        let now = iso8601Now()
        let sql = """
        INSERT INTO test_runs (run_id, git_hash, branch_name, started_at)
        VALUES (?, ?, ?, ?)
        """
        _ = try lock.withLock {
            try prepareAndBind(sql, bindings: [.text(runID), .text(gitHash), .optionalText(branch), .text(now)])
        }
        return runID
    }

    /// Record a test group (scope) within a run.
    ///
    /// - Parameters:
    ///   - runID: The parent run ID.
    ///   - scope: The scope name (e.g., "nats", "flywheel").
    /// - Returns: The auto-generated group ID.
    @discardableResult
    public func recordGroup(runID: String, scope: String) throws -> Int64 {
        let now = iso8601Now()
        let sql = """
        INSERT INTO test_groups (run_id, scope_name, started_at)
        VALUES (?, ?, ?)
        """
        return try lock.withLock {
            try prepareAndBind(sql, bindings: [.text(runID), .text(scope), .text(now)])
            return sqlite3_last_insert_rowid(db)
        }
    }

    /// Record an individual test result.
    ///
    /// - Parameters:
    ///   - runID: The parent run ID.
    ///   - groupID: The parent group ID (optional).
    ///   - testFile: The source file containing the test.
    ///   - testName: The test function name.
    ///   - suiteName: The test suite/class name (optional).
    ///   - status: The test status.
    ///   - durationMs: Execution time in milliseconds (optional).
    ///   - error: Error message if failed (optional).
    ///   - errorFile: Error source location (optional).
    ///   - rawOutput: Captured stdout/stderr (optional).
    @discardableResult
    public func recordResult(
        runID: String,
        groupID: Int64? = nil,
        testFile: String,
        testName: String,
        suiteName: String? = nil,
        status: TestStatus,
        durationMs: Int64? = nil,
        error: String? = nil,
        errorFile: String? = nil,
        rawOutput: String? = nil
    ) throws -> Int64 {
        let sql = """
        INSERT INTO test_results
            (run_id, group_id, test_file, test_name, suite_name, status, duration_ms, error_message, error_file, raw_output)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        return try lock.withLock {
            try prepareAndBind(sql, bindings: [
                .text(runID),
                .optionalInt64(groupID),
                .text(testFile),
                .text(testName),
                .optionalText(suiteName),
                .text(status.rawValue),
                .optionalInt64(durationMs),
                .optionalText(error),
                .optionalText(errorFile),
                .optionalText(rawOutput),
            ])
            return sqlite3_last_insert_rowid(db)
        }
    }

    /// Finish a test run by setting finished_at and summary counts.
    public func finishRun(
        runID: String,
        totalTests: Int64,
        passed: Int64,
        failed: Int64,
        skipped: Int64,
        durationMs: Int64
    ) throws {
        let now = iso8601Now()
        let sql = """
        UPDATE test_runs
        SET finished_at = ?, total_tests = ?, passed = ?, failed = ?, skipped = ?, duration_ms = ?
        WHERE run_id = ?
        """
        _ = try lock.withLock {
            try prepareAndBind(sql, bindings: [
                .text(now),
                .int64(totalTests),
                .int64(passed),
                .int64(failed),
                .int64(skipped),
                .int64(durationMs),
                .text(runID),
            ])
        }
    }

    /// Finish a test group by setting finished_at and summary counts.
    public func finishGroup(
        groupID: Int64,
        totalTests: Int64,
        passed: Int64,
        failed: Int64,
        skipped: Int64,
        durationMs: Int64
    ) throws {
        let now = iso8601Now()
        let sql = """
        UPDATE test_groups
        SET finished_at = ?, total_tests = ?, passed = ?, failed = ?, skipped = ?, duration_ms = ?
        WHERE id = ?
        """
        _ = try lock.withLock {
            try prepareAndBind(sql, bindings: [
                .text(now),
                .int64(totalTests),
                .int64(passed),
                .int64(failed),
                .int64(skipped),
                .int64(durationMs),
                .int64(groupID),
            ])
        }
    }

    // MARK: - Queries

    /// Fetch all test results for a given run.
    public func resultsForRun(_ runID: String) throws -> [TestResultRow] {
        let sql = "SELECT id, run_id, group_id, test_file, test_name, suite_name, status, duration_ms, error_message, error_file, raw_output FROM test_results WHERE run_id = ? ORDER BY id"
        return try lock.withLock {
            try query(sql, bindings: [.text(runID)]) { stmt in
                TestResultRow(
                    id: sqlite3_column_int64(stmt, 0),
                    runID: String(cString: sqlite3_column_text(stmt, 1)),
                    groupID: sqlite3_column_type(stmt, 2) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 2),
                    testFile: String(cString: sqlite3_column_text(stmt, 3)),
                    testName: String(cString: sqlite3_column_text(stmt, 4)),
                    suiteName: sqlite3_column_type(stmt, 5) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, 5)),
                    status: TestStatus(rawValue: String(cString: sqlite3_column_text(stmt, 6))) ?? .failed,
                    durationMs: sqlite3_column_type(stmt, 7) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 7),
                    errorMessage: sqlite3_column_type(stmt, 8) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, 8)),
                    errorFile: sqlite3_column_type(stmt, 9) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, 9)),
                    rawOutput: sqlite3_column_type(stmt, 10) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, 10))
                )
            }
        }
    }

    /// Fetch a test run by its ID.
    public func fetchRun(_ runID: String) throws -> TestRunRow? {
        let sql = "SELECT run_id, git_hash, branch_name, started_at, finished_at, total_tests, passed, failed, skipped, duration_ms FROM test_runs WHERE run_id = ?"
        let rows: [TestRunRow] = try lock.withLock {
            try query(sql, bindings: [.text(runID)]) { stmt in
                TestRunRow(
                    runID: String(cString: sqlite3_column_text(stmt, 0)),
                    gitHash: String(cString: sqlite3_column_text(stmt, 1)),
                    branchName: sqlite3_column_type(stmt, 2) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, 2)),
                    startedAt: String(cString: sqlite3_column_text(stmt, 3)),
                    finishedAt: sqlite3_column_type(stmt, 4) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, 4)),
                    totalTests: sqlite3_column_type(stmt, 5) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 5),
                    passed: sqlite3_column_type(stmt, 6) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 6),
                    failed: sqlite3_column_type(stmt, 7) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 7),
                    skipped: sqlite3_column_type(stmt, 8) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 8),
                    durationMs: sqlite3_column_type(stmt, 9) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 9)
                )
            }
        }
        return rows.first
    }

    /// Fetch all groups for a run.
    public func groupsForRun(_ runID: String) throws -> [TestGroupRow] {
        let sql = "SELECT id, run_id, scope_name, started_at, finished_at, total_tests, passed, failed, skipped, duration_ms FROM test_groups WHERE run_id = ? ORDER BY id"
        return try lock.withLock {
            try query(sql, bindings: [.text(runID)]) { stmt in
                TestGroupRow(
                    id: sqlite3_column_int64(stmt, 0),
                    runID: String(cString: sqlite3_column_text(stmt, 1)),
                    scopeName: String(cString: sqlite3_column_text(stmt, 2)),
                    startedAt: sqlite3_column_type(stmt, 3) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, 3)),
                    finishedAt: sqlite3_column_type(stmt, 4) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, 4)),
                    totalTests: sqlite3_column_type(stmt, 5) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 5),
                    passed: sqlite3_column_type(stmt, 6) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 6),
                    failed: sqlite3_column_type(stmt, 7) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 7),
                    skipped: sqlite3_column_type(stmt, 8) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 8),
                    durationMs: sqlite3_column_type(stmt, 9) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 9)
                )
            }
        }
    }

    /// Fetch all runs, most recent first.
    public func allRuns(limit: Int = 20) throws -> [TestRunRow] {
        let sql = "SELECT run_id, git_hash, branch_name, started_at, finished_at, total_tests, passed, failed, skipped, duration_ms FROM test_runs ORDER BY started_at DESC LIMIT ?"
        return try lock.withLock {
            try query(sql, bindings: [.int64(Int64(limit))]) { stmt in
                TestRunRow(
                    runID: String(cString: sqlite3_column_text(stmt, 0)),
                    gitHash: String(cString: sqlite3_column_text(stmt, 1)),
                    branchName: sqlite3_column_type(stmt, 2) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, 2)),
                    startedAt: String(cString: sqlite3_column_text(stmt, 3)),
                    finishedAt: sqlite3_column_type(stmt, 4) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, 4)),
                    totalTests: sqlite3_column_type(stmt, 5) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 5),
                    passed: sqlite3_column_type(stmt, 6) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 6),
                    failed: sqlite3_column_type(stmt, 7) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 7),
                    skipped: sqlite3_column_type(stmt, 8) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 8),
                    durationMs: sqlite3_column_type(stmt, 9) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 9)
                )
            }
        }
    }

    /// Fetch results for a specific test name across all runs (for regression detection).
    public func historyForTest(_ testName: String, limit: Int = 20) throws -> [TestResultRow] {
        let sql = """
        SELECT t.id, t.run_id, t.group_id, t.test_file, t.test_name, t.suite_name, t.status,
               t.duration_ms, t.error_message, t.error_file, t.raw_output
        FROM test_results t
        JOIN test_runs r ON t.run_id = r.run_id
        WHERE t.test_name = ?
        ORDER BY r.started_at DESC
        LIMIT ?
        """
        return try lock.withLock {
            try query(sql, bindings: [.text(testName), .int64(Int64(limit))]) { stmt in
                TestResultRow(
                    id: sqlite3_column_int64(stmt, 0),
                    runID: String(cString: sqlite3_column_text(stmt, 1)),
                    groupID: sqlite3_column_type(stmt, 2) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 2),
                    testFile: String(cString: sqlite3_column_text(stmt, 3)),
                    testName: String(cString: sqlite3_column_text(stmt, 4)),
                    suiteName: sqlite3_column_type(stmt, 5) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, 5)),
                    status: TestStatus(rawValue: String(cString: sqlite3_column_text(stmt, 6))) ?? .failed,
                    durationMs: sqlite3_column_type(stmt, 7) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 7),
                    errorMessage: sqlite3_column_type(stmt, 8) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, 8)),
                    errorFile: sqlite3_column_type(stmt, 9) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, 9)),
                    rawOutput: sqlite3_column_type(stmt, 10) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, 10))
                )
            }
        }
    }

    // MARK: - Merge

    /// Merge test data from a temporary agent SQLite into this persistent store.
    ///
    /// Attaches the source database, copies all rows, then detaches.
    /// Used for the agent test SQLite handoff pattern.
    ///
    /// - Parameter sourcePath: Path to the temporary SQLite file to merge from.
    public func mergeFrom(sourcePath: String) throws {
        try lock.withLock {
            try executeRaw("ATTACH DATABASE '\(sourcePath)' AS tmp_source")
            defer {
                _ = try? executeRaw("DETACH DATABASE tmp_source")
            }

            // Merge runs (skip conflicts — same run_id means already merged)
            try executeRaw("""
            INSERT OR IGNORE INTO test_runs
            SELECT * FROM tmp_source.test_runs
            """)

            // Merge groups
            // We need to remap IDs since they're auto-increment
            // Strategy: insert and let auto-increment generate new IDs,
            // then use a mapping to update result references.
            // For simplicity in Wave 1, we use INSERT with explicit columns
            // and rely on AUTOINCREMENT for new IDs.
            try executeRaw("""
            INSERT INTO test_groups (run_id, scope_name, started_at, finished_at, total_tests, passed, failed, skipped, duration_ms)
            SELECT run_id, scope_name, started_at, finished_at, total_tests, passed, failed, skipped, duration_ms
            FROM tmp_source.test_groups
            """)

            // Merge results — assign to the newly inserted groups by matching run_id + scope
            try executeRaw("""
            INSERT INTO test_results (run_id, group_id, test_file, test_name, suite_name, status, duration_ms, error_message, error_file, raw_output)
            SELECT r.run_id, g_new.id, r.test_file, r.test_name, r.suite_name, r.status, r.duration_ms, r.error_message, r.error_file, r.raw_output
            FROM tmp_source.test_results r
            LEFT JOIN tmp_source.test_groups g_old ON r.group_id = g_old.id
            LEFT JOIN test_groups g_new ON g_new.run_id = g_old.run_id AND g_new.scope_name = g_old.scope_name
            """)
        }
    }

    // MARK: - Low-Level Helpers

    @discardableResult
    private func execute(_ sql: String) throws -> Int32 {
        var errMsg: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if result != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errMsg)
            throw SQLiteStoreError.queryFailed(msg)
        }
        return result
    }

    @discardableResult
    private func executeRaw(_ sql: String) throws -> Int32 {
        try execute(sql)
    }

    private enum Binding {
        case text(String)
        case optionalText(String?)
        case int64(Int64)
        case optionalInt64(Int64?)
    }

    @discardableResult
    private func prepareAndBind(_ sql: String, bindings: [Binding]) throws -> Int32 {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw SQLiteStoreError.prepareFailed(msg)
        }
        defer { sqlite3_finalize(stmt) }

        for (index, binding) in bindings.enumerated() {
            let pos = Int32(index + 1)
            switch binding {
            case .text(let value):
                sqlite3_bind_text(stmt, pos, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            case .optionalText(let value):
                if let value {
                    sqlite3_bind_text(stmt, pos, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                } else {
                    sqlite3_bind_null(stmt, pos)
                }
            case .int64(let value):
                sqlite3_bind_int64(stmt, pos, value)
            case .optionalInt64(let value):
                if let value {
                    sqlite3_bind_int64(stmt, pos, value)
                } else {
                    sqlite3_bind_null(stmt, pos)
                }
            }
        }

        let result = sqlite3_step(stmt)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw SQLiteStoreError.queryFailed(msg)
        }
        return result
    }

    private func query<T>(_ sql: String, bindings: [Binding], mapper: (OpaquePointer) -> T) throws -> [T] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw SQLiteStoreError.prepareFailed(msg)
        }
        defer { sqlite3_finalize(stmt) }

        for (index, binding) in bindings.enumerated() {
            let pos = Int32(index + 1)
            switch binding {
            case .text(let value):
                sqlite3_bind_text(stmt, pos, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            case .optionalText(let value):
                if let value {
                    sqlite3_bind_text(stmt, pos, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                } else {
                    sqlite3_bind_null(stmt, pos)
                }
            case .int64(let value):
                sqlite3_bind_int64(stmt, pos, value)
            case .optionalInt64(let value):
                if let value {
                    sqlite3_bind_int64(stmt, pos, value)
                } else {
                    sqlite3_bind_null(stmt, pos)
                }
            }
        }

        var rows: [T] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(mapper(stmt!))
        }
        return rows
    }

    private func iso8601Now() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
