import Foundation

/// Thread-safe in-memory storage for the embedded ShikiServer.
///
/// Uses Swift actor isolation for safe concurrent access. Stores entries
/// as serialized JSON `Data` to satisfy strict Sendable requirements.
///
/// This is v1 storage — good enough for local dev and single-user CLI.
/// PostgreSQL migration is a later phase.
public actor InMemoryStore {
    // Each collection stores entries as serialized JSON Data.
    // This avoids `[String: Any]` crossing actor boundaries (not Sendable in Swift 6).
    private var events: [Data] = []
    private var memories: [Data] = []
    private var decisions: [Data] = []
    private var plans: [Data] = []
    private var contexts: [Data] = []

    public init() {}

    // MARK: - Events

    public func addEvent(_ json: Data) -> Data {
        let enriched = enrichEntry(json)
        events.append(enriched)
        return enriched
    }

    public func getEvents(projectId: String? = nil, type: String? = nil, limit: Int = 100) -> [Data] {
        var result = events
        if let projectId {
            result = result.filter { field($0, "projectId") == projectId }
        }
        if let type {
            result = result.filter { field($0, "type") == type }
        }
        return Array(result.suffix(limit))
    }

    // MARK: - Memories

    public func addMemory(_ json: Data) -> Data {
        let enriched = enrichEntry(json)
        memories.append(enriched)
        return enriched
    }

    public func searchMemories(query: String, projectIds: [String] = [], limit: Int = 20) -> [Data] {
        let queryLower = query.lowercased()
        let queryTerms = queryLower.split(separator: " ").map(String.init)

        var scored: [(entry: Data, score: Double)] = []

        for memory in memories {
            // Filter by project if specified
            if !projectIds.isEmpty {
                guard let pid = field(memory, "projectId"), projectIds.contains(pid) else {
                    continue
                }
            }

            // Build searchable text from all string values
            let searchText = extractSearchableText(from: memory).lowercased()

            // Simple term-match scoring
            var score: Double = 0
            for term in queryTerms {
                if searchText.contains(term) {
                    score += 1.0
                    // Bonus for exact word boundary match
                    let words = searchText.split(separator: " ").map(String.init)
                    if words.contains(term) {
                        score += 0.5
                    }
                }
            }

            if score > 0 {
                scored.append((memory, score))
            }
        }

        scored.sort { $0.score > $1.score }
        return Array(scored.prefix(limit).map(\.entry))
    }

    // MARK: - Decisions

    public func addDecision(_ json: Data) -> Data {
        let enriched = enrichEntry(json)
        decisions.append(enriched)
        return enriched
    }

    public func getDecisions(limit: Int = 100) -> [Data] {
        Array(decisions.suffix(limit))
    }

    public func updateDecision(id: String, updates: Data) -> Data? {
        guard let index = decisions.firstIndex(where: { field($0, "id") == id }) else {
            return nil
        }
        // Merge updates into existing entry
        if var existing = deserialize(decisions[index]),
           let updateDict = deserialize(updates) {
            for (key, value) in updateDict {
                existing[key] = value
            }
            existing["updated_at"] = ISO8601DateFormatter().string(from: Date())
            if let merged = serialize(existing) {
                decisions[index] = merged
                return merged
            }
        }
        return nil
    }

    // MARK: - Plans

    public func addPlan(_ json: Data) -> Data {
        let enriched = enrichEntry(json)
        plans.append(enriched)
        return enriched
    }

    public func getPlans(limit: Int = 100) -> [Data] {
        Array(plans.suffix(limit))
    }

    // MARK: - Contexts

    public func saveContext(_ json: Data) -> Data {
        let enriched = enrichEntry(json)
        contexts.append(enriched)
        return enriched
    }

    public func getContexts(sessionId: String? = nil, limit: Int = 20) -> [Data] {
        var result = contexts
        if let sessionId {
            result = result.filter { field($0, "sessionId") == sessionId }
        }
        return Array(result.suffix(limit))
    }

    // MARK: - Data Sync (unified ingest)

    /// Route a data-sync payload to the appropriate collection based on `type`.
    public func ingest(type: String, projectId: String?, payload: Data) -> Data {
        // Enrich payload with type and projectId
        var dict = deserialize(payload) ?? [:]
        dict["type"] = type
        if let projectId {
            dict["projectId"] = projectId
        }
        let enrichedData = serialize(dict) ?? payload

        switch type {
        case "memory":
            return addMemory(enrichedData)
        case "decision":
            return addDecision(enrichedData)
        case "plan":
            return addPlan(enrichedData)
        case "context", "context_compaction", "context_session_start", "context_session_end":
            return saveContext(enrichedData)
        default:
            return addEvent(enrichedData)
        }
    }

    // MARK: - Private Helpers

    /// Add id and created_at if missing.
    private func enrichEntry(_ data: Data) -> Data {
        guard var dict = deserialize(data) else { return data }
        if dict["id"] == nil {
            dict["id"] = UUID().uuidString
        }
        if dict["created_at"] == nil {
            dict["created_at"] = ISO8601DateFormatter().string(from: Date())
        }
        return serialize(dict) ?? data
    }

    /// Extract a top-level string field from serialized JSON.
    private func field(_ data: Data, _ key: String) -> String? {
        guard let dict = deserialize(data) else { return nil }
        return dict[key] as? String
    }

    /// Recursively extract all string values for text search.
    private func extractSearchableText(from data: Data) -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return "" }
        return extractStrings(from: obj).joined(separator: " ")
    }

    private func extractStrings(from obj: Any) -> [String] {
        var parts: [String] = []
        if let str = obj as? String {
            parts.append(str)
        } else if let arr = obj as? [Any] {
            for item in arr {
                parts.append(contentsOf: extractStrings(from: item))
            }
        } else if let dict = obj as? [String: Any] {
            for (_, value) in dict {
                parts.append(contentsOf: extractStrings(from: value))
            }
        }
        return parts
    }

    private func deserialize(_ data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func serialize(_ dict: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: dict)
    }
}
