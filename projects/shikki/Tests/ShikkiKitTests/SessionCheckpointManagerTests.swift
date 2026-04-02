import Foundation
import Testing
@testable import ShikkiKit

@Suite("PausedSessionManager — checkpoint save/load/cleanup")
struct PausedSessionManagerTests {

    private func makeTempDir() -> String {
        let path = NSTemporaryDirectory() + "shikki-session-test-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    private func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    private func makeSession(
        branch: String = "feature/test",
        summary: String? = "Working on tests",
        activeTasks: [String] = [],
        pendingPRs: [Int] = [],
        decisions: [String] = [],
        nextAction: String? = nil,
        workspaceRoot: String = "/tmp/workspace"
    ) -> PausedSession {
        PausedSession(
            branch: branch,
            summary: summary,
            activeTasks: activeTasks,
            pendingPRs: pendingPRs,
            decisions: decisions,
            nextAction: nextAction,
            workspaceRoot: workspaceRoot
        )
    }

    // MARK: - Pause (save)

    @Test("Pause creates sessions directory if absent")
    func pause_createsDirectory() throws {
        let dir = NSTemporaryDirectory() + "shikki-absent-\(UUID().uuidString)"
        defer { cleanup(dir) }

        let manager = PausedSessionManager(sessionsDir: dir)
        let session = makeSession()

        try manager.pause(checkpoint: session)

        #expect(FileManager.default.fileExists(atPath: dir))
    }

    @Test("Pause writes valid JSON file")
    func pause_writesJSON() throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let manager = PausedSessionManager(sessionsDir: dir)
        let session = makeSession(branch: "develop")

        try manager.pause(checkpoint: session)

        let filePath = "\(dir)/\(session.sessionId).json"
        #expect(FileManager.default.fileExists(atPath: filePath))

        let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PausedSession.self, from: data)
        #expect(decoded.branch == "develop")
        #expect(decoded.sessionId == session.sessionId)
    }

    // MARK: - Resume (load)

    @Test("Resume by ID loads matching session")
    func resume_byIdLoadsSession() throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let manager = PausedSessionManager(sessionsDir: dir)
        let session = makeSession(branch: "feature/resume-test")

        try manager.pause(checkpoint: session)

        let loaded = try manager.resume(sessionId: session.sessionId)
        #expect(loaded != nil)
        #expect(loaded?.branch == "feature/resume-test")
        #expect(loaded?.sessionId == session.sessionId)
    }

    @Test("Resume with no ID returns most recent session")
    func resume_noIdReturnsMostRecent() throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let manager = PausedSessionManager(sessionsDir: dir)

        let older = PausedSession(
            pausedAt: Date().addingTimeInterval(-3600),
            branch: "feature/older"
        )
        let newer = PausedSession(
            pausedAt: Date(),
            branch: "feature/newer"
        )

        try manager.pause(checkpoint: older)
        try manager.pause(checkpoint: newer)

        let loaded = try manager.resume()
        #expect(loaded?.branch == "feature/newer")
    }

    @Test("Resume returns nil for nonexistent session ID")
    func resume_returnsNilForUnknownId() throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let manager = PausedSessionManager(sessionsDir: dir)
        let loaded = try manager.resume(sessionId: "nonexistent-id")
        #expect(loaded == nil)
    }

    @Test("Resume returns nil when sessions directory does not exist")
    func resume_returnsNilWhenNoDirExists() throws {
        let manager = PausedSessionManager(sessionsDir: "/tmp/nonexistent-sessions-\(UUID())")
        let loaded = try manager.resume()
        #expect(loaded == nil)
    }

    // MARK: - List checkpoints

    @Test("listCheckpoints returns sorted by pausedAt descending")
    func listCheckpoints_sortedByPausedAt() throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let manager = PausedSessionManager(sessionsDir: dir)

        let first = PausedSession(
            pausedAt: Date().addingTimeInterval(-7200),
            branch: "first"
        )
        let second = PausedSession(
            pausedAt: Date().addingTimeInterval(-3600),
            branch: "second"
        )
        let third = PausedSession(
            pausedAt: Date(),
            branch: "third"
        )

        try manager.pause(checkpoint: first)
        try manager.pause(checkpoint: second)
        try manager.pause(checkpoint: third)

        let checkpoints = try manager.listCheckpoints()
        #expect(checkpoints.count == 3)
        #expect(checkpoints[0].branch == "third")
        #expect(checkpoints[1].branch == "second")
        #expect(checkpoints[2].branch == "first")
    }

    @Test("listCheckpoints returns empty when no sessions exist")
    func listCheckpoints_emptyWhenNone() throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let manager = PausedSessionManager(sessionsDir: dir)
        let checkpoints = try manager.listCheckpoints()
        #expect(checkpoints.isEmpty)
    }

    // MARK: - Cleanup

    @Test("Cleanup keeps last N sessions and removes older ones")
    func cleanup_keepsLastN() throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let manager = PausedSessionManager(sessionsDir: dir)

        // Create 5 sessions with decreasing age
        for i in 0..<5 {
            let session = PausedSession(
                pausedAt: Date().addingTimeInterval(Double(-i) * 3600),
                branch: "branch-\(i)"
            )
            try manager.pause(checkpoint: session)
        }

        let beforeCleanup = try manager.listCheckpoints()
        #expect(beforeCleanup.count == 5)

        try manager.cleanup(keep: 3)

        let afterCleanup = try manager.listCheckpoints()
        #expect(afterCleanup.count == 3)
        // The 3 most recent are kept
        #expect(afterCleanup[0].branch == "branch-0")
        #expect(afterCleanup[1].branch == "branch-1")
        #expect(afterCleanup[2].branch == "branch-2")
    }

    @Test("Cleanup is noop when fewer sessions than keep count")
    func cleanup_noopWhenFewer() throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }

        let manager = PausedSessionManager(sessionsDir: dir)

        try manager.pause(checkpoint: makeSession())
        try manager.pause(checkpoint: makeSession())

        try manager.cleanup(keep: 10)

        let checkpoints = try manager.listCheckpoints()
        #expect(checkpoints.count == 2)
    }

    // MARK: - Build resume context

    @Test("buildResumeContext includes session ID and branch")
    func buildResumeContext_includesSessionAndBranch() {
        let manager = PausedSessionManager(sessionsDir: "/tmp")
        let session = makeSession(branch: "feature/context-test")

        let output = manager.buildResumeContext(checkpoint: session)

        #expect(output.contains(session.sessionId))
        #expect(output.contains("feature/context-test"))
    }

    @Test("buildResumeContext includes summary when present")
    func buildResumeContext_includesSummary() {
        let manager = PausedSessionManager(sessionsDir: "/tmp")
        let session = makeSession(summary: "Fixing parser edge cases")

        let output = manager.buildResumeContext(checkpoint: session)

        #expect(output.contains("Last Session Summary"))
        #expect(output.contains("Fixing parser edge cases"))
    }

    @Test("buildResumeContext includes active tasks")
    func buildResumeContext_includesActiveTasks() {
        let manager = PausedSessionManager(sessionsDir: "/tmp")
        let session = makeSession(activeTasks: ["task-A", "task-B"])

        let output = manager.buildResumeContext(checkpoint: session)

        #expect(output.contains("Active Tasks"))
        #expect(output.contains("task-A"))
        #expect(output.contains("task-B"))
    }

    @Test("buildResumeContext includes pending PRs")
    func buildResumeContext_includesPendingPRs() {
        let manager = PausedSessionManager(sessionsDir: "/tmp")
        let session = makeSession(pendingPRs: [42, 99])

        let output = manager.buildResumeContext(checkpoint: session)

        #expect(output.contains("Pending PRs"))
        #expect(output.contains("#42"))
        #expect(output.contains("#99"))
    }

    @Test("buildResumeContext includes decisions limited to 5")
    func buildResumeContext_includesDecisions() {
        let manager = PausedSessionManager(sessionsDir: "/tmp")
        let decisions = (1...7).map { "Decision \($0)" }
        let session = makeSession(decisions: decisions)

        let output = manager.buildResumeContext(checkpoint: session)

        #expect(output.contains("Recent Decisions"))
        #expect(output.contains("Decision 1"))
        #expect(output.contains("Decision 5"))
        #expect(!output.contains("Decision 6"))
    }

    @Test("buildResumeContext includes next action when present")
    func buildResumeContext_includesNextAction() {
        let manager = PausedSessionManager(sessionsDir: "/tmp")
        let session = makeSession(nextAction: "Run the full test suite")

        let output = manager.buildResumeContext(checkpoint: session)

        #expect(output.contains("Next Action"))
        #expect(output.contains("Run the full test suite"))
    }

    @Test("buildResumeContext omits empty sections")
    func buildResumeContext_omitsEmptySections() {
        let manager = PausedSessionManager(sessionsDir: "/tmp")
        let session = makeSession(
            summary: nil,
            activeTasks: [],
            pendingPRs: [],
            decisions: [],
            nextAction: nil
        )

        let output = manager.buildResumeContext(checkpoint: session)

        #expect(!output.contains("Last Session Summary"))
        #expect(!output.contains("Active Tasks"))
        #expect(!output.contains("Pending PRs"))
        #expect(!output.contains("Recent Decisions"))
        #expect(!output.contains("Next Action"))
    }

    // MARK: - PausedSession model

    @Test("PausedSession is Codable round-trip")
    func pausedSession_codableRoundTrip() throws {
        let original = PausedSession(
            branch: "develop",
            summary: "Test summary",
            activeTasks: ["task-1"],
            pendingPRs: [10, 20],
            decisions: ["decision-1"],
            nextAction: "next step",
            workspaceRoot: "/workspace",
            personality: ["curious"]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PausedSession.self, from: data)

        #expect(decoded.sessionId == original.sessionId)
        #expect(decoded.branch == "develop")
        #expect(decoded.summary == "Test summary")
        #expect(decoded.activeTasks == ["task-1"])
        #expect(decoded.pendingPRs == [10, 20])
        #expect(decoded.decisions == ["decision-1"])
        #expect(decoded.nextAction == "next step")
        #expect(decoded.workspaceRoot == "/workspace")
        #expect(decoded.personality == ["curious"])
    }
}
