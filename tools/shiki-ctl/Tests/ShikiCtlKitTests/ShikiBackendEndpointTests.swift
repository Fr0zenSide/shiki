import Foundation
import Testing
@testable import ShikiCtlKit

@Suite("ShikiBackendEndpoint — typed endpoint URL/method/body")
struct ShikiBackendEndpointTests {

    // MARK: - Health

    @Test("health endpoint builds correct path and GET method")
    func healthEndpoint() {
        let ep = ShikiBackendEndpoint.health
        #expect(ep.path == "/health")
        #expect(ep.method == .GET)
        #expect(ep.body == nil)
        #expect(ep.queryParams == nil)
    }

    // MARK: - Orchestrator

    @Test("orchestratorStatus endpoint")
    func orchestratorStatus() {
        let ep = ShikiBackendEndpoint.orchestratorStatus
        #expect(ep.path == "/api/orchestrator/status")
        #expect(ep.method == .GET)
        #expect(ep.body == nil)
    }

    @Test("staleCompanies endpoint with threshold query param")
    func staleCompanies() {
        let ep = ShikiBackendEndpoint.staleCompanies(thresholdMinutes: 10)
        #expect(ep.path == "/api/orchestrator/stale")
        #expect(ep.method == .GET)
        let params = ep.queryParams as? [String: String]
        #expect(params?["threshold_minutes"] == "10")
    }

    @Test("readyCompanies endpoint")
    func readyCompanies() {
        let ep = ShikiBackendEndpoint.readyCompanies
        #expect(ep.path == "/api/orchestrator/ready")
        #expect(ep.method == .GET)
    }

    @Test("dispatcherQueue endpoint")
    func dispatcherQueue() {
        let ep = ShikiBackendEndpoint.dispatcherQueue
        #expect(ep.path == "/api/orchestrator/dispatcher-queue")
        #expect(ep.method == .GET)
    }

    @Test("dailyReport endpoint with date query param")
    func dailyReportWithDate() {
        let ep = ShikiBackendEndpoint.dailyReport(date: "2026-03-15")
        #expect(ep.path == "/api/orchestrator/report")
        #expect(ep.method == .GET)
        let params = ep.queryParams as? [String: String]
        #expect(params?["date"] == "2026-03-15")
    }

    @Test("dailyReport endpoint without date has nil query params")
    func dailyReportNoDate() {
        let ep = ShikiBackendEndpoint.dailyReport(date: nil)
        #expect(ep.queryParams == nil)
    }

    @Test("heartbeat endpoint is POST with correct body")
    func heartbeat() {
        let ep = ShikiBackendEndpoint.heartbeat(companyId: "c-1", sessionId: "s-1")
        #expect(ep.path == "/api/orchestrator/heartbeat")
        #expect(ep.method == .POST)
        let body = ep.body as? [String: String]
        #expect(body?["companyId"] == "c-1")
        #expect(body?["sessionId"] == "s-1")
    }

    // MARK: - Companies

    @Test("companies endpoint with status filter")
    func companiesWithStatus() {
        let ep = ShikiBackendEndpoint.companies(status: "active")
        #expect(ep.path == "/api/companies")
        #expect(ep.method == .GET)
        let params = ep.queryParams as? [String: String]
        #expect(params?["status"] == "active")
    }

    @Test("patchCompany endpoint is PATCH with id in path")
    func patchCompany() {
        let ep = ShikiBackendEndpoint.patchCompany(id: "abc-123", updates: ["status": "paused"])
        #expect(ep.path == "/api/companies/abc-123")
        #expect(ep.method == .PATCH)
        let body = ep.body as? [String: String]
        #expect(body?["status"] == "paused")
    }

    // MARK: - Decisions

    @Test("pendingDecisions endpoint")
    func pendingDecisions() {
        let ep = ShikiBackendEndpoint.pendingDecisions
        #expect(ep.path == "/api/decision-queue/pending")
        #expect(ep.method == .GET)
    }

    @Test("answerDecision endpoint is PATCH with body")
    func answerDecision() {
        let ep = ShikiBackendEndpoint.answerDecision(id: "d-1", answer: "actor", answeredBy: "@Daimyo")
        #expect(ep.path == "/api/decision-queue/d-1")
        #expect(ep.method == .PATCH)
        let body = ep.body as? [String: String]
        #expect(body?["answer"] == "actor")
        #expect(body?["answeredBy"] == "@Daimyo")
    }

    // MARK: - Session Transcripts

    @Test("createTranscript endpoint is POST")
    func createTranscript() {
        let payload: [String: Any] = ["companyId": "c-1", "sessionId": "s-1", "companySlug": "wabisabi", "taskTitle": "test", "phase": "building"]
        let ep = ShikiBackendEndpoint.createTranscript(payload: payload)
        #expect(ep.path == "/api/session-transcripts")
        #expect(ep.method == .POST)
        #expect(ep.body != nil)
    }

    @Test("listTranscripts endpoint with query params")
    func listTranscripts() {
        let ep = ShikiBackendEndpoint.listTranscripts(companySlug: "maya", taskId: "t-1", limit: 10)
        #expect(ep.path == "/api/session-transcripts")
        #expect(ep.method == .GET)
        let params = ep.queryParams as? [String: String]
        #expect(params?["company_slug"] == "maya")
        #expect(params?["task_id"] == "t-1")
        #expect(params?["limit"] == "10")
    }

    @Test("getTranscript endpoint has id in path")
    func getTranscript() {
        let ep = ShikiBackendEndpoint.getTranscript(id: "tr-42")
        #expect(ep.path == "/api/session-transcripts/tr-42")
        #expect(ep.method == .GET)
    }

    // MARK: - Board

    @Test("boardOverview endpoint")
    func boardOverview() {
        let ep = ShikiBackendEndpoint.boardOverview
        #expect(ep.path == "/api/orchestrator/board")
        #expect(ep.method == .GET)
    }

    // MARK: - Shared properties

    @Test("all endpoints use http scheme, localhost, port 3900")
    func sharedProperties() {
        let endpoints: [ShikiBackendEndpoint] = [
            .health, .orchestratorStatus, .readyCompanies, .boardOverview,
        ]
        for ep in endpoints {
            #expect(ep.scheme == "http")
            #expect(ep.host == "localhost")
            #expect(ep.port == 3900)
        }
    }
}
