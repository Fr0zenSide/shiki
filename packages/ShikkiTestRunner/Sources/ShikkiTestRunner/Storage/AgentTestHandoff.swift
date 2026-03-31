// MARK: - AgentTestHandoff.swift
// ShikkiTestRunner — Model + merge logic for agent test result handoff.
// Each sub-agent produces a temp SQLite; this merges it into persistent history.

import Foundation

/// Report from a sub-agent's test run, used for the SQLite handoff pattern.
///
/// After an agent completes its work in a worktree:
/// 1. Agent runs `shikki test --scope <changed>` → creates temp SQLite
/// 2. Agent commits code + pushes branch
/// 3. Before worktree cleanup, agent creates this report
/// 4. Report is merged into persistent test-history.sqlite
/// 5. Worktree deleted, test history preserved
public struct AgentTestReport: Sendable, Equatable, Codable {
    /// Agent identifier (e.g. "w2-1-nats", "w5-dispatch").
    public let agentID: String

    /// Branch the agent was working on.
    public let branch: String

    /// Git commit hash at the time of the test run.
    public let commit: String

    /// Scope(s) that were tested.
    public let scopes: [String]

    /// Attempt number (1-based; increments on retries).
    public let attempt: Int

    /// Whether this agent was part of a speculative (racing) execution.
    public let isRacer: Bool

    /// Whether this racer's code was ultimately kept (only meaningful when isRacer = true).
    public let wonRace: Bool

    /// Path to the agent's temporary SQLite database.
    public let tmpDBPath: String

    /// Timestamp when the report was created.
    public let createdAt: Date

    public init(
        agentID: String,
        branch: String,
        commit: String,
        scopes: [String],
        attempt: Int = 1,
        isRacer: Bool = false,
        wonRace: Bool = false,
        tmpDBPath: String,
        createdAt: Date = Date()
    ) {
        self.agentID = agentID
        self.branch = branch
        self.commit = commit
        self.scopes = scopes
        self.attempt = attempt
        self.isRacer = isRacer
        self.wonRace = wonRace
        self.tmpDBPath = tmpDBPath
        self.createdAt = createdAt
    }
}

/// Handles merging agent test SQLite databases into persistent history.
public struct AgentTestHandoff: Sendable {

    public init() {}

    // MARK: - Merge

    /// Merge an agent's temporary test SQLite into the persistent history database.
    ///
    /// This is the core of the agent test handoff pattern:
    /// - Opens the persistent DB at `historyDBPath`
    /// - Tags all runs in the agent's temp DB with agent metadata
    /// - Merges temp DB rows into persistent DB using SQLiteStore.mergeFrom
    ///
    /// - Parameters:
    ///   - report: The agent's test report containing metadata and temp DB path.
    ///   - historyDBPath: Path to the persistent test-history.sqlite.
    /// - Returns: Number of test runs merged.
    @discardableResult
    public func mergeAgentReport(
        report: AgentTestReport,
        historyDBPath: String
    ) throws -> Int {
        // First, tag the agent's temp DB with metadata
        let tmpStore = try SQLiteStore(path: report.tmpDBPath)
        let runsBeforeMerge = try tmpStore.allRuns(limit: 1000)

        // Tag each run in the temp DB with agent metadata
        try tagRunsWithAgentMetadata(
            store: tmpStore,
            report: report,
            runIDs: runsBeforeMerge.map(\.runID)
        )

        // Now merge into persistent
        let historyStore = try SQLiteStore(path: historyDBPath)
        try historyStore.mergeFrom(sourcePath: report.tmpDBPath)

        return runsBeforeMerge.count
    }

    /// Create a new agent test report for the standard handoff flow.
    ///
    /// Convenience factory that generates the temp DB path from the agent ID.
    public func createReport(
        agentID: String,
        branch: String,
        commit: String,
        scopes: [String],
        attempt: Int = 1,
        isRacer: Bool = false,
        wonRace: Bool = false
    ) -> AgentTestReport {
        let tmpPath = NSTemporaryDirectory() + "shikki-test-\(agentID).sqlite"
        return AgentTestReport(
            agentID: agentID,
            branch: branch,
            commit: commit,
            scopes: scopes,
            attempt: attempt,
            isRacer: isRacer,
            wonRace: wonRace,
            tmpDBPath: tmpPath
        )
    }

    // MARK: - Private

    /// Tag all runs in a store with agent metadata.
    private func tagRunsWithAgentMetadata(
        store: SQLiteStore,
        report: AgentTestReport,
        runIDs: [String]
    ) throws {
        for runID in runIDs {
            let sql = """
            UPDATE test_runs
            SET agent_id = ?, attempt = ?, is_racer = ?, won_race = ?
            WHERE run_id = ?
            """
            try store.prepareAndBind(sql, bindings: [
                .text(report.agentID),
                .int64(Int64(report.attempt)),
                .int64(report.isRacer ? 1 : 0),
                .int64(report.wonRace ? 1 : 0),
                .text(runID),
            ])
        }
    }
}
