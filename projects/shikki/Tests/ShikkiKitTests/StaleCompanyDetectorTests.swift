import Foundation
import Testing
@testable import ShikkiKit

@Suite("StaleCompanyDetectorService")
struct StaleCompanyDetectorTests {

    // MARK: - Helpers

    private func makeSnapshot(
        health: HealthStatus = .healthy,
        dispatchQueue: [DispatcherTask] = [],
        sessions: [SessionInfo] = []
    ) -> KernelSnapshot {
        KernelSnapshot(
            health: health,
            dispatchQueue: dispatchQueue,
            sessions: sessions
        )
    }

    // MARK: - Tests

    @Test("Detects stale company with pending tasks")
    func test_detects_stale_with_tasks() async throws {
        let client = MockBackendClient()
        client.staleCompaniesResult = [TestFixtures.company(slug: "acme")]

        let service = StaleCompanyDetectorService(client: client)

        let task = TestFixtures.dispatcherTask(companySlug: "acme")
        let snapshot = makeSnapshot(dispatchQueue: [task])

        try await service.tick(snapshot: snapshot)

        let detected = await service.lastDetectedStaleSlugs
        #expect(detected.contains("acme"))
    }

    @Test("Skips stale company with no pending tasks")
    func test_skips_stale_without_tasks() async throws {
        let client = MockBackendClient()
        client.staleCompaniesResult = [TestFixtures.company(slug: "acme")]

        let service = StaleCompanyDetectorService(client: client)
        let snapshot = makeSnapshot(dispatchQueue: [])

        try await service.tick(snapshot: snapshot)

        let detected = await service.lastDetectedStaleSlugs
        #expect(detected.isEmpty)
    }

    @Test("Skips stale company with running session")
    func test_skips_stale_with_running_session() async throws {
        let client = MockBackendClient()
        client.staleCompaniesResult = [TestFixtures.company(slug: "acme")]

        let service = StaleCompanyDetectorService(client: client)

        let task = TestFixtures.dispatcherTask(companySlug: "acme")
        let session = SessionInfo(slug: "acme:task-1", companySlug: "acme", isRunning: true)
        let snapshot = makeSnapshot(dispatchQueue: [task], sessions: [session])

        try await service.tick(snapshot: snapshot)

        let detected = await service.lastDetectedStaleSlugs
        #expect(detected.isEmpty)
    }

    @Test("Skips stale company with exhausted budget")
    func test_skips_budget_exhausted() async throws {
        let client = MockBackendClient()
        client.staleCompaniesResult = [TestFixtures.company(slug: "acme")]

        let service = StaleCompanyDetectorService(client: client)

        let task = TestFixtures.dispatcherTask(
            companySlug: "acme",
            spentToday: 10.0,
            dailyBudget: 10.0
        )
        let snapshot = makeSnapshot(dispatchQueue: [task])

        try await service.tick(snapshot: snapshot)

        let detected = await service.lastDetectedStaleSlugs
        #expect(detected.isEmpty)
    }

    @Test("Skips when backend unhealthy")
    func test_skips_when_unhealthy() async throws {
        let client = MockBackendClient()
        client.staleCompaniesResult = [TestFixtures.company(slug: "acme")]

        let service = StaleCompanyDetectorService(client: client)
        let snapshot = makeSnapshot(health: .unreachable)

        try await service.tick(snapshot: snapshot)

        let detected = await service.lastDetectedStaleSlugs
        #expect(detected.isEmpty)
    }

    @Test("Returns empty when no stale companies")
    func test_no_stale_companies() async throws {
        let client = MockBackendClient()
        client.staleCompaniesResult = []

        let service = StaleCompanyDetectorService(client: client)
        let snapshot = makeSnapshot()

        try await service.tick(snapshot: snapshot)

        let detected = await service.lastDetectedStaleSlugs
        #expect(detected.isEmpty)
    }
}
