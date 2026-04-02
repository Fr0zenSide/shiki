import Foundation

/// HTTP route handler for the embedded ShikiServer.
///
/// Matches incoming requests to the appropriate handler and returns
/// (statusCode, responseBody) tuples. All responses are JSON.
///
/// Routes mirror the Deno backend API surface that `BackendClient` calls.
public struct ServerRoutes: Sendable {
    private let store: InMemoryStore

    public init(store: InMemoryStore) {
        self.store = store
    }

    // MARK: - Route Dispatch

    /// Handle an HTTP request and return (statusCode, responseJSON).
    public func handle(method: String, path: String, body: Data?) async -> (Int, Data) {
        // Strip query string for path matching
        let cleanPath = path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? path

        // Health check
        if cleanPath == "/health" && method == "GET" {
            return jsonResponse(200, ["ok": true])
        }

        // Data sync (unified ingest)
        if cleanPath == "/api/data-sync" && method == "POST" {
            return await handleDataSync(body: body)
        }

        // Memories search
        if cleanPath == "/api/memories/search" && method == "POST" {
            return await handleMemoriesSearch(body: body)
        }

        // Events
        if cleanPath == "/api/events" && method == "GET" {
            return await handleGetEvents(queryString: extractQuery(from: path))
        }

        // Decisions
        if cleanPath == "/api/decisions" && method == "GET" {
            return await handleGetDecisions()
        }
        if cleanPath.hasPrefix("/api/decision-queue/pending") && method == "GET" {
            return await handleGetDecisions()
        }
        if cleanPath.hasPrefix("/api/decision-queue/") && method == "PATCH" {
            let id = String(cleanPath.dropFirst("/api/decision-queue/".count))
            return await handlePatchDecision(id: id, body: body)
        }

        // Plans
        if cleanPath == "/api/plans" && method == "GET" {
            return await handleGetPlans()
        }

        // Contexts
        if cleanPath == "/api/contexts" && method == "GET" {
            return await handleGetContexts(queryString: extractQuery(from: path))
        }

        // Orchestrator status (stub -- returns empty structure for compatibility)
        if cleanPath == "/api/orchestrator/status" && method == "GET" {
            return handleOrchestratorStatus()
        }
        if cleanPath == "/api/orchestrator/board" && method == "GET" {
            return emptyArrayResponse()
        }
        if cleanPath.hasPrefix("/api/orchestrator/stale") && method == "GET" {
            return emptyArrayResponse()
        }
        if cleanPath.hasPrefix("/api/orchestrator/ready") && method == "GET" {
            return emptyArrayResponse()
        }
        if cleanPath == "/api/orchestrator/dispatcher-queue" && method == "GET" {
            return emptyArrayResponse()
        }
        if cleanPath.hasPrefix("/api/orchestrator/report") && method == "GET" {
            return handleDailyReportStub()
        }
        if cleanPath == "/api/orchestrator/heartbeat" && method == "POST" {
            return await handleHeartbeat(body: body)
        }

        // Companies (stub)
        if cleanPath == "/api/companies" || cleanPath.hasPrefix("/api/companies?") {
            if method == "GET" { return emptyArrayResponse() }
        }
        if cleanPath.hasPrefix("/api/companies/") && method == "PATCH" {
            return jsonResponse(200, ["error": "not implemented in embedded server"])
        }

        // Session transcripts (stub)
        if cleanPath == "/api/session-transcripts" && method == "POST" {
            return await handleCreateTranscript(body: body)
        }
        if cleanPath == "/api/session-transcripts" || cleanPath.hasPrefix("/api/session-transcripts?") {
            if method == "GET" { return emptyArrayResponse() }
        }
        if cleanPath.hasPrefix("/api/session-transcripts/") && method == "GET" {
            return jsonResponse(404, ["error": "not found"])
        }

        // Backlog (stub)
        if cleanPath == "/api/backlog" || cleanPath.hasPrefix("/api/backlog?") {
            if method == "GET" { return emptyArrayResponse() }
            if method == "POST" { return await handleCreateBacklogItem(body: body) }
        }
        if cleanPath == "/api/backlog/count" || cleanPath.hasPrefix("/api/backlog/count?") {
            if method == "GET" { return jsonResponse(200, ["count": 0]) }
        }
        if cleanPath == "/api/backlog/reorder" && method == "POST" {
            return jsonResponse(200, ["ok": true])
        }
        if cleanPath.hasPrefix("/api/backlog/") && cleanPath.hasSuffix("/enrich") && method == "POST" {
            return jsonResponse(200, ["error": "not implemented in embedded server"])
        }
        if cleanPath.hasPrefix("/api/backlog/") && cleanPath.hasSuffix("/kill") && method == "POST" {
            return jsonResponse(200, ["error": "not implemented in embedded server"])
        }
        if cleanPath.hasPrefix("/api/backlog/") {
            if method == "GET" { return jsonResponse(404, ["error": "not found"]) }
            if method == "PATCH" { return jsonResponse(200, ["error": "not implemented in embedded server"]) }
        }

        return jsonResponse(404, ["error": "Not found: \(method) \(cleanPath)"])
    }

    // MARK: - Route Handlers

    private func handleDataSync(body: Data?) async -> (Int, Data) {
        guard let body, let json = parseJSON(body) else {
            return jsonResponse(400, ["error": "Invalid JSON body"])
        }

        guard let type = json["type"] as? String else {
            return jsonResponse(400, ["error": "Missing 'type' field"])
        }

        let projectId = json["projectId"] as? String

        // Extract payload sub-object, or use the whole body
        let payloadData: Data
        if let payloadDict = json["payload"] as? [String: Any],
           let serialized = try? JSONSerialization.data(withJSONObject: payloadDict) {
            payloadData = serialized
        } else {
            payloadData = body
        }

        _ = await store.ingest(type: type, projectId: projectId, payload: payloadData)
        return jsonResponse(200, ["ok": true])
    }

    private func handleMemoriesSearch(body: Data?) async -> (Int, Data) {
        guard let body, let json = parseJSON(body) else {
            return jsonResponse(400, ["error": "Invalid JSON body"])
        }

        let query = json["query"] as? String ?? ""
        let projectIds = json["projectIds"] as? [String] ?? []
        let limit = json["limit"] as? Int ?? 20

        let results = await store.searchMemories(query: query, projectIds: projectIds, limit: limit)
        return dataArrayResponse(200, results)
    }

    private func handleGetEvents(queryString: String?) async -> (Int, Data) {
        let params = parseQuery(queryString)
        let projectId = params["projectId"]
        let type = params["type"]
        let limit = params["limit"].flatMap(Int.init) ?? 100

        let events = await store.getEvents(projectId: projectId, type: type, limit: limit)
        return dataArrayResponse(200, events)
    }

    private func handleGetDecisions() async -> (Int, Data) {
        let decisions = await store.getDecisions()
        return dataArrayResponse(200, decisions)
    }

    private func handlePatchDecision(id: String, body: Data?) async -> (Int, Data) {
        guard let body else {
            return jsonResponse(400, ["error": "Invalid JSON body"])
        }

        if let updated = await store.updateDecision(id: id, updates: body) {
            return (200, updated)
        }
        return jsonResponse(404, ["error": "Decision not found: \(id)"])
    }

    private func handleGetPlans() async -> (Int, Data) {
        let plans = await store.getPlans()
        return dataArrayResponse(200, plans)
    }

    private func handleGetContexts(queryString: String?) async -> (Int, Data) {
        let params = parseQuery(queryString)
        let sessionId = params["sessionId"]
        let limit = params["limit"].flatMap(Int.init) ?? 20

        let contexts = await store.getContexts(sessionId: sessionId, limit: limit)
        return dataArrayResponse(200, contexts)
    }

    private func handleOrchestratorStatus() -> (Int, Data) {
        let status: [String: Any] = [
            "overview": [
                "active_companies": 0,
                "total_pending_tasks": 0,
                "total_running_tasks": 0,
                "total_blocked_tasks": 0,
                "total_pending_decisions": 0,
                "t1_pending_decisions": 0,
                "today_total_spend": 0.0,
            ] as [String: Any],
            "activeCompanies": [[String: Any]](),
            "pendingDecisions": [[String: Any]](),
            "staleCompanies": [[String: Any]](),
            "packageLocks": [[String: Any]](),
            "timestamp": ISO8601DateFormatter().string(from: Date()),
        ]
        let data = (try? JSONSerialization.data(withJSONObject: status)) ?? Data("{}".utf8)
        return (200, data)
    }

    private func handleDailyReportStub() -> (Int, Data) {
        let report: [String: Any] = [
            "date": ISO8601DateFormatter().string(from: Date()),
            "perCompany": [[String: Any]](),
            "blocked": [[String: Any]](),
            "prsCreated": [[String: Any]](),
        ]
        let data = (try? JSONSerialization.data(withJSONObject: report)) ?? Data("{}".utf8)
        return (200, data)
    }

    private func handleHeartbeat(body: Data?) async -> (Int, Data) {
        guard let body, let json = parseJSON(body) else {
            return jsonResponse(400, ["error": "Invalid JSON body"])
        }
        let response: [String: Any] = [
            "budgetexceeded": false,
            "sessionid": (json["sessionId"] as? String) ?? UUID().uuidString,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
        ]
        // Also store as event
        _ = await store.ingest(type: "heartbeat", projectId: json["companyId"] as? String, payload: body)
        let data = (try? JSONSerialization.data(withJSONObject: response)) ?? Data("{}".utf8)
        return (200, data)
    }

    private func handleCreateTranscript(body: Data?) async -> (Int, Data) {
        guard let body, let json = parseJSON(body) else {
            return jsonResponse(400, ["error": "Invalid JSON body"])
        }
        let stored = await store.ingest(type: "session_transcript", projectId: json["companyId"] as? String, payload: body)
        return (200, stored)
    }

    private func handleCreateBacklogItem(body: Data?) async -> (Int, Data) {
        guard let body, let json = parseJSON(body) else {
            return jsonResponse(400, ["error": "Invalid JSON body"])
        }
        let stored = await store.ingest(type: "backlog_item", projectId: json["companyId"] as? String, payload: body)
        return (200, stored)
    }

    // MARK: - JSON Helpers

    private func parseJSON(_ data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func jsonResponse(_ status: Int, _ body: [String: Any]) -> (Int, Data) {
        let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        return (status, data)
    }

    /// Build a JSON array response from an array of pre-serialized Data entries.
    private func dataArrayResponse(_ status: Int, _ entries: [Data]) -> (Int, Data) {
        // Build "[entry1,entry2,...]" manually to avoid deserialize+reserialize
        if entries.isEmpty {
            return (status, Data("[]".utf8))
        }
        var result = Data("[".utf8)
        for (i, entry) in entries.enumerated() {
            if i > 0 { result.append(Data(",".utf8)) }
            result.append(entry)
        }
        result.append(Data("]".utf8))
        return (status, result)
    }

    private func emptyArrayResponse() -> (Int, Data) {
        (200, Data("[]".utf8))
    }

    private func extractQuery(from path: String) -> String? {
        guard let idx = path.firstIndex(of: "?") else { return nil }
        return String(path[path.index(after: idx)...])
    }

    private func parseQuery(_ query: String?) -> [String: String] {
        guard let query, !query.isEmpty else { return [:] }
        var result: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                result[String(parts[0])] = String(parts[1])
            }
        }
        return result
    }
}
