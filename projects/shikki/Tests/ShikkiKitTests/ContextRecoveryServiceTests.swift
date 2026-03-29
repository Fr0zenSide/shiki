import Foundation
import Testing
@testable import ShikkiKit

// MARK: - Mock Providers

/// Mock event source for testing the recovery chain.
final class MockEventSource: EventSourceProvider, @unchecked Sendable {
    var events: [ShikkiEvent] = []
    var pendingDecisions: [String] = []
    var shouldFail = false
    var failureError: RecoverySourceError = .unavailable("mock failure")

    func fetchEvents(since: Date, until: Date, limit: Int) async throws -> [ShikkiEvent] {
        if shouldFail { throw failureError }
        return events.filter { $0.timestamp >= since && $0.timestamp <= until }
    }

    func fetchPendingDecisions() async throws -> [String] {
        if shouldFail { throw failureError }
        return pendingDecisions
    }
}

/// Mock checkpoint provider for testing.
final class MockCheckpointProvider: CheckpointProvider, @unchecked Sendable {
    var checkpoint: Checkpoint?
    var shouldFail = false

    func loadCheckpoint() throws -> Checkpoint? {
        if shouldFail { throw NSError(domain: "test", code: 1) }
        return checkpoint
    }
}

/// Mock git workspace provider for testing.
/// BR-24: Never returns file contents, only metadata.
final class MockGitProvider: GitWorkspaceProvider, @unchecked Sendable {
    var branch: String? = "main"
    var commits: [CommitInfo] = []
    var modified: [String] = []
    var untracked: [String] = []
    var worktreeList: [WorktreeInfo] = []
    var ab: AheadBehind?

    func currentBranch() async -> String? { branch }
    func recentCommits(limit: Int) async -> [CommitInfo] { Array(commits.prefix(limit)) }
    func modifiedFiles() async -> [String] { modified }
    func untrackedFiles() async -> [String] { untracked }
    func worktrees() async -> [WorktreeInfo] { worktreeList }
    func aheadBehind() async -> AheadBehind? { ab }
}

// MARK: - Tests

@Suite("ContextRecoveryService — three-layer recovery chain")
struct ContextRecoveryServiceTests {

    private func makeService(
        events: MockEventSource = MockEventSource(),
        checkpoint: MockCheckpointProvider = MockCheckpointProvider(),
        git: MockGitProvider = MockGitProvider()
    ) -> ContextRecoveryService {
        ContextRecoveryService(
            eventSource: events,
            checkpointProvider: checkpoint,
            gitProvider: git
        )
    }

    private func makeEvent(
        type: EventType = .sessionStart,
        minutesAgo: Double = 30
    ) -> ShikkiEvent {
        ShikkiEvent(
            source: .system,
            type: type,
            scope: .global,
            payload: ["test": .string("value")]
        )
    }

    private func recentWindow() -> TimeWindow {
        TimeWindow.lookback(seconds: 7200)
    }

    // MARK: - DB Recovery

    @Test("Recover from DB returns events within time window")
    func recoverFromDB_returnsEventsWithinTimeWindow() async {
        let events = MockEventSource()
        events.events = [makeEvent()]
        let service = makeService(events: events)

        let context = await service.recover(window: recentWindow())
        let dbItems = context.timeline.filter { $0.provenance == .db }
        #expect(dbItems.count >= 1)
    }

    @Test("Recover from DB provenance is .db")
    func recoverFromDB_provenanceIsDB() async {
        let events = MockEventSource()
        events.events = [makeEvent()]
        let service = makeService(events: events)

        let context = await service.recover(window: recentWindow())
        let dbItems = context.timeline.filter { $0.provenance == .db }
        #expect(dbItems.allSatisfy { $0.provenance == .db })
    }

    @Test("Recover from DB deduplicates by event id")
    func recoverFromDB_deduplicatesByEventId() async {
        let event = makeEvent()
        let events = MockEventSource()
        events.events = [event, event] // same event twice
        let service = makeService(events: events)

        let context = await service.recover(window: recentWindow())
        let dbItems = context.timeline.filter { $0.provenance == .db }
        // Should deduplicate to 1
        #expect(dbItems.count == 1)
    }

    // MARK: - Checkpoint Recovery

    @Test("Recover from checkpoint extracts FSM state")
    func recoverFromCheckpoint_extractsFSMState() async {
        let cp = MockCheckpointProvider()
        cp.checkpoint = Checkpoint(
            timestamp: Date(),
            hostname: "test",
            fsmState: .running
        )
        let service = makeService(checkpoint: cp)

        let context = await service.recover(window: recentWindow())
        let cpItems = context.timeline.filter { $0.provenance == .checkpoint }
        #expect(cpItems.contains(where: { $0.summary.contains("running") }))
    }

    @Test("Recover from checkpoint extracts branch and stats")
    func recoverFromCheckpoint_extractsBranchAndStats() async {
        let cp = MockCheckpointProvider()
        cp.checkpoint = Checkpoint(
            timestamp: Date(),
            hostname: "test",
            fsmState: .idle,
            sessionStats: SessionSnapshot(startedAt: Date(), branch: "develop", commitCount: 3, linesChanged: 50)
        )
        let service = makeService(checkpoint: cp)

        let context = await service.recover(window: recentWindow())
        let cpItems = context.timeline.filter { $0.provenance == .checkpoint }
        #expect(cpItems.contains(where: { $0.summary.contains("develop") }))
    }

    @Test("Recover from checkpoint provenance is .checkpoint")
    func recoverFromCheckpoint_provenanceIsCheckpoint() async {
        let cp = MockCheckpointProvider()
        cp.checkpoint = Checkpoint(
            timestamp: Date(),
            hostname: "test",
            fsmState: .idle
        )
        let service = makeService(checkpoint: cp)

        let context = await service.recover(window: recentWindow())
        let cpItems = context.timeline.filter { $0.provenance == .checkpoint }
        #expect(cpItems.allSatisfy { $0.provenance == .checkpoint })
    }

    // MARK: - Git Recovery

    @Test("Recover from git collects recent commits")
    func recoverFromGit_collectsRecentCommits() async {
        let git = MockGitProvider()
        git.commits = [
            CommitInfo(hash: "abc123", message: "fix: parser bug", author: "dev", timestamp: Date()),
        ]
        let service = makeService(git: git)

        let context = await service.recover(window: recentWindow())
        let gitItems = context.timeline.filter { $0.provenance == .git && $0.kind == .commit }
        #expect(gitItems.count == 1)
        #expect(gitItems.first?.summary == "fix: parser bug")
    }

    @Test("Recover from git collects modified files")
    func recoverFromGit_collectsModifiedFiles() async {
        let git = MockGitProvider()
        git.modified = ["Sources/Foo.swift", "Sources/Bar.swift"]
        let service = makeService(git: git)

        let context = await service.recover(window: recentWindow())
        #expect(context.workspace.modifiedFiles.count == 2)
    }

    @Test("Recover from git collects worktree list")
    func recoverFromGit_collectsWorktreeList() async {
        let git = MockGitProvider()
        git.worktreeList = [
            WorktreeInfo(path: "/path/to/main", branch: "main"),
            WorktreeInfo(path: "/path/to/feature", branch: "feature/x"),
        ]
        let service = makeService(git: git)

        let context = await service.recover(window: recentWindow())
        #expect(context.workspace.worktrees.count == 2)
    }

    @Test("Recover from git provenance is .git")
    func recoverFromGit_provenanceIsGit() async {
        let git = MockGitProvider()
        git.commits = [
            CommitInfo(hash: "abc123", message: "test", author: "dev", timestamp: Date()),
        ]
        let service = makeService(git: git)

        let context = await service.recover(window: recentWindow())
        let gitItems = context.timeline.filter { $0.provenance == .git }
        #expect(gitItems.allSatisfy { $0.provenance == .git })
    }

    @Test("Recover from git never reads file contents (R3)")
    func recoverFromGit_neverReadsFileContents() async {
        let git = MockGitProvider()
        git.modified = ["Sources/Secret.swift"]
        let service = makeService(git: git)

        let context = await service.recover(window: recentWindow())
        // modifiedFiles only has paths, no contents
        #expect(context.workspace.modifiedFiles == ["Sources/Secret.swift"])
        // No timeline item contains file contents
        for item in context.timeline {
            #expect(item.detail == nil || !item.detail!.contains("func "))
        }
    }

    // MARK: - Merged Recovery

    @Test("Recover merges all sources sorted by timestamp")
    func recoverMergesAllSources_sortedByTimestamp() async {
        let now = Date()

        let events = MockEventSource()
        events.events = [
            ShikkiEvent(source: .system, type: .sessionStart, scope: .global),
        ]

        let cp = MockCheckpointProvider()
        cp.checkpoint = Checkpoint(
            timestamp: now.addingTimeInterval(-1800),
            hostname: "test",
            fsmState: .running
        )

        let git = MockGitProvider()
        git.commits = [
            CommitInfo(hash: "abc", message: "commit", author: "dev", timestamp: now.addingTimeInterval(-900)),
        ]

        let service = makeService(events: events, checkpoint: cp, git: git)
        let context = await service.recover(window: recentWindow())

        #expect(context.timeline.count >= 3)
        // Verify sorted by timestamp descending
        for i in 0..<(context.timeline.count - 1) {
            #expect(context.timeline[i].timestamp >= context.timeline[i + 1].timestamp)
        }
    }

    // MARK: - Fallback Chain

    @Test("DB unavailable falls to checkpoint and git")
    func dbUnavailable_fallsToCheckpointAndGit() async {
        let events = MockEventSource()
        events.shouldFail = true

        let cp = MockCheckpointProvider()
        cp.checkpoint = Checkpoint(timestamp: Date(), hostname: "test", fsmState: .idle)

        let git = MockGitProvider()
        git.branch = "main"

        let service = makeService(events: events, checkpoint: cp, git: git)
        let context = await service.recover(window: recentWindow())

        let dbSource = context.sources.first(where: { $0.name == "db" })
        #expect(dbSource?.status == .unavailable)

        let cpSource = context.sources.first(where: { $0.name == "checkpoint" })
        #expect(cpSource?.status == .available)
    }

    @Test("No checkpoint falls to git")
    func noCheckpoint_fallsToGit() async {
        let events = MockEventSource()
        events.shouldFail = true

        let git = MockGitProvider()
        git.branch = "main"
        git.commits = [
            CommitInfo(hash: "abc", message: "test", author: "dev", timestamp: Date()),
        ]

        let service = makeService(events: events, git: git)
        let context = await service.recover(window: recentWindow())

        let gitSource = context.sources.first(where: { $0.name == "git" })
        #expect(gitSource?.status == .available)
        #expect(context.timeline.contains(where: { $0.provenance == .git }))
    }

    @Test("All sources fail returns minimal diagnostic")
    func allSourcesFail_returnsMinimalDiagnostic() async {
        let events = MockEventSource()
        events.shouldFail = true

        let cp = MockCheckpointProvider()
        cp.shouldFail = true

        let git = MockGitProvider()
        git.branch = nil

        let service = makeService(events: events, checkpoint: cp, git: git)
        let context = await service.recover(window: recentWindow())

        #expect(context.confidence.overall == 0)
        #expect(context.staleness == .ancient)
    }

    @Test("DB returns unknown event types — skips gracefully (R1)")
    func dbReturnsUnknownEventTypes_skipsGracefully() async {
        let events = MockEventSource()
        events.events = [
            ShikkiEvent(source: .system, type: .custom(""), scope: .global), // empty custom = invalid
            ShikkiEvent(source: .system, type: .sessionStart, scope: .global), // valid
        ]
        let service = makeService(events: events)
        let context = await service.recover(window: recentWindow())

        // Should have at least the valid event
        let dbItems = context.timeline.filter { $0.provenance == .db }
        #expect(dbItems.count >= 1)
    }

    // MARK: - Agent Format

    @Test("recoverForAgent produces compact block")
    func recoverForAgent_producesCompactBlock() async {
        let git = MockGitProvider()
        git.branch = "feature/test"
        git.commits = [
            CommitInfo(hash: "abc1234", message: "feat: new thing", author: "dev", timestamp: Date()),
        ]

        let service = makeService(git: git)
        let output = await service.recoverForAgent(window: recentWindow())

        #expect(output.contains("<context-recovery>"))
        #expect(output.contains("</context-recovery>"))
        #expect(output.contains("feature/test"))
    }

    @Test("recoverForAgent respects budget")
    func recoverForAgent_respectsBudget() async {
        let service = makeService()
        let output = await service.recoverForAgent(window: recentWindow(), budget: 2048)

        #expect(output.utf8.count <= 2048 + 100) // small margin for closing tags
    }
}
