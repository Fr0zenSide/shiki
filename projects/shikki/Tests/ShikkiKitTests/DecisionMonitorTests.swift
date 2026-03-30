import Foundation
import Testing
@testable import ShikkiKit

@Suite("DecisionMonitorService")
struct DecisionMonitorTests {

    // MARK: - Helpers

    private func makeSnapshot(
        health: HealthStatus = .healthy,
        decisions: [Decision] = []
    ) -> KernelSnapshot {
        KernelSnapshot(
            health: health,
            pendingDecisions: decisions
        )
    }

    // MARK: - Tests

    @Test("Notifies on new T1 decisions")
    func test_notifies_new_t1_decisions() async throws {
        let notifier = MockNotificationSender()
        let service = DecisionMonitorService(notifier: notifier)

        let decision = TestFixtures.decision(id: "d-1", tier: 1, companySlug: "acme")
        let snapshot = makeSnapshot(decisions: [decision])

        try await service.tick(snapshot: snapshot)

        #expect(notifier.sentNotifications.count == 1)
        #expect(notifier.sentNotifications.first?.title == "T1: acme")
    }

    @Test("Skips T2+ decisions for notification")
    func test_skips_non_t1_decisions() async throws {
        let notifier = MockNotificationSender()
        let service = DecisionMonitorService(notifier: notifier)

        let t2 = TestFixtures.decision(id: "d-2", tier: 2)
        let t3 = TestFixtures.decision(id: "d-3", tier: 3)
        let snapshot = makeSnapshot(decisions: [t2, t3])

        try await service.tick(snapshot: snapshot)

        #expect(notifier.sentNotifications.isEmpty)
    }

    @Test("Does not re-notify same decision")
    func test_no_duplicate_notification() async throws {
        let notifier = MockNotificationSender()
        let service = DecisionMonitorService(notifier: notifier)

        let decision = TestFixtures.decision(id: "d-1", tier: 1)
        let snapshot = makeSnapshot(decisions: [decision])

        // First tick — notifies
        try await service.tick(snapshot: snapshot)
        #expect(notifier.sentNotifications.count == 1)

        // Second tick with same decision — should NOT re-notify
        try await service.tick(snapshot: snapshot)
        #expect(notifier.sentNotifications.count == 1)
    }

    @Test("Detects answered decisions")
    func test_detects_answered_decisions() async throws {
        let notifier = MockNotificationSender()
        let service = DecisionMonitorService(notifier: notifier)

        let decision = TestFixtures.decision(id: "d-1", tier: 1)

        // Tick 1: decision is pending
        try await service.tick(snapshot: makeSnapshot(decisions: [decision]))

        // Tick 2: decision is gone (answered)
        try await service.tick(snapshot: makeSnapshot(decisions: []))

        let answered = await service.lastAnsweredIds
        #expect(answered.contains("d-1"))
    }

    @Test("Skips when backend unhealthy")
    func test_skips_when_unhealthy() async throws {
        let notifier = MockNotificationSender()
        let service = DecisionMonitorService(notifier: notifier)

        let decision = TestFixtures.decision(id: "d-1", tier: 1)
        let snapshot = makeSnapshot(health: .unreachable, decisions: [decision])

        try await service.tick(snapshot: snapshot)

        // No notification sent because health check failed
        #expect(notifier.sentNotifications.isEmpty)
    }

    @Test("Tolerates notification failure")
    func test_tolerates_notification_failure() async throws {
        let notifier = MockNotificationSender()
        notifier.shouldThrow = NSError(domain: "ntfy", code: -1)
        let service = DecisionMonitorService(notifier: notifier)

        let decision = TestFixtures.decision(id: "d-1", tier: 1)
        let snapshot = makeSnapshot(decisions: [decision])

        // Should not throw even though notifier fails
        try await service.tick(snapshot: snapshot)

        // Decision still tracked (notification attempted)
        let count = await service.notifiedCount
        #expect(count == 1)
    }

    @Test("canRun defaults to healthy-only")
    func test_canRun() async {
        let notifier = MockNotificationSender()
        let service = DecisionMonitorService(notifier: notifier)

        #expect(await service.canRun(health: .healthy) == true)
        #expect(await service.canRun(health: .unreachable) == false)
    }
}
