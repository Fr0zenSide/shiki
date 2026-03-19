import Foundation
import Testing
@testable import ShikiCtlKit

@Suite("SessionLifecycle state machine")
struct SessionLifecycleTests {

    @Test("Valid transition: spawning → working")
    func validTransitionSpawningToWorking() async throws {
        let lifecycle = SessionLifecycle(
            sessionId: "test-1",
            context: TaskContext(taskId: "t-1", companySlug: "maya", projectPath: "maya")
        )
        try await lifecycle.transition(to: .working, actor: .system, reason: "Claude started")
        let state = await lifecycle.currentState
        #expect(state == .working)
    }

    @Test("Invalid transition: done → working throws")
    func invalidTransitionDoneToWorking() async throws {
        let lifecycle = SessionLifecycle(
            sessionId: "test-2",
            context: TaskContext(taskId: "t-2", companySlug: "maya", projectPath: "maya"),
            initialState: .done
        )
        await #expect(throws: SessionLifecycleError.invalidTransition(from: .done, to: .working)) {
            try await lifecycle.transition(to: .working, actor: .system, reason: "attempt restart")
        }
    }

    @Test("Attention zone: prOpen → .review")
    func attentionZonePrOpenIsReview() async {
        let lifecycle = SessionLifecycle(
            sessionId: "test-3",
            context: TaskContext(taskId: "t-3", companySlug: "maya", projectPath: "maya"),
            initialState: .prOpen
        )
        let zone = await lifecycle.attentionZone
        #expect(zone == .review)
    }

    @Test("Attention zone: approved → .merge")
    func attentionZoneApprovedIsMerge() async {
        let lifecycle = SessionLifecycle(
            sessionId: "test-4",
            context: TaskContext(taskId: "t-4", companySlug: "maya", projectPath: "maya"),
            initialState: .approved
        )
        let zone = await lifecycle.attentionZone
        #expect(zone == .merge)
    }

    @Test("Budget pause when spent >= daily budget")
    func budgetPauseTrigger() async throws {
        let context = TaskContext(
            taskId: "t-5", companySlug: "maya", projectPath: "maya",
            budgetDailyUsd: 10.0, spentTodayUsd: 10.0
        )
        let lifecycle = SessionLifecycle(
            sessionId: "test-5", context: context, initialState: .working
        )
        let shouldPause = await lifecycle.shouldBudgetPause
        #expect(shouldPause)
    }

    @Test("ZFC reconcile: tmux dead + state working → done")
    func zfcReconcileTmuxDeadTransitionsToDone() async throws {
        let lifecycle = SessionLifecycle(
            sessionId: "test-6",
            context: TaskContext(taskId: "t-6", companySlug: "maya", projectPath: "maya"),
            initialState: .working
        )
        try await lifecycle.reconcile(tmuxAlive: false, pidAlive: false)
        let state = await lifecycle.currentState
        #expect(state == .done)
    }

    @Test("ZFC reconcile: tmux alive + state done → no change")
    func zfcReconcileTmuxAliveNoChange() async throws {
        let lifecycle = SessionLifecycle(
            sessionId: "test-7",
            context: TaskContext(taskId: "t-7", companySlug: "maya", projectPath: "maya"),
            initialState: .done
        )
        try await lifecycle.reconcile(tmuxAlive: true, pidAlive: true)
        let state = await lifecycle.currentState
        #expect(state == .done)
    }

    @Test("Transition history records actor and reason")
    func transitionHistoryRecorded() async throws {
        let lifecycle = SessionLifecycle(
            sessionId: "test-8",
            context: TaskContext(taskId: "t-8", companySlug: "wabisabi", projectPath: "wabisabi")
        )
        try await lifecycle.transition(to: .working, actor: .agent("claude-1"), reason: "Task claimed")
        try await lifecycle.transition(to: .prOpen, actor: .agent("claude-1"), reason: "PR created")

        let history = await lifecycle.transitionHistory
        #expect(history.count == 2)
        #expect(history[0].from == .spawning)
        #expect(history[0].to == .working)
        #expect(history[0].actor == .agent("claude-1"))
        #expect(history[0].reason == "Task claimed")
        #expect(history[1].to == .prOpen)
    }
}
