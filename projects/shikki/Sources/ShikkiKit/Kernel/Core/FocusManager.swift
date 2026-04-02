import Foundation

// MARK: - Focus State

/// Persisted focus mode state stored at ~/.shikki/focus.json.
public struct FocusState: Codable, Sendable, Equatable {
    public var startedAt: Date
    /// Duration in seconds. nil = no timer (elapsed-only mode).
    public var durationSeconds: Double?
    public var active: Bool

    public init(startedAt: Date, durationSeconds: Double? = nil, active: Bool) {
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.active = active
    }
}

// MARK: - Duration Parser

/// Parses duration strings like "20m", "90s", "1h" into seconds.
/// BR-EM-14: Explicit duration support.
public enum DurationParser {
    /// Returns seconds for input like "20m", "90s", "1h", "3600".
    /// Returns nil for unrecognised formats.
    public static func parse(_ input: String) -> Double? {
        let s = input.trimmingCharacters(in: .whitespaces).lowercased()
        if s.hasSuffix("h"), let value = Double(s.dropLast()) {
            return value * 3600
        } else if s.hasSuffix("m"), let value = Double(s.dropLast()) {
            return value * 60
        } else if s.hasSuffix("s"), let value = Double(s.dropLast()) {
            return value
        } else if let value = Double(s) {
            // Bare number treated as seconds
            return value
        }
        return nil
    }

    /// Human-readable representation of a duration in seconds.
    public static func format(_ seconds: Double) -> String {
        let s = Int(seconds)
        if s >= 3600 {
            let h = s / 3600
            let m = (s % 3600) / 60
            return m > 0 ? "\(h)h \(m)m" : "\(h)h"
        } else if s >= 60 {
            let m = s / 60
            let rem = s % 60
            return rem > 0 ? "\(m)m \(rem)s" : "\(m)m"
        } else {
            return "\(s)s"
        }
    }
}

// MARK: - Focus Manager

/// Manages focus mode state persisted at ~/.shikki/focus.json.
/// BR-EM-14: Focus mode stores startedAt, duration, active flag.
public struct FocusManager: Sendable {
    public let directory: String

    /// Filename for focus state.
    private static let filename = "focus.json"

    public init(directory: String? = nil) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.directory = directory ?? "\(home)/.shikki"
    }

    /// Full path to the focus state file.
    public var focusPath: String { "\(directory)/\(Self.filename)" }

    // MARK: - CRUD

    /// Save focus state to disk atomically.
    public func save(_ state: FocusState) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directory) {
            try fm.createDirectory(atPath: directory, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)

        // Atomic write: write to .tmp then rename
        let tmpPath = "\(directory)/focus.tmp"
        let tmpURL = URL(fileURLWithPath: tmpPath)
        let targetURL = URL(fileURLWithPath: focusPath)
        try data.write(to: tmpURL, options: .atomic)
        if fm.fileExists(atPath: focusPath) {
            try fm.removeItem(at: targetURL)
        }
        try fm.moveItem(at: tmpURL, to: targetURL)
    }

    /// Load focus state from disk. Returns nil if no file exists.
    public func load() throws -> FocusState? {
        guard FileManager.default.fileExists(atPath: focusPath) else { return nil }
        let data = try Data(contentsOf: URL(fileURLWithPath: focusPath))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(FocusState.self, from: data)
    }

    /// Delete the focus state file.
    public func delete() throws {
        if FileManager.default.fileExists(atPath: focusPath) {
            try FileManager.default.removeItem(atPath: focusPath)
        }
    }

    /// Returns true if focus mode is currently active.
    public func isActive() -> Bool {
        (try? load())?.active == true
    }
}
