import Foundation

// MARK: - EditorRenderer

/// Renders the editor mode TUI overlay.
/// Stateless renderer -- all state is passed in as parameters.
public enum EditorRenderer {

    /// Render the full editor screen to a string (for snapshot testing).
    public static func render(
        engine: EditorEngine,
        autocompleteItems: [(label: String, description: String)] = [],
        selectedAutocomplete: Int = 0,
        ghostText: String = "",
        width: Int = TerminalOutput.terminalWidth(),
        height: Int = TerminalOutput.terminalHeight()
    ) -> String {
        var lines: [String] = []
        let innerWidth = width - 4

        // Top border with file name
        lines.append(boxTop(filePath: engine.filePath, isDirty: engine.buffer.isDirty, width: width))

        // Content area
        let footerHeight = 2 // footer + bottom border
        let autocompleteHeight = autocompleteItems.isEmpty ? 0 : min(autocompleteItems.count + 1, 6)
        let contentHeight = max(1, height - footerHeight - autocompleteHeight - 2) // -2 for top border + separator

        let visibleRange = engine.visibleRange(viewportHeight: contentHeight)

        for row in visibleRange {
            let line = engine.buffer.lines[row]
            let isCursorLine = row == engine.buffer.cursorRow

            let lineNum = "\(ANSI.dim)\(String(format: "%3d", row + 1))\(ANSI.reset) "
            let lineNumWidth = 4 // "NNN "
            let contentWidth = innerWidth - lineNumWidth

            if isCursorLine {
                // Render cursor line with highlight
                let displayLine = renderCursorLine(
                    line,
                    cursorCol: engine.buffer.cursorCol,
                    ghostText: ghostText,
                    maxWidth: contentWidth
                )
                lines.append(boxLine("\(lineNum)\(displayLine)", width: width))
            } else {
                let truncated = truncate(line, maxWidth: contentWidth)
                lines.append(boxLine("\(lineNum)\(truncated)", width: width))
            }
        }

        // Pad remaining content area
        let renderedLines = visibleRange.count
        let padding = max(0, contentHeight - renderedLines)
        for _ in 0..<padding {
            lines.append(boxLine("\(ANSI.dim)  ~\(ANSI.reset)", width: width))
        }

        // Autocomplete popup (if active)
        if !autocompleteItems.isEmpty {
            let header = engine.activeTrigger.map { triggerLabel($0) } ?? "AUTOCOMPLETE"
            lines.append(boxLine("  \(ANSI.bold)\(ANSI.dim)\(header)\(ANSI.reset)", width: width))
            let maxShow = min(autocompleteItems.count, 5)
            for (i, item) in autocompleteItems.prefix(maxShow).enumerated() {
                let isSelected = i == selectedAutocomplete
                let prefix = isSelected ? "\(ANSI.inverse)" : "  "
                let suffix = isSelected ? "\(ANSI.reset)" : ""
                let itemLine = "\(prefix)\(item.label)  \(ANSI.dim)\(item.description)\(ANSI.reset)\(suffix)"
                lines.append(boxLine(itemLine, width: width))
            }
        }

        // Footer
        let dirtyIndicator = engine.buffer.isDirty ? " [modified]" : ""
        let positionInfo = "Ln \(engine.buffer.cursorRow + 1), Col \(engine.buffer.cursorCol + 1)"
        let footerLeft = "\(ANSI.dim)Ctrl-S save \u{00B7} Ctrl-P search \u{00B7} @ autocomplete \u{00B7} Esc exit\(ANSI.reset)"
        let footerRight = "\(ANSI.dim)\(positionInfo)\(dirtyIndicator)\(ANSI.reset)"
        let footerSpacing = max(1, innerWidth - TerminalOutput.visibleLength(footerLeft) - TerminalOutput.visibleLength(footerRight))
        lines.append(boxLine("\(footerLeft)\(String(repeating: " ", count: footerSpacing))\(footerRight)", width: width))

        // Bottom border
        lines.append(boxBottom(width: width))

        return lines.joined(separator: "\n")
    }

    // MARK: - Cursor Line Rendering

    private static func renderCursorLine(
        _ line: String,
        cursorCol: Int,
        ghostText: String,
        maxWidth: Int
    ) -> String {
        let clampedCol = min(cursorCol, line.count)
        let before = String(line.prefix(clampedCol))
        let after = String(line.suffix(from: line.index(line.startIndex, offsetBy: clampedCol)))

        var result = before

        if after.isEmpty {
            // Cursor at end of line
            result += "\(ANSI.inverse) \(ANSI.reset)"
            if !ghostText.isEmpty {
                result += "\(ANSI.dim)\(ghostText)\(ANSI.reset)"
            }
        } else {
            // Cursor in middle of text
            let cursorChar = after.first!
            let rest = String(after.dropFirst())
            result += "\(ANSI.inverse)\(cursorChar)\(ANSI.reset)\(rest)"
        }

        return truncate(result, maxWidth: maxWidth)
    }

    // MARK: - Trigger Labels

    private static func triggerLabel(_ trigger: EditorTrigger) -> String {
        switch trigger {
        case .atMention: return "AUTOCOMPLETE"
        case .inlineSearch(let prefix, _):
            if prefix.hasPrefix("d:") { return "DECISION SEARCH" }
            if prefix.hasPrefix("f:") { return "FEATURE SEARCH" }
            if prefix.hasPrefix("m:") { return "MEMORY SEARCH" }
            return "SEARCH"
        case .scopeRef: return "SCOPE"
        }
    }

    // MARK: - Box Drawing

    private static func boxTop(filePath: String?, isDirty: Bool, width: Int) -> String {
        let title = " SHIKKI EDITOR "
        let fileLabel = filePath.map { " \(($0 as NSString).lastPathComponent)\(isDirty ? " *" : "") " } ?? ""
        let titlePart = "\u{250C}\u{2500}\(ANSI.bold)\(title)\(ANSI.reset)"
        let filePart = fileLabel.isEmpty ? "" : "\(ANSI.dim)\(fileLabel)\(ANSI.reset)"
        let usedWidth = 2 + title.count + (fileLabel.isEmpty ? 0 : fileLabel.count)
        let remaining = max(0, width - usedWidth)
        return "\(titlePart)\(String(repeating: "\u{2500}", count: max(0, remaining - (fileLabel.isEmpty ? 0 : fileLabel.count))))\(filePart)\u{2510}"
    }

    private static func boxBottom(width: Int) -> String {
        "\u{2514}\(String(repeating: "\u{2500}", count: max(0, width - 2)))\u{2518}"
    }

    private static func boxLine(_ content: String, width: Int) -> String {
        let innerWidth = width - 4
        let padded = TerminalOutput.pad(content, innerWidth)
        return "\u{2502} \(padded) \u{2502}"
    }

    private static func truncate(_ text: String, maxWidth: Int) -> String {
        let visible = TerminalOutput.visibleLength(text)
        guard visible > maxWidth, maxWidth > 3 else { return text }
        // Simple truncation -- strip ANSI for length check but keep for display
        return String(text.prefix(maxWidth - 3)) + "..."
    }
}
