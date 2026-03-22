import Foundation

// MARK: - PR Review State Manager

/// Loads/saves PRReviewProgress from `docs/prN-cache/review-state.json`.
/// Local-first: file is source of truth, GitHub sync is secondary.
public struct PRReviewStateManager: Sendable {

    private let cacheDir: String
    private let statePath: String

    public init(prNumber: Int, basePath: String = "docs") {
        self.cacheDir = "\(basePath)/pr\(prNumber)-cache"
        self.statePath = "\(cacheDir)/review-state.json"
    }

    // MARK: - Init with explicit path (for testing)

    public init(cacheDir: String) {
        self.cacheDir = cacheDir
        self.statePath = "\(cacheDir)/review-state.json"
    }

    // MARK: - Load

    /// Load review state, or nil if no state file exists.
    public func load() throws -> PRReviewProgress? {
        guard FileManager.default.fileExists(atPath: statePath) else { return nil }
        let data = try Data(contentsOf: URL(fileURLWithPath: statePath))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PRReviewProgress.self, from: data)
    }

    // MARK: - Save

    public func save(_ state: PRReviewProgress) throws {
        try FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: URL(fileURLWithPath: statePath))
    }

    // MARK: - Load or Create

    /// Load existing state, or create a new one from the given file paths.
    public func loadOrCreate(prNumber: Int, filePaths: [String]) throws -> PRReviewProgress {
        if var existing = try load() {
            // Prune files no longer in the PR
            existing.prune(currentPaths: filePaths)
            // Add new files not yet tracked
            let tracked = Set(existing.reviewedFiles.map(\.path))
            for path in filePaths where !tracked.contains(path) {
                existing.reviewedFiles.append(.init(path: path))
            }
            return existing
        }
        return PRReviewProgress(
            prNumber: prNumber,
            reviewedFiles: filePaths.map { .init(path: $0) }
        )
    }

    /// Check if state file exists.
    public var hasState: Bool {
        FileManager.default.fileExists(atPath: statePath)
    }
}
