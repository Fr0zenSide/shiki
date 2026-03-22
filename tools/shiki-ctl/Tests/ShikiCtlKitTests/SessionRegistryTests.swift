import Foundation
import Testing
@testable import ShikiCtlKit

// MARK: - Test Doubles

final class MockSessionDiscoverer: SessionDiscoverer, @unchecked Sendable {
    var discoveredSessions: [DiscoveredSession] = []

    func discover() async -> [DiscoveredSession] {
        discoveredSessions
    }
}

// MARK: - TmuxDiscoverer Parsing Tests

@Suite("TmuxDiscoverer parsing")
struct TmuxDiscovererParsingTests {

    @Test("Parse tmux list-panes output")
    func parseTmuxOutput() {
        let output = """
        shiki:maya:spm-wave3 %5 12345
        shiki:wabisabi:onboard %6 12346
        shiki:orchestrator %1 99999
        """
        let sessions = TmuxDiscoverer.parsePaneOutput(output, sessionName: "shiki")
        #expect(sessions.count == 3)
        #expect(sessions[0].windowName == "maya:spm-wave3")
        #expect(sessions[0].paneId == "%5")
        #expect(sessions[0].pid == 12345)
    }

    @Test("Handle empty output (no session)")
    func handleEmptyOutput() {
        let sessions = TmuxDiscoverer.parsePaneOutput("", sessionName: "shiki")
        #expect(sessions.isEmpty)
    }

    @Test("Handle dead panes (no PID)")
    func handleDeadPanes() {
        let output = "shiki:maya:task %5 "
        let sessions = TmuxDiscoverer.parsePaneOutput(output, sessionName: "shiki")
        // Dead pane with no valid PID should be discovered with pid 0
        #expect(sessions.count == 1)
        #expect(sessions[0].pid == 0)
    }

    @Test("Only discover panes in shiki session")
    func onlyShikiSession() {
        let output = """
        other:window1 %1 11111
        shiki:maya:task %2 22222
        """
        let sessions = TmuxDiscoverer.parsePaneOutput(output, sessionName: "shiki")
        #expect(sessions.count == 1)
        #expect(sessions[0].windowName == "maya:task")
    }
}

// MARK: - SessionRegistry Tests

@Suite("SessionRegistry")
struct SessionRegistryTests {

    private func makeRegistry(sessions: [DiscoveredSession] = []) -> (SessionRegistry, MockSessionDiscoverer) {
        let discoverer = MockSessionDiscoverer()
        discoverer.discoveredSessions = sessions
        let journal = SessionJournal(basePath: NSTemporaryDirectory() + "shiki-reg-test-\(UUID().uuidString)")
        let registry = SessionRegistry(discoverer: discoverer, journal: journal)
        return (registry, discoverer)
    }

    @Test("Discover finds panes and registers them")
    func discoverRegisters() async throws {
        let (registry, _) = makeRegistry(sessions: [
            DiscoveredSession(windowName: "maya:spm-wave3", paneId: "%5", pid: 12345),
            DiscoveredSession(windowName: "wabisabi:onboard", paneId: "%6", pid: 12346),
        ])
        await registry.refresh()
        let all = await registry.allSessions
        #expect(all.count == 2)
    }

    @Test("Discover ignores reserved windows")
    func discoverIgnoresReserved() async throws {
        // Single-window layout: only "orchestrator" is reserved
        let (registry, _) = makeRegistry(sessions: [
            DiscoveredSession(windowName: "orchestrator", paneId: "%1", pid: 99999),
            DiscoveredSession(windowName: "maya:task", paneId: "%5", pid: 12345),
            DiscoveredSession(windowName: "flsh:deploy", paneId: "%6", pid: 12346),
        ])
        await registry.refresh()
        let all = await registry.allSessions
        #expect(all.count == 2)
        #expect(all.contains { $0.windowName == "maya:task" })
        #expect(all.contains { $0.windowName == "flsh:deploy" })
    }

    @Test("Reconcile: missing pane + 5min stale → reap")
    func reconcileReapsStale() async throws {
        let (registry, discoverer) = makeRegistry(sessions: [
            DiscoveredSession(windowName: "maya:task", paneId: "%5", pid: 12345),
        ])
        // First refresh registers
        await registry.refresh()
        #expect(await registry.allSessions.count == 1)

        // Simulate pane disappearing
        discoverer.discoveredSessions = []

        // Mark the session as stale (> 5 min ago)
        await registry.setLastSeen(windowName: "maya:task", date: Date().addingTimeInterval(-301))

        await registry.refresh()
        #expect(await registry.allSessions.count == 0)
    }

    @Test("Reconcile: missing pane + 2min → keep")
    func reconcileKeepsRecent() async throws {
        let (registry, discoverer) = makeRegistry(sessions: [
            DiscoveredSession(windowName: "maya:task", paneId: "%5", pid: 12345),
        ])
        await registry.refresh()

        discoverer.discoveredSessions = []
        // lastSeen is recent (just registered) — should NOT reap
        await registry.refresh()
        #expect(await registry.allSessions.count == 1)
    }

    @Test("Never reap awaitingApproval sessions")
    func neverReapAwaitingApproval() async throws {
        let (registry, discoverer) = makeRegistry(sessions: [
            DiscoveredSession(windowName: "maya:task", paneId: "%5", pid: 12345),
        ])
        await registry.refresh()

        // Set state to awaitingApproval
        await registry.setSessionState(windowName: "maya:task", state: .awaitingApproval)

        // Simulate pane disappearing + stale
        discoverer.discoveredSessions = []
        await registry.setLastSeen(windowName: "maya:task", date: Date().addingTimeInterval(-600))

        await registry.refresh()
        // Should still be here — never reap awaitingApproval
        #expect(await registry.allSessions.count == 1)
    }

    @Test("sessionsByAttention returns merge first, idle last")
    func sessionsByAttentionOrder() async throws {
        let (registry, _) = makeRegistry()

        // Register sessions with different states
        await registry.registerManual(
            windowName: "idle-sess", paneId: "%1", pid: 111,
            state: .done
        )
        await registry.registerManual(
            windowName: "merge-sess", paneId: "%2", pid: 222,
            state: .approved
        )
        await registry.registerManual(
            windowName: "work-sess", paneId: "%3", pid: 333,
            state: .working
        )

        let sorted = await registry.sessionsByAttention()
        #expect(sorted.count == 3)
        #expect(sorted[0].windowName == "merge-sess") // .merge = 0
        #expect(sorted[1].windowName == "work-sess")  // .working = 4
        #expect(sorted[2].windowName == "idle-sess")   // .idle = 5
    }

    @Test("Register and deregister")
    func registerDeregister() async {
        let (registry, _) = makeRegistry()

        await registry.registerManual(
            windowName: "test-sess", paneId: "%1", pid: 111,
            state: .working
        )
        #expect(await registry.allSessions.count == 1)

        await registry.deregister(windowName: "test-sess")
        #expect(await registry.allSessions.count == 0)
    }
}
