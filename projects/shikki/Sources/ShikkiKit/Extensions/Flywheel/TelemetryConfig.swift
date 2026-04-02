import Foundation

// MARK: - TelemetryLevel

/// User-controlled telemetry opt-in levels.
/// Default is `.local` — data stays on-device.
public enum TelemetryLevel: String, Codable, Sendable, Equatable, CaseIterable {
    /// Share anonymized outcome data with the community.
    case community

    /// Collect data locally for self-improvement only (default).
    case local

    /// No data collection at all.
    case off
}

// MARK: - TelemetryConfig

/// Persistent telemetry configuration.
/// Stored at `~/.config/shikki/telemetry.json`.
public struct TelemetryConfig: Codable, Sendable, Equatable {
    public var level: TelemetryLevel
    public var installId: String
    public var consentDate: Date?
    public var version: Int

    /// Current config schema version.
    public static let currentVersion = 1

    public init(
        level: TelemetryLevel = .local,
        installId: String = UUID().uuidString,
        consentDate: Date? = nil,
        version: Int = TelemetryConfig.currentVersion
    ) {
        self.level = level
        self.installId = installId
        self.consentDate = consentDate
        self.version = version
    }

    /// Whether any data should be collected (local or community).
    public var isCollectionEnabled: Bool {
        level != .off
    }

    /// Whether anonymized data can be shared externally.
    public var isSharingEnabled: Bool {
        level == .community
    }
}

// MARK: - TelemetryConfigStore

/// Reads and writes TelemetryConfig to disk.
public struct TelemetryConfigStore: Sendable {
    private let configPath: String

    public init(configPath: String? = nil) {
        self.configPath = configPath ?? Self.defaultConfigPath()
    }

    public static func defaultConfigPath() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.config/shikki/telemetry.json"
    }

    public func load() throws -> TelemetryConfig {
        let url = URL(fileURLWithPath: configPath)
        guard FileManager.default.fileExists(atPath: configPath) else {
            return TelemetryConfig()
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TelemetryConfig.self, from: data)
    }

    public func save(_ config: TelemetryConfig) throws {
        let url = URL(fileURLWithPath: configPath)
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: url, options: .atomic)
    }

    /// Update the telemetry level, preserving install ID.
    public func setLevel(_ level: TelemetryLevel) throws -> TelemetryConfig {
        var config = (try? load()) ?? TelemetryConfig()
        config.level = level
        if level == .community {
            config.consentDate = Date()
        }
        try save(config)
        return config
    }
}
