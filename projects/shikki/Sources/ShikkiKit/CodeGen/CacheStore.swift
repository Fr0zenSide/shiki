import Foundation

/// Errors that can occur in ``CacheStore`` operations.
public enum CacheStoreError: Error, LocalizedError, Sendable {
    case encodingFailed
    case decodingFailed(String)
    case directoryCreationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode architecture cache to JSON"
        case .decodingFailed(let detail):
            return "Failed to decode architecture cache: \(detail)"
        case .directoryCreationFailed(let path):
            return "Failed to create cache directory: \(path)"
        }
    }
}

/// Stores and retrieves ``ArchitectureCache`` per project as JSON files.
///
/// Default location: `~/.shikki/cache/<projectId>.json`
public final class CacheStore: @unchecked Sendable {

    private let basePath: URL

    /// Create a cache store.
    ///
    /// - Parameter basePath: Override the cache directory. Defaults to `~/.shikki/cache/`.
    public init(basePath: URL? = nil) {
        if let basePath {
            self.basePath = basePath
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            self.basePath = home.appendingPathComponent(".shikki/cache")
        }
    }

    /// Save an architecture cache to disk.
    public func save(_ cache: ArchitectureCache) throws {
        try ensureDirectory()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(cache)
        let fileURL = basePath.appendingPathComponent("\(cache.projectId).json")
        try data.write(to: fileURL, options: .atomic)
    }

    /// Load a cached architecture for the given project ID.
    ///
    /// - Returns: The cache, or `nil` if no cache exists.
    public func load(projectId: String) throws -> ArchitectureCache? {
        let fileURL = basePath.appendingPathComponent("\(projectId).json")
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ArchitectureCache.self, from: data)
    }

    /// Check if the cache for a project is stale (different git hash).
    public func isStale(projectId: String, currentGitHash: String) -> Bool {
        guard let cache = try? load(projectId: projectId) else {
            return true  // No cache = stale
        }
        return cache.gitHash != currentGitHash
    }

    /// Remove the cache for a project.
    public func invalidate(projectId: String) throws {
        let fileURL = basePath.appendingPathComponent("\(projectId).json")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    /// List all cached project IDs.
    public func listCached() -> [String] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: basePath,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        return contents
            .filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    // MARK: - Private

    private func ensureDirectory() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: basePath.path) {
            do {
                try fm.createDirectory(at: basePath, withIntermediateDirectories: true)
            } catch {
                throw CacheStoreError.directoryCreationFailed(basePath.path)
            }
        }
    }
}
