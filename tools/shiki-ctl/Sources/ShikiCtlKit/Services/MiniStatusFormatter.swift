import Foundation

/// Formats session data into compact or expanded single-line output for tmux status bar.
public enum MiniStatusFormatter {

    /// Icons for session status mapping.
    /// ● = working (green), ▲ = needs attention (yellow), ✗ = failed (red), ○ = idle (dim)
    private enum StatusIcon: String {
        case working = "●"
        case attention = "▲"
        case failed = "✗"
        case idle = "○"
    }

    /// Compact format: "●2 ▲1 ○3 Q:1 $4/$15"
    /// Only shows categories with count > 0 (except Q and $ which always show).
    public static func formatCompact(
        sessions: [RegisteredSession],
        pendingQuestions: Int,
        spentUsd: Double,
        budgetUsd: Double
    ) -> String {
        let counts = countByCategory(sessions)
        var parts: [String] = []

        if counts.working > 0 { parts.append("\(StatusIcon.working.rawValue)\(counts.working)") }
        if counts.attention > 0 { parts.append("\(StatusIcon.attention.rawValue)\(counts.attention)") }
        if counts.failed > 0 { parts.append("\(StatusIcon.failed.rawValue)\(counts.failed)") }
        if counts.idle > 0 { parts.append("\(StatusIcon.idle.rawValue)\(counts.idle)") }

        parts.append("Q:\(pendingQuestions)")
        parts.append("$\(formatBudgetNumber(spentUsd))/$\(formatBudgetNumber(budgetUsd))")

        return parts.joined(separator: " ")
    }

    /// Expanded format: "maya:● wabi:▲ flsh:○ | Q:1 | $4.20/$15"
    public static func formatExpanded(
        sessions: [RegisteredSession],
        pendingQuestions: Int,
        spentUsd: Double,
        budgetUsd: Double
    ) -> String {
        let sessionParts = sessions
            .sorted(by: { $0.attentionZone < $1.attentionZone })
            .map { session in
                let slug = extractCompanySlug(from: session.windowName)
                let icon = iconForState(session.state)
                return "\(slug):\(icon.rawValue)"
            }

        var sections: [String] = []
        if !sessionParts.isEmpty {
            sections.append(sessionParts.joined(separator: " "))
        }
        sections.append("Q:\(pendingQuestions)")
        sections.append("$\(formatBudgetNumber(spentUsd))/$\(formatBudgetNumber(budgetUsd))")

        return sections.joined(separator: " | ")
    }

    /// Fallback when backend is unreachable.
    public static func formatUnreachable() -> String {
        "? Q:? $?"
    }

    // MARK: - Private Helpers

    private struct CategoryCounts {
        var working: Int = 0
        var attention: Int = 0
        var failed: Int = 0
        var idle: Int = 0
    }

    private static func countByCategory(_ sessions: [RegisteredSession]) -> CategoryCounts {
        var counts = CategoryCounts()
        for session in sessions {
            switch iconForState(session.state) {
            case .working: counts.working += 1
            case .attention: counts.attention += 1
            case .failed: counts.failed += 1
            case .idle: counts.idle += 1
            }
        }
        return counts
    }

    private static func iconForState(_ state: SessionState) -> StatusIcon {
        switch state.attentionZone {
        case .merge, .review: .working
        case .respond: .attention
        case .pending: .attention
        case .working: .working
        case .idle: .idle
        }
    }

    /// Extract company slug from window name (e.g., "maya:spm-wave3" → "maya").
    private static func extractCompanySlug(from windowName: String) -> String {
        let parts = windowName.split(separator: ":", maxSplits: 1)
        return String(parts.first ?? Substring(windowName))
    }

    private static func formatBudgetNumber(_ value: Double) -> String {
        if value == 0 { return "0" }
        if value == value.rounded(.down) {
            return String(format: "%.0f", value)
        }
        return String(format: "%.2f", value)
    }
}
