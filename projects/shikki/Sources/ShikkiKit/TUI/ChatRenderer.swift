import Foundation

// MARK: - ChatRenderer

/// Renders the chat TUI overlay.
/// Stateless renderer — all state is passed in as parameters.
public enum ChatRenderer {

    /// Render the full chat screen to a string.
    public static func render(
        messages: [ChatMessage],
        inputText: String,
        autocompleteResults: [(label: String, description: String)],
        selectedAutocomplete: Int,
        showAutocomplete: Bool,
        width: Int = TerminalOutput.terminalWidth(),
        height: Int = TerminalOutput.terminalHeight()
    ) -> String {
        var lines: [String] = []
        let innerWidth = width - 4

        // Top border
        lines.append(boxTop(width: width))

        // Messages area (fills available space)
        let footerLines = showAutocomplete ? min(autocompleteResults.count + 2, 8) : 3
        let messageAreaHeight = max(1, height - footerLines - 3)
        let visibleMessages = Array(messages.suffix(messageAreaHeight))

        // Pad empty space if fewer messages than available height
        let emptyLines = max(0, messageAreaHeight - visibleMessages.count)
        for _ in 0..<emptyLines {
            lines.append(boxLine("", width: width))
        }

        // Render messages
        for msg in visibleMessages {
            let formatted = formatMessage(msg, maxWidth: innerWidth)
            lines.append(boxLine(formatted, width: width))
        }

        // Separator
        lines.append(boxLine(String(repeating: "\u{2500}", count: innerWidth), width: width))

        // Autocomplete popup (if active)
        if showAutocomplete && !autocompleteResults.isEmpty {
            let maxShow = min(autocompleteResults.count, 5)
            for (i, item) in autocompleteResults.prefix(maxShow).enumerated() {
                let isSelected = i == selectedAutocomplete
                let prefix = isSelected ? "\(ANSI.inverse)" : ""
                let suffix = isSelected ? "\(ANSI.reset)" : ""
                let line = "\(prefix)\(item.label)  \(ANSI.dim)\(item.description)\(ANSI.reset)\(suffix)"
                lines.append(boxLine(line, width: width))
            }
            lines.append(boxLine("", width: width))
        }

        // Input line
        let inputPrefix = "\(ANSI.cyan)>\(ANSI.reset) "
        let inputDisplay = inputText.isEmpty
            ? "\(ANSI.dim)@target message...\(ANSI.reset)"
            : inputText
        lines.append(boxLine("\(inputPrefix)\(inputDisplay)", width: width))

        // Footer
        let footer = "\(ANSI.dim)Enter send \u{00B7} Tab autocomplete @target \u{00B7} Esc close\(ANSI.reset)"
        lines.append(boxLine(footer, width: width))

        // Bottom border
        lines.append(boxBottom(width: width))

        return lines.joined(separator: "\n")
    }

    // MARK: - Message Formatting

    static func formatMessage(_ msg: ChatMessage, maxWidth: Int) -> String {
        if msg.isOutgoing {
            let label = targetPrefix(msg.target)
            return "\(ANSI.bold)\(label)\(ANSI.reset) \(truncate(msg.content, maxWidth: maxWidth - 20))"
        } else {
            let indent = "  \u{250C}\u{2500} "
            return "\(indent)\(ANSI.dim)\(msg.senderLabel):\(ANSI.reset) \(truncate(msg.content, maxWidth: maxWidth - 20))"
        }
    }

    private static func targetPrefix(_ target: ChatTarget) -> String {
        switch target {
        case .orchestrator: return "@orchestrator"
        case .agent(let id): return "@\(id)"
        case .persona(let p): return "@\(p.rawValue)"
        case .broadcast: return "@all"
        }
    }

    private static func truncate(_ text: String, maxWidth: Int) -> String {
        guard text.count > maxWidth, maxWidth > 3 else { return text }
        return String(text.prefix(maxWidth - 3)) + "..."
    }

    // MARK: - Box Drawing

    private static func boxTop(width: Int) -> String {
        let title = " SHIKKI CHAT "
        let remaining = width - 2 - title.count
        return "\u{250C}\u{2500}\(ANSI.bold)\(title)\(ANSI.reset)\(String(repeating: "\u{2500}", count: max(0, remaining)))\u{2510}"
    }

    private static func boxBottom(width: Int) -> String {
        "\u{2514}\(String(repeating: "\u{2500}", count: max(0, width - 2)))\u{2518}"
    }

    static func boxLine(_ content: String, width: Int) -> String {
        let innerWidth = width - 4
        let padded = TerminalOutput.pad(content, innerWidth)
        return "\u{2502} \(padded) \u{2502}"
    }
}
