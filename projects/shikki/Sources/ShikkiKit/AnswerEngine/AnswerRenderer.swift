import Foundation

/// Renders ``AnswerResult`` to terminal output.
///
/// Design: fits in one screen, cited sources at the bottom.
/// Supports ANSI styling for readability.
public enum AnswerRenderer {

    /// Render a full answer result to a string.
    ///
    /// - Parameters:
    ///   - result: The answer result to render.
    ///   - query: The original query (shown in the header).
    ///   - plain: If true, strip ANSI codes (for piping/testing).
    /// - Returns: A formatted string ready for terminal output.
    public static func render(
        result: AnswerResult,
        query: String,
        plain: Bool = false
    ) -> String {
        var lines: [String] = []

        // Header
        let title = extractTitle(from: result)
        let separator = String(repeating: "\u{2500}", count: min(title.count + 4, 60))

        if plain {
            lines.append("")
            lines.append("  \(title)")
            lines.append("  \(separator)")
        } else {
            lines.append("")
            lines.append("  \(ANSI.bold)\(title)\(ANSI.reset)")
            lines.append("  \(ANSI.dim)\(separator)\(ANSI.reset)")
        }

        // Answer body
        let bodyLines = result.answer
            .components(separatedBy: "\n")
            .map { "  \($0)" }
        lines.append(contentsOf: bodyLines)

        // Citations
        if !result.citations.isEmpty {
            lines.append("")
            if plain {
                lines.append("  Sources cited:")
            } else {
                lines.append("  \(ANSI.dim)Sources cited:\(ANSI.reset)")
            }
            for citation in result.citations {
                let prefix = citationIcon(for: citation.sourceType)
                let location = citation.location
                if plain {
                    lines.append("  \(prefix) \(location)")
                } else {
                    lines.append("  \(ANSI.cyan)\(prefix)\(ANSI.reset) \(location)")
                }
            }
        }

        // Footer: confidence + latency
        let confidencePercent = Int(result.confidence * 100)
        let latencyMs = Int(result.latency * 1000)
        let footer = "confidence: \(confidencePercent)% | latency: \(latencyMs)ms | \(result.citations.count) source(s)"
        if plain {
            lines.append("")
            lines.append("  \(footer)")
        } else {
            lines.append("")
            lines.append("  \(ANSI.dim)\(footer)\(ANSI.reset)")
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }

    // MARK: - Private

    /// Extract a title from the answer (first line or query-based).
    static func extractTitle(from result: AnswerResult) -> String {
        // Look for a structured summary line
        let firstLine = result.answer.components(separatedBy: "\n").first ?? ""
        if firstLine.contains(":") {
            // Use the first part as title
            let parts = firstLine.split(separator: ":", maxSplits: 1)
            if let title = parts.first {
                return String(title).trimmingCharacters(in: .whitespaces)
            }
        }
        // Fallback: truncate first line
        if firstLine.count > 60 {
            return String(firstLine.prefix(57)) + "..."
        }
        return firstLine
    }

    /// Icon prefix for citation source type.
    static func citationIcon(for sourceType: CitationSourceType) -> String {
        switch sourceType {
        case .sourceCode: return ">"
        case .specDocument: return "#"
        case .architectureCache: return "@"
        case .database: return "~"
        }
    }
}
