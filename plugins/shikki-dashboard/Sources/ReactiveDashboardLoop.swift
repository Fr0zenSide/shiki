import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// MARK: - ReactiveDashboardLoop

/// TUI loop that renders dashboard state from the ReactiveDashboardEngine.
/// Similar to DashboardRenderer.runLive but pulls state from the engine
/// instead of re-gathering from system sources each cycle.
public enum ReactiveDashboardLoop {

    /// Run the reactive dashboard loop until user quits.
    public static func run(
        engine: ReactiveDashboardEngine,
        session: String = "shiki",
        refreshInterval: TimeInterval = 2.0
    ) async {
        guard isatty(STDIN_FILENO) == 1 else {
            // Non-TTY: render single snapshot and exit
            let state = await engine.currentState()
            Swift.print(DashboardRenderer.render(state: state, width: TerminalOutput.terminalWidth()))
            return
        }

        let raw = RawMode()
        TerminalOutput.hideCursor()

        // Handle SIGINT gracefully
        signal(SIGINT) { _ in
            TerminalOutput.showCursor()
            TerminalOutput.clearScreen()
            TerminalOutput.flush()
            exit(0)
        }

        var showEvents = true
        var running = true

        // Seed engine with initial git branch
        if let branch = runCapture("/usr/bin/git", args: ["rev-parse", "--abbrev-ref", "HEAD"]) {
            await engine.setBranch(branch)
        }
        await engine.setVersion("0.3.0-pre")

        while running {
            var state = await engine.currentState()
            state.showEvents = showEvents

            let width = TerminalOutput.terminalWidth()
            TerminalOutput.clearScreen()

            // Add reactive indicator to distinguish from static mode
            let reactiveTag = ANSI.green + " [REACTIVE]" + ANSI.reset
            Swift.print(DashboardRenderer.renderColored(state: state, width: width))
            TerminalOutput.moveTo(row: 1, col: width - 12)
            Swift.print(reactiveTag, terminator: "")
            TerminalOutput.flush()

            // Wait for keypress or timeout
            var pollFd = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
            let timeoutMs = Int32(refreshInterval * 1000)
            let ready = poll(&pollFd, 1, timeoutMs)

            if ready > 0 {
                let key = TerminalInput.readKey()
                switch key {
                case .char("q"), .char("Q"), .escape:
                    running = false
                case .char("r"), .char("R"):
                    // Force refresh git branch
                    if let branch = runCapture("/usr/bin/git", args: ["rev-parse", "--abbrev-ref", "HEAD"]) {
                        await engine.setBranch(branch)
                    }
                case .char("e"), .char("E"):
                    showEvents.toggle()
                case .char("p"), .char("P"):
                    break // Placeholder for PR panel
                default:
                    break
                }
            }
            // On timeout, state auto-updates from engine (events streamed in)
        }

        TerminalOutput.showCursor()
        TerminalOutput.clearScreen()
        TerminalOutput.flush()
        raw.restore()
    }

    // MARK: - Helpers

    private static func runCapture(_ executable: String, args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}
