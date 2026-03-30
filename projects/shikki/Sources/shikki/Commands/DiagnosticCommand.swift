import ArgumentParser
import Foundation
import ShikkiKit

/// `shikki diagnostic` — Recover recent work context from ShikiDB,
/// local checkpoints, and git for humans and agents.
/// Also accessible as `shikki doctor --context`.
struct DiagnosticCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "diagnostic",
        abstract: "Recover recent work context from DB, checkpoints, and git"
    )

    @Option(name: .long, help: "Time window to look back. Format: 2h, 30m, 3600s, 7d. Default: 2h.")
    var from: String?

    @Option(name: .long, help: "Output format: human (default), agent, json.")
    var format: String = "human"

    @Option(name: .long, help: "Token budget for agent format. Default: 2048.")
    var budget: Int = 2048

    @Flag(name: .long, help: "Show full event payloads.")
    var verbose: Bool = false

    @Flag(name: .long, help: "Copy output to clipboard (macOS pbcopy) or ~/.shikki/last-recovery.md.")
    var copy: Bool = false

    func run() async throws {
        // Parse output format
        let outputFormat: DiagnosticOutputFormat
        switch format.lowercased() {
        case "human": outputFormat = .human
        case "agent": outputFormat = .agent
        case "json": outputFormat = .json
        default:
            throw ValidationError("Unknown format '\(format)'. Use: human, agent, json.")
        }

        // Parse time window
        let window: TimeWindow
        if let fromStr = from {
            let parsed = try DurationParser.parseForRecovery(fromStr)
            if parsed.clamped {
                FileHandle.standardError.write(Data("Warning: duration clamped to 7d maximum.\n".utf8))
            }
            window = TimeWindow.lookback(seconds: parsed.seconds)
        } else {
            // BR-07: Check checkpoint timestamp for smart default
            window = defaultWindow()
        }

        // Recover context
        let service = ContextRecoveryService()
        let context = await service.recover(window: window, verbose: verbose)

        // Format output
        let output: String
        switch outputFormat {
        case .human:
            let isTTY = isatty(fileno(stdout)) != 0
            output = DiagnosticFormatter.formatHuman(context, isTTY: isTTY, verbose: verbose)
        case .agent:
            let effectiveBudget = verbose ? max(budget, 4096) : budget
            output = DiagnosticFormatter.formatAgent(context, budget: effectiveBudget)
        case .json:
            output = DiagnosticFormatter.formatJSON(context, verbose: verbose)
        }

        // BR-23: --copy flag
        if copy {
            copyToClipboard(output)
        }

        // Output — using FileHandle to avoid print() overhead
        FileHandle.standardOutput.write(Data(output.utf8))
        FileHandle.standardOutput.write(Data("\n".utf8))

        // BR-15: If all sources failed
        if context.confidence.overall == 0 && context.timeline.isEmpty {
            FileHandle.standardError.write(
                Data("No context available. Run `shikki doctor` to check environment health.\n".utf8)
            )
        }
    }

    /// BR-07: Smart default window.
    /// If checkpoint exists and is newer than 2h, start from checkpoint minus 10m.
    /// Otherwise, default 2h.
    private func defaultWindow() -> TimeWindow {
        let checkpointManager = CheckpointManager()
        if let checkpoint = try? checkpointManager.load() {
            let twoHoursAgo = Date().addingTimeInterval(-DurationParser.defaultRecoveryDuration)
            if checkpoint.timestamp > twoHoursAgo {
                let since = checkpoint.timestamp.addingTimeInterval(-600) // 10 min overlap
                return TimeWindow(since: since)
            }
        }
        return TimeWindow.lookback(seconds: DurationParser.defaultRecoveryDuration)
    }

    /// BR-23: Copy to clipboard or fallback file.
    private func copyToClipboard(_ content: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["pbcopy"]
        let stdin = Pipe()
        process.standardInput = stdin
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            stdin.fileHandleForWriting.write(Data(content.utf8))
            try stdin.fileHandleForWriting.close()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                FileHandle.standardError.write(Data("Copied to clipboard.\n".utf8))
                return
            }
        } catch {}

        // Fallback: write to file
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dir = "\(home)/.shikki"
        let path = "\(dir)/last-recovery.md"
        let fm = FileManager.default
        do {
            if !fm.fileExists(atPath: dir) {
                try fm.createDirectory(atPath: dir, withIntermediateDirectories: true,
                                       attributes: [.posixPermissions: 0o700])
            }
            try content.write(toFile: path, atomically: true, encoding: .utf8)
            FileHandle.standardError.write(Data("Written to \(path)\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("Failed to write recovery file: \(error)\n".utf8))
        }
    }
}
