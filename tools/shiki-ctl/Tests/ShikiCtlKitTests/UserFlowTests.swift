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

@Suite("Flow B: PR Review Lifecycle")
struct FlowPRReviewTests {

    @Test("Review flow: navigate → verdict → summary")
    func reviewFlow() {
        let sections = [
            ReviewSection(index: 0, title: "Architecture", body: "Clean layers", questions: [ReviewQuestion(text: "DI correct?")]),
            ReviewSection(index: 1, title: "Tests", body: "Coverage ok", questions: [ReviewQuestion(text: "Edge cases?")]),
            ReviewSection(index: 2, title: "Security", body: "No secrets", questions: []),
        ]
        let review = PRReview(title: "Test PR", branch: "test", filesChanged: 3, testsInfo: "10/10", sections: sections, checklist: [])
        var engine = PRReviewEngine(review: review, quickMode: true)

        // Start in section list (quick mode)
        #expect(engine.currentScreen == .sectionList)

        // Navigate to section 0
        engine.handle(key: .enter)
        #expect(engine.currentScreen == .sectionView(0))

        // Approve section 0
        engine.handle(key: .char("a"))
        #expect(engine.currentScreen == .sectionList)
        #expect(engine.state.verdicts[0] == .approved)

        // Navigate to section 1
        engine.handle(key: .down)
        engine.handle(key: .enter)
        #expect(engine.currentScreen == .sectionView(1))

        // Request changes on section 1
        engine.handle(key: .char("r"))
        #expect(engine.state.verdicts[1] == .requestChanges)

        // Go to summary
        engine.handle(key: .char("s"))
        #expect(engine.currentScreen == .summary)

        // Verify counts
        let counts = engine.state.verdictCounts()
        #expect(counts.approved == 1)
        #expect(counts.requestChanges == 1)
    }
}

@Suite("Flow C: Agent Handoff Chain")
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

@Suite("Flow D: Crash Recovery")
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

@Suite("Flow E: Watchdog Escalation")
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

@Suite("Flow F: Multi-PR Queue")
struct FlowPRQueueTests {

    @Test("Queue sorts and filters PRs by risk")
    func queueSortAndFilter() {
        let queue = PRQueue(workspacePath: "/tmp")

        let entries = [
            PRQueueEntry(number: 6, title: "v3 orchestrator", branch: "feat/v3", baseBranch: "develop",
                         additions: 3600, deletions: 1, fileCount: 32, risk: .high,
                         hasPrecomputedReview: true, hasReviewState: false),
            PRQueueEntry(number: 2, title: "MediaKit", branch: "story/media", baseBranch: "develop",
                         additions: 2022, deletions: 0, fileCount: 48, risk: .medium,
                         hasPrecomputedReview: true, hasReviewState: false),
            PRQueueEntry(number: 5, title: "CLI v0.2.0", branch: "feat/cli", baseBranch: "develop",
                         additions: 3010, deletions: 767, fileCount: 28, risk: .high,
                         hasPrecomputedReview: true, hasReviewState: false),
        ]

        let sorted = queue.sorted(entries)

        // High risk first (by size tiebreak: #6 > #5 since 3601 > 3777)
        #expect(sorted[0].risk == .high)
        #expect(sorted[1].risk == .high)
        #expect(sorted[2].risk == .medium)

        // All have precomputed reviews
        #expect(sorted.allSatisfy { $0.hasPrecomputedReview })
    }
}
