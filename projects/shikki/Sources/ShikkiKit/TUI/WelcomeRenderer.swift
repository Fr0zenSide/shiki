import Foundation

/// "Welcome back" display for shikki session resume.
/// BR-45: On resume, appears first before standard startup.
/// BR-46: Format: relative time + duration + pane count.
/// BR-47: Relative time: <1m / Xm / Xh / Xd.
/// BR-48: >7d staleness warning.
/// BR-49: Clean start (no checkpoint) = no message.
public enum WelcomeRenderer {

    /// Render the welcome-back message as a string (for testing).
    /// Returns nil if no checkpoint (clean start, BR-49).
    public static func renderToString(checkpoint: Checkpoint?, now: Date = Date()) -> String? {
        guard let cp = checkpoint else { return nil }

        let timeAgo = relativeTime(from: cp.timestamp, to: now)
        var parts: [String] = []

        // Duration
        if let stats = cp.sessionStats {
            let duration = formatDuration(from: stats.startedAt, to: cp.timestamp)
            parts.append("Welcome back — last session \(timeAgo) ago (\(duration))")
        } else {
            parts.append("Welcome back — last session \(timeAgo) ago")
        }

        // Pane count
        if let layout = cp.tmuxLayout {
            parts[0] += ". Restoring \(layout.paneCount) panes."
        }

        // BR-48: Staleness warning
        let daysSince = now.timeIntervalSince(cp.timestamp) / 86400
        if daysSince > 7 {
            let days = Int(daysSince)
            parts.append("(checkpoint is \(days)d old — layout may be outdated)")
        }

        return parts.joined(separator: " ")
    }

    /// Render to stdout if TTY. No-op if piped.
    public static func render(checkpoint: Checkpoint?, now: Date = Date()) {
        guard isatty(STDIN_FILENO) == 1 else { return }
        guard let output = renderToString(checkpoint: checkpoint, now: now) else { return }
        print(output)
    }

    /// BR-47: Relative time formatting.
    public static func relativeTime(from date: Date, to now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        let minutes = Int(seconds / 60)
        let hours = Int(seconds / 3600)
        let days = Int(seconds / 86400)

        if minutes < 1 { return "<1m" }
        if hours < 1 { return "\(minutes)m" }
        if days < 1 { return "\(hours)h" }
        return "\(days)d"
    }

    /// Format a duration between two dates as "Xh Ym", omitting zero components.
    private static func formatDuration(from start: Date, to end: Date) -> String {
        let seconds = end.timeIntervalSince(start)
        let totalMinutes = Int(seconds / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 && minutes > 0 {
            return "\(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(minutes)m"
        }
    }
}
