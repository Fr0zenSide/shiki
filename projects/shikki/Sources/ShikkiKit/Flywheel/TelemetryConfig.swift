import Foundation

// MARK: - TelemetryLevel

/// User's opt-in telemetry preference.
/// Default is `.local` — data stays on-device.
public enum TelemetryLevel: String, Codable, Sendable, CaseIterable {
    /// Share anonymized outcomes with the community.
    case community
    /// Collect locally for self-improvement only.
    case local
    /// No collection at all.
    case off
}

// MARK: - TelemetryConfig

/// Manages user telemetry preferences.
/// Persisted to `~/.config/shikki/telemetry.json`.
public struct TelemetryConfig: Codable, Sendable, Equatable {
    public var level: TelemetryLevel
    public var installId: String
    public var consentDate: Date?
    public var lastSyncDate: Date?

    /// Categories the user has opted into sharing (when level == .community).
    public var sharedCategories: Set<OutcomeCategory>

    public init(
        level: TelemetryLevel = .local,
        installId: String = UUID().uuidString,
        consentDate: Date? = nil,
        lastSyncDate: Date? = nil,
        sharedCategories: Set<OutcomeCategory> = OutcomeCategory.defaultShared
    ) {
        self.level = level
        self.installId = installId
        self.consentDate = consentDate
        self.lastSyncDate = lastSyncDate
        self.sharedCategories = sharedCategories
    }
}

// MARK: - OutcomeCategory

/// Categories of anonymized data that can be shared.
public enum OutcomeCategory: String, Codable, Sendable, Hashable, CaseIterable {
    case riskScores
    case watchdogPatterns
    case promptEffectiveness
    case specPatterns
    case taskOutcomes

    /// Default categories shared when user opts into community telemetry.
    public static let defaultShared: Set<OutcomeCategory> = [
        .riskScores, .watchdogPatterns, .taskOutcomes,
    ]
}

// MARK: - TelemetryConfigStore

/// Actor-isolated persistent store for telemetry configuration.
public actor TelemetryConfigStore {
    private var config: TelemetryConfig
    private let filePath: String

    public init(filePath: String? = nil) {
        let path = filePath ?? Self.defaultPath()
        self.filePath = path
        self.config = Self.load(from: path) ?? TelemetryConfig()
    }

    /// Read the current config.
    public func current() -> TelemetryConfig {
        config
    }

    /// Update the telemetry level.
    public func setLevel(_ level: TelemetryLevel) throws {
        config.level = level
        if level == .community && config.consentDate == nil {
            config.consentDate = Date()
        }
        try save()
    }

    /// Update shared categories.
    public func setSharedCategories(_ categories: Set<OutcomeCategory>) throws {
        config.sharedCategories = categories
        try save()
    }

    /// Record a successful sync.
    public func recordSync() throws {
        config.lastSyncDate = Date()
        try save()
    }

    /// Check if a category is allowed for sharing.
    public func isSharingAllowed(for category: OutcomeCategory) -> Bool {
        config.level == .community && config.sharedCategories.contains(category)
    }

    /// Check if any collection is enabled.
    public func isCollectionEnabled() -> Bool {
        config.level != .off
    }

    // MARK: - Persistence

    private func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(config)
        let url = URL(fileURLWithPath: filePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)
    }

    private static func load(from path: String) -> TelemetryConfig? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(TelemetryConfig.self, from: data)
    }

    private static func defaultPath() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.config/shikki/telemetry.json"
    }
}
