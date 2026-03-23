import Foundation

/// Composable ANSI style builder.
/// Works with the existing `ANSI` enum for raw codes, adding a higher-level API
/// for combining styles: `styled("text", .bold, .green)`.
public struct ANSIStyle: Sendable, Equatable {
    public let code: String

    public init(_ code: String) {
        self.code = code
    }

    // MARK: - Predefined Styles

    public static let bold    = ANSIStyle(ANSI.bold)
    public static let dim     = ANSIStyle(ANSI.dim)
    public static let reset   = ANSIStyle(ANSI.reset)
    public static let inverse = ANSIStyle(ANSI.inverse)

    // Colors
    public static let red     = ANSIStyle(ANSI.red)
    public static let green   = ANSIStyle(ANSI.green)
    public static let yellow  = ANSIStyle(ANSI.yellow)
    public static let cyan    = ANSIStyle(ANSI.cyan)
    public static let white   = ANSIStyle(ANSI.white)
    public static let magenta = ANSIStyle(ANSI.magenta)

    // Dracula purple (matches SplashRenderer)
    public static let purple = ANSIStyle("\u{1B}[38;2;189;147;249m")
}

/// Apply one or more ANSI styles to a string, automatically resetting at the end.
/// Returns the plain string when `styles` is empty.
public func styled(_ text: String, _ styles: ANSIStyle...) -> String {
    guard !styles.isEmpty else { return text }
    let prefix = styles.map(\.code).joined()
    return "\(prefix)\(text)\(ANSI.reset)"
}

/// Strip all ANSI escape sequences from a string (useful for testing).
public func stripANSI(_ text: String) -> String {
    text.replacingOccurrences(
        of: "\u{1B}\\[[0-9;]*m",
        with: "",
        options: .regularExpression
    )
}
