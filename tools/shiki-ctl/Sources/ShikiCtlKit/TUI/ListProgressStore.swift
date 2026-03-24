import Foundation

// MARK: - Progress Model

/// Persisted progress state for a list review session.
public struct ListProgress: Codable, Sendable, Equatable {
    public let listId: String
    public var reviewedItemIds: [String]
    public var pinnedOrder: [String]
    public var lastIndex: Int
    public var lastUpdated: Date

    public init(
        listId: String,
        reviewedItemIds: [String] = [],
        pinnedOrder: [String] = [],
        lastIndex: Int = 0,
        lastUpdated: Date = Date()
    ) {
        self.listId = listId
        self.reviewedItemIds = reviewedItemIds
        self.pinnedOrder = pinnedOrder
        self.lastIndex = lastIndex
        self.lastUpdated = lastUpdated
    }
}

// MARK: - Progress Store

/// Reads and writes list review progress to a local JSON file.
/// Falls back gracefully when the file or directory does not exist.
public struct ListProgressStore: Sendable {
    private let filePath: URL

    /// Default path: `~/.config/shiki/list-progress.json`.
    public init(filePath: URL? = nil) {
        if let filePath {
            self.filePath = filePath
        } else {
            let configDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/shiki", isDirectory: true)
            self.filePath = configDir.appendingPathComponent("list-progress.json")
        }
    }

    /// Load progress for a given listId. Returns nil if missing or corrupted.
    public func load(listId: String) -> ListProgress? {
        guard let data = try? Data(contentsOf: filePath) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let dict = try? decoder.decode([String: ListProgress].self, from: data) else {
            return nil
        }
        return dict[listId]
    }

    /// Save progress, upserting into the existing file. Creates directory if needed.
    /// Writes atomically (to temp file then rename).
    public func save(_ progress: ListProgress) {
        let fm = FileManager.default
        let dir = filePath.deletingLastPathComponent()

        // Create directory if missing
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        // Load existing entries
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var dict: [String: ListProgress] = [:]
        if let data = try? Data(contentsOf: filePath),
           let existing = try? decoder.decode([String: ListProgress].self, from: data) {
            dict = existing
        }

        // Upsert
        dict[progress.listId] = progress

        // Encode
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(dict) else { return }

        // Atomic write: write to temp, then rename
        let tempPath = filePath.appendingPathExtension("tmp")
        do {
            try data.write(to: tempPath, options: .atomic)
            // On macOS/Linux, .atomic already does a rename under the hood,
            // but we write to a .tmp extension for extra safety
            if fm.fileExists(atPath: filePath.path) {
                try fm.removeItem(at: filePath)
            }
            try fm.moveItem(at: tempPath, to: filePath)
        } catch {
            // Fallback: direct write
            try? data.write(to: filePath, options: .atomic)
        }
    }

    /// Remove the progress entry for a given listId.
    public func clear(listId: String) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let data = try? Data(contentsOf: filePath),
              var dict = try? decoder.decode([String: ListProgress].self, from: data) else {
            return
        }

        dict.removeValue(forKey: listId)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        if let newData = try? encoder.encode(dict) {
            try? newData.write(to: filePath, options: .atomic)
        }
    }
}
