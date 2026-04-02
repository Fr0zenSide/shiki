import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

// MARK: - Data Types

public struct StartupDisplayData: Sendable {
    public let version: String
    public let isHealthy: Bool
    public let lastSessionTasks: [(company: String, completed: Int)]
    public let upcomingTasks: [(company: String, pending: Int)]
    public let sessionStats: [ProjectStats]
    public let weeklyInsertions: Int
    public let weeklyDeletions: Int
    public let weeklyProjectCount: Int
    public let pendingDecisions: Int
    public let staleCompanies: Int
    public let spentToday: Double
    public let companySlugs: [String]

    public init(
        version: String,
        isHealthy: Bool,
        lastSessionTasks: [(company: String, completed: Int)],
        upcomingTasks: [(company: String, pending: Int)],
        sessionStats: [ProjectStats],
        weeklyInsertions: Int,
        weeklyDeletions: Int,
        weeklyProjectCount: Int,
        pendingDecisions: Int,
        staleCompanies: Int,
        spentToday: Double,
        companySlugs: [String] = []
    ) {
        self.version = version
        self.isHealthy = isHealthy
        self.lastSessionTasks = lastSessionTasks
        self.upcomingTasks = upcomingTasks
        self.sessionStats = sessionStats
        self.weeklyInsertions = weeklyInsertions
        self.weeklyDeletions = weeklyDeletions
        self.weeklyProjectCount = weeklyProjectCount
        self.pendingDecisions = pendingDecisions
        self.staleCompanies = staleCompanies
        self.spentToday = spentToday
        self.companySlugs = companySlugs
    }
}

// MARK: - Renderer
// Uses ANSI enum from TUI/TerminalOutput.swift

public enum StartupRenderer {

    // MARK: - Public API

    public static func render(_ data: StartupDisplayData) {
        let width = terminalWidth()

        // Top border
        printLine(top: true, bottom: false, width: width)

        // Title row
        let status = data.isHealthy
            ? "\(ANSI.green)\(ANSI.bold)\u{25CF} System Ready\(ANSI.reset)"
            : "\(ANSI.red)\(ANSI.bold)\u{25CF} Unhealthy\(ANSI.reset)"
        let title = "\(ANSI.bold)  SHIKKI v\(data.version)\(ANSI.reset)"
        printPaddedRow(left: title, right: status, width: width)

        // Split header
        let leftColWidth = (width - 3) / 2
        let rightColWidth = width - 3 - leftColWidth
        printSplitBorder(leftWidth: leftColWidth, rightWidth: rightColWidth)

        // Last Session / Upcoming columns
        let leftHeader = "  Last Session"
        let rightHeader = "  Upcoming"
        let leftUnderline = "  \u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}"
        let rightUnderline = "  \u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}"
        printSplitRow(left: leftHeader, right: rightHeader, leftWidth: leftColWidth, rightWidth: rightColWidth)
        printSplitRow(left: leftUnderline, right: rightUnderline, leftWidth: leftColWidth, rightWidth: rightColWidth)

        let maxRows = max(data.lastSessionTasks.count, data.upcomingTasks.count)
        for i in 0..<max(maxRows, 1) {
            let leftText: String
            if i < data.lastSessionTasks.count {
                let t = data.lastSessionTasks[i]
                let taskWord = t.completed == 1 ? "task" : "tasks"
                leftText = "  \(ANSI.green)\u{2713}\(ANSI.reset) \(t.company): \(t.completed) \(taskWord) done"
            } else {
                leftText = ""
            }

            let rightText: String
            if i < data.upcomingTasks.count {
                let t = data.upcomingTasks[i]
                rightText = "  \(ANSI.yellow)\u{2192}\(ANSI.reset) \(t.company): \(t.pending) pending"
            } else {
                rightText = ""
            }

            printSplitRow(left: leftText, right: rightText, leftWidth: leftColWidth, rightWidth: rightColWidth)
        }

        // Empty row in split section
        printSplitRow(left: "", right: "", leftWidth: leftColWidth, rightWidth: rightColWidth)

        // Merge border (split -> full width)
        printMergeBorder(leftWidth: leftColWidth, rightWidth: rightColWidth)

        // Session Stats section
        printContentRow("  \(ANSI.bold)Session Stats\(ANSI.reset) \(ANSI.dim)(since last session)\(ANSI.reset)", width: width)
        printContentRow("  \u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}", width: width)

        for stat in data.sessionStats {
            let maturitySuffix = stat.isMatureStage ? "  \(ANSI.dim)\u{2248} mature\(ANSI.reset)" : ""
            let line = "  \(pad(stat.name + ":", 12))+\(formatNumber(stat.insertions)) / -\(formatNumber(stat.deletions)) lines (\(stat.commits) \(stat.commits == 1 ? "commit" : "commits"))\(maturitySuffix)"
            printContentRow(line, width: width)
        }

        printContentRow("", width: width)
        let weeklyLine = "  \(ANSI.bold)Weekly:\(ANSI.reset) +\(formatNumber(data.weeklyInsertions)) / -\(formatNumber(data.weeklyDeletions)) lines across \(data.weeklyProjectCount) projects"
        printContentRow(weeklyLine, width: width)

        // Footer separator
        printHorizontalBorder(width: width)

        // Footer row
        let decisions = data.pendingDecisions > 0
            ? "\(ANSI.red)\(data.pendingDecisions) T1 decisions pending\(ANSI.reset)"
            : "\(ANSI.dim)0 T1 decisions pending\(ANSI.reset)"
        let stale = data.staleCompanies > 0
            ? "\(ANSI.yellow)\(data.staleCompanies) stale \(data.staleCompanies == 1 ? "company" : "companies")\(ANSI.reset)"
            : "\(ANSI.dim)0 stale companies\(ANSI.reset)"
        let spent = "\(ANSI.dim)$\(String(format: "%.0f", data.spentToday)) spent today\(ANSI.reset)"
        let footer = "  \(decisions) \u{00B7} \(stale) \u{00B7} \(spent)"
        printContentRow(footer, width: width)

        // Bottom border
        printLine(top: false, bottom: true, width: width)
    }

    // MARK: - Terminal Width

    private static func terminalWidth() -> Int {
        #if canImport(Darwin) || canImport(Glibc)
        guard isatty(STDOUT_FILENO) == 1 else { return 80 }
        var ws = winsize()
        if ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &ws) == 0, ws.ws_col > 0 {
            return max(Int(ws.ws_col), 66)
        }
        #endif
        return 80
    }

    // MARK: - Box Drawing

    private static func printLine(top: Bool, bottom: Bool, width: Int) {
        let left = top ? "\u{2554}" : "\u{255A}"
        let right = top ? "\u{2557}" : "\u{255D}"
        let fill = String(repeating: "\u{2550}", count: width - 2)
        print("\(left)\(fill)\(right)")
    }

    private static func printHorizontalBorder(width: Int) {
        let fill = String(repeating: "\u{2550}", count: width - 2)
        print("\u{2560}\(fill)\u{2563}")
    }

    private static func printSplitBorder(leftWidth: Int, rightWidth: Int) {
        let leftFill = String(repeating: "\u{2550}", count: leftWidth)
        let rightFill = String(repeating: "\u{2550}", count: rightWidth)
        print("\u{2560}\(leftFill)\u{2566}\(rightFill)\u{2563}")
    }

    private static func printMergeBorder(leftWidth: Int, rightWidth: Int) {
        let leftFill = String(repeating: "\u{2550}", count: leftWidth)
        let rightFill = String(repeating: "\u{2550}", count: rightWidth)
        print("\u{2560}\(leftFill)\u{2569}\(rightFill)\u{2563}")
    }

    private static func printContentRow(_ content: String, width: Int) {
        let visible = visibleLength(content)
        let padding = max(0, width - 2 - visible)
        print("\u{2551}\(content)\(String(repeating: " ", count: padding))\u{2551}")
    }

    private static func printPaddedRow(left: String, right: String, width: Int) {
        let leftVisible = visibleLength(left)
        let rightVisible = visibleLength(right)
        let gap = max(1, width - 2 - leftVisible - rightVisible)
        print("\u{2551}\(left)\(String(repeating: " ", count: gap))\(right)\u{2551}")
    }

    private static func printSplitRow(left: String, right: String, leftWidth: Int, rightWidth: Int) {
        let leftVisible = visibleLength(left)
        let rightVisible = visibleLength(right)
        let leftPad = max(0, leftWidth - leftVisible)
        let rightPad = max(0, rightWidth - rightVisible)
        print("\u{2551}\(left)\(String(repeating: " ", count: leftPad))\u{2551}\(right)\(String(repeating: " ", count: rightPad))\u{2551}")
    }

    // MARK: - Text Helpers

    /// Visible character count, stripping ANSI escape sequences.
    private static func visibleLength(_ string: String) -> Int {
        string.replacingOccurrences(
            of: "\u{1B}\\[[0-9;]*m", with: "",
            options: .regularExpression
        ).count
    }

    private static func pad(_ string: String, _ width: Int) -> String {
        let visible = visibleLength(string)
        if visible >= width { return string }
        return string + String(repeating: " ", count: width - visible)
    }

    private static func formatNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
