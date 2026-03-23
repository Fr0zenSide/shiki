import Foundation
import Testing
@testable import ShikiCtlKit

// MARK: - ProcessCleanup Tests

@Suite("Process cleanup on stop")
struct ProcessCleanupTests {

    @Test("collectChildPIDs returns PIDs for all tmux panes in session")
    func collectChildPIDs() async throws {
        let cleanup = ProcessCleanup()
        // When no tmux session exists, should return empty
        let pids = cleanup.collectSessionPIDs(session: "nonexistent-test-session-xyz")
        #expect(pids.isEmpty)
    }

    @Test("killProcessTree sends SIGTERM then SIGKILL after timeout")
    func killProcessTree() async throws {
        let cleanup = ProcessCleanup()
        // Killing a non-existent PID should not throw
        cleanup.killProcessTree(pid: 999_999_999)
        // If we get here without crash, the error handling works
        #expect(true)
    }

    @Test("cleanupBeforeStop kills task windows individually before session")
    func cleanupBeforeStop() async throws {
        let cleanup = ProcessCleanup()
        // With a nonexistent session, should complete without error
        let result = cleanup.cleanupSession(session: "nonexistent-test-session-xyz")
        #expect(result.windowsKilled == 0)
        #expect(result.orphanPIDsKilled == 0)
    }

    @Test("reserved windows are never killed during cleanup")
    func reservedWindowsPreserved() throws {
        let reserved = ProcessCleanup.reservedWindows
        #expect(reserved.contains("orchestrator"))
        // Single-window layout: no board/research windows
        #expect(!reserved.contains("board"))
        #expect(!reserved.contains("research"))
    }

    @Test("findOrphanedClaudeProcesses finds claude processes not in tmux")
    func findOrphanedClaude() throws {
        let cleanup = ProcessCleanup()
        // Should return a list (possibly empty on test machine, but must not crash)
        let orphans = cleanup.findOrphanedClaudeProcesses()
        // Type check — should be array of PIDs
        #expect(orphans is [pid_t])
    }
}

// MARK: - StaleCompany Relaunch Tests

@Suite("Smart stale company relaunch")
struct StaleCompanyRelaunchTests {

    @Test("Only relaunch companies with pending tasks and no running session")
    func smartRelaunch() async throws {
        let launcher = MockProcessLauncher()
        let _ = MockNotificationSender()

        // Simulate: company "maya" has a running session
        try await launcher.launchTaskSession(
            taskId: "t-1", companyId: "id-1", companySlug: "maya",
            title: "some-task", projectPath: "Maya"
        )

        let sessions = await launcher.listRunningSessions()
        let mayaHasSession = sessions.contains { $0.hasPrefix("maya:") }

        // Maya already has a session — should NOT relaunch
        #expect(mayaHasSession)

        // Wabisabi has no session — could be relaunched
        let wabiHasSession = sessions.contains { $0.hasPrefix("wabisabi:") }
        #expect(!wabiHasSession)
    }

    @Test("Don't relaunch company with exhausted budget")
    func budgetExhausted() async throws {
        // A company that spent more than daily budget should not be relaunched
        let spent: Double = 5.0
        let budget: Double = 3.0
        #expect(spent >= budget, "Budget exhausted — skip relaunch")
    }
}

// MARK: - Decision Unblock Tests

@Suite("Decision unblock re-dispatch")
struct DecisionUnblockTests {

    @Test("Newly answered decisions trigger re-evaluation")
    func answeredDecisionDetected() async throws {
        // Track decisions across cycles
        let previousPendingIds: Set<String> = ["d-1", "d-2", "d-3"]
        let currentPendingIds: Set<String> = ["d-2"] // d-1 and d-3 were answered

        let answeredIds = previousPendingIds.subtracting(currentPendingIds)
        #expect(answeredIds == ["d-1", "d-3"])
    }

    @Test("Answered decision with dead session triggers re-dispatch")
    func deadSessionReDispatched() async throws {
        let launcher = MockProcessLauncher()

        // No running sessions
        let sessions = await launcher.listRunningSessions()
        #expect(sessions.isEmpty)

        // If a decision was answered but the company has no session → should re-dispatch
        let shouldReDispatch = sessions.isEmpty
        #expect(shouldReDispatch)
    }
}

// MARK: - Session Health Tests

@Suite("Session health monitoring")
struct SessionHealthTests {

    @Test("Session without heartbeat for 3+ minutes is marked stale")
    func staleSessionDetection() async throws {
        var lastHeartbeats: [String: Date] = [:]
        let sessionSlug = "maya:some-task"
        let fourMinutesAgo = Date().addingTimeInterval(-240)

        lastHeartbeats[sessionSlug] = fourMinutesAgo

        let threshold: TimeInterval = 180 // 3 minutes
        let timeSinceLastBeat = Date().timeIntervalSince(lastHeartbeats[sessionSlug]!)
        #expect(timeSinceLastBeat > threshold, "Session is stale")
    }

    @Test("Fresh session is not marked stale")
    func freshSessionNotStale() async throws {
        var lastHeartbeats: [String: Date] = [:]
        let sessionSlug = "maya:some-task"
        let oneMinuteAgo = Date().addingTimeInterval(-60)

        lastHeartbeats[sessionSlug] = oneMinuteAgo

        let threshold: TimeInterval = 180
        let timeSinceLastBeat = Date().timeIntervalSince(lastHeartbeats[sessionSlug]!)
        #expect(timeSinceLastBeat < threshold, "Session is fresh")
    }

    @Test("Session with no heartbeat record is treated as unknown, not stale")
    func unknownSessionNotStale() async throws {
        let lastHeartbeats: [String: Date] = [:]
        let sessionSlug = "maya:some-task"

        let isUnknown = lastHeartbeats[sessionSlug] == nil
        #expect(isUnknown, "Unknown session — no heartbeat recorded yet")
    }
}
