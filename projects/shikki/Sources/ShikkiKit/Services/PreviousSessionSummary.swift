import Foundation
import Logging

// MARK: - Session Record

/// A recorded session entry, stored in `.shikki/sessions/`.
public struct SessionRecord: Sendable, Codable, Equatable {
    public let id: String
    public let startedAt: Date
    public let endedAt: Date?
    public let branch: String
    public let specsDelivered: Int
    public let testsGreen: Int
    public let branchesMerged: Int
    public let pendingSpecs: Int
    public let pendingReviews: Int

    public init(
        id: String = UUID().uuidString,
        startedAt: Date,
        endedAt: Date? = nil,
        branch: String = "develop",
        specsDelivered: Int = 0,
        testsGreen: Int = 0,
        branchesMerged: Int = 0,
        pendingSpecs: Int = 0,
        pendingReviews: Int = 0
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.branch = branch
        self.specsDelivered = specsDelivered
        self.testsGreen = testsGreen
        self.branchesMerged = branchesMerged
        self.pendingSpecs = pendingSpecs
        self.pendingReviews = pendingReviews
    }

    /// Duration of the session, or nil if still active.
    public var duration: TimeInterval? {
        guard let end = endedAt else { return nil }
        return end.timeIntervalSince(startedAt)
    }

    /// Formatted duration string (e.g. "12h 35m").
    public var formattedDuration: String? {
        guard let dur = duration else { return nil }
        return Self.formatDuration(dur)
    }

    /// Format a TimeInterval into human-readable duration.
    public static func formatDuration(_ interval: TimeInterval) -> String {
        let totalMinutes = Int(interval / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    /// Session date label (e.g. "shikki-2026-04-01").
    public var dateLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "shikki-\(formatter.string(from: startedAt))"
    }
}

// MARK: - Session Storage Protocol

/// Abstraction for session persistence, enabling test doubles.
public protocol SessionStorageProviding: Sendable {
    func loadSessions() throws -> [SessionRecord]
    func saveSession(_ session: SessionRecord) throws
    func lastSession() throws -> SessionRecord?
    func recentSessions(count: Int) throws -> [SessionRecord]
}

// MARK: - File-Based Session Storage

/// Stores session records as JSON files in `.shikki/sessions/`.
public struct FileSessionStorage: SessionStorageProviding, Sendable {
    private let directory: String
    private let logger: Logger

    public init(
        directory: String? = nil,
        logger: Logger = Logger(label: "shikki.session-storage")
    ) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.directory = directory ?? "\(home)/.shikki/sessions"
        self.logger = logger
    }

    public func loadSessions() throws -> [SessionRecord] {
        let fm = FileManager.default

        guard fm.fileExists(atPath: directory) else {
            return []
        }

        let files = try fm.contentsOfDirectory(atPath: directory)
            .filter { $0.hasSuffix(".json") }
            .sorted(by: >) // newest first by filename

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var sessions: [SessionRecord] = []
        for file in files {
            let path = "\(directory)/\(file)"
            guard let data = fm.contents(atPath: path) else { continue }
            if let session = try? decoder.decode(SessionRecord.self, from: data) {
                sessions.append(session)
            }
        }

        return sessions.sorted { $0.startedAt > $1.startedAt }
    }

    public func saveSession(_ session: SessionRecord) throws {
        let fm = FileManager.default

        if !fm.fileExists(atPath: directory) {
            try fm.createDirectory(
                atPath: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(session)

        let filename = "\(session.dateLabel)-\(session.id.prefix(8)).json"
        let path = "\(directory)/\(filename)"
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    public func lastSession() throws -> SessionRecord? {
        let sessions = try loadSessions()
        return sessions.first
    }

    public func recentSessions(count: Int) throws -> [SessionRecord] {
        let sessions = try loadSessions()
        return Array(sessions.prefix(count))
    }
}

// MARK: - PreviousSessionSummary

/// Formats and renders previous session information.
/// Used on startup after welcome/resume message.
public struct PreviousSessionSummary: Sendable {
    private let storage: any SessionStorageProviding
    private let logger: Logger

    public init(
        storage: (any SessionStorageProviding)? = nil,
        logger: Logger = Logger(label: "shikki.previous-session")
    ) {
        self.storage = storage ?? FileSessionStorage()
        self.logger = logger
    }

    // MARK: - Format Last Session

    /// Generate a summary string for the last session.
    /// Returns nil if no previous session exists.
    public func lastSessionSummary() -> String? {
        guard let session = try? storage.lastSession() else {
            return nil
        }
        return formatSession(session)
    }

    /// Generate summary for a specific session record.
    public func formatSession(_ session: SessionRecord) -> String {
        var parts: [String] = []

        // Duration
        if let duration = session.formattedDuration {
            parts.append(duration)
        }

        // Activity counts
        var activity: [String] = []
        if session.specsDelivered > 0 {
            activity.append("\(session.specsDelivered) spec\(session.specsDelivered == 1 ? "" : "s")")
        }
        if session.testsGreen > 0 {
            activity.append("\(formatNumber(session.testsGreen)) test\(session.testsGreen == 1 ? "" : "s")")
        }
        if session.branchesMerged > 0 {
            activity.append("\(session.branchesMerged) branch\(session.branchesMerged == 1 ? "" : "es") merged")
        }

        if activity.isEmpty {
            activity.append("no recorded activity")
        }

        let activityStr = activity.joined(separator: ", ")

        if parts.isEmpty {
            return "Last session: \(activityStr)"
        }

        return "Last session: \(activityStr) (\(parts.joined(separator: ", ")))"
    }

    // MARK: - Render for Terminal

    /// Render the last session summary for terminal output.
    /// Returns empty string if no previous session.
    public func renderLastSession() -> String {
        guard let summary = lastSessionSummary() else {
            return ""
        }
        return "  \u{1B}[2m\(summary)\u{1B}[0m"
    }

    // MARK: - Current Session Overview

    /// Format a session overview (for `shikki session` command).
    public func formatSessionOverview(_ session: SessionRecord, now: Date = Date()) -> String {
        var lines: [String] = []

        let separator = String(repeating: "\u{2501}", count: 42)
        lines.append(separator)

        // Session name
        lines.append("  Session: \(session.dateLabel)")

        // Started time
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        lines.append("  Started: \(dateFormatter.string(from: session.startedAt))")

        // Duration
        let elapsed: TimeInterval
        if let end = session.endedAt {
            elapsed = end.timeIntervalSince(session.startedAt)
        } else {
            elapsed = now.timeIntervalSince(session.startedAt)
        }
        lines.append("  Duration: \(SessionRecord.formatDuration(elapsed))")

        lines.append("")

        // Activity
        lines.append("  Specs delivered: \(session.specsDelivered)")
        lines.append("  Tests: \(formatNumber(session.testsGreen)) green")
        lines.append("  Branches merged: \(session.branchesMerged)")

        // Pending items
        if session.pendingSpecs > 0 || session.pendingReviews > 0 {
            lines.append("")
            lines.append("  Pending:")
            if session.pendingSpecs > 0 {
                lines.append("    \(session.pendingSpecs) spec\(session.pendingSpecs == 1 ? "" : "s") awaiting review")
            }
            if session.pendingReviews > 0 {
                lines.append("    \(session.pendingReviews) review\(session.pendingReviews == 1 ? "" : "s") pending")
            }
        }

        lines.append(separator)

        return lines.joined(separator: "\n")
    }

    // MARK: - Session History

    /// Format a list of sessions for history view.
    public func formatSessionHistory(_ sessions: [SessionRecord]) -> String {
        guard !sessions.isEmpty else {
            return "  No session history found."
        }

        var lines: [String] = []

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        for (index, session) in sessions.enumerated() {
            let date = dateFormatter.string(from: session.startedAt)
            let duration = session.formattedDuration ?? "active"

            var activity: [String] = []
            if session.specsDelivered > 0 {
                activity.append("\(session.specsDelivered) specs")
            }
            if session.testsGreen > 0 {
                activity.append("\(formatNumber(session.testsGreen)) tests")
            }
            if session.branchesMerged > 0 {
                activity.append("\(session.branchesMerged) merged")
            }

            let activityStr = activity.isEmpty ? "no activity" : activity.joined(separator: ", ")
            let marker = index == 0 ? "\u{25CF}" : "\u{25CB}"

            lines.append("  \(marker) \(date)  \(duration.padding(toLength: 8, withPad: " ", startingAt: 0))  \(activityStr)")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    private func formatNumber(_ n: Int) -> String {
        if n >= 1000 {
            let thousands = Double(n) / 1000.0
            return String(format: "%.1fk", thousands)
        }
        return "\(n)"
    }
}

// MARK: - Mock Session Storage

public final class MockSessionStorage: SessionStorageProviding, @unchecked Sendable {
    public var sessions: [SessionRecord]
    public private(set) var saveCallCount = 0

    public init(sessions: [SessionRecord] = []) {
        self.sessions = sessions
    }

    public func loadSessions() throws -> [SessionRecord] {
        sessions.sorted { $0.startedAt > $1.startedAt }
    }

    public func saveSession(_ session: SessionRecord) throws {
        saveCallCount += 1
        sessions.append(session)
    }

    public func lastSession() throws -> SessionRecord? {
        try loadSessions().first
    }

    public func recentSessions(count: Int) throws -> [SessionRecord] {
        try Array(loadSessions().prefix(count))
    }
}
