import Foundation

/// Manages personality observations — behavioral patterns that shape tone across sessions.
/// Append-only: observations are ADDED, never removed or edited.
/// Loaded at session start as part of the system context.
public struct PersonalityManager: Sendable {
    public let personalityPath: String

    public init(personalityPath: String = "~/.shikki/personality.md") {
        self.personalityPath = (personalityPath as NSString).expandingTildeInPath
    }

    /// Append a behavioral observation with timestamp.
    public func observe(_ observation: String) throws {
        let fm = FileManager.default
        let dir = (personalityPath as NSString).deletingLastPathComponent

        if !fm.fileExists(atPath: dir) {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let entry = "- [\(timestamp)] \(observation)\n"

        if fm.fileExists(atPath: personalityPath) {
            let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: personalityPath))
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            guard let data = entry.data(using: .utf8) else { return }
            handle.write(data)
        } else {
            let header = "# Personality Observations\n\n"
            let content = header + entry
            try content.write(toFile: personalityPath, atomically: true, encoding: .utf8)
        }
    }

    /// Load all observations for session context injection.
    public func loadPersonality() throws -> String {
        let fm = FileManager.default
        guard fm.fileExists(atPath: personalityPath) else {
            return ""
        }
        return try String(contentsOfFile: personalityPath, encoding: .utf8)
    }

    /// Count observations (lines starting with "- [").
    public func observationCount() throws -> Int {
        let content = try loadPersonality()
        guard !content.isEmpty else { return 0 }
        return content.components(separatedBy: "\n")
            .filter { $0.hasPrefix("- [") }
            .count
    }
}
