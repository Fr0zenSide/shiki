import Foundation

// MARK: - ObservatoryRenderer

/// Renders the Observatory TUI dashboard — timeline, decisions, questions, reports.
/// Pure rendering: takes ObservatoryEngine state and produces strings. No side effects.
public struct ObservatoryRenderer: Sendable {

    private let width: Int
    private let height: Int

    public init(width: Int = 80, height: Int = 24) {
        self.width = max(width, 60)
        self.height = max(height, 12)
    }

    // MARK: - Full Frame

    /// Render the complete Observatory frame.
    public func render(engine: ObservatoryEngine) -> String {
        var lines: [String] = []

        // Header
        lines.append(renderHeader(tab: engine.currentTab))

        // Separator
        lines.append(renderSeparator())

        // Content area
        let contentLines: [String]
        switch engine.currentTab {
        case .timeline:
            contentLines = renderTimeline(
                entries: engine.timelineEntries,
                selectedIndex: engine.selectedIndex
            )
        case .decisions:
            let decisionEntries = engine.timelineEntries.filter {
                $0.significance == .decision
            }
            contentLines = renderDecisions(
                entries: decisionEntries,
                selectedIndex: engine.selectedIndex
            )
        case .questions:
            contentLines = renderQuestions(
                questions: engine.pendingQuestions,
                selectedIndex: engine.selectedIndex
            )
        case .reports:
            contentLines = renderReports(
                reports: engine.reports,
                selectedIndex: engine.selectedIndex
            )
        }

        lines.append(contentsOf: contentLines)

        // Footer
        lines.append(renderSeparator())
        lines.append(renderFooter(tab: engine.currentTab))

        return lines.joined(separator: "\n")
    }

    // MARK: - Header

    /// Render the tab bar header.
    public func renderHeader(tab: ObservatoryTab) -> String {
        let tabs = ObservatoryTab.allCases.map { t -> String in
            if t == tab {
                return "\(ANSI.inverse) \(t.rawValue.uppercased()) \(ANSI.reset)"
            }
            return " \(t.rawValue) "
        }
        let tabBar = tabs.joined(separator: " | ")
        return "\(ANSI.bold)SHIKKI OBSERVATORY\(ANSI.reset)  \(tabBar)"
    }

    // MARK: - Timeline

    /// Render timeline entries with selection highlight.
    public func renderTimeline(
        entries: [ObservatoryEntry],
        selectedIndex: Int
    ) -> [String] {
        guard !entries.isEmpty else {
            return ["\(ANSI.dim)  No events yet.\(ANSI.reset)"]
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"

        let maxVisible = height - 6 // header + footer + separator + padding
        let visibleEntries = Array(entries.prefix(max(maxVisible, 1)))

        return visibleEntries.enumerated().map { i, entry in
            let timeStr = formatter.string(from: entry.timestamp)
            let color = ObservatoryHeatmap.color(for: entry.significance)
            let icon = entry.icon
            let cursor = i == selectedIndex ? "\(ANSI.inverse)>\(ANSI.reset)" : " "
            let title = String(entry.title.prefix(width - 20))
            let detail = entry.detail.isEmpty ? "" : " \(ANSI.dim)\(entry.detail)\(ANSI.reset)"

            return "\(cursor) \(ANSI.dim)\(timeStr)\(ANSI.reset) \(color)\(icon)\(ANSI.reset) \(title)\(detail)"
        }
    }

    // MARK: - Decisions

    /// Render decision entries.
    public func renderDecisions(
        entries: [ObservatoryEntry],
        selectedIndex: Int
    ) -> [String] {
        guard !entries.isEmpty else {
            return ["\(ANSI.dim)  No decisions recorded.\(ANSI.reset)"]
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        return entries.enumerated().map { i, entry in
            let timeStr = formatter.string(from: entry.timestamp)
            let cursor = i == selectedIndex ? "\(ANSI.inverse)>\(ANSI.reset)" : " "
            let title = String(entry.title.prefix(width - 25))
            return "\(cursor) \(ANSI.dim)\(timeStr)\(ANSI.reset) \(ANSI.bold)\u{25C6}\(ANSI.reset) \(title)"
        }
    }

    // MARK: - Questions

    /// Render pending questions.
    public func renderQuestions(
        questions: [PendingQuestion],
        selectedIndex: Int
    ) -> [String] {
        guard !questions.isEmpty else {
            return ["\(ANSI.dim)  No pending questions.\(ANSI.reset)"]
        }

        var lines: [String] = []

        for (i, q) in questions.enumerated() {
            let cursor = i == selectedIndex ? "\(ANSI.inverse)>\(ANSI.reset)" : " "
            let age = formatAge(since: q.askedAt)
            let answered = q.answer != nil ? "\(ANSI.green)answered\(ANSI.reset)" : "\(ANSI.yellow)pending\(ANSI.reset)"

            lines.append("\(cursor) \(ANSI.bold)Q\(i + 1)\(ANSI.reset) [\(q.sessionId)] \(answered)  \(ANSI.dim)\(age)\(ANSI.reset)")
            lines.append("  \(ANSI.dim)Context: \(String(q.context.prefix(width - 15)))\(ANSI.reset)")
            lines.append("  \(q.question)")

            if let answer = q.answer {
                lines.append("  \(ANSI.green)> \(answer)\(ANSI.reset)")
            }
            lines.append("")
        }

        return lines
    }

    // MARK: - Reports

    /// Render agent report cards.
    public func renderReports(
        reports: [AgentReportCard],
        selectedIndex: Int
    ) -> [String] {
        guard !reports.isEmpty else {
            return ["\(ANSI.dim)  No agent reports.\(ANSI.reset)"]
        }

        var lines: [String] = []

        for (i, report) in reports.enumerated() {
            let isExpanded = i == selectedIndex
            lines.append(report.renderTUI(expanded: isExpanded))
            lines.append("")
        }

        return lines
    }

    // MARK: - Separator + Footer

    func renderSeparator() -> String {
        String(repeating: "\u{2500}", count: width)
    }

    /// Render the footer with keyboard shortcuts.
    public func renderFooter(tab: ObservatoryTab) -> String {
        let base = "\(ANSI.dim)\u{2191}/\u{2193} navigate \u{00B7} Tab switch \u{00B7} Enter expand \u{00B7} q quit\(ANSI.reset)"

        switch tab {
        case .questions:
            return "\(ANSI.dim)\u{2191}/\u{2193} navigate \u{00B7} Tab switch \u{00B7} Enter edit \u{00B7} Ctrl-S submit \u{00B7} q quit\(ANSI.reset)"
        default:
            return base
        }
    }

    // MARK: - Helpers

    private func formatAge(since date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        return "\(hours)h ago"
    }
}

// MARK: - Static Snapshot (for tests)

extension ObservatoryRenderer {

    /// Render a static snapshot of the full dashboard.
    /// Returns an array of lines without ANSI codes (for testing).
    public func renderPlain(engine: ObservatoryEngine) -> [String] {
        let raw = render(engine: engine)
        let stripped = raw.replacingOccurrences(
            of: "\u{1B}\\[[0-9;]*m", with: "",
            options: .regularExpression
        )
        return stripped.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }
}
