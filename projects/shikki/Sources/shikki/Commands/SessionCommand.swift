import ArgumentParser
import Foundation
import ShikkiKit

struct SessionCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "session",
        abstract: "Show session overview, previous session, or session history"
    )

    @Flag(name: .long, help: "Show previous session summary")
    var previous: Bool = false

    @Option(name: .long, help: "Show last N sessions")
    var history: Int?

    @Option(name: .long, help: "Sessions directory (for testing)")
    var sessionsDir: String?

    func run() async throws {
        let storage: any SessionStorageProviding
        if let dir = sessionsDir {
            storage = FileSessionStorage(directory: dir)
        } else {
            storage = FileSessionStorage()
        }

        let summary = PreviousSessionSummary(storage: storage)

        if let count = history {
            try runHistory(count: count, storage: storage, summary: summary)
            return
        }

        if previous {
            try runPrevious(storage: storage, summary: summary)
            return
        }

        try runCurrent(storage: storage, summary: summary)
    }

    // MARK: - Subcommand Logic

    private func runCurrent(storage: any SessionStorageProviding, summary: PreviousSessionSummary) throws {
        print("\u{1B}[1m\u{1B}[36mShikki Session\u{1B}[0m")
        print()

        // Try to find an active session (no endedAt)
        let sessions = try storage.loadSessions()
        let active = sessions.first { $0.endedAt == nil }

        if let session = active {
            let overview = summary.formatSessionOverview(session)
            print(overview)
        } else if let latest = sessions.first {
            // No active session — show the most recent completed one
            print("  \u{1B}[33mNo active session.\u{1B}[0m Showing most recent:")
            print()
            let overview = summary.formatSessionOverview(latest)
            print(overview)
        } else {
            print("  No sessions recorded yet.")
            print("  Start a session with: \u{1B}[1mshikki\u{1B}[0m")
        }
    }

    private func runPrevious(storage: any SessionStorageProviding, summary: PreviousSessionSummary) throws {
        print("\u{1B}[1m\u{1B}[36mPrevious Session\u{1B}[0m")
        print()

        let sessions = try storage.loadSessions()

        // Skip active session, find the last completed one
        let completed = sessions.first { $0.endedAt != nil }

        if let session = completed {
            let overview = summary.formatSessionOverview(session)
            print(overview)
        } else {
            print("  No previous session found.")
        }
    }

    private func runHistory(count: Int, storage: any SessionStorageProviding, summary: PreviousSessionSummary) throws {
        let effectiveCount = max(1, min(count, 100))

        print("\u{1B}[1m\u{1B}[36mSession History\u{1B}[0m (last \(effectiveCount))")
        print()

        let sessions = try storage.recentSessions(count: effectiveCount)
        let formatted = summary.formatSessionHistory(sessions)
        print(formatted)
    }
}
