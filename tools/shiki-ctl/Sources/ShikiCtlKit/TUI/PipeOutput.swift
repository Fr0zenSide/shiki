import Foundation

/// Non-interactive output modes for pipe/scripting use.
public enum PipeOutput {

    /// JSON output with items, progress, and urgency.
    public static func json(items: [ListItem], config: ListReviewerConfig) -> String {
        var result: [String: Any] = [:]
        result["title"] = config.title

        let itemDicts: [[String: Any]] = items.map { item in
            let urgency = UrgencyCalculator.urgency(for: item, withinScope: items)
            var dict: [String: Any] = [
                "id": item.id,
                "title": item.title,
                "status": item.status.rawValue,
                "urgency": urgency.rawValue,
            ]
            if let subtitle = item.subtitle {
                dict["subtitle"] = subtitle
            }
            if let company = item.metadata["company"] {
                dict["company"] = company
            }
            return dict
        }
        result["items"] = itemDicts

        let reviewed = items.filter(\.status.isReviewed).count
        result["progress"] = [
            "reviewed": reviewed,
            "total": items.count,
        ]

        // Use JSONSerialization for reliable output
        guard let data = try? JSONSerialization.data(
            withJSONObject: result,
            options: [.prettyPrinted, .sortedKeys]
        ) else {
            return "{}"
        }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// Count mode: outputs a single integer.
    public static func count(items: [ListItem]) -> String {
        "\(items.count)\n"
    }

    /// Plain text mode: same as renderToString but with ANSI codes stripped.
    public static func plain(items: [ListItem], config: ListReviewerConfig) -> String {
        let rendered = ListReviewer.renderToString(items: items, config: config)
        return stripANSI(rendered)
    }
}
