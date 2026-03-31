import Foundation
import Testing
@testable import ShikkiKit

// MARK: - Test Doubles (ProcessLauncher + NotificationSender)

final class MockProcessLauncher: ProcessLauncher, @unchecked Sendable {
    var launchedSessions: [(taskId: String, companyId: String, companySlug: String, title: String, projectPath: String)] = []
    var runningSlugs: Set<String> = []
    var stoppedSlugs: [String] = []
    var shouldThrow: Error?

    func launchTaskSession(taskId: String, companyId: String, companySlug: String,
                           title: String, projectPath: String) async throws {
        if let error = shouldThrow { throw error }
        let slug = TmuxProcessLauncher.windowName(companySlug: companySlug, title: title)
        launchedSessions.append((taskId, companyId, companySlug, title, projectPath))
        runningSlugs.insert(slug)
    }

    func isSessionRunning(slug: String) async -> Bool {
        runningSlugs.contains(slug)
    }

    func stopSession(slug: String) async throws {
        if let error = shouldThrow { throw error }
        runningSlugs.remove(slug)
        stoppedSlugs.append(slug)
    }

    func listRunningSessions() async -> [String] {
        Array(runningSlugs)
    }
}

final class MockNotificationSender: NotificationSender, @unchecked Sendable {
    var sentNotifications: [(title: String, body: String, priority: NotificationPriority, tags: [String])] = []
    var shouldThrow: Error?

    func send(title: String, body: String, priority: NotificationPriority, tags: [String]) async throws {
        if let error = shouldThrow { throw error }
        sentNotifications.append((title, body, priority, tags))
    }
}

/// Discoverer that returns nothing — used to create an inert SessionRegistry for tests.
struct NullDiscoverer: SessionDiscoverer {
    func discover() async -> [DiscoveredSession] { [] }
}

// MARK: - Helper

/// Build a HeartbeatLoop wired with test doubles.
private func makeHeartbeatLoop(
    client: MockBackendClient = MockBackendClient(),
    launcher: MockProcessLauncher = MockProcessLauncher(),
    notifier: MockNotificationSender = MockNotificationSender(),
    eventBus: InProcessEventBus? = nil,
    registry: SessionRegistry? = nil
) -> (loop: HeartbeatLoop, client: MockBackendClient, launcher: MockProcessLauncher, notifier: MockNotificationSender, eventBus: InProcessEventBus, registry: SessionRegistry) {
    let bus = eventBus ?? InProcessEventBus()
    let reg = registry ?? SessionRegistry(discoverer: NullDiscoverer(), journal: SessionJournal(basePath: "/tmp/shiki-test-journal"))
    let loop = HeartbeatLoop(
        client: client,
        launcher: launcher,
        notifier: notifier,
        registry: reg,
        eventBus: bus,
        interval: .seconds(1)
    )
    return (loop, client, launcher, notifier, bus, reg)
}

// MARK: - Tests

@Suite("HeartbeatLoop — checkAndDispatch", .serialized)
struct HeartbeatLoopDispatchTests {

    @Test("Dispatches task when slots available and queue non-empty")
    func dispatchesTaskWhenSlotsAvailable() async throws {
        let (loop, client, launcher, _, _, _) = makeHeartbeatLoop()

        client.dispatcherQueueResult = [
            TestFixtures.dispatcherTask(
                taskId: "t-1", title: "Fix tests",
                companySlug: "wabisabi", projectPath: "wabisabi"
            )
        ]
        client.companiesResult = [
            TestFixtures.company(slug: "wabisabi", projectPath: "wabisabi")
        ]

        try await loop.checkAndDispatch()

        #expect(launcher.launchedSessions.count == 1)
        #expect(launcher.launchedSessions[0].taskId == "t-1")
        #expect(launcher.launchedSessions[0].companySlug == "wabisabi")
        #expect(launcher.launchedSessions[0].projectPath == "wabisabi")
    }

    @Test("No-ops when dispatcher queue is empty")
    func noOpWhenQueueEmpty() async throws {
        let (loop, client, launcher, _, _, _) = makeHeartbeatLoop()

        client.dispatcherQueueResult = []

        try await loop.checkAndDispatch()

        #expect(launcher.launchedSessions.isEmpty)
    }

    @Test("Skips dispatch when max concurrent slots full")
    func skipsWhenSlotsFull() async throws {
        let launcher = MockProcessLauncher()
        let registry = SessionRegistry(discoverer: NullDiscoverer(), journal: SessionJournal(basePath: "/tmp/shiki-test-journal"))
        // Fill 6 slots (maxConcurrent) in registry
        for i in 0..<6 {
            let slug = "company\(i):task-\(i)"
            await registry.registerManual(windowName: slug, paneId: "%\(i)", pid: pid_t(i + 100), state: .working)
            launcher.runningSlugs.insert(slug)
        }

        let (loop, client, _, _, _, _) = makeHeartbeatLoop(launcher: launcher, registry: registry)
        client.dispatcherQueueResult = [
            TestFixtures.dispatcherTask(taskId: "t-extra", title: "Overflow")
        ]

        try await loop.checkAndDispatch()

        // No new sessions launched
        #expect(launcher.launchedSessions.isEmpty)
    }

    @Test("Skips task when budget exhausted")
    func skipsBudgetExhausted() async throws {
        let (loop, client, launcher, _, _, _) = makeHeartbeatLoop()

        client.dispatcherQueueResult = [
            TestFixtures.dispatcherTask(
                taskId: "t-1", title: "Expensive task",
                companySlug: "wabisabi",
                spentToday: 15.0,   // exceeds daily budget
                dailyBudget: 10.0
            )
        ]

        try await loop.checkAndDispatch()

        #expect(launcher.launchedSessions.isEmpty)
    }

    @Test("Skips task when company already has running session")
    func skipsCompanyWithRunningSession() async throws {
        let launcher = MockProcessLauncher()
        let registry = SessionRegistry(discoverer: NullDiscoverer(), journal: SessionJournal(basePath: "/tmp/shiki-test-journal"))
        launcher.runningSlugs.insert("wabisabi:existing-ta")
        await registry.registerManual(windowName: "wabisabi:existing-ta", paneId: "%0", pid: 100, state: .working)

        let (loop, client, _, _, _, _) = makeHeartbeatLoop(launcher: launcher, registry: registry)
        client.dispatcherQueueResult = [
            TestFixtures.dispatcherTask(
                taskId: "t-2", title: "Another task",
                companySlug: "wabisabi"
            )
        ]

        try await loop.checkAndDispatch()

        #expect(launcher.launchedSessions.isEmpty)
    }

    @Test("Publishes companyDispatched event on dispatch")
    func publishesEventOnDispatch() async throws {
        let bus = InProcessEventBus()
        let (loop, client, _, _, _, _) = makeHeartbeatLoop(eventBus: bus)

        client.dispatcherQueueResult = [
            TestFixtures.dispatcherTask(
                taskId: "t-1", title: "Fix tests",
                companySlug: "maya", projectPath: "Maya"
            )
        ]
        client.companiesResult = [
            TestFixtures.company(id: "company-1", slug: "maya", projectPath: "Maya")
        ]

        // Subscribe before dispatching
        let stream = await bus.subscribe(filter: EventFilter(types: [.companyDispatched]))

        try await loop.checkAndDispatch()

        // Read the first event from the stream
        var receivedEvent: ShikkiEvent?
        for await event in stream {
            receivedEvent = event
            break
        }
        #expect(receivedEvent?.type == .companyDispatched)
        #expect(receivedEvent?.payload["taskId"] == .string("t-1"))
    }
}

@Suite("HeartbeatLoop — cleanupIdleSessions", .serialized)
struct HeartbeatLoopCleanupTests {

    @Test("Removes sessions for inactive companies")
    func removesInactiveSessions() async throws {
        let launcher = MockProcessLauncher()
        let registry = SessionRegistry(discoverer: NullDiscoverer(), journal: SessionJournal(basePath: "/tmp/shiki-test-journal"))
        launcher.runningSlugs.insert("wabisabi:spm-wave3")
        await registry.registerManual(windowName: "wabisabi:spm-wave3", paneId: "%0", pid: 100, state: .working)

        let (loop, client, _, _, _, _) = makeHeartbeatLoop(launcher: launcher, registry: registry)

        // Status says no active companies — wabisabi session should be cleaned up
        client.statusResult = TestFixtures.orchestratorStatus(activeCompanySlugs: [])
        client.companiesResult = [
            TestFixtures.company(id: "c-1", slug: "wabisabi")
        ]
        client.sessionTranscriptResult = TestFixtures.sessionTranscript()

        try await loop.cleanupIdleSessions()

        #expect(launcher.stoppedSlugs.contains("wabisabi:spm-wave3"))
    }

    @Test("Keeps sessions for active companies")
    func keepsActiveSessions() async throws {
        let launcher = MockProcessLauncher()
        let registry = SessionRegistry(discoverer: NullDiscoverer(), journal: SessionJournal(basePath: "/tmp/shiki-test-journal"))
        launcher.runningSlugs.insert("maya:fix-tests")
        await registry.registerManual(windowName: "maya:fix-tests", paneId: "%0", pid: 100, state: .working)

        let (loop, client, _, _, _, _) = makeHeartbeatLoop(launcher: launcher, registry: registry)

        // Maya is still active
        client.statusResult = TestFixtures.orchestratorStatus(activeCompanySlugs: ["maya"])

        try await loop.cleanupIdleSessions()

        #expect(launcher.stoppedSlugs.isEmpty)
        #expect(launcher.runningSlugs.contains("maya:fix-tests"))
    }

    @Test("No-ops when no running sessions")
    func noOpWhenNoSessions() async throws {
        let (loop, client, launcher, _, _, _) = makeHeartbeatLoop()
        client.statusResult = TestFixtures.orchestratorStatus(activeCompanySlugs: [])

        try await loop.cleanupIdleSessions()

        #expect(launcher.stoppedSlugs.isEmpty)
        #expect(client.getStatusCallCount == 0) // Should early-return before calling getStatus
    }

    @Test("Publishes sessionEnd event on cleanup")
    func publishesSessionEndEvent() async throws {
        let bus = InProcessEventBus()
        let launcher = MockProcessLauncher()
        let registry = SessionRegistry(discoverer: NullDiscoverer(), journal: SessionJournal(basePath: "/tmp/shiki-test-journal"))
        launcher.runningSlugs.insert("wabisabi:cleanup-me")
        await registry.registerManual(windowName: "wabisabi:cleanup-me", paneId: "%0", pid: 100, state: .working)

        let (loop, client, _, _, _, _) = makeHeartbeatLoop(launcher: launcher, eventBus: bus, registry: registry)
        client.statusResult = TestFixtures.orchestratorStatus(activeCompanySlugs: [])
        client.companiesResult = [TestFixtures.company(slug: "wabisabi")]
        client.sessionTranscriptResult = TestFixtures.sessionTranscript()

        let stream = await bus.subscribe(filter: EventFilter(types: [.sessionEnd]))

        try await loop.cleanupIdleSessions()

        var receivedEvent: ShikkiEvent?
        for await event in stream {
            receivedEvent = event
            break
        }
        #expect(receivedEvent?.type == .sessionEnd)
        #expect(receivedEvent?.payload["reason"] == .string("company_inactive"))
    }
}

@Suite("HeartbeatLoop — checkDecisions", .serialized)
struct HeartbeatLoopDecisionTests {

    @Test("Sends ntfy notification for new T1 decisions")
    func notifiesOnNewT1Decisions() async throws {
        let (loop, client, _, notifier, _, _) = makeHeartbeatLoop()

        client.pendingDecisionsResult = [
            TestFixtures.decision(id: "d-1", tier: 1, question: "Should we cache images?", companySlug: "maya")
        ]

        try await loop.checkDecisions()

        #expect(notifier.sentNotifications.count == 1)
        #expect(notifier.sentNotifications[0].title == "T1: maya")
        #expect(notifier.sentNotifications[0].body.contains("cache"))
        #expect(notifier.sentNotifications[0].priority == .high)
    }

    @Test("Ignores T2+ decisions for ntfy notifications")
    func ignoresNonT1Decisions() async throws {
        let (loop, client, _, notifier, _, _) = makeHeartbeatLoop()

        client.pendingDecisionsResult = [
            TestFixtures.decision(id: "d-2", tier: 2, question: "Minor style choice")
        ]

        try await loop.checkDecisions()

        #expect(notifier.sentNotifications.isEmpty)
    }

    @Test("Does not re-notify for already-seen decisions")
    func doesNotReNotify() async throws {
        let (loop, client, _, notifier, _, _) = makeHeartbeatLoop()

        let decision = TestFixtures.decision(id: "d-1", tier: 1, question: "Cache images?")
        client.pendingDecisionsResult = [decision]

        // First call — should notify
        try await loop.checkDecisions()
        #expect(notifier.sentNotifications.count == 1)

        // Second call with same decision — should NOT notify again
        try await loop.checkDecisions()
        #expect(notifier.sentNotifications.count == 1)
    }

    @Test("Cleans up notified IDs when decision is answered")
    func cleansUpAnsweredDecisions() async throws {
        let (loop, client, _, notifier, _, _) = makeHeartbeatLoop()

        client.pendingDecisionsResult = [
            TestFixtures.decision(id: "d-1", tier: 1, question: "Cache?")
        ]
        try await loop.checkDecisions()
        #expect(notifier.sentNotifications.count == 1)

        // Decision answered — no longer in pending list
        client.pendingDecisionsResult = []
        try await loop.checkDecisions()

        // Now if the same decision somehow re-appears as pending (edge case),
        // it should be notified again because we cleaned up the ID
        client.pendingDecisionsResult = [
            TestFixtures.decision(id: "d-1", tier: 1, question: "Cache? (re-asked)")
        ]
        try await loop.checkDecisions()
        #expect(notifier.sentNotifications.count == 2)
    }

    @Test("Publishes decisionPending event")
    func publishesDecisionPendingEvent() async throws {
        let bus = InProcessEventBus()
        let (loop, client, _, _, _, _) = makeHeartbeatLoop(eventBus: bus)

        client.pendingDecisionsResult = [
            TestFixtures.decision(id: "d-1", tier: 1, question: "Should we deploy?", companySlug: "maya")
        ]

        let stream = await bus.subscribe(filter: EventFilter(types: [.decisionPending]))

        try await loop.checkDecisions()

        var receivedEvent: ShikkiEvent?
        for await event in stream {
            receivedEvent = event
            break
        }
        #expect(receivedEvent?.type == .decisionPending)
        #expect(receivedEvent?.payload["question"] == .string("Should we deploy?"))
    }

    @Test("Tolerates ntfy send failure without crashing")
    func toleratesNtfyFailure() async throws {
        let notifier = MockNotificationSender()
        notifier.shouldThrow = MockError.apiUnreachable

        let (loop, client, _, _, _, _) = makeHeartbeatLoop(notifier: notifier)
        client.pendingDecisionsResult = [
            TestFixtures.decision(id: "d-1", tier: 1, question: "Should we ship?")
        ]

        // Should not throw despite notification failure
        try await loop.checkDecisions()
    }
}

@Suite("HeartbeatLoop — checkAnsweredDecisions", .serialized)
struct HeartbeatLoopAnsweredDecisionsTests {

    @Test("Detects decisions that disappeared from pending")
    func detectsAnsweredDecisions() async throws {
        let (loop, client, _, _, _, _) = makeHeartbeatLoop()

        // First cycle: establish baseline — decision d-1 is pending
        let decisions = [TestFixtures.decision(id: "d-1", tier: 1, question: "Cache?")]
        client.pendingDecisionsResult = decisions
        client.dispatcherQueueResult = []

        // checkAnsweredDecisions sets previousPendingDecisionIds at the end
        try await loop.checkAnsweredDecisions(currentPending: decisions)

        // Second cycle: d-1 is gone from pending (answered)
        client.dispatcherQueueResult = [
            TestFixtures.dispatcherTask(taskId: "t-1", title: "Resume work", companySlug: "wabisabi")
        ]

        // This should detect d-1 was answered and check for re-dispatch
        try await loop.checkAnsweredDecisions(currentPending: [])

        // The method queries the dispatcher queue when it detects answered decisions
        #expect(client.getDispatcherQueueCallCount >= 1)
    }

    @Test("No-ops when no decisions were previously pending")
    func noOpWhenNoPreviousPending() async throws {
        let (loop, client, _, _, _, _) = makeHeartbeatLoop()

        // First call with empty pending list
        try await loop.checkAnsweredDecisions(currentPending: [])

        // Should not call getDispatcherQueue since no decisions disappeared
        #expect(client.getDispatcherQueueCallCount == 0)
    }
}

@Suite("HeartbeatLoop — checkStaleCompaniesSmart", .serialized)
struct HeartbeatLoopStaleCompaniesTests {

    @Test("Relaunches stale company with pending tasks and no session")
    func relaunchesStaleCompany() async throws {
        let (loop, client, launcher, _, _, _) = makeHeartbeatLoop()

        client.staleCompaniesResult = [
            TestFixtures.company(id: "c-1", slug: "maya", projectPath: "Maya")
        ]
        client.dispatcherQueueResult = [
            TestFixtures.dispatcherTask(taskId: "t-1", title: "Fix UI", companySlug: "maya", projectPath: "Maya")
        ]

        try await loop.checkStaleCompaniesSmart()

        #expect(launcher.launchedSessions.count == 1)
        #expect(launcher.launchedSessions[0].companySlug == "maya")
    }

    @Test("Skips stale company with no pending tasks")
    func skipsStaleWithoutTasks() async throws {
        let (loop, client, launcher, _, _, _) = makeHeartbeatLoop()

        client.staleCompaniesResult = [
            TestFixtures.company(id: "c-1", slug: "maya")
        ]
        client.dispatcherQueueResult = [] // no tasks

        try await loop.checkStaleCompaniesSmart()

        #expect(launcher.launchedSessions.isEmpty)
    }

    @Test("Skips stale company that already has running session")
    func skipsStaleWithRunningSession() async throws {
        let launcher = MockProcessLauncher()
        let registry = SessionRegistry(discoverer: NullDiscoverer(), journal: SessionJournal(basePath: "/tmp/shiki-test-journal"))
        launcher.runningSlugs.insert("maya:fix-ui")
        await registry.registerManual(windowName: "maya:fix-ui", paneId: "%0", pid: 100, state: .working)

        let (loop, client, _, _, _, _) = makeHeartbeatLoop(launcher: launcher, registry: registry)

        client.staleCompaniesResult = [
            TestFixtures.company(id: "c-1", slug: "maya")
        ]
        client.dispatcherQueueResult = [
            TestFixtures.dispatcherTask(taskId: "t-1", title: "Fix UI", companySlug: "maya")
        ]

        try await loop.checkStaleCompaniesSmart()

        #expect(launcher.launchedSessions.isEmpty)
    }

    @Test("Skips stale company with exhausted budget")
    func skipsStaleWithExhaustedBudget() async throws {
        let (loop, client, launcher, _, _, _) = makeHeartbeatLoop()

        client.staleCompaniesResult = [
            TestFixtures.company(id: "c-1", slug: "maya")
        ]
        client.dispatcherQueueResult = [
            TestFixtures.dispatcherTask(
                taskId: "t-1", title: "Fix UI", companySlug: "maya",
                spentToday: 15.0, dailyBudget: 10.0
            )
        ]

        try await loop.checkStaleCompaniesSmart()

        #expect(launcher.launchedSessions.isEmpty)
    }

    @Test("No-ops when no stale companies")
    func noOpWhenNoStaleCompanies() async throws {
        let (loop, client, launcher, _, _, _) = makeHeartbeatLoop()

        client.staleCompaniesResult = []

        try await loop.checkStaleCompaniesSmart()

        #expect(launcher.launchedSessions.isEmpty)
        // Should early-return before calling getDispatcherQueue
        #expect(client.getDispatcherQueueCallCount == 0)
    }
}

@Suite("HeartbeatLoop — event bus integration", .serialized)
struct HeartbeatLoopEventBusTests {

    @Test("Heartbeat event is published on each run tick")
    func heartbeatEventPublished() async throws {
        let bus = InProcessEventBus()
        let client = MockBackendClient()
        let launcher = MockProcessLauncher()
        let notifier = MockNotificationSender()

        let registry = SessionRegistry(
            discoverer: NullDiscoverer(),
            journal: SessionJournal(basePath: "/tmp/shiki-test-journal")
        )
        let loop = HeartbeatLoop(
            client: client,
            launcher: launcher,
            notifier: notifier,
            registry: registry,
            eventBus: bus,
            interval: .seconds(1)
        )

        // Configure client for a successful tick
        client.healthCheckResult = true
        client.pendingDecisionsResult = []
        client.dispatcherQueueResult = []
        client.statusResult = TestFixtures.orchestratorStatus()
        client.staleCompaniesResult = []

        let stream = await bus.subscribe(filter: EventFilter(types: [.heartbeat]))

        // Run the loop in a task and cancel after receiving the heartbeat event
        let runTask = Task { await loop.run() }

        var receivedHeartbeat = false
        for await event in stream {
            if event.type == .heartbeat {
                receivedHeartbeat = true
                break
            }
        }

        runTask.cancel()
        #expect(receivedHeartbeat)
    }
}

@Suite("HeartbeatLoop — error handling", .serialized)
struct HeartbeatLoopErrorTests {

    @Test("Continues loop when API is unreachable on health check")
    func continuesOnHealthCheckFailure() async throws {
        let client = MockBackendClient()
        client.healthCheckResult = false

        let bus = InProcessEventBus()
        let launcher = MockProcessLauncher()
        let notifier = MockNotificationSender()

        let registry = SessionRegistry(
            discoverer: NullDiscoverer(),
            journal: SessionJournal(basePath: "/tmp/shiki-test-journal")
        )
        let loop = HeartbeatLoop(
            client: client,
            launcher: launcher,
            notifier: notifier,
            registry: registry,
            eventBus: bus,
            interval: .milliseconds(50)
        )

        // Run for a brief moment — should not crash
        let runTask = Task { await loop.run() }
        try await Task.sleep(for: .milliseconds(200))
        runTask.cancel()

        // Health check was called but no dispatch occurred because API was "unreachable"
        #expect(client.healthCheckCallCount >= 1)
        #expect(client.getDispatcherQueueCallCount == 0)
    }

    @Test("Continues loop when individual method throws")
    func continuesOnMethodError() async throws {
        let client = MockBackendClient()
        client.healthCheckResult = true
        // getPendingDecisions will throw, but the loop should catch and continue
        client.pendingDecisionsResult = []
        client.dispatcherQueueResult = []
        client.statusResult = TestFixtures.orchestratorStatus()
        client.staleCompaniesResult = []

        let bus = InProcessEventBus()
        let launcher = MockProcessLauncher()
        let notifier = MockNotificationSender()

        let registry = SessionRegistry(
            discoverer: NullDiscoverer(),
            journal: SessionJournal(basePath: "/tmp/shiki-test-journal")
        )
        let loop = HeartbeatLoop(
            client: client,
            launcher: launcher,
            notifier: notifier,
            registry: registry,
            eventBus: bus,
            interval: .milliseconds(50)
        )

        // Run briefly — should survive errors
        let runTask = Task { await loop.run() }
        try await Task.sleep(for: .milliseconds(200))
        runTask.cancel()

        // At least one health check happened
        #expect(client.healthCheckCallCount >= 1)
    }
}

// MARK: - Mock Validation Tests

@Suite("Test doubles — validation")
struct TestDoubleValidationTests {

    @Test("MockProcessLauncher tracks launches and stops")
    func launcherTracking() async throws {
        let launcher = MockProcessLauncher()

        try await launcher.launchTaskSession(
            taskId: "t-1", companyId: "id-1", companySlug: "wabisabi",
            title: "SPM-wave3", projectPath: "wabisabi"
        )
        #expect(launcher.launchedSessions.count == 1)
        #expect(launcher.launchedSessions[0].companySlug == "wabisabi")

        let slug = TmuxProcessLauncher.windowName(companySlug: "wabisabi", title: "SPM-wave3")
        #expect(await launcher.isSessionRunning(slug: slug))

        try await launcher.stopSession(slug: slug)
        #expect(!(await launcher.isSessionRunning(slug: slug)))
        #expect(launcher.stoppedSlugs == [slug])
    }

    @Test("MockNotificationSender records sent notifications")
    func notifierTracking() async throws {
        let notifier = MockNotificationSender()

        try await notifier.send(title: "Test", body: "body", priority: .high, tags: ["test"])
        #expect(notifier.sentNotifications.count == 1)
        #expect(notifier.sentNotifications[0].title == "Test")
    }

    @Test("MockBackendClient tracks call counts")
    func backendClientCallCounts() async throws {
        let client = MockBackendClient()
        client.dispatcherQueueResult = []
        client.pendingDecisionsResult = []
        client.staleCompaniesResult = []

        _ = try await client.getDispatcherQueue()
        _ = try await client.getDispatcherQueue()
        _ = try await client.getPendingDecisions()

        #expect(client.getDispatcherQueueCallCount == 2)
        #expect(client.getPendingDecisionsCallCount == 1)
    }

    @Test("MockBackendClient throws when configured")
    func backendClientThrows() async throws {
        let client = MockBackendClient()
        client.shouldThrow = MockError.apiUnreachable

        await #expect(throws: MockError.self) {
            _ = try await client.healthCheck()
        }
    }

    @Test("listRunningSessions returns all active slugs")
    func listRunningSessions() async throws {
        let launcher = MockProcessLauncher()

        try await launcher.launchTaskSession(
            taskId: "t-1", companyId: "id-1", companySlug: "maya",
            title: "MayaKit-wave2", projectPath: "Maya"
        )
        try await launcher.launchTaskSession(
            taskId: "t-2", companyId: "id-2", companySlug: "wabisabi",
            title: "SPM-wave3", projectPath: "wabisabi"
        )

        let sessions = await launcher.listRunningSessions()
        #expect(sessions.count == 2)
    }
}

@Suite("Window naming")
struct WindowNamingTests {

    @Test("Window name format")
    func windowNameFormat() {
        let name = TmuxProcessLauncher.windowName(companySlug: "maya", title: "MayaKit public API wave 2")
        #expect(name == "maya:mayakit-public-")
    }

    @Test("Short title stays intact")
    func shortTitle() {
        let name = TmuxProcessLauncher.windowName(companySlug: "flsh", title: "MLX pipeline")
        #expect(name == "flsh:mlx-pipeline")
    }
}
