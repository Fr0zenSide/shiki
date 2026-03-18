import Foundation

// MARK: - PaletteRenderer

/// Renders the command palette TUI overlay.
/// Stateless renderer — all state is passed in as parameters.
public enum PaletteRenderer {

    /// Render the full palette screen.
    ///
    /// - Parameters:
    ///   - query: Current search text
    ///   - results: Filtered/scored results from PaletteEngine
    ///   - selectedIndex: Currently highlighted item (flat index across all groups)
    ///   - scope: Active scope filter (e.g. "session"), or nil for all
    ///   - width: Terminal width
    ///   - height: Terminal height
    public static func render(
        query: String,
        results: [PaletteResult],
        selectedIndex: Int,
        scope: String?,
        width: Int = TerminalOutput.terminalWidth(),
        height: Int = TerminalOutput.terminalHeight()
    ) {
        TerminalOutput.clearScreen()

        let innerWidth = width - 4  // 2 border + 2 padding

        // Top border
        printBoxTop(width: width)

        // Search bar
        let scopeLabel = scope.map { " [scope: \($0)]" } ?? " [scope: all]"
        let searchPrefix = "\(ANSI.cyan)>\(ANSI.reset) "
        let queryDisplay = query.isEmpty ? "\(ANSI.dim)type to search...\(ANSI.reset)" : query
        let searchLine = "\(searchPrefix)\(queryDisplay)"
        let searchPadded = TerminalOutput.pad(searchLine, innerWidth - TerminalOutput.visibleLength(scopeLabel))
        printBoxLine("\(searchPadded)\(ANSI.dim)\(scopeLabel)\(ANSI.reset)", width: width)

        // Separator
        printBoxLine("", width: width)

        if results.isEmpty {
            // Empty state
            printBoxLine(
                "\(ANSI.dim)No results for \"\(TerminalSnapshot.stripANSI(query))\"\(ANSI.reset)",
                width: width
            )
            // Fill remaining space
            let usedLines = 5  // top + search + separator + no-results + footer
            let remaining = max(0, height - usedLines - 2)
            for _ in 0..<remaining {
                printBoxLine("", width: width)
            }
        } else {
            // Group results by category (preserve encounter order)
            let grouped = groupByCategory(results)

            var flatIndex = 0
            var linesUsed = 3  // top + search + separator
            let maxContentLines = height - 5  // reserve for footer + bottom border

            for (category, items) in grouped {
                guard linesUsed < maxContentLines else { break }

                // Category header
                let header = "\(ANSI.bold)\(ANSI.dim)\(category.uppercased())\(ANSI.reset)"
                printBoxLine(header, width: width)
                linesUsed += 1

                // Items
                for item in items {
                    guard linesUsed < maxContentLines else { break }

                    let isSelected = flatIndex == selectedIndex
                    let line = formatResultLine(item, selected: isSelected, maxWidth: innerWidth)
                    printBoxLine(line, width: width)

                    flatIndex += 1
                    linesUsed += 1
                }

                // Blank line between groups
                if linesUsed < maxContentLines {
                    printBoxLine("", width: width)
                    linesUsed += 1
                }
            }

            // Fill remaining space
            let remaining = max(0, maxContentLines - linesUsed)
            for _ in 0..<remaining {
                printBoxLine("", width: width)
            }
        }

        // Footer
        let footer = "\(ANSI.dim)\u{2191}/\u{2193} navigate \u{00B7} Enter select \u{00B7} Tab cycle \u{00B7} Esc close\(ANSI.reset)"
        printBoxLine(footer, width: width)

        // Bottom border
        printBoxBottom(width: width)

        TerminalOutput.flush()
    }

    // MARK: - Box Drawing

    private static func printBoxTop(width: Int) {
        let title = " SHIKI "
        let remaining = width - 2 - title.count
        let line = "\u{250C}\u{2500}\(ANSI.bold)\(title)\(ANSI.reset)\(String(repeating: "\u{2500}", count: max(0, remaining)))\u{2510}"
        print(line)
    }

    private static func printBoxBottom(width: Int) {
        let line = "\u{2514}\(String(repeating: "\u{2500}", count: max(0, width - 2)))\u{2518}"
        print(line)
    }

    private static func printBoxLine(_ content: String, width: Int) {
        let innerWidth = width - 4
        let padded = TerminalOutput.pad(content, innerWidth)
        print("\u{2502} \(padded) \u{2502}")
    }

    // MARK: - Result Formatting

    private static func formatResultLine(
        _ result: PaletteResult,
        selected: Bool,
        maxWidth: Int
    ) -> String {
        let icon = result.icon ?? "-"
        let subtitle = result.subtitle.map { "  \(ANSI.dim)\($0)\(ANSI.reset)" } ?? ""
        let titlePart = "\(icon) \(result.title)"

        if selected {
            return "\(ANSI.inverse)\(TerminalOutput.pad("\(titlePart)\(subtitle)", maxWidth))\(ANSI.reset)"
        }

        return "\(titlePart)\(subtitle)"
    }

    // MARK: - Grouping

    /// Group results by category, preserving the order categories first appear.
    private static func groupByCategory(_ results: [PaletteResult]) -> [(String, [PaletteResult])] {
        var seen: [String] = []
        var groups: [String: [PaletteResult]] = [:]

        for result in results {
            if groups[result.category] == nil {
                seen.append(result.category)
                groups[result.category] = []
            }
            groups[result.category]?.append(result)
        }

        return seen.compactMap { cat in
            guard let items = groups[cat] else { return nil }
            return (cat, items)
        }
    }
}
