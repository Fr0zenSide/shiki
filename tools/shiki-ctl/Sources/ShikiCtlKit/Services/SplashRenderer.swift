import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Terminal splash screen shown on `shiki start`.
/// ASCII art title with Dracula-inspired colors, version, and optional resume context.
public enum SplashRenderer {

    /// The ASCII art title block.
    static let asciiTitle = """
    ┌───────────────────────────────────────────────┐
    │                                               │
    │   ███████╗██╗  ██╗██╗██╗  ██╗██╗  ██╗██╗     │
    │   ██╔════╝██║  ██║██║██║ ██╔╝██║ ██╔╝██║     │
    │   ███████╗███████║██║█████╔╝ █████╔╝ ██║     │
    │   ╚════██║██╔══██║██║██╔═██╗ ██╔═██╗ ██║     │
    │   ███████║██║  ██║██║██║  ██╗██║  ██╗██║     │
    │   ╚══════╝╚═╝  ╚═╝╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  │
    │                                               │
    └───────────────────────────────────────────────┘
    """

    /// Render the splash screen. Returns immediately if not a TTY.
    /// - Parameters:
    ///   - version: The version string to display below the title.
    ///   - resumeContext: Optional session resume state (branch, last summary).
    ///   - skipSleep: If true, skip the 1-second pause (for testing).
    public static func render(version: String, resumeContext: String? = nil, skipSleep: Bool = false) {
        guard isatty(STDIN_FILENO) == 1 else { return }

        TerminalOutput.clearScreen()

        // Dracula purple: RGB(189, 147, 249)
        let purple = "\u{1B}[38;2;189;147;249m"
        let dim = "\u{1B}[2m"
        let reset = "\u{1B}[0m"

        print("\(purple)\(asciiTitle)\(reset)")
        print("\(dim)          v\(version)\(reset)")
        print()

        if let context = resumeContext {
            print("\(dim)\(context)\(reset)")
            print()
        }

        if !skipSleep {
            Thread.sleep(forTimeInterval: 1.0)
        }
    }

    /// Render splash to a string (for testing/snapshot purposes).
    /// Does NOT check for TTY — always produces output.
    public static func renderToString(version: String, resumeContext: String? = nil) -> String {
        let purple = "\u{1B}[38;2;189;147;249m"
        let dim = "\u{1B}[2m"
        let reset = "\u{1B}[0m"

        var lines: [String] = []
        lines.append("\(purple)\(asciiTitle)\(reset)")
        lines.append("\(dim)          v\(version)\(reset)")
        lines.append("")

        if let context = resumeContext {
            lines.append("\(dim)\(context)\(reset)")
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}
