import Foundation
import Logging

/// HTTP client for the Shiki orchestrator backend.
/// Uses `curl` subprocess for reliability over long-running sessions
/// (AsyncHTTPClient connection pools go stale with Docker networking).
public actor BackendClient: BackendClientProtocol {
    private let baseURL: String
    private let logger: Logger

    public init(baseURL: String = "http://localhost:3900", logger: Logger = Logger(label: "shiki-ctl.backend")) {
        self.baseURL = baseURL
        self.logger = logger
    }

    /// No-op for backward compatibility — curl processes don't need shutdown.
    public func shutdown() async throws {}

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

    public func createSessionTranscript(_ input: SessionTranscriptInput) async throws -> SessionTranscript {
        try await post("/api/session-transcripts", body: input.toDictionary())
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

    // MARK: - Backlog

    public func listBacklogItems(
        status: BacklogItem.Status? = nil,
        companyId: String? = nil,
        tags: [String]? = nil,
        sort: BacklogSort? = nil
    ) async throws -> [BacklogItem] {
        var query = "?"
        if let status { query += "status=\(status.rawValue)&" }
        if let companyId { query += "company_id=\(companyId)&" }
        if let tags, !tags.isEmpty { query += "tags=\(tags.joined(separator: ","))&" }
        if let sort { query += "sort=\(sort.rawValue)&" }
        if query == "?" { query = "" }
        else { query = String(query.dropLast()) } // remove trailing &
        return try await get("/api/backlog\(query)")
    }

    public func getBacklogItem(id: String) async throws -> BacklogItem {
        try await get("/api/backlog/\(id)")
    }

    public func createBacklogItem(
        title: String,
        description: String? = nil,
        companyId: String? = nil,
        sourceType: BacklogItem.SourceType = .manual,
        sourceRef: String? = nil,
        priority: Int? = nil,
        tags: [String] = []
    ) async throws -> BacklogItem {
        var body: [String: Any] = ["title": title, "sourceType": sourceType.rawValue, "tags": tags]
        if let description { body["description"] = description }
        if let companyId { body["companyId"] = companyId }
        if let sourceRef { body["sourceRef"] = sourceRef }
        if let priority { body["priority"] = priority }
        return try await post("/api/backlog", body: body)
    }

    public func updateBacklogItem(
        id: String,
        status: BacklogItem.Status? = nil,
        priority: Int? = nil,
        sortOrder: Int? = nil,
        tags: [String]? = nil,
        description: String? = nil
    ) async throws -> BacklogItem {
        var body: [String: Any] = [:]
        if let status { body["status"] = status.rawValue }
        if let priority { body["priority"] = priority }
        if let sortOrder { body["sortOrder"] = sortOrder }
        if let tags { body["tags"] = tags }
        if let description { body["description"] = description }
        return try await patch("/api/backlog/\(id)", body: body)
    }

    public func enrichBacklogItem(
        id: String,
        notes: String,
        tags: [String]? = nil,
        description: String? = nil
    ) async throws -> BacklogItem {
        var body: [String: Any] = ["enrichmentNotes": notes]
        if let tags { body["tags"] = tags }
        if let description { body["description"] = description }
        return try await post("/api/backlog/\(id)/enrich", body: body)
    }

    public func killBacklogItem(id: String, reason: String) async throws -> BacklogItem {
        try await post("/api/backlog/\(id)/kill", body: ["killReason": reason])
    }

    public func reorderBacklogItems(_ items: [(id: String, sortOrder: Int)]) async throws {
        let payload: [[String: Any]] = items.map { ["id": $0.id, "sortOrder": $0.sortOrder] }
        let _: [String: AnyCodable] = try await post("/api/backlog/reorder", body: ["items": payload])
    }

    public func getBacklogCount(status: BacklogItem.Status? = nil, companyId: String? = nil) async throws -> Int {
        var query = "?"
        if let status { query += "status=\(status.rawValue)&" }
        if let companyId { query += "company_id=\(companyId)&" }
        if query == "?" { query = "" }
        else { query = String(query.dropLast()) }
        let result: [String: AnyCodable] = try await get("/api/backlog/count\(query)")
        if case .int(let count) = result["count"] {
            return count
        }
        // Backend may return string count (Postgres quirk)
        if case .string(let str) = result["count"], let count = Int(str) {
            return count
        }
        return 0
    }

    // MARK: - Health

    public func healthCheck() async throws -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["curl", "-sf", "--max-time", "5", "\(baseURL)/health"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    // MARK: - HTTP Helpers (curl-based)

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let data = try curlRequest(method: "GET", path: path)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func post<T: Decodable>(_ path: String, body payload: [String: Any]) async throws -> T {
        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        let data = try curlRequest(method: "POST", path: path, body: jsonData)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func patch<T: Decodable>(_ path: String, body payload: [String: Any]) async throws -> T {
        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        let data = try curlRequest(method: "PATCH", path: path, body: jsonData)
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Execute an HTTP request using curl subprocess.
    /// Reliable across Docker restarts and network interruptions — no connection pool.
    private func curlRequest(method: String, path: String, body: Data? = nil, timeoutSeconds: Int = 15) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")

        var args = [
            "curl", "-s",
            "--max-time", "\(timeoutSeconds)",
            "-X", method,
            "-H", "Accept: application/json",
        ]

        if body != nil {
            args += ["-H", "Content-Type: application/json", "-d", "@-"]
        }

        args.append("\(baseURL)\(path)")
        process.arguments = args

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        if let bodyData = body {
            let stdin = Pipe()
            process.standardInput = stdin
            try process.run()
            stdin.fileHandleForWriting.write(bodyData)
            stdin.fileHandleForWriting.closeFile()
        } else {
            try process.run()
        }

        // Read pipes BEFORE waitUntilExit to prevent pipe buffer deadlock (~64KB)
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errString = String(data: errData, encoding: .utf8) ?? ""
            logger.error("curl \(method) \(path) failed (exit \(process.terminationStatus)): \(errString)")
            throw BackendError.httpError(statusCode: Int(process.terminationStatus), body: errString)
        }

        // Check for HTTP error in response body
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? String {
            let code = (json["statusCode"] as? Int) ?? 400
            throw BackendError.httpError(statusCode: code, body: error)
        }

        return data
    }
}

public struct SessionTranscriptInput: Sendable {
    public let companyId: String
    public let sessionId: String
    public let companySlug: String
    public let taskTitle: String
    public let phase: String
    public let taskId: String?
    public let projectPath: String?
    public let summary: String?
    public let planOutput: String?
    public let filesChanged: [String]?
    public let testResults: String?
    public let prsCreated: [String]?
    public let errors: [String]?
    public let durationMinutes: Int?
    public let contextPct: Int?
    public let compactionCount: Int?
    public let rawLog: String?

    public init(
        companyId: String,
        sessionId: String,
        companySlug: String,
        taskTitle: String,
        phase: String,
        taskId: String? = nil,
        projectPath: String? = nil,
        summary: String? = nil,
        planOutput: String? = nil,
        filesChanged: [String]? = nil,
        testResults: String? = nil,
        prsCreated: [String]? = nil,
        errors: [String]? = nil,
        durationMinutes: Int? = nil,
        contextPct: Int? = nil,
        compactionCount: Int? = nil,
        rawLog: String? = nil
    ) {
        self.companyId = companyId
        self.sessionId = sessionId
        self.companySlug = companySlug
        self.taskTitle = taskTitle
        self.phase = phase
        self.taskId = taskId
        self.projectPath = projectPath
        self.summary = summary
        self.planOutput = planOutput
        self.filesChanged = filesChanged
        self.testResults = testResults
        self.prsCreated = prsCreated
        self.errors = errors
        self.durationMinutes = durationMinutes
        self.contextPct = contextPct
        self.compactionCount = compactionCount
        self.rawLog = rawLog
    }

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "companyId": companyId,
            "sessionId": sessionId,
            "companySlug": companySlug,
            "taskTitle": taskTitle,
            "phase": phase,
        ]
        if let taskId { dict["taskId"] = taskId }
        if let projectPath { dict["projectPath"] = projectPath }
        if let summary { dict["summary"] = summary }
        if let planOutput { dict["planOutput"] = planOutput }
        if let filesChanged { dict["filesChanged"] = filesChanged }
        if let testResults { dict["testResults"] = testResults }
        if let prsCreated { dict["prsCreated"] = prsCreated }
        if let errors { dict["errors"] = errors }
        if let durationMinutes { dict["durationMinutes"] = durationMinutes }
        if let contextPct { dict["contextPct"] = contextPct }
        if let compactionCount { dict["compactionCount"] = compactionCount }
        if let rawLog { dict["rawLog"] = rawLog }
        return dict
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
