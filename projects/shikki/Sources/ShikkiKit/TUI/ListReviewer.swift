import Foundation

// MARK: - Models

/// A single item in a reviewable list.
public struct ListItem: Sendable, Equatable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let status: ItemStatus
    public let metadata: [String: String]

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        status: ItemStatus = .pending,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.status = status
        self.metadata = metadata
    }

    public enum ItemStatus: String, Sendable, CaseIterable {
        case pending, inReview, validated, corrected, rejected, killed

        /// Unicode status indicator.
        public var indicator: String {
            switch self {
            case .pending:   return "\u{25CB}"   // ○
            case .inReview:  return "\u{25D0}"   // ◐
            case .validated: return "\u{2713}"   // ✓
            case .corrected: return "\u{2713}"   // ✓ (corrected is still a pass)
            case .rejected:  return "\u{2717}"   // ✗
            case .killed:    return "\u{2298}"   // ⊘
            }
        }

        /// ANSI style for this status.
        public var style: ANSIStyle {
            switch self {
            case .pending:   return .white
            case .inReview:  return .yellow
            case .validated: return .green
            case .corrected: return .cyan
            case .rejected:  return .red
            case .killed:    return .dim
            }
        }

        /// Whether this status counts as "reviewed" (done).
        public var isReviewed: Bool {
            switch self {
            case .validated, .corrected, .rejected, .killed: return true
            case .pending, .inReview: return false
            }
        }
    }
}

// MARK: - Configuration

/// Configuration for a ListReviewer instance.
public struct ListReviewerConfig: Sendable {
    public let title: String
    public let showProgress: Bool
    public let actions: [ListAction]

    public init(
        title: String,
        showProgress: Bool = true,
        actions: [ListAction] = ListAction.defaults
    ) {
        self.title = title
        self.showProgress = showProgress
        self.actions = actions
    }

    /// A single-key action available in the list.
    public struct ListAction: Sendable {
        public let key: Character
        public let label: String
        public let appliesTo: Set<ListItem.ItemStatus>

        public init(key: Character, label: String, appliesTo: Set<ListItem.ItemStatus>) {
            self.key = key
            self.label = label
            self.appliesTo = appliesTo
        }

        /// Default actions for a review list.
        public static let defaults: [ListAction] = [
            ListAction(key: "a", label: "approve", appliesTo: [.pending, .inReview]),
            ListAction(key: "k", label: "kill", appliesTo: [.pending, .inReview]),
            ListAction(key: "e", label: "enrich", appliesTo: [.pending]),
            ListAction(key: "d", label: "defer", appliesTo: [.pending, .inReview]),
            ListAction(key: "n", label: "next", appliesTo: Set(ListItem.ItemStatus.allCases)),
            ListAction(key: "q", label: "quit", appliesTo: Set(ListItem.ItemStatus.allCases)),
        ]
    }

    /// Filter actions applicable to a given status.
    public func availableActions(for status: ListItem.ItemStatus) -> [ListAction] {
        actions.filter { $0.appliesTo.contains(status) }
    }
}

// MARK: - ListReviewer

/// Synchronous terminal renderer for reviewable lists.
/// Render-only (non-interactive). Interactive input is a future addition.
public enum ListReviewer {

    // MARK: - List Rendering

    /// Render the full list view to a string.
    public static func renderToString(items: [ListItem], config: ListReviewerConfig) -> String {
        var lines: [String] = []

        // Title
        lines.append(styled(config.title, .bold, .purple))
        lines.append(styled(String(repeating: "\u{2500}", count: min(config.title.count + 4, 60)), .dim))

        // Empty state
        if items.isEmpty {
            lines.append("")
            lines.append(styled("  No items.", .dim))
            lines.append("")
            return lines.joined(separator: "\n")
        }

        lines.append("")

        // Items
        for (index, item) in items.enumerated() {
            let number = String(format: "%2d", index + 1)
            let indicator = item.status.indicator
            let statusTag = "(\(item.status.rawValue))"

            let line = styled(
                "[\(number)] \(indicator) \(item.title) \(statusTag)",
                item.status.style
            )
            lines.append(line)

            if let subtitle = item.subtitle {
                lines.append(styled("      \(subtitle)", .dim))
            }
        }

        // Progress
        if config.showProgress {
            let reviewed = items.filter(\.status.isReviewed).count
            lines.append("")
            lines.append(progressBar(done: reviewed, total: items.count, width: 20))
        }

        // Action legend
        if !config.actions.isEmpty {
            lines.append("")
            let legend = config.actions.map { action in
                let key = String(action.key)
                let rest = action.label.dropFirst()
                return "[\(key)]\(rest)"
            }.joined(separator: " ")
            lines.append(styled(legend, .dim))
        }

        return lines.joined(separator: "\n")
    }

    /// Render the full list to stdout.
    public static func render(items: [ListItem], config: ListReviewerConfig) {
        let output = renderToString(items: items, config: config)
        Swift.print(output)
    }

    // MARK: - Detail View

    /// Render a single item's detail view to a string.
    public static func renderDetailToString(item: ListItem, config: ListReviewerConfig) -> String {
        var lines: [String] = []

        // Header
        let indicator = item.status.indicator
        lines.append(styled("\(indicator) \(item.title)", .bold, item.status.style))
        lines.append(styled(String(repeating: "\u{2500}", count: min(item.title.count + 4, 60)), .dim))

        // Status
        lines.append(styled("  Status: \(item.status.rawValue)", item.status.style))

        // Subtitle
        if let subtitle = item.subtitle {
            lines.append(styled("  \(subtitle)", .dim))
        }

        // Metadata
        if !item.metadata.isEmpty {
            lines.append("")
            let sortedKeys = item.metadata.keys.sorted()
            for key in sortedKeys {
                if let value = item.metadata[key] {
                    lines.append(styled("  \(key): ", .bold) + value)
                }
            }
        }

        // Available actions
        let available = config.availableActions(for: item.status)
        if !available.isEmpty {
            lines.append("")
            let legend = available.map { action in
                let key = String(action.key)
                let rest = action.label.dropFirst()
                return "[\(key)]\(rest)"
            }.joined(separator: " ")
            lines.append(styled(legend, .dim))
        }

        return lines.joined(separator: "\n")
    }

    /// Render a single item's detail view to stdout.
    public static func renderDetail(item: ListItem, config: ListReviewerConfig) {
        let output = renderDetailToString(item: item, config: config)
        Swift.print(output)
    }

    // MARK: - Progress Bar

    /// Format a progress bar: "████░░░░ 4 of 8 reviewed"
    /// - Parameters:
    ///   - done: Number of completed items.
    ///   - total: Total number of items.
    ///   - width: Character width of the bar (filled + empty).
    /// - Returns: Styled progress string.
    public static func progressBar(done: Int, total: Int, width: Int = 20) -> String {
        guard total > 0 else {
            let empty = String(repeating: "\u{2591}", count: width)
            return styled(empty, .dim) + " 0 of 0 reviewed"
        }

        let clamped = min(max(done, 0), total)
        let filled = (clamped * width) / total
        let remaining = width - filled

        let filledBar = String(repeating: "\u{2588}", count: filled)
        let emptyBar = String(repeating: "\u{2591}", count: remaining)

        let bar = styled(filledBar, .green) + styled(emptyBar, .dim)
        return "\(bar) \(clamped) of \(total) reviewed"
    }
}
