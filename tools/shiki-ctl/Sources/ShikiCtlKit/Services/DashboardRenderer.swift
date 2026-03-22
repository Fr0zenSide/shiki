import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// MARK: - Dashboard State

/// Full state for the reactive dashboard TUI.
public struct DashboardState: Sendable {
    public var version: String
    public var branch: String
    public var sessionStatus: String
    public var sessionUptime: TimeInterval
    public var agents: [AgentStatus]
    public var budget: BudgetDisplay
    public var testCount: Int
    public var openPRs: Int
    public var events: [DashboardEvent]
    public var showEvents: Bool

    public init(
        version: String = "0.2.0",
        branch: String = "develop",
        sessionStatus: String = "active",
        sessionUptime: TimeInterval = 0,
        agents: [AgentStatus] = [],
        budget: BudgetDisplay = BudgetDisplay(spent: 0, limit: 0),
        testCount: Int = 0,
        openPRs: Int = 0,
        events: [DashboardEvent] = [],
        showEvents: Bool = true
    ) {
        self.version = version
        self.branch = branch
        self.sessionStatus = sessionStatus
        self.sessionUptime = sessionUptime
        self.agents = agents
        self.budget = budget
        self.testCount = testCount
        self.openPRs = openPRs
        self.events = events
        self.showEvents = showEvents
    }

    // MARK: - Nested Types

    public struct AgentStatus: Sendable {
        public let name: String
        public let status: Status
        public let progress: Int   // 0-100
        public let detail: String  // "Building Wave 3" or "PR #24 created"

        public enum Status: String, Sendable {
            case active
            case completed
            case queued
            case failed
        }

        public init(name: String, status: Status, progress: Int, detail: String) {
            self.name = name
            self.status = status
            self.progress = progress
            self.detail = detail
        }
    }

    public struct BudgetDisplay: Sendable {
        public let spent: Double
        public let limit: Double

        public init(spent: Double, limit: Double) {
            self.spent = spent
            self.limit = limit
        }

        public var percent: Int {
            limit > 0 ? min(100, Int((spent / limit) * 100)) : 0
        }

        /// 20-character progress bar using block characters.
        public var bar: String {
            progressBar(percent: percent, width: 15)
        }
    }

    public struct DashboardEvent: Sendable {
        public let timestamp: Date
        public let type: String
        public let agent: String
        public let detail: String

        public init(timestamp: Date, type: String, agent: String, detail: String) {
            self.timestamp = timestamp
            self.type = type
            self.agent = agent
            self.detail = detail
        }
    }
}

// MARK: - Progress Bar Helper

/// Render a progress bar: filled blocks + empty blocks.
public func progressBar(percent: Int, width: Int) -> String {
    let clamped = max(0, min(100, percent))
    let filled = Int(Double(clamped) / 100.0 * Double(width))
    let empty = width - filled
    return String(repeating: "\u{2588}", count: filled) + String(repeating: "\u{2591}", count: empty)
}

// MARK: - Dashboard Renderer

public enum DashboardRenderer {

    // MARK: - Box Drawing Characters

    private static let topLeft     = "\u{250C}"
    private static let topRight    = "\u{2510}"
    private static let bottomLeft  = "\u{2514}"
    private static let bottomRight = "\u{2518}"
    private static let horizontal  = "\u{2500}"
    private static let vertical    = "\u{2502}"
    private static let leftTee     = "\u{251C}"
    private static let rightTee    = "\u{2524}"
    private static let topTee      = "\u{252C}"
    private static let bottomTee   = "\u{2534}"

    // MARK: - Public API

    /// Render the full dashboard to a string (pure, for testing and display).
    public static func render(state: DashboardState, width: Int = 60) -> String {
        let innerWidth = width - 2  // account for left/right border
        var lines: [String] = []

        // Top border
        lines.append(topLeft + String(repeating: horizontal, count: innerWidth) + topRight)

        // Title bar
        let title = "SHIKKI DASHBOARD"
        let versionTag = "v\(state.version)"
        let titlePadding = innerWidth - title.count - versionTag.count
        let titleLine = "  " + title + String(repeating: " ", count: max(1, titlePadding - 2)) + versionTag
        lines.append(vertical + padToWidth(titleLine, innerWidth) + vertical)

        // Separator with T-junction for two-column split
        let leftColWidth = (innerWidth - 1) / 2  // -1 for center vertical
        let rightColWidth = innerWidth - leftColWidth - 1
        lines.append(leftTee + String(repeating: horizontal, count: leftColWidth) + topTee + String(repeating: horizontal, count: rightColWidth) + rightTee)

        // Build left column (orchestrator + budget + tests/PRs)
        var leftLines: [String] = []
        leftLines.append("")
        leftLines.append("  Orchestrator")
        leftLines.append("  Branch: \(state.branch)")
        leftLines.append("  Session: \(state.sessionStatus)")
        leftLines.append("  Uptime: \(formatUptime(state.sessionUptime))")
        leftLines.append("")
        leftLines.append("  Budget")
        leftLines.append("  \(state.budget.bar) \(state.budget.percent)%")
        leftLines.append("  $\(formatMoney(state.budget.spent)) / $\(formatMoney(state.budget.limit))")
        leftLines.append("")
        leftLines.append("  Tests: \(state.testCount) green")
        leftLines.append("  PRs: \(state.openPRs) open")
        leftLines.append("")

        // Build right column (agents)
        var rightLines: [String] = []
        rightLines.append("")
        rightLines.append("  Agents")
        rightLines.append("")

        if state.agents.isEmpty {
            rightLines.append("  No active sessions")
            rightLines.append("")
        } else {
            for agent in state.agents {
                let icon = statusIcon(agent.status)
                let barWidth = 8
                switch agent.status {
                case .active:
                    let bar = progressBar(percent: agent.progress, width: barWidth)
                    rightLines.append("  \(icon) \(agent.name)  \(bar) \(agent.progress)%")
                    rightLines.append("    \(agent.detail)")
                case .completed:
                    rightLines.append("  \(icon) \(agent.name)  \(progressBar(percent: 100, width: barWidth)) 100%")
                    rightLines.append("    \(agent.detail)")
                case .queued:
                    rightLines.append("  \(icon) \(agent.name)  QUEUED")
                    rightLines.append("    \(agent.detail)")
                case .failed:
                    rightLines.append("  \(icon) \(agent.name)  FAILED")
                    rightLines.append("    \(agent.detail)")
                }
                rightLines.append("")
            }
        }

        // Equalize column heights
        let maxRows = max(leftLines.count, rightLines.count)
        while leftLines.count < maxRows { leftLines.append("") }
        while rightLines.count < maxRows { rightLines.append("") }

        // Merge columns
        for i in 0..<maxRows {
            let left = padToWidth(leftLines[i], leftColWidth)
            let right = padToWidth(rightLines[i], rightColWidth)
            lines.append(vertical + left + vertical + right + vertical)
        }

        // Events section
        if state.showEvents {
            lines.append(leftTee + String(repeating: horizontal, count: leftColWidth) + bottomTee + String(repeating: horizontal, count: rightColWidth) + rightTee)

            let eventsTitle = "  Events (latest first)"
            lines.append(vertical + padToWidth(eventsTitle, innerWidth) + vertical)

            let eventsToShow = Array(state.events.prefix(4))
            if eventsToShow.isEmpty {
                lines.append(vertical + padToWidth("  No events", innerWidth) + vertical)
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm"
                for event in eventsToShow {
                    let time = formatter.string(from: event.timestamp)
                    let eventLine = "  \(time) \(padPlain(event.type, 17)) \(padPlain(event.agent, 10)) \(event.detail)"
                    lines.append(vertical + padToWidth(eventLine, innerWidth) + vertical)
                }
            }
        } else {
            // Close the two-column section
            lines.append(leftTee + String(repeating: horizontal, count: leftColWidth) + bottomTee + String(repeating: horizontal, count: rightColWidth) + rightTee)
        }

        // Hotkeys footer
        let hotkeys = "  q:quit  r:refresh  e:toggle events  p:toggle PRs"
        lines.append(leftTee + String(repeating: horizontal, count: innerWidth) + rightTee)
        lines.append(vertical + padToWidth(hotkeys, innerWidth) + vertical)

        // Bottom border
        lines.append(bottomLeft + String(repeating: horizontal, count: innerWidth) + bottomRight)

        return lines.joined(separator: "\n")
    }

    /// Render the dashboard with ANSI colors for terminal display.
    public static func renderColored(state: DashboardState, width: Int = 60) -> String {
        let innerWidth = width - 2
        var lines: [String] = []

        // Top border
        lines.append(ANSI.dim + topLeft + String(repeating: horizontal, count: innerWidth) + topRight + ANSI.reset)

        // Title bar
        let title = "SHIKKI DASHBOARD"
        let versionTag = "v\(state.version)"
        let titlePadding = innerWidth - title.count - versionTag.count
        let titleLine = "  " + ANSI.bold + ANSI.cyan + title + ANSI.reset + String(repeating: " ", count: max(1, titlePadding - 2)) + ANSI.dim + versionTag + ANSI.reset
        lines.append(ANSI.dim + vertical + ANSI.reset + padToWidthAnsi(titleLine, innerWidth) + ANSI.dim + vertical + ANSI.reset)

        // Separator
        let leftColWidth = (innerWidth - 1) / 2
        let rightColWidth = innerWidth - leftColWidth - 1
        lines.append(ANSI.dim + leftTee + String(repeating: horizontal, count: leftColWidth) + topTee + String(repeating: horizontal, count: rightColWidth) + rightTee + ANSI.reset)

        // Build left column
        var leftLines: [String] = []
        leftLines.append("")
        leftLines.append("  " + ANSI.bold + "Orchestrator" + ANSI.reset)
        leftLines.append("  Branch: " + ANSI.cyan + state.branch + ANSI.reset)
        leftLines.append("  Session: " + sessionColor(state.sessionStatus) + state.sessionStatus + ANSI.reset)
        leftLines.append("  Uptime: " + formatUptime(state.sessionUptime))
        leftLines.append("")
        leftLines.append("  " + ANSI.bold + "Budget" + ANSI.reset)
        leftLines.append("  " + budgetBarColored(state.budget) + " " + budgetPercentColored(state.budget))
        leftLines.append("  $\(formatMoney(state.budget.spent)) / $\(formatMoney(state.budget.limit))")
        leftLines.append("")
        leftLines.append("  Tests: " + ANSI.green + "\(state.testCount) green" + ANSI.reset)
        leftLines.append("  PRs: \(state.openPRs) open")
        leftLines.append("")

        // Build right column
        var rightLines: [String] = []
        rightLines.append("")
        rightLines.append("  " + ANSI.bold + "Agents" + ANSI.reset)
        rightLines.append("")

        if state.agents.isEmpty {
            rightLines.append("  " + ANSI.dim + "No active sessions" + ANSI.reset)
            rightLines.append("")
        } else {
            for agent in state.agents {
                let icon = statusIconColored(agent.status)
                let barWidth = 8
                switch agent.status {
                case .active:
                    let bar = ANSI.green + progressBar(percent: agent.progress, width: barWidth) + ANSI.reset
                    rightLines.append("  \(icon) \(agent.name)  \(bar) \(agent.progress)%")
                    rightLines.append("    " + ANSI.dim + agent.detail + ANSI.reset)
                case .completed:
                    let bar = ANSI.green + progressBar(percent: 100, width: barWidth) + ANSI.reset
                    rightLines.append("  \(icon) \(agent.name)  \(bar) 100%")
                    rightLines.append("    " + ANSI.green + agent.detail + ANSI.reset)
                case .queued:
                    rightLines.append("  \(icon) \(agent.name)  " + ANSI.dim + "QUEUED" + ANSI.reset)
                    rightLines.append("    " + ANSI.dim + agent.detail + ANSI.reset)
                case .failed:
                    rightLines.append("  \(icon) \(agent.name)  " + ANSI.red + "FAILED" + ANSI.reset)
                    rightLines.append("    " + ANSI.red + agent.detail + ANSI.reset)
                }
                rightLines.append("")
            }
        }

        // Equalize heights
        let maxRows = max(leftLines.count, rightLines.count)
        while leftLines.count < maxRows { leftLines.append("") }
        while rightLines.count < maxRows { rightLines.append("") }

        for i in 0..<maxRows {
            let left = padToWidthAnsi(leftLines[i], leftColWidth)
            let right = padToWidthAnsi(rightLines[i], rightColWidth)
            lines.append(ANSI.dim + vertical + ANSI.reset + left + ANSI.dim + vertical + ANSI.reset + right + ANSI.dim + vertical + ANSI.reset)
        }

        // Events section
        if state.showEvents {
            lines.append(ANSI.dim + leftTee + String(repeating: horizontal, count: leftColWidth) + bottomTee + String(repeating: horizontal, count: rightColWidth) + rightTee + ANSI.reset)

            let eventsTitle = "  " + ANSI.bold + "Events" + ANSI.reset + ANSI.dim + " (latest first)" + ANSI.reset
            lines.append(ANSI.dim + vertical + ANSI.reset + padToWidthAnsi(eventsTitle, innerWidth) + ANSI.dim + vertical + ANSI.reset)

            let eventsToShow = Array(state.events.prefix(4))
            if eventsToShow.isEmpty {
                let noEvents = "  " + ANSI.dim + "No events" + ANSI.reset
                lines.append(ANSI.dim + vertical + ANSI.reset + padToWidthAnsi(noEvents, innerWidth) + ANSI.dim + vertical + ANSI.reset)
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm"
                for event in eventsToShow {
                    let time = ANSI.dim + formatter.string(from: event.timestamp) + ANSI.reset
                    let eventLine = "  \(time) \(padPlainAnsi(ANSI.yellow + event.type + ANSI.reset, 17)) \(padPlainAnsi(ANSI.cyan + event.agent + ANSI.reset, 10)) \(event.detail)"
                    lines.append(ANSI.dim + vertical + ANSI.reset + padToWidthAnsi(eventLine, innerWidth) + ANSI.dim + vertical + ANSI.reset)
                }
            }
        } else {
            lines.append(ANSI.dim + leftTee + String(repeating: horizontal, count: leftColWidth) + bottomTee + String(repeating: horizontal, count: rightColWidth) + rightTee + ANSI.reset)
        }

        // Hotkeys footer
        let hotkeys = "  " + ANSI.dim + "q" + ANSI.reset + ":quit  " + ANSI.dim + "r" + ANSI.reset + ":refresh  " + ANSI.dim + "e" + ANSI.reset + ":toggle events  " + ANSI.dim + "p" + ANSI.reset + ":toggle PRs"
        lines.append(ANSI.dim + leftTee + String(repeating: horizontal, count: innerWidth) + rightTee + ANSI.reset)
        lines.append(ANSI.dim + vertical + ANSI.reset + padToWidthAnsi(hotkeys, innerWidth) + ANSI.dim + vertical + ANSI.reset)

        // Bottom border
        lines.append(ANSI.dim + bottomLeft + String(repeating: horizontal, count: innerWidth) + bottomRight + ANSI.reset)

        return lines.joined(separator: "\n")
    }

    /// Run the live dashboard loop (auto-refresh every 2s, keyboard input).
    public static func runLive(
        session: String = "shiki",
        refreshInterval: TimeInterval = 2.0
    ) async {
        guard isatty(STDIN_FILENO) == 1 else {
            // Non-TTY: render single snapshot and exit
            let state = await gatherState(session: session)
            Swift.print(render(state: state, width: TerminalOutput.terminalWidth()))
            return
        }

        let raw = RawMode()
        TerminalOutput.hideCursor()

        // Handle SIGINT gracefully
        signal(SIGINT) { _ in
            TerminalOutput.showCursor()
            TerminalOutput.clearScreen()
            TerminalOutput.flush()
            // Restore terminal — best effort, raw mode restore happens below
            exit(0)
        }

        var state = await gatherState(session: session)
        var running = true

        while running {
            let width = TerminalOutput.terminalWidth()
            TerminalOutput.clearScreen()
            Swift.print(renderColored(state: state, width: width))
            TerminalOutput.flush()

            // Wait for keypress or timeout (poll-based)
            var pollFd = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
            let timeoutMs = Int32(refreshInterval * 1000)
            let ready = poll(&pollFd, 1, timeoutMs)

            if ready > 0 {
                // Key available
                let key = TerminalInput.readKey()
                switch key {
                case .char("q"), .char("Q"), .escape:
                    running = false
                case .char("r"), .char("R"):
                    state = await gatherState(session: session)
                case .char("e"), .char("E"):
                    state.showEvents.toggle()
                case .char("p"), .char("P"):
                    // Placeholder for PR panel toggle
                    break
                default:
                    break
                }
            } else {
                // Timeout — auto-refresh
                state = await gatherState(session: session)
            }
        }

        TerminalOutput.showCursor()
        TerminalOutput.clearScreen()
        TerminalOutput.flush()
        raw.restore()
    }

    // MARK: - Data Gathering

    /// Gather dashboard state from system sources (git, tmux, gh).
    public static func gatherState(session sessionName: String = "shiki") async -> DashboardState {
        let branch = runCapture("/usr/bin/git", args: ["rev-parse", "--abbrev-ref", "HEAD"]) ?? "unknown"

        // Gather agents from tmux
        let agents = gatherAgents(session: sessionName)

        // Gather budget from registered sessions
        let budget = gatherBudget(session: sessionName)

        // Open PRs (best-effort)
        let prCount = gatherOpenPRs()

        return DashboardState(
            version: "0.2.0",
            branch: branch,
            sessionStatus: agents.isEmpty ? "idle" : "active",
            sessionUptime: 0, // Would need session start tracking
            agents: agents,
            budget: budget,
            testCount: 0, // Requires last test run cache
            openPRs: prCount,
            events: [],
            showEvents: true
        )
    }

    private static func gatherAgents(session sessionName: String) -> [DashboardState.AgentStatus] {
        guard let output = runCapture("/usr/bin/env", args: [
            "tmux", "list-panes", "-s", "-t", sessionName,
            "-F", "#{window_name} #{pane_current_command}",
        ]) else { return [] }

        let reservedWindows: Set<String> = ["orchestrator", "board", "research"]

        return output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 1)
            guard let windowName = parts.first else { return nil }
            let name = String(windowName)
            guard !reservedWindows.contains(name) else { return nil }

            let command = parts.count > 1 ? String(parts[1]) : ""
            let isActive = !command.isEmpty && command != "zsh" && command != "bash"

            return DashboardState.AgentStatus(
                name: name,
                status: isActive ? .active : .queued,
                progress: isActive ? 50 : 0,
                detail: isActive ? command : "Waiting"
            )
        }
    }

    private static func gatherBudget(session: String) -> DashboardState.BudgetDisplay {
        // Default budget — would be populated from orchestrator status
        DashboardState.BudgetDisplay(spent: 0, limit: 0)
    }

    private static func gatherOpenPRs() -> Int {
        guard let output = runCapture("/usr/bin/env", args: [
            "gh", "pr", "list", "--state", "open", "--json", "number",
        ]) else { return 0 }
        // Count JSON array elements (lightweight parse)
        return output.components(separatedBy: "\"number\"").count - 1
    }

    // MARK: - Formatting Helpers

    static func formatUptime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "\(total)s"
        }
    }

    static func formatMoney(_ value: Double) -> String {
        if value == 0 { return "0.00" }
        return String(format: "%.2f", value)
    }

    /// Status icon without color.
    static func statusIcon(_ status: DashboardState.AgentStatus.Status) -> String {
        switch status {
        case .active:    return "\u{25CF}" // ●
        case .completed: return "\u{2713}" // ✓
        case .queued:    return "\u{25CB}" // ○
        case .failed:    return "\u{2717}" // ✗
        }
    }

    /// Status icon with ANSI color.
    private static func statusIconColored(_ status: DashboardState.AgentStatus.Status) -> String {
        switch status {
        case .active:    return ANSI.green + "\u{25CF}" + ANSI.reset   // ● green
        case .completed: return ANSI.green + "\u{2713}" + ANSI.reset   // ✓ green
        case .queued:    return ANSI.dim + "\u{25CB}" + ANSI.reset     // ○ dim
        case .failed:    return ANSI.red + "\u{2717}" + ANSI.reset     // ✗ red
        }
    }

    private static func sessionColor(_ status: String) -> String {
        switch status {
        case "active": return ANSI.green
        case "idle":   return ANSI.dim
        default:       return ANSI.yellow
        }
    }

    private static func budgetBarColored(_ budget: DashboardState.BudgetDisplay) -> String {
        let color: String
        if budget.percent > 80 { color = ANSI.red }
        else if budget.percent > 60 { color = ANSI.yellow }
        else { color = ANSI.green }
        return color + budget.bar + ANSI.reset
    }

    private static func budgetPercentColored(_ budget: DashboardState.BudgetDisplay) -> String {
        let color: String
        if budget.percent > 80 { color = ANSI.red }
        else if budget.percent > 60 { color = ANSI.yellow }
        else { color = ANSI.green }
        return color + "\(budget.percent)%" + ANSI.reset
    }

    /// Pad plain text (no ANSI) to width.
    private static func padToWidth(_ s: String, _ width: Int) -> String {
        if s.count >= width { return String(s.prefix(width)) }
        return s + String(repeating: " ", count: width - s.count)
    }

    /// Pad text with ANSI codes to width (accounts for invisible escape chars).
    private static func padToWidthAnsi(_ s: String, _ width: Int) -> String {
        let visible = TerminalOutput.visibleLength(s)
        if visible >= width { return s }
        return s + String(repeating: " ", count: width - visible)
    }

    /// Pad plain text content to visible width.
    private static func padPlain(_ s: String, _ width: Int) -> String {
        if s.count >= width { return String(s.prefix(width)) }
        return s + String(repeating: " ", count: width - s.count)
    }

    /// Pad ANSI-colored text to visible width.
    private static func padPlainAnsi(_ s: String, _ width: Int) -> String {
        let visible = TerminalOutput.visibleLength(s)
        if visible >= width { return s }
        return s + String(repeating: " ", count: width - visible)
    }

    // MARK: - Process Helpers

    private static func runCapture(_ executable: String, args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            // Read pipe BEFORE waitUntilExit to avoid deadlock
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}
