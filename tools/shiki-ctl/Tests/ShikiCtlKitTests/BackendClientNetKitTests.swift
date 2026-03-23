import Foundation
import NetKit
import Testing
@testable import ShikiCtlKit

@Suite("BackendClient — NetKit integration")
struct BackendClientNetKitTests {

    // MARK: - Helpers

    /// Minimal valid JSON for a HeartbeatResponse.
    private static let heartbeatJSON = """
    {
        "budgetExceeded": false,
        "sessionId": "s-123",
        "timestamp": "2026-03-15T10:00:00Z"
    }
    """.data(using: .utf8)!

    /// Minimal valid JSON for a Company array.
    private static let companiesJSON = """
    [{
        "id": "c-1",
        "project_id": "p-1",
        "slug": "test",
        "display_name": "Test Co",
        "status": "active",
        "priority": 3,
        "budget": {"daily_usd": 8, "monthly_usd": 200, "spent_today_usd": 0},
        "schedule": {"active_hours": [8, 22], "timezone": "UTC", "days": [1,2,3,4,5]},
        "config": {},
        "created_at": "2026-01-01T00:00:00Z",
        "updated_at": "2026-01-01T00:00:00Z"
    }]
    """.data(using: .utf8)!

    /// Minimal valid JSON for a Decision array.
    private static let decisionsJSON = """
    [{
        "id": "d-1",
        "company_id": "c-1",
        "tier": 1,
        "question": "Which approach?",
        "options": null,
        "answered": false,
        "created_at": "2026-03-15T10:00:00Z",
        "metadata": {}
    }]
    """.data(using: .utf8)!

    // MARK: - Tests

    @Test("sendHeartbeat decodes response via MockNetworkService")
    func sendHeartbeatSuccess() async throws {
        let mock = MockNetworkService()
        mock.resultData = Self.heartbeatJSON

        let client = BackendClient(network: mock)
        let response = try await client.sendHeartbeat(companyId: "c-1", sessionId: "s-123")

        #expect(response.budgetExceeded == false)
        #expect(response.sessionId == "s-123")
        #expect(mock.capturedRequests.count == 1)

        let request = mock.capturedRequests[0]
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/api/orchestrator/heartbeat")
    }

    @Test("getReadyCompanies decodes array via MockNetworkService")
    func getReadyCompanies() async throws {
        let mock = MockNetworkService()
        mock.resultData = Self.companiesJSON

        let client = BackendClient(network: mock)
        let companies = try await client.getReadyCompanies()

        #expect(companies.count == 1)
        #expect(companies[0].slug == "test")
        #expect(mock.capturedRequests[0].httpMethod == "GET")
        #expect(mock.capturedRequests[0].url?.path == "/api/orchestrator/ready")
    }

    @Test("getPendingDecisions decodes decisions via MockNetworkService")
    func getPendingDecisions() async throws {
        let mock = MockNetworkService()
        mock.resultData = Self.decisionsJSON

        let client = BackendClient(network: mock)
        let decisions = try await client.getPendingDecisions()

        #expect(decisions.count == 1)
        #expect(decisions[0].tier == 1)
        #expect(mock.capturedRequests[0].url?.path == "/api/decision-queue/pending")
    }

    @Test("network error maps to BackendError.httpError")
    func networkErrorMapping() async throws {
        let mock = MockNetworkService()
        mock.statusCode = 500

        let client = BackendClient(network: mock)

        await #expect(throws: BackendError.self) {
            let _: [Company] = try await client.getReadyCompanies()
        }
    }

    @Test("baseURL parsing configures endpoint host and port")
    func baseURLParsing() async throws {
        let mock = MockNetworkService()
        mock.resultData = Self.companiesJSON

        let client = BackendClient(baseURL: "http://192.168.1.12:4000", network: mock)
        _ = try await client.getReadyCompanies()

        let url = mock.capturedRequests[0].url
        #expect(url?.host == "192.168.1.12")
        #expect(url?.port == 4000)
        #expect(url?.scheme == "http")
    }
}
