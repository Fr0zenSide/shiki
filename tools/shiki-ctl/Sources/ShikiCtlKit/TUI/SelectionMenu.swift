import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Arrow-key selection menu for terminal UIs.
/// Falls back to numbered list + readLine when not a tty.
public struct SelectionMenu<T: CustomStringConvertible & Sendable>: Sendable {
    public let items: [T]
    public let title: String
    public let formatter: @Sendable (T, Bool) -> String

    public init(
        items: [T],
        title: String = "",
        formatter: @escaping @Sendable (T, Bool) -> String = { item, selected in
            let prefix = selected ? "\(ANSI.cyan)> \(ANSI.bold)" : "  "
            let suffix = selected ? ANSI.reset : ""
            return "\(prefix)\(item)\(suffix)"
        }
    ) {
        self.items = items
        self.title = title
        self.formatter = formatter
    }

    /// Show menu and return selected index, or nil if user pressed Escape.
    public func run() -> Int? {
        guard isatty(STDIN_FILENO) == 1 else {
            return runFallback()
        }
        return runInteractive()
    }

    // MARK: - Interactive Mode

    private func runInteractive() -> Int? {
        let raw = RawMode()
        defer {
            raw.restore()
            TerminalOutput.showCursor()
        }

        TerminalOutput.hideCursor()
        var selected = 0

        // Initial render
        renderMenu(selected: selected)

        while true {
            let key = TerminalInput.readKey()
            switch key {
            case .up:
                if selected > 0 { selected -= 1 }
            case .down:
                if selected < items.count - 1 { selected += 1 }
            case .enter:
                // Move cursor below menu before returning
                print()
                return selected
            case .escape, .char("q"):
                print()
                return nil
            default:
                continue
            }
            // Redraw: move cursor up and overwrite
            rerenderMenu(selected: selected)
        }
    }

    private func renderMenu(selected: Int) {
        if !title.isEmpty {
            print(title)
        }
        for (i, item) in items.enumerated() {
            print(formatter(item, i == selected))
        }
        TerminalOutput.flush()
    }

    private func rerenderMenu(selected: Int) {
        // Move cursor up by item count
        let lines = items.count
        print("\u{1B}[\(lines)A", terminator: "")
        for (i, item) in items.enumerated() {
            TerminalOutput.clearLine()
            print(formatter(item, i == selected))
        }
        TerminalOutput.flush()
    }

    // MARK: - Fallback (piped mode)

    private func runFallback() -> Int? {
        if !title.isEmpty {
            print(title)
        }
        for (i, item) in items.enumerated() {
            print("  [\(i + 1)] \(item)")
        }
        print("Enter number (or 'q' to quit): ", terminator: "")
        guard let input = readLine()?.trimmingCharacters(in: .whitespaces) else {
            return nil
        }
        if input.lowercased() == "q" { return nil }
        if let num = Int(input), num >= 1, num <= items.count {
            return num - 1
        }
        return nil
    }
}
