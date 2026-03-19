import Foundation
import Testing
@testable import ShikiCtlKit

/// Full user flow scenarios testing the logic of each feature path
/// without requiring tmux, backend, or interactive terminal.

/// Thread-safe event collector for async test assertions.
private actor EventCollector {
    var events: [ShikiEvent] = []
    func add(_ event: ShikiEvent) { events.append(event) }
}

@Suite("Flow A: Session Dispatch Lifecycle")
struct FlowSessionDispatchTests {

    @Test("Full lifecycle: spawn → work → PR → review → merge → done")
    func fullLifecycle() async throws {
        let journal = SessionJournal(basePath: NSTemporaryDirectory() + "shiki-flow-a-\(UUID().uuidString)")
        let discoverer = MockSessionDiscoverer()
        let registry = SessionRegistry(discoverer: discoverer, journal: journal)
        let bus = InProcessEventBus()

        // Subscribe to events via a thread-safe collector
        let stream = await bus.subscribe(filter: .all)
        let eventCollector = EventCollector()
        let collector = Task {
            for await event in stream {
                await eventCollector.add(event)
            }
        }

        // 1. Dispatch: register session
        let context = TaskContext(
            taskId: "t-1", companySlug: "maya", projectPath: "maya",
            budgetDailyUsd: 15.0, spentTodayUsd: 0
        )
        await registry.register(windowName: "maya:spm-wave3", paneId: "%5", pid: 12345, context: context)
        await bus.publish(ShikiEvent(source: .orchestrator, type: .companyDispatched, scope: .project(slug: "maya")))

        // 2. Lifecycle transitions
        let lifecycle = SessionLifecycle(sessionId: "maya:spm-wave3", context: context)
        try await lifecycle.transition(to: .working, actor: .agent("claude-1"), reason: "Task claimed")
        try await lifecycle.transition(to: .prOpen, actor: .agent("claude-1"), reason: "PR created")
        try await lifecycle.transition(to: .reviewPending, actor: .system, reason: "Reviewer assigned")
        try await lifecycle.transition(to: .approved, actor: .user("jeoffrey"), reason: "LGTM")
        try await lifecycle.transition(to: .merged, actor: .system, reason: "Auto-merge")
        try await lifecycle.transition(to: .done, actor: .system, reason: "Cleanup")

        // 3. Journal each transition
        for transition in await lifecycle.transitionHistory {
            let checkpoint = SessionCheckpoint(
                sessionId: "maya:spm-wave3", state: transition.to,
                reason: .stateTransition, metadata: ["reason": transition.reason]
            )
            try await journal.checkpoint(checkpoint)
        }

        // 4. Verify journal
        let checkpoints = try await journal.loadCheckpoints(sessionId: "maya:spm-wave3")
        #expect(checkpoints.count == 6)
        #expect(checkpoints.last?.state == .done)

        // 5. Verify event was published
        try await Task.sleep(for: .milliseconds(50))
        collector.cancel()
        let events = await eventCollector.events
        #expect(events.count >= 1)
        #expect(events[0].type == .companyDispatched)

        // 6. Final state
        #expect(await lifecycle.currentState == .done)
        #expect(await lifecycle.attentionZone == .idle)
    }
}

@Suite("Flow B: Agent Handoff Chain")
struct FlowAgentHandoffTests {

    @Test("Standard chain: implement → verify → review")
    func standardHandoff() throws {
        let chain = HandoffChain.standard

        // Step 1: implement finishes
        let next1 = chain.next(after: .implement)
        #expect(next1 == .verify)

        // Step 2: serialize handoff context
        let context = HandoffContext(
            fromPersona: .implement, toPersona: .verify,
            specPath: ".shiki/specs/t-1.md",
            changedFiles: ["Foo.swift", "FooTests.swift"],
            testResults: "42 tests passed",
            summary: "Feature complete"
        )
        let data = try JSONEncoder().encode(context)
        let decoded = try JSONDecoder().decode(HandoffContext.self, from: data)
        #expect(decoded.changedFiles.count == 2)
        #expect(decoded.testResults == "42 tests passed")

        // Step 3: verify finishes → review
        let next2 = chain.next(after: .verify)
        #expect(next2 == .review)

        // Step 4: review is terminal
        let next3 = chain.next(after: .review)
        #expect(next3 == nil)

        // Step 5: verify persona constraints
        #expect(!AgentPersona.verify.canEdit)
        #expect(AgentPersona.verify.canTest)
        #expect(!AgentPersona.review.canEdit)
    }
}

@Suite("Flow C: Crash Recovery")
struct FlowCrashRecoveryTests {

    @Test("Full recovery: journal → crash → scan → recover")
    func fullRecovery() async throws {
        let basePath = NSTemporaryDirectory() + "shiki-flow-d-\(UUID().uuidString)"
        let journal = SessionJournal(basePath: basePath)

        // 1. Normal operation: session working, checkpoints written
        let c1 = SessionCheckpoint(sessionId: "crashed-sess", state: .spawning, reason: .stateTransition, metadata: ["task": "t-5"])
        let c2 = SessionCheckpoint(sessionId: "crashed-sess", state: .working, reason: .stateTransition, metadata: ["task": "t-5", "branch": "feature/auth"])
        try await journal.checkpoint(c1)
        try await journal.checkpoint(c2)

        // 2. Simulate crash (no .done checkpoint)

        // 3. Recovery scan
        let recovery = RecoveryManager(journal: journal)
        let recoverable = try await recovery.findRecoverableSessions()
        #expect(recoverable.count == 1)
        #expect(recoverable[0].sessionId == "crashed-sess")
        #expect(recoverable[0].lastState == .working)

        // 4. Build recovery plan
        let plan = try await recovery.buildRecoveryPlan(sessionId: "crashed-sess")
        #expect(plan != nil)
        #expect(plan?.checkpoints.count == 2)
        #expect(plan?.metadata?["branch"] == "feature/auth")

        try? FileManager.default.removeItem(atPath: basePath)
    }
}

@Suite("Flow D: Watchdog Escalation")
struct FlowWatchdogTests {

    @Test("Progressive escalation through all levels")
    func progressiveEscalation() {
        let watchdog = Watchdog(config: .default)

        // Normal working — no action at 30s
        #expect(watchdog.evaluate(idleSeconds: 30, state: .working, contextPct: 20) == .none)

        // Level 1: warn at 2min
        #expect(watchdog.evaluate(idleSeconds: 120, state: .working, contextPct: 20) == .warn)

        // Level 2: nudge at 5min
        #expect(watchdog.evaluate(idleSeconds: 300, state: .working, contextPct: 20) == .nudge)

        // Level 3: AI triage at 10min
        #expect(watchdog.evaluate(idleSeconds: 600, state: .working, contextPct: 20) == .aiTriage)

        // Level 4: terminate at 15min
        #expect(watchdog.evaluate(idleSeconds: 900, state: .working, contextPct: 20) == .terminate)

        // Decision gate: skip ALL escalation for awaitingApproval
        #expect(watchdog.evaluate(idleSeconds: 900, state: .awaitingApproval, contextPct: 20) == .none)

        // Context pressure: 85% context + 1min idle = warn (effectively 2min)
        #expect(watchdog.evaluate(idleSeconds: 60, state: .working, contextPct: 85) == .warn)
    }
}

