public protocol Migration: Sendable {
    var version: Int { get }
    var sql: String { get }
    var description: String { get }
}

public struct MigrationRunner: Sendable {

    public init() {}

    /// Runs pending migrations in version order.
    /// Creates a `_migrations` table to track which versions have been applied.
    /// - Parameters:
    ///   - migrations: The list of migrations to apply.
    ///   - execute: A closure that executes a raw SQL statement.
    public func run(
        migrations: [any Migration],
        execute: @Sendable (String) async throws -> Void
    ) async throws {
        // Create tracking table
        try await execute("""
            CREATE TABLE IF NOT EXISTS _migrations (
                version INTEGER PRIMARY KEY,
                description TEXT NOT NULL,
                applied_at TEXT NOT NULL DEFAULT (datetime('now'))
            )
        """)

        let sorted = migrations.sorted { $0.version < $1.version }

        for migration in sorted {
            // Check if already applied — use a marker approach since we only have execute
            // We use INSERT OR IGNORE: if version already exists, nothing happens
            // But we need to know if it was already there. Use a two-step:
            // 1. Try to insert the migration record
            // 2. If it succeeds (no conflict), run the migration SQL
            // Since we can't query with just execute, we wrap in a transaction approach:
            // Actually, we run the SQL first, then record it. If it fails, we don't record.
            // To skip already-applied, we use a different strategy.

            // We'll use INSERT OR IGNORE and rely on the caller providing a query-capable execute.
            // Simpler: just attempt the insert and catch uniqueness errors.
            // Best approach with our constraint: create a temp marker.

            // Use a pragmatic approach: try inserting, if duplicate the SQL is a no-op
            do {
                try await execute(
                    "INSERT INTO _migrations (version, description) VALUES (\(migration.version), '\(migration.description.replacingOccurrences(of: "'", with: "''"))')"
                )
            } catch {
                // Already applied (UNIQUE constraint on version PK) — skip
                continue
            }

            // Run the actual migration SQL
            do {
                let statements = migration.sql.split(separator: ";")
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                for statement in statements {
                    try await execute(statement)
                }
            } catch {
                // Clean up the migration record since it failed
                try? await execute("DELETE FROM _migrations WHERE version = \(migration.version)")
                throw StorageError.migrationFailed(
                    version: migration.version,
                    reason: error.localizedDescription
                )
            }
        }
    }
}
