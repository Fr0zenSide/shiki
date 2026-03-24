import Foundation

// MARK: - Decide Progress Persistence

/// Tracks which decisions have been reviewed across sessions.
public struct DecideProgress: Codable, Sendable {
    public var reviewed: [String: ReviewedDecision]
    public var lastSessionDate: String

    public struct ReviewedDecision: Codable, Sendable {
        public let decisionId: String
        public let action: String  // "answered", "deferred", "dismissed"
        public let answer: String?
        public let timestamp: String
    }

    public init(reviewed: [String: ReviewedDecision] = [:], lastSessionDate: String = "") {
        self.reviewed = reviewed
        self.lastSessionDate = lastSessionDate
    }
}

// MARK: - DecideListReviewer

/// Adapts Decision models to ListReviewer items for the `shikki decide` command.
/// Handles conversion, progress persistence, and decide-specific configuration.
public enum DecideListReviewer {

    /// Configuration for the decide list.
    public static let decideActions: [ListReviewerConfig.ListAction] = [
        .init(key: "a", label: "answer", appliesTo: [.pending, .inReview], batchable: true),
        .init(key: "d", label: "defer", appliesTo: [.pending, .inReview], batchable: true),
        .init(key: "k", label: "dismiss", appliesTo: [.pending, .inReview], batchable: true),
        .init(key: "n", label: "next", appliesTo: Set(ListItem.ItemStatus.allCases), batchable: false),
        .init(key: "q", label: "quit", appliesTo: Set(ListItem.ItemStatus.allCases), batchable: false),
    ]

    /// Build a ListReviewerConfig for the decide command.
    public static func makeConfig(companyScope: String? = nil) -> ListReviewerConfig {
        let title: String
        if let scope = companyScope {
            title = "Pending Decisions [\(scope)]"
        } else {
            title = "Pending Decisions"
        }
        return ListReviewerConfig(
            title: title,
            listId: "decide",
            showProgress: true,
            actions: decideActions
        )
    }

    /// Convert a Decision to a ListItem.
    public static func toListItem(_ decision: Decision, progress: DecideProgress? = nil) -> ListItem {
        let tierLabel = "T\(decision.tier)"
        let company = decision.companySlug ?? decision.companyName ?? "unknown"

        var metadata: [String: String] = [
            "company": company,
            "tier": tierLabel,
        ]
        if let context = decision.context {
            metadata["context"] = context
        }
        if let taskId = decision.taskId {
            metadata["task"] = taskId
        }
        if let options = decision.options {
            let optStr = options.sorted(by: { $0.key < $1.key })
                .map { "(\($0.key)) \($0.value)" }
                .joined(separator: ", ")
            metadata["options"] = optStr
        }

        // Check progress for status
        let status: ListItem.ItemStatus
        if let reviewed = progress?.reviewed[decision.id] {
            switch reviewed.action {
            case "answered": status = .validated
            case "deferred": status = .deferred
            case "dismissed": status = .killed
            default: status = .pending
            }
        } else {
            status = .pending
        }

        return ListItem(
            id: decision.id,
            title: decision.question,
            subtitle: "\(tierLabel) \u{2022} \(company)",
            status: status,
            metadata: metadata
        )
    }

    /// Convert all decisions to ListItems, applying progress and optional company filter.
    public static func toListItems(
        _ decisions: [Decision],
        progress: DecideProgress? = nil,
        companyScope: String? = nil
    ) -> [ListItem] {
        var filtered = decisions
        if let scope = companyScope {
            filtered = decisions.filter {
                ($0.companySlug ?? "").lowercased() == scope.lowercased()
                    || ($0.companyName ?? "").lowercased() == scope.lowercased()
            }
        }

        // Sort: T1 first, then T2, then T3 within each company group
        let sorted = filtered.sorted { a, b in
            if a.tier != b.tier { return a.tier < b.tier }
            let slugA = a.companySlug ?? ""
            let slugB = b.companySlug ?? ""
            return slugA < slugB
        }

        return sorted.map { toListItem($0, progress: progress) }
    }

    // MARK: - Progress Persistence

    /// Default progress file path.
    public static func progressPath(baseDir: String = "~/.config/shiki") -> String {
        let expanded = NSString(string: baseDir).expandingTildeInPath
        return "\(expanded)/decide-progress.json"
    }

    /// Load progress from disk.
    public static func loadProgress(baseDir: String = "~/.config/shiki") -> DecideProgress? {
        let path = progressPath(baseDir: baseDir)
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return try? JSONDecoder().decode(DecideProgress.self, from: data)
    }

    /// Save progress to disk.
    public static func saveProgress(_ progress: DecideProgress, baseDir: String = "~/.config/shiki") throws {
        let path = progressPath(baseDir: baseDir)
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(progress)
        try data.write(to: URL(fileURLWithPath: path))
    }

    /// Record a decision action in progress.
    public static func recordAction(
        progress: inout DecideProgress,
        decisionId: String,
        action: String,
        answer: String? = nil
    ) {
        let formatter = ISO8601DateFormatter()
        progress.reviewed[decisionId] = DecideProgress.ReviewedDecision(
            decisionId: decisionId,
            action: action,
            answer: answer,
            timestamp: formatter.string(from: Date())
        )
        progress.lastSessionDate = formatter.string(from: Date())
    }
}
