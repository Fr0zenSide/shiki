import Foundation

// MARK: - DecisionJournal

/// Append-only JSONL journal for decision persistence.
/// Each session gets its own file at `{basePath}/{sessionId}-decisions.jsonl`.
/// Thread-safe via actor isolation.
public actor DecisionJournal {
    public let basePath: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// In-memory cache for fast queries. Lazily loaded per session.
    private var cache: [String: [DecisionEvent]] = [:]

    public init(basePath: String? = nil) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.basePath = basePath ?? "\(home)/.shikki/decisions"
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Write

    /// Record a decision to the session's journal file.
    public func record(_ decision: DecisionEvent) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: basePath) {
            try fm.createDirectory(atPath: basePath, withIntermediateDirectories: true)
        }

        let filePath = journalPath(for: decision.sessionId)
        let data = try encoder.encode(decision)
        guard var line = String(data: data, encoding: .utf8) else { return }
        line += "\n"

        if fm.fileExists(atPath: filePath) {
            let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: filePath))
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
        } else {
            fm.createFile(atPath: filePath, contents: Data(line.utf8))
        }

        // Update cache
        cache[decision.sessionId, default: []].append(decision)
    }

    // MARK: - Read

    /// Load all decisions for a session.
    public func loadDecisions(sessionId: String) throws -> [DecisionEvent] {
        if let cached = cache[sessionId] {
            return cached
        }

        let filePath = journalPath(for: sessionId)
        guard FileManager.default.fileExists(atPath: filePath) else { return [] }

        let content = try String(contentsOfFile: filePath, encoding: .utf8)
        let decisions = content.split(separator: "\n").compactMap { line -> DecisionEvent? in
            let data = Data(line.utf8)
            return try? decoder.decode(DecisionEvent.self, from: data)
        }

        cache[sessionId] = decisions
        return decisions
    }

    /// Load all decisions across all sessions.
    public func loadAllDecisions() throws -> [DecisionEvent] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: basePath) else { return [] }

        let files = try fm.contentsOfDirectory(atPath: basePath)
        var allDecisions: [DecisionEvent] = []

        for file in files where file.hasSuffix("-decisions.jsonl") {
            let sessionId = String(file.dropLast("-decisions.jsonl".count))
            let decisions = try loadDecisions(sessionId: sessionId)
            allDecisions.append(contentsOf: decisions)
        }

        return allDecisions.sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - Query

    /// Query decisions matching a filter.
    public func query(_ filter: DecisionQuery) throws -> [DecisionEvent] {
        let allDecisions: [DecisionEvent]

        if let sessionId = filter.sessionId {
            allDecisions = try loadDecisions(sessionId: sessionId)
        } else {
            allDecisions = try loadAllDecisions()
        }

        return allDecisions.filter { filter.matches($0) }
    }

    /// Build a decision chain starting from a root decision.
    public func buildChain(rootId: UUID) throws -> DecisionChain? {
        let all = try loadAllDecisions()

        guard let root = all.first(where: { $0.id == rootId }) else {
            return nil
        }

        let children = all.filter { $0.parentDecisionId == rootId }
        return DecisionChain(root: root, children: children)
    }

    /// Build the full chain from any decision, walking up to root.
    public func buildFullChain(from decisionId: UUID) throws -> DecisionChain? {
        let all = try loadAllDecisions()
        let index = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

        guard let start = index[decisionId] else { return nil }

        // Walk up to find root
        var current = start
        while let parentId = current.parentDecisionId, let parent = index[parentId] {
            current = parent
        }

        let root = current
        let children = all.filter { $0.parentDecisionId == root.id }
        return DecisionChain(root: root, children: children)
    }

    // MARK: - Maintenance

    /// Prune journal files older than the given threshold. Returns count of pruned files.
    @discardableResult
    public func prune(olderThan seconds: TimeInterval) throws -> Int {
        let fm = FileManager.default
        guard fm.fileExists(atPath: basePath) else { return 0 }

        let cutoff = Date().addingTimeInterval(-seconds)
        let files = try fm.contentsOfDirectory(atPath: basePath)
        var pruned = 0

        for file in files where file.hasSuffix("-decisions.jsonl") {
            let filePath = "\(basePath)/\(file)"
            let attrs = try fm.attributesOfItem(atPath: filePath)
            if let modified = attrs[.modificationDate] as? Date, modified < cutoff {
                try fm.removeItem(atPath: filePath)
                let sessionId = String(file.dropLast("-decisions.jsonl".count))
                cache.removeValue(forKey: sessionId)
                pruned += 1
            }
        }

        return pruned
    }

    /// Clear the in-memory cache (useful for tests).
    public func clearCache() {
        cache.removeAll()
    }

    // MARK: - Private

    private func journalPath(for sessionId: String) -> String {
        "\(basePath)/\(sessionId)-decisions.jsonl"
    }
}
