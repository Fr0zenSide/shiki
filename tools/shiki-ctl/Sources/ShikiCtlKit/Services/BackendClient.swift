import AsyncHTTPClient
import Foundation
import Logging
import NIOCore
import NIOFoundationCompat

/// HTTP client for the Shiki orchestrator backend.
public actor BackendClient {
    private let httpClient: HTTPClient
    private let baseURL: String
    private let logger: Logger

    public init(baseURL: String = "http://localhost:3900", logger: Logger = Logger(label: "shiki-ctl.backend")) {
        self.httpClient = HTTPClient(configuration: .init(timeout: .init(connect: .seconds(5))))
        self.baseURL = baseURL
        self.logger = logger
    }

    public func shutdown() async throws {
        try await httpClient.shutdown()
    }

    // MARK: - Orchestrator

    public func getStatus() async throws -> OrchestratorStatus {
        try await get("/api/orchestrator/status")
    }

    public func getStaleCompanies(thresholdMinutes: Int = 5) async throws -> [Company] {
        try await get("/api/orchestrator/stale?threshold_minutes=\(thresholdMinutes)")
    }

    public func getReadyCompanies() async throws -> [Company] {
        try await get("/api/orchestrator/ready")
    }

    public func getDispatcherQueue() async throws -> [DispatcherTask] {
        try await get("/api/orchestrator/dispatcher-queue")
    }

    public func getDailyReport(date: String? = nil) async throws -> DailyReport {
        let query = date.map { "?date=\($0)" } ?? ""
        return try await get("/api/orchestrator/report\(query)")
    }

    public func sendHeartbeat(companyId: String, sessionId: String) async throws -> HeartbeatResponse {
        try await post("/api/orchestrator/heartbeat", body: [
            "companyId": companyId,
            "sessionId": sessionId,
        ])
    }

    // MARK: - Companies

    public func getCompanies(status: String? = nil) async throws -> [Company] {
        let query = status.map { "?status=\($0)" } ?? ""
        return try await get("/api/companies\(query)")
    }

    public func patchCompany(id: String, updates: [String: Any]) async throws -> Company {
        try await patch("/api/companies/\(id)", body: updates)
    }

    // MARK: - Decisions

    public func getPendingDecisions() async throws -> [Decision] {
        try await get("/api/decision-queue/pending")
    }

    public func answerDecision(id: String, answer: String, answeredBy: String) async throws -> Decision {
        try await patch("/api/decision-queue/\(id)", body: [
            "answer": answer,
            "answeredBy": answeredBy,
        ])
    }

    // MARK: - Session Transcripts

    public func createSessionTranscript(_ payload: [String: Any]) async throws -> SessionTranscript {
        try await post("/api/session-transcripts", body: payload)
    }

    public func getSessionTranscripts(companySlug: String? = nil, taskId: String? = nil, limit: Int = 20) async throws -> [SessionTranscript] {
        var query = "?"
        if let slug = companySlug { query += "company_slug=\(slug)&" }
        if let tid = taskId { query += "task_id=\(tid)&" }
        query += "limit=\(limit)"
        return try await get("/api/session-transcripts\(query)")
    }

    public func getSessionTranscript(id: String) async throws -> SessionTranscript {
        try await get("/api/session-transcripts/\(id)")
    }

    // MARK: - Board

    public func getBoardOverview() async throws -> [BoardEntry] {
        try await get("/api/orchestrator/board")
    }

    // MARK: - Health

    public func healthCheck() async throws -> Bool {
        do {
            let request = HTTPClientRequest(url: "\(baseURL)/health")
            let response = try await httpClient.execute(request, timeout: .seconds(5))
            return response.status == .ok
        } catch {
            return false
        }
    }

    // MARK: - HTTP Helpers

    private func get<T: Decodable>(_ path: String) async throws -> T {
        var request = HTTPClientRequest(url: "\(baseURL)\(path)")
        request.method = .GET
        request.headers.add(name: "Accept", value: "application/json")

        let response = try await httpClient.execute(request, timeout: .seconds(30))
        let body = try await response.body.collect(upTo: 10 * 1024 * 1024)
        try checkStatus(response, body: body, path: path)
        return try JSONDecoder().decode(T.self, from: body)
    }

    private func post<T: Decodable>(_ path: String, body payload: [String: Any]) async throws -> T {
        var request = HTTPClientRequest(url: "\(baseURL)\(path)")
        request.method = .POST
        request.headers.add(name: "Content-Type", value: "application/json")
        request.headers.add(name: "Accept", value: "application/json")
        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        request.body = .bytes(ByteBuffer(data: jsonData))

        let response = try await httpClient.execute(request, timeout: .seconds(30))
        let body = try await response.body.collect(upTo: 10 * 1024 * 1024)
        try checkStatus(response, body: body, path: path)
        return try JSONDecoder().decode(T.self, from: body)
    }

    private func patch<T: Decodable>(_ path: String, body payload: [String: Any]) async throws -> T {
        var request = HTTPClientRequest(url: "\(baseURL)\(path)")
        request.method = .PATCH
        request.headers.add(name: "Content-Type", value: "application/json")
        request.headers.add(name: "Accept", value: "application/json")
        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        request.body = .bytes(ByteBuffer(data: jsonData))

        let response = try await httpClient.execute(request, timeout: .seconds(30))
        let body = try await response.body.collect(upTo: 10 * 1024 * 1024)
        try checkStatus(response, body: body, path: path)
        return try JSONDecoder().decode(T.self, from: body)
    }

    private func checkStatus(_ response: HTTPClientResponse, body: ByteBuffer, path: String) throws {
        guard (200...299).contains(Int(response.status.code)) else {
            let bodyString = String(buffer: body)
            logger.error("API error \(response.status.code) on \(path): \(bodyString)")
            throw BackendError.httpError(statusCode: Int(response.status.code), body: bodyString)
        }
    }
}

public enum BackendError: Error, CustomStringConvertible {
    case httpError(statusCode: Int, body: String)

    public var description: String {
        switch self {
        case .httpError(let code, let body):
            "HTTP \(code): \(body)"
        }
    }
}
