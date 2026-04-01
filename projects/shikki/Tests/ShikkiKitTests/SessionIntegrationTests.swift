import Foundation
import Testing
@testable import ShikkiKit

@Suite("Session integration (lifecycle + journal + registry)")
struct SessionIntegrationTests {

    private func makeComponents() -> (SessionRegistry, SessionJournal, MockSessionDiscoverer, String) {
        let basePath = NSTemporaryDirectory() + "shiki-integ-test-\(UUID().uuidString)"
        let journal = SessionJournal(basePath: basePath)
        let discoverer = MockSessionDiscoverer()
        let registry = SessionRegistry(discoverer: discoverer, journal: journal)
        return (registry, journal, discoverer, basePath)
    }

    @Test("Full pipeline: register → transition → checkpoint → reap")
    func fullPipeline() async throws {
        let (registry, journal, discoverer, basePath) = makeComponents()

        // 1. Discover a session
        discoverer.discoveredSessions = [
            DiscoveredSession(windowName: "maya:spm-wave3", paneId: "%5", pid: 12345),
        ]
        await registry.refresh()
        #expect(await registry.allSessions.count == 1)

        // 2. Create a lifecycle and transition
        let lifecycle = SessionLifecycle(
            sessionId: "maya:spm-wave3",
            context: TaskContext(taskId: "t-1", companySlug: "maya", projectPath: "maya")
        )
        try await lifecycle.transition(to: .working, actor: .agent("claude-1"), reason: "Task claimed")

        // 3. Journal the checkpoint
        let checkpoint = SessionCheckpoint(
            sessionId: "maya:spm-wave3",
            state: await lifecycle.currentState,
            reason: .stateTransition,
            metadata: ["task": "t-1"]
        )
        try await journal.checkpoint(checkpoint)

        // 4. Verify journal
        let loaded = try await journal.loadCheckpoints(sessionId: "maya:spm-wave3")
        #expect(loaded.count == 1)
        #expect(loaded[0].state == .working)

        // 5. Simulate pane death + staleness → reap
        discoverer.discoveredSessions = []
        await registry.setLastSeen(windowName: "maya:spm-wave3", date: Date().addingTimeInterval(-600))
        await registry.refresh()
        #expect(await registry.allSessions.count == 0)

        // 6. Journal should have the reap checkpoint too
        let afterReap = try await journal.loadCheckpoints(sessionId: "maya:spm-wave3")
        #expect(afterReap.count == 2)
        #expect(afterReap[1].state == .done)

        try? FileManager.default.removeItem(atPath: basePath)
    }

    @Test("Attention sort with mixed states")
    func attentionSortMixedStates() async throws {
        let (registry, _, _, basePath) = makeComponents()

        // Register sessions with various states
        await registry.registerManual(windowName: "idle-1", paneId: "%1", pid: 1, state: .done)
        await registry.registerManual(windowName: "merge-1", paneId: "%2", pid: 2, state: .approved)
        await registry.registerManual(windowName: "respond-1", paneId: "%3", pid: 3, state: .awaitingApproval)
        await registry.registerManual(windowName: "work-1", paneId: "%4", pid: 4, state: .working)
        await registry.registerManual(windowName: "review-1", paneId: "%5", pid: 5, state: .prOpen)

        let sorted = await registry.sessionsByAttention()
        #expect(sorted.count == 5)

        // Verify order: merge(0) > respond(1) > review(2) > working(4) > idle(5)
        #expect(sorted[0].attentionZone == .merge)
        #expect(sorted[1].attentionZone == .respond)
        #expect(sorted[2].attentionZone == .review)
        #expect(sorted[3].attentionZone == .working)
        #expect(sorted[4].attentionZone == .idle)

        try? FileManager.default.removeItem(atPath: basePath)
    }

    @Test("Graceful shutdown journals all sessions")
    func gracefulShutdownJournalsAll() async throws {
        let (registry, journal, _, basePath) = makeComponents()

        // Register several sessions
        await registry.registerManual(windowName: "sess-a", paneId: "%1", pid: 1, state: .working)
        await registry.registerManual(windowName: "sess-b", paneId: "%2", pid: 2, state: .prOpen)
        await registry.registerManual(windowName: "sess-c", paneId: "%3", pid: 3, state: .approved)

        // Simulate graceful shutdown: journal final checkpoint for each
        let sessions = await registry.allSessions
        for session in sessions {
            let checkpoint = SessionCheckpoint(
                sessionId: session.windowName,
                state: session.state,
                reason: .userAction,
                metadata: ["action": "shutdown"]
            )
            try await journal.checkpoint(checkpoint)
        }

        // Verify all 3 got journaled
        for name in ["sess-a", "sess-b", "sess-c"] {
            let checkpoints = try await journal.loadCheckpoints(sessionId: name)
            #expect(checkpoints.count == 1)
            #expect(checkpoints[0].metadata?["action"] == "shutdown")
        }

        try? FileManager.default.removeItem(atPath: basePath)
    }

    @Test("Session number assignment is sequential")
    func sessionNumberAssignment() async throws {
        let (registry, _, _, basePath) = makeComponents()

        // Register sessions in order
        await registry.registerManual(windowName: "first", paneId: "%1", pid: 1, state: .spawning)
        await registry.registerManual(windowName: "second", paneId: "%2", pid: 2, state: .working)
        await registry.registerManual(windowName: "third", paneId: "%3", pid: 3, state: .prOpen)

        let all = await registry.allSessions
        #expect(all.count == 3)

        // Deregister middle, register new — count stays correct
        await registry.deregister(windowName: "second")
        await registry.registerManual(windowName: "fourth", paneId: "%4", pid: 4, state: .spawning)
        #expect(await registry.allSessions.count == 3)

        try? FileManager.default.removeItem(atPath: basePath)
    }

    @Test("Cost context preserved through lifecycle")
    func costContextPreserved() async throws {
        let (registry, _, _, basePath) = makeComponents()

        let context = TaskContext(
            taskId: "t-1", companySlug: "maya", projectPath: "maya",
            budgetDailyUsd: 15.0, spentTodayUsd: 7.50
        )
        await registry.register(
            windowName: "maya:cost-test", paneId: "%1", pid: 123,
            context: context
        )

        let sessions = await registry.allSessions
        #expect(sessions.count == 1)
        #expect(sessions[0].context?.budgetDailyUsd == 15.0)
        #expect(sessions[0].context?.spentTodayUsd == 7.50)
        #expect(sessions[0].context?.companySlug == "maya")

        try? FileManager.default.removeItem(atPath: basePath)
    }

    @Test("Lifecycle state transitions chain correctly")
    func lifecycleChain() async throws {
        let lifecycle = SessionLifecycle(
            sessionId: "chain-test",
            context: TaskContext(taskId: "t-1", companySlug: "wabisabi", projectPath: "wabisabi")
        )

        // Full happy path: spawning → working → prOpen → reviewPending → approved → merged → done
        try await lifecycle.transition(to: .working, actor: .agent("claude"), reason: "started")
        try await lifecycle.transition(to: .prOpen, actor: .agent("claude"), reason: "PR created")
        try await lifecycle.transition(to: .reviewPending, actor: .system, reason: "reviewer assigned")
        try await lifecycle.transition(to: .approved, actor: .user("jeoffrey"), reason: "LGTM")
        try await lifecycle.transition(to: .merged, actor: .system, reason: "auto-merge")
        try await lifecycle.transition(to: .done, actor: .system, reason: "cleanup")

        let state = await lifecycle.currentState
        #expect(state == .done)

        let history = await lifecycle.transitionHistory
        #expect(history.count == 6)

        // Verify attention zones moved through the right levels
        let zones = history.map { stateToAttentionZone($0.to) }
        #expect(zones == [.working, .review, .review, .merge, .idle, .idle])
    }
}

// Helper to map state → zone for test assertions (uses single source of truth)
private func stateToAttentionZone(_ state: SessionState) -> AttentionZone {
    state.attentionZone
}
