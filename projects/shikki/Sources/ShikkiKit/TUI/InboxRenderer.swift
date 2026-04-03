import Foundation

/// Renders inbox items grouped by urgency zone with themed formatting.
/// Uses Dracula 24-bit palette. When Wave 5 migrates to DSKintsugiTUI,
/// this renderer will switch imports — for now, standalone ANSI.
public enum InboxRenderer {

    // MARK: - Dracula 24-bit Palette

    private static let purple = "\u{1B}[38;2;189;147;249m"
    private static let green  = "\u{1B}[38;2;80;250;123m"
    private static let yellow = "\u{1B}[38;2;241;250;140m"
    private static let red    = "\u{1B}[38;2;255;85;85m"
    private static let cyan   = "\u{1B}[38;2;139;233;253m"
    private static let orange = "\u{1B}[38;2;255;184;108m"
    private static let fg     = "\u{1B}[38;2;248;248;242m"
    private static let dim    = "\u{1B}[38;2;98;114;164m"
    private static let reset  = "\u{1B}[0m"
    private static let bold   = "\u{1B}[1m"

    // MARK: - Box Drawing Characters

    private struct BoxChars {
        let topLeft: String
        let topRight: String
        let bottomLeft: String
        let bottomRight: String
        let horizontal: String
        let vertical: String

        static let unicode = BoxChars(
            topLeft: "╭", topRight: "╮",
            bottomLeft: "╰", bottomRight: "╯",
            horizontal: "─", vertical: "│"
        )

        static let ascii = BoxChars(
            topLeft: "+", topRight: "+",
            bottomLeft: "+", bottomRight: "+",
            horizontal: "-", vertical: "|"
        )
    }

    // MARK: - Public API

    /// Render inbox items as a formatted string with urgency zones.
    /// - Parameters:
    ///   - items: The inbox items to render.
    ///   - branch: Current git branch name for the header.
    ///   - plain: When true, strips ANSI codes and uses ASCII box chars.
    /// - Returns: The complete rendered string.
    public static func render(
        items: [InboxItem],
        branch: String = "develop",
        plain: Bool = false
    ) -> String {
        var lines: [String] = []
        let box = plain ? BoxChars.ascii : BoxChars.unicode
        let width = 64

        if items.isEmpty {
            lines.append(contentsOf: renderEmptyBox(box: box, width: width, plain: plain))
            return lines.joined(separator: "\n")
        }

        // Header box
        lines.append(contentsOf: renderHeader(
            items: items,
            branch: branch,
            box: box,
            width: width,
            plain: plain
        ))
        lines.append("")

        // Group into urgency zones
        let hot = items.filter { $0.urgencyScore >= 70 }
        let active = items.filter { $0.urgencyScore >= 40 && $0.urgencyScore < 70 }
        let queued = items.filter { $0.urgencyScore < 40 }

        if !hot.isEmpty {
            lines.append(renderZoneHeader("Hot (70+)", emoji: "🔥", color: red, plain: plain))
            for item in hot {
                lines.append(contentsOf: renderItem(item, plain: plain))
            }
            lines.append("")
        }

        if !active.isEmpty {
            lines.append(renderZoneHeader("Active (40-69)", emoji: "⚡", color: yellow, plain: plain))
            for item in active {
                lines.append(contentsOf: renderItem(item, plain: plain))
            }
            lines.append("")
        }

        if !queued.isEmpty {
            lines.append(renderZoneHeader("Queued (<40)", emoji: "📋", color: green, plain: plain))
            for item in queued {
                lines.append(contentsOf: renderItem(item, plain: plain))
            }
            lines.append("")
        }

        // Footer
        lines.append(contentsOf: renderFooter(box: box, width: width, plain: plain))

        return lines.joined(separator: "\n")
    }

    // MARK: - Empty Box

    private static func renderEmptyBox(box: BoxChars, width: Int, plain: Bool) -> [String] {
        let innerWidth = width - 2
        let topBorder = "\(box.topLeft)\(String(repeating: box.horizontal, count: innerWidth))\(box.topRight)"
        let bottomBorder = "\(box.bottomLeft)\(String(repeating: box.horizontal, count: innerWidth))\(box.bottomRight)"
        let message = "Inbox is empty"
        let padding = innerWidth - message.count
        let leftPad = padding / 2
        let rightPad = padding - leftPad
        let content = "\(box.vertical)\(String(repeating: " ", count: leftPad))\(message)\(String(repeating: " ", count: rightPad))\(box.vertical)"

        if plain {
            return [topBorder, content, bottomBorder]
        }
        return [
            "\(dim)\(topBorder)\(reset)",
            "\(dim)\(box.vertical)\(reset)\(String(repeating: " ", count: leftPad))\(fg)\(message)\(reset)\(String(repeating: " ", count: rightPad))\(dim)\(box.vertical)\(reset)",
            "\(dim)\(bottomBorder)\(reset)",
        ]
    }

    // MARK: - Header Box

    private static func renderHeader(
        items: [InboxItem],
        branch: String,
        box: BoxChars,
        width: Int,
        plain: Bool
    ) -> [String] {
        let innerWidth = width - 2

        // Count per type
        let spCount = items.filter { $0.type == .spec }.count
        let prCount = items.filter { $0.type == .pr }.count
        let dcCount = items.filter { $0.type == .decision }.count
        let tkCount = items.filter { $0.type == .task }.count
        let gtCount = items.filter { $0.type == .gate }.count

        let title = "Inbox"
        let topBar = "\(box.topLeft)\(box.horizontal) \(title) \(String(repeating: box.horizontal, count: innerWidth - title.count - 3))\(box.topRight)"

        let countLabel = "\(items.count) items"
        let typeCounts = "SP:\(spCount)  PR:\(prCount)  DC:\(dcCount)  TK:\(tkCount)  GT:\(gtCount)"
        // Build the content line: "  {count} │ {types}  │  {branch}  "
        let separator = box.vertical
        let contentText = "  \(countLabel) \(separator) \(typeCounts)  \(separator)  \(branch)"
        let contentVisible = contentText.count
        let rightPad = max(0, innerWidth - contentVisible)
        let paddedContent = "\(contentText)\(String(repeating: " ", count: rightPad))"

        let contentLine = "\(box.vertical)\(paddedContent)\(box.vertical)"
        let bottomBar = "\(box.bottomLeft)\(String(repeating: box.horizontal, count: innerWidth))\(box.bottomRight)"

        if plain {
            return [topBar, contentLine, bottomBar]
        }
        return [
            "\(dim)\(topBar)\(reset)",
            "\(dim)\(box.vertical)\(reset)  \(bold)\(fg)\(countLabel)\(reset) \(dim)\(separator)\(reset) \(fg)\(typeCounts)\(reset)  \(dim)\(separator)\(reset)  \(cyan)\(branch)\(reset)\(String(repeating: " ", count: rightPad))\(dim)\(box.vertical)\(reset)",
            "\(dim)\(bottomBar)\(reset)",
        ]
    }

    // MARK: - Zone Header

    private static func renderZoneHeader(
        _ label: String,
        emoji: String,
        color: String,
        plain: Bool
    ) -> String {
        if plain {
            return " \(emoji) \(label)"
        }
        return " \(emoji) \(color)\(bold)\(label)\(reset)"
    }

    // MARK: - Item Row

    private static func renderItem(_ item: InboxItem, plain: Bool) -> [String] {
        var lines: [String] = []

        let badge = typeBadge(item.type, plain: plain)
        let bar = urgencyBar(item.urgencyScore, width: 8)
        let scoreStr = String(format: "%3d", item.urgencyScore)
        let ageStr = formatAge(item.age)
        let slugTag = item.companySlug.map { "[\($0)]" } ?? ""

        if plain {
            let line = " \(badge)  \(bar) \(scoreStr)  \(item.title)  \(slugTag)  (\(ageStr))"
            lines.append(line)
        } else {
            let typeColor = colorForType(item.type)
            let scoreColor = colorForScore(item.urgencyScore)
            let line = " \(typeColor)\(badge)\(reset)  \(scoreColor)\(bar)\(reset) \(scoreColor)\(scoreStr)\(reset)  \(bold)\(fg)\(item.title)\(reset)  \(cyan)\(slugTag)\(reset)  \(dim)(\(ageStr))\(reset)"
            lines.append(line)
        }

        if let subtitle = item.subtitle {
            if plain {
                lines.append("         \(subtitle)")
            } else {
                lines.append("         \(dim)\(subtitle)\(reset)")
            }
        }

        return lines
    }

    // MARK: - Footer

    private static func renderFooter(box: BoxChars, width: Int, plain: Bool) -> [String] {
        let separator = String(repeating: box.horizontal, count: width)
        let hint = " Filter: --prs --specs --tasks \(box.vertical) Sort: --sort urgency|age|type"

        if plain {
            return [separator, hint]
        }
        return [
            "\(dim)\(separator)\(reset)",
            "\(dim)\(hint)\(reset)",
        ]
    }

    // MARK: - Urgency Bar

    /// Generate an urgency bar of the given width.
    /// Score 0-100 maps to filled (█) and empty (░) characters.
    static func urgencyBar(_ score: Int, width: Int) -> String {
        let clamped = max(0, min(score, 100))
        let filled = clamped * width / 100
        let empty = width - filled
        return String(repeating: "█", count: filled) + String(repeating: "░", count: empty)
    }

    // MARK: - Type Badge

    private static func typeBadge(_ type: InboxItem.ItemType, plain: Bool) -> String {
        switch type {
        case .spec:     return "SP"
        case .pr:       return "PR"
        case .decision: return "DC"
        case .task:     return "TK"
        case .gate:     return "GT"
        }
    }

    // MARK: - Color Helpers

    private static func colorForType(_ type: InboxItem.ItemType) -> String {
        switch type {
        case .spec:     return purple
        case .pr:       return green
        case .decision: return orange
        case .task:     return cyan
        case .gate:     return red
        }
    }

    private static func colorForScore(_ score: Int) -> String {
        switch score {
        case 70...: return red
        case 40..<70: return yellow
        default: return green
        }
    }

    // MARK: - Age Formatting

    static func formatAge(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds / 3600)
        if hours < 1 { return "<1h" }
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        return "\(days)d"
    }
}
