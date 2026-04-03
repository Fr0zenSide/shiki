import Foundation

// MARK: - SetupState

/// Tracks whether the Shikki environment has been fully set up.
/// Persisted at `~/.shikki/setup.json`. Used by SetupGuard to decide
/// whether to run bootstrap on launch.
public struct SetupState: Sendable, Codable, Equatable {

    /// The Shikki version that completed setup.
    public var version: String

    /// When setup was last completed.
    public var completedAt: Date

    /// Individual setup steps and their completion status.
    public var steps: [String: Bool]

    /// All known setup step names.
    public static let allSteps: [String] = [
        "dependencies",
        "workspace",
        "dotenv",
        "completions",
    ]

    public init(version: String, completedAt: Date = Date(), steps: [String: Bool] = [:]) {
        self.version = version
        self.completedAt = completedAt
        self.steps = steps
    }

    // MARK: - Persistence

    /// Default path: `~/.shikki/setup.json`
    public static var defaultPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.shikki/setup.json"
    }

    /// Load state from disk. Returns nil if file doesn't exist or is corrupt.
    public static func load(from path: String? = nil) -> SetupState? {
        let filePath = path ?? defaultPath
        guard FileManager.default.fileExists(atPath: filePath),
              let data = FileManager.default.contents(atPath: filePath) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SetupState.self, from: data)
    }

    /// Write state to disk, creating parent directories if needed.
    public func save(to path: String? = nil) throws {
        let filePath = path ?? Self.defaultPath
        let dir = (filePath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: URL(fileURLWithPath: filePath))
    }

    // MARK: - Queries

    /// True if setup file exists and its version matches the current binary version.
    public static func isComplete(currentVersion: String, path: String? = nil) -> Bool {
        guard let state = load(from: path) else { return false }
        return state.version == currentVersion
    }

    /// True if setup is missing or the version doesn't match.
    public static func needsSetup(currentVersion: String, path: String? = nil) -> Bool {
        !isComplete(currentVersion: currentVersion, path: path)
    }

    /// Mark setup as fully complete for the given version.
    public static func markComplete(version: String, path: String? = nil) throws {
        var steps: [String: Bool] = [:]
        for step in allSteps {
            steps[step] = true
        }
        let state = SetupState(version: version, completedAt: Date(), steps: steps)
        try state.save(to: path)
    }

    /// Mark an individual step as done (preserves other state).
    public mutating func markStep(_ step: String) {
        steps[step] = true
    }

    /// Check if a specific step has been completed.
    public func isStepComplete(_ step: String) -> Bool {
        steps[step] == true
    }

    /// True when all known steps are marked complete.
    public var allStepsComplete: Bool {
        Self.allSteps.allSatisfy { steps[$0] == true }
    }
}
