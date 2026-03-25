import Foundation
@testable import ShikkiKit

/// Configurable mock for ``BackendClientProtocol``.
/// Each method records calls and returns pre-configured responses.
/// Set `shouldThrow` to inject errors on demand.
final class MockBackendClient: BackendClientProtocol, @unchecked Sendable {

    // MARK: - Call Tracking

    var healthCheckCallCount = 0
    var getStatusCallCount = 0
    var getStaleCompaniesCallCount = 0
    var getReadyCompaniesCallCount = 0
    var getDispatcherQueueCallCount = 0
    var getDailyReportCallCount = 0
    var sendHeartbeatCallCount = 0
    var getCompaniesCallCount = 0
    var getPendingDecisionsCallCount = 0
    var answerDecisionCallCount = 0
    var createSessionTranscriptCallCount = 0
    var getSessionTranscriptsCallCount = 0
    var getSessionTranscriptCallCount = 0
    var getBoardOverviewCallCount = 0
    var shutdownCallCount = 0

    // MARK: - Configurable Responses

    var healthCheckResult: Bool = true
    var statusResult: OrchestratorStatus?
    var staleCompaniesResult: [Company] = []
    var readyCompaniesResult: [Company] = []
    var dispatcherQueueResult: [DispatcherTask] = []
    var dailyReportResult: DailyReport?
    var heartbeatResult: HeartbeatResponse?
    var companiesResult: [Company] = []
    var pendingDecisionsResult: [Decision] = []
    var answerDecisionResult: Decision?
    var sessionTranscriptResult: SessionTranscript?
    var sessionTranscriptsResult: [SessionTranscript] = []
    var boardOverviewResult: [BoardEntry] = []

    // MARK: - Error Injection

    var shouldThrow: Error?

    // MARK: - Protocol Implementation

    func healthCheck() async throws -> Bool {
        healthCheckCallCount += 1
        if let error = shouldThrow { throw error }
        return healthCheckResult
    }

    func getStatus() async throws -> OrchestratorStatus {
        getStatusCallCount += 1
        if let error = shouldThrow { throw error }
        guard let result = statusResult else {
            throw MockError.notConfigured("statusResult")
        }
        return result
    }

    func getStaleCompanies(thresholdMinutes: Int) async throws -> [Company] {
        getStaleCompaniesCallCount += 1
        if let error = shouldThrow { throw error }
        return staleCompaniesResult
    }

    func getReadyCompanies() async throws -> [Company] {
        getReadyCompaniesCallCount += 1
        if let error = shouldThrow { throw error }
        return readyCompaniesResult
    }

    func getDispatcherQueue() async throws -> [DispatcherTask] {
        getDispatcherQueueCallCount += 1
        if let error = shouldThrow { throw error }
        return dispatcherQueueResult
    }

    func getDailyReport(date: String?) async throws -> DailyReport {
        getDailyReportCallCount += 1
        if let error = shouldThrow { throw error }
        guard let result = dailyReportResult else {
            throw MockError.notConfigured("dailyReportResult")
        }
        return result
    }

    func sendHeartbeat(companyId: String, sessionId: String) async throws -> HeartbeatResponse {
        sendHeartbeatCallCount += 1
        if let error = shouldThrow { throw error }
        guard let result = heartbeatResult else {
            throw MockError.notConfigured("heartbeatResult")
        }
        return result
    }

    func getCompanies(status: String?) async throws -> [Company] {
        getCompaniesCallCount += 1
        if let error = shouldThrow { throw error }
        return companiesResult
    }

    func getPendingDecisions() async throws -> [Decision] {
        getPendingDecisionsCallCount += 1
        if let error = shouldThrow { throw error }
        return pendingDecisionsResult
    }

    func answerDecision(id: String, answer: String, answeredBy: String) async throws -> Decision {
        answerDecisionCallCount += 1
        if let error = shouldThrow { throw error }
        guard let result = answerDecisionResult else {
            throw MockError.notConfigured("answerDecisionResult")
        }
        return result
    }

    func createSessionTranscript(_ input: SessionTranscriptInput) async throws -> SessionTranscript {
        createSessionTranscriptCallCount += 1
        if let error = shouldThrow { throw error }
        guard let result = sessionTranscriptResult else {
            throw MockError.notConfigured("sessionTranscriptResult")
        }
        return result
    }

    func getSessionTranscripts(companySlug: String?, taskId: String?, limit: Int) async throws -> [SessionTranscript] {
        getSessionTranscriptsCallCount += 1
        if let error = shouldThrow { throw error }
        return sessionTranscriptsResult
    }

    func getSessionTranscript(id: String) async throws -> SessionTranscript {
        getSessionTranscriptCallCount += 1
        if let error = shouldThrow { throw error }
        guard let result = sessionTranscriptResult else {
            throw MockError.notConfigured("sessionTranscriptResult")
        }
        return result
    }

    func getBoardOverview() async throws -> [BoardEntry] {
        getBoardOverviewCallCount += 1
        if let error = shouldThrow { throw error }
        return boardOverviewResult
    }

    func shutdown() async throws {
        shutdownCallCount += 1
        if let error = shouldThrow { throw error }
    }

    // MARK: - Backlog (stub implementations)

    var backlogItems: [BacklogItem] = []

    func listBacklogItems(status: BacklogItem.Status?, companyId: String?, tags: [String]?, sort: BacklogSort?) async throws -> [BacklogItem] {
        if let error = shouldThrow { throw error }
        return backlogItems
    }

    func getBacklogItem(id: String) async throws -> BacklogItem {
        if let error = shouldThrow { throw error }
        guard let item = backlogItems.first(where: { $0.id == id }) else {
            throw MockError.notConfigured("backlogItems[\(id)]")
        }
        return item
    }

    func createBacklogItem(title: String, description: String?, companyId: String?, sourceType: BacklogItem.SourceType, sourceRef: String?, priority: Int?, tags: [String]) async throws -> BacklogItem {
        if let error = shouldThrow { throw error }
        throw MockError.notConfigured("createBacklogItem")
    }

    func updateBacklogItem(id: String, status: BacklogItem.Status?, priority: Int?, sortOrder: Int?, tags: [String]?, description: String?) async throws -> BacklogItem {
        if let error = shouldThrow { throw error }
        throw MockError.notConfigured("updateBacklogItem")
    }

    func enrichBacklogItem(id: String, notes: String, tags: [String]?, description: String?) async throws -> BacklogItem {
        if let error = shouldThrow { throw error }
        throw MockError.notConfigured("enrichBacklogItem")
    }

    func killBacklogItem(id: String, reason: String) async throws -> BacklogItem {
        if let error = shouldThrow { throw error }
        throw MockError.notConfigured("killBacklogItem")
    }

    func reorderBacklogItems(_ items: [(id: String, sortOrder: Int)]) async throws {
        if let error = shouldThrow { throw error }
    }

    func getBacklogCount(status: BacklogItem.Status?, companyId: String?) async throws -> Int {
        if let error = shouldThrow { throw error }
        return backlogItems.count
    }
}

// MARK: - MockError

enum MockError: Error, LocalizedError {
    case notConfigured(String)
    case apiUnreachable

    var errorDescription: String? {
        switch self {
        case .notConfigured(let field): "MockBackendClient.\(field) not configured"
        case .apiUnreachable: "Mock API unreachable"
        }
    }
}
