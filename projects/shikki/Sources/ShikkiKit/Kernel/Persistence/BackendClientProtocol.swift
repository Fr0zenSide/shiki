import Foundation

/// Protocol for the orchestrator backend HTTP client.
///
/// Extracted from ``BackendClient`` to enable dependency injection and mocking
/// in tests (especially ``HeartbeatLoop`` unit tests).
public protocol BackendClientProtocol: Sendable {
    func healthCheck() async throws -> Bool
    func getStatus() async throws -> OrchestratorStatus
    func getStaleCompanies(thresholdMinutes: Int) async throws -> [Company]
    func getReadyCompanies() async throws -> [Company]
    func getDispatcherQueue() async throws -> [DispatcherTask]
    func getDailyReport(date: String?) async throws -> DailyReport
    func sendHeartbeat(companyId: String, sessionId: String) async throws -> HeartbeatResponse
    func getCompanies(status: String?) async throws -> [Company]
    func getPendingDecisions() async throws -> [Decision]
    func answerDecision(id: String, answer: String, answeredBy: String) async throws -> Decision
    func createSessionTranscript(_ input: SessionTranscriptInput) async throws -> SessionTranscript
    func getSessionTranscripts(companySlug: String?, taskId: String?, limit: Int) async throws -> [SessionTranscript]
    func getSessionTranscript(id: String) async throws -> SessionTranscript
    func getBoardOverview() async throws -> [BoardEntry]
    func shutdown() async throws

    // MARK: - Backlog

    func listBacklogItems(
        status: BacklogItem.Status?,
        companyId: String?,
        tags: [String]?,
        sort: BacklogSort?
    ) async throws -> [BacklogItem]

    func getBacklogItem(id: String) async throws -> BacklogItem

    func createBacklogItem(
        title: String,
        description: String?,
        companyId: String?,
        sourceType: BacklogItem.SourceType,
        sourceRef: String?,
        priority: Int?,
        tags: [String]
    ) async throws -> BacklogItem

    func updateBacklogItem(
        id: String,
        status: BacklogItem.Status?,
        priority: Int?,
        sortOrder: Int?,
        tags: [String]?,
        description: String?
    ) async throws -> BacklogItem

    func enrichBacklogItem(
        id: String,
        notes: String,
        tags: [String]?,
        description: String?
    ) async throws -> BacklogItem

    func killBacklogItem(id: String, reason: String) async throws -> BacklogItem

    func reorderBacklogItems(_ items: [(id: String, sortOrder: Int)]) async throws

    func getBacklogCount(status: BacklogItem.Status?, companyId: String?) async throws -> Int
}

// Default parameter values for protocol methods
public extension BackendClientProtocol {
    func getStaleCompanies() async throws -> [Company] {
        try await getStaleCompanies(thresholdMinutes: 5)
    }

    func getDailyReport() async throws -> DailyReport {
        try await getDailyReport(date: nil)
    }

    func getCompanies() async throws -> [Company] {
        try await getCompanies(status: nil)
    }

    func getSessionTranscripts(companySlug: String? = nil, taskId: String? = nil) async throws -> [SessionTranscript] {
        try await getSessionTranscripts(companySlug: companySlug, taskId: taskId, limit: 20)
    }

    func listBacklogItems() async throws -> [BacklogItem] {
        try await listBacklogItems(status: nil, companyId: nil, tags: nil, sort: nil)
    }

    func getBacklogCount() async throws -> Int {
        try await getBacklogCount(status: nil, companyId: nil)
    }
}
