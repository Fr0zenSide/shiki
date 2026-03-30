import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// MARK: - ANSI Helpers

public enum ANSI {
    public static let reset   = "\u{1B}[0m"
    public static let bold    = "\u{1B}[1m"
    public static let dim     = "\u{1B}[2m"
    public static let green   = "\u{1B}[32m"
    public static let yellow  = "\u{1B}[33m"
    public static let red     = "\u{1B}[31m"
    public static let cyan    = "\u{1B}[36m"
    public static let white   = "\u{1B}[37m"
    public static let magenta = "\u{1B}[35m"
    public static let inverse = "\u{1B}[7m"
}

// MARK: - Terminal Output

public enum TerminalOutput {

    /// Visible character count, stripping ANSI escape sequences.
    public static func visibleLength(_ string: String) -> Int {
        string.replacingOccurrences(
            of: "\u{1B}\\[[0-9;]*m", with: "",
            options: .regularExpression
        ).count
    }

    /// Pad string to width, accounting for ANSI escape sequences.
    public static func pad(_ string: String, _ width: Int) -> String {
        let visible = visibleLength(string)
        if visible >= width { return string }
        return string + String(repeating: " ", count: width - visible)
    }

    /// Get terminal width via ioctl. Returns at least 66, defaults to 80 if not a tty.
    public static func terminalWidth() -> Int {
        #if canImport(Darwin) || canImport(Glibc)
        guard isatty(STDOUT_FILENO) == 1 else { return 80 }
        var ws = winsize()
        if ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &ws) == 0, ws.ws_col > 0 {
            return max(Int(ws.ws_col), 66)
        }
        #endif
        return 80
    }

    /// Get terminal height via ioctl. Defaults to 24.
    public static func terminalHeight() -> Int {
        #if canImport(Darwin) || canImport(Glibc)
        guard isatty(STDOUT_FILENO) == 1 else { return 24 }
        var ws = winsize()
        if ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &ws) == 0, ws.ws_row > 0 {
            return Int(ws.ws_row)
        }
        #endif
        return 24
    }

    /// Move cursor to row, col (1-based).
    public static func moveTo(row: Int, col: Int) {
        print("\u{1B}[\(row);\(col)H", terminator: "")
    }

    /// Clear current line.
    public static func clearLine() {
        print("\u{1B}[2K", terminator: "")
    }

    /// Clear entire screen.
    public static func clearScreen() {
        print("\u{1B}[2J\u{1B}[H", terminator: "")
    }

    /// Hide cursor.
    public static func hideCursor() {
        print("\u{1B}[?25l", terminator: "")
    }

    /// Show cursor.
    public static func showCursor() {
        print("\u{1B}[?25h", terminator: "")
    }

    /// Flush stdout.
    public static func flush() {
        fflush(stdout)
    }

    /// Format number with thousand separators.
    public static func formatNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
