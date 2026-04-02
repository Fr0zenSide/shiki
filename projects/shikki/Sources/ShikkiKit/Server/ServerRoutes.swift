import Foundation

/// HTTP route handler for the embedded ShikiServer.
///
/// Matches incoming requests to the appropriate handler and returns
/// (statusCode, responseBody) tuples. All responses are JSON.
///
/// v2: KISS — 4 routes only.
///   GET  /health                    → {"ok": true}
///   POST /api/data-sync             → ingest any event type
///   POST /api/memories/search       → query memories with text search
///   GET  /api/events?type=X&since=Y → universal event query with filters
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

        // Events (universal query)
        if cleanPath == "/api/events" && method == "GET" {
            return await handleGetEvents(queryString: extractQuery(from: path))
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
