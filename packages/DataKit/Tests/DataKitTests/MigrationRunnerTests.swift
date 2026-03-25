import Testing
@testable import DataKit

struct TestMigration: Migration, Sendable {
    let version: Int
    let sql: String
    let description: String
}

/// Thread-safe collector for SQL statements executed during migration tests.
final class SQLCollector: @unchecked Sendable {
    private var _statements: [String] = []
    private var _insertedVersions: Set<Int> = []

    var statements: [String] { _statements }

    func append(_ sql: String) {
        _statements.append(sql)
    }

    /// Simulates UNIQUE constraint on _migrations version column.
    /// Throws if a version was already inserted.
    func trackInsert(_ sql: String) throws {
        _statements.append(sql)
        // Detect INSERT INTO _migrations and extract the version number
        if sql.contains("INSERT INTO _migrations") {
            // Extract version number from "VALUES (1, ...)"
            if let range = sql.range(of: "VALUES ("),
               let commaRange = sql[range.upperBound...].range(of: ",") {
                let versionStr = String(sql[range.upperBound..<commaRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                if let version = Int(versionStr) {
                    if _insertedVersions.contains(version) {
                        throw StorageError.insertFailed("UNIQUE constraint failed: _migrations.version")
                    }
                    _insertedVersions.insert(version)
                }
            }
        }
    }

    func reset() {
        _statements = []
        _insertedVersions = []
    }
}

@Suite("MigrationRunner")
struct MigrationRunnerTests {

    @Test("runs migrations in version order")
    func runsInOrder() async throws {
        let collector = SQLCollector()
        let runner = MigrationRunner()

        let migrations: [any Migration] = [
            TestMigration(version: 2, sql: "CREATE TABLE b (id TEXT)", description: "create b"),
            TestMigration(version: 1, sql: "CREATE TABLE a (id TEXT)", description: "create a"),
        ]

        try await runner.run(migrations: migrations) { sql in
            collector.append(sql)
        }

        let createStatements = collector.statements.filter {
            $0.starts(with: "CREATE TABLE") && !$0.contains("_migrations")
        }
        #expect(createStatements.count == 2)
        #expect(createStatements[0].contains("a"))
        #expect(createStatements[1].contains("b"))
    }

    @Test("skips already-applied migrations on second run")
    func skipsApplied() async throws {
        let collector = SQLCollector()
        let runner = MigrationRunner()

        let migrations: [any Migration] = [
            TestMigration(version: 1, sql: "CREATE TABLE a (id TEXT)", description: "create a"),
        ]

        // Run once — use trackInsert to simulate UNIQUE constraint behavior
        try await runner.run(migrations: migrations) { sql in
            try collector.trackInsert(sql)
        }

        // Run again — the INSERT into _migrations should fail (duplicate PK), so migration is skipped
        let secondCollector = collector  // Reuse same collector so it remembers inserted versions
        let statementsBeforeSecondRun = secondCollector.statements.count
        try await runner.run(migrations: migrations) { sql in
            try secondCollector.trackInsert(sql)
        }

        // Second run statements should not include CREATE TABLE a
        let secondRunStatements = Array(secondCollector.statements.dropFirst(statementsBeforeSecondRun))
        let createA = secondRunStatements.filter { $0.contains("CREATE TABLE a") }
        #expect(createA.isEmpty)
    }

    @Test("creates _migrations tracking table")
    func createsTrackingTable() async throws {
        let collector = SQLCollector()
        let runner = MigrationRunner()

        try await runner.run(migrations: []) { sql in
            collector.append(sql)
        }

        let createMigrations = collector.statements.filter { $0.contains("_migrations") }
        #expect(!createMigrations.isEmpty)
    }

    @Test("throws migrationFailed on bad SQL")
    func throwsOnBadSQL() async throws {
        let runner = MigrationRunner()

        let migrations: [any Migration] = [
            TestMigration(version: 1, sql: "INVALID SQL STATEMENT", description: "bad migration"),
        ]

        await #expect(throws: StorageError.self) {
            try await runner.run(migrations: migrations) { sql in
                if sql.contains("INVALID") {
                    throw StorageError.queryFailed("syntax error")
                }
            }
        }
    }
}
