//
//  DateFormatter+Extensions.swift
//  ShikkiKit
//
//  Mirrors CoreKit/DateFormatter+Extensions — shared date formatting (DRY).
//  When ShikkiKit gains a CoreKit dependency, delete this file and use CoreKit's.
//

import Foundation

// MARK: - Shared Date Formatters

public extension DateFormatter {

    /// Short display: `2026-03-26 14:30` — local timezone.
    static var shortDisplay: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = .current
        return f
    }

    /// Compact display: `Mar 26 14:30` — local timezone.
    static var compactDisplay: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "MMM dd HH:mm"
        f.timeZone = .current
        return f
    }

    /// Time only: `14:30:05` — local timezone.
    static var timeOnly: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.timeZone = .current
        return f
    }

    /// Date only: `2026-03-26` — local timezone.
    static var dateOnly: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }

    /// Time display (hours:minutes only): `14:30` — local timezone.
    static var timeDisplay: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.timeZone = .current
        return f
    }
}

// MARK: - Shared ISO8601 Formatters

public extension ISO8601DateFormatter {

    /// Standard ISO 8601 for API communication and DB storage.
    /// Example: `2026-03-26T14:30:05Z`
    static var standard: ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }

    /// ISO 8601 with fractional seconds for high-precision timestamps.
    /// Example: `2026-03-26T14:30:05.123Z`
    static var precise: ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }
}

// MARK: - Date Convenience

public extension Date {

    /// Format with the shared short display formatter.
    var shortDisplay: String { DateFormatter.shortDisplay.string(from: self) }

    /// Format with the shared compact display formatter.
    var compactDisplay: String { DateFormatter.compactDisplay.string(from: self) }

    /// Format as time only (HH:mm:ss).
    var timeOnly: String { DateFormatter.timeOnly.string(from: self) }

    /// Format as date only (yyyy-MM-dd).
    var dateOnly: String { DateFormatter.dateOnly.string(from: self) }

    /// Format as standard ISO 8601.
    var iso8601: String { ISO8601DateFormatter.standard.string(from: self) }

    /// Format as precise ISO 8601 (with fractional seconds).
    var iso8601Precise: String { ISO8601DateFormatter.precise.string(from: self) }

    /// Human-readable relative time: "2h ago", "3d ago", "just now".
    var relativeDisplay: String {
        let interval = Date().timeIntervalSince(self)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        if interval < 604800 { return "\(Int(interval / 86400))d ago" }
        return self.shortDisplay
    }
}
