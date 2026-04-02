import ArgumentParser
import Foundation
import ShikkiKit

/// BR-EM-14: Focus mode — suppress notifications, queue inbox items, set tmux indicator.
/// Emoji alias: 🔇
///
/// Usage:
///   shi focus          — show elapsed time (or "not active")
///   shi focus 20m      — start focus for 20 minutes
///   shi focus stop     — stop focus mode early
struct FocusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "focus",
        abstract: "🔇 Focus mode — suppress notifications and queue inbox items"
    )

    @Argument(help: "Duration (e.g. 20m, 90s, 1h) or 'stop' to end focus mode")
    var input: String?

    /// Injected directory for testing; defaults to ~/.shikki.
    var managerDirectory: String? = nil

    func run() async throws {
        let manager = FocusManager(directory: managerDirectory)
        let arg = input?.trimmingCharacters(in: .whitespaces)

        // MARK: stop
        if arg?.lowercased() == "stop" {
            guard let state = try manager.load(), state.active else {
                print("\(ANSI.yellow)Focus mode is not active.\(ANSI.reset)")
                return
            }
            try manager.delete()
            print("\(ANSI.green)🔇 Focus mode stopped.\(ANSI.reset) Time to ☕ recharge.")
            return
        }

        // MARK: show elapsed (no args)
        if arg == nil {
            if let state = try manager.load(), state.active {
                let elapsed = Date().timeIntervalSince(state.startedAt)
                let formattedElapsed = DurationParser.format(elapsed)
                if let total = state.durationSeconds {
                    let remaining = max(0, total - elapsed)
                    print("\(ANSI.cyan)🔇 Focus mode active\(ANSI.reset) — elapsed: \(formattedElapsed), remaining: \(DurationParser.format(remaining))")
                } else {
                    print("\(ANSI.cyan)🔇 Focus mode active\(ANSI.reset) — elapsed: \(formattedElapsed) (no timer)")
                }
            } else {
                print("\(ANSI.dim)Focus mode is not active.\(ANSI.reset)")
                print("  \(ANSI.dim)Usage: shi focus <duration>  (e.g. shi focus 20m)\(ANSI.reset)")
            }
            return
        }

        // MARK: start with duration
        guard let durationStr = arg, let durationSec = DurationParser.parse(durationStr) else {
            print("\(ANSI.red)Unknown argument '\(arg ?? "")'. Use a duration like 20m, 90s, 1h, or 'stop'.\(ANSI.reset)")
            throw ExitCode.failure
        }

        let state = FocusState(startedAt: Date(), durationSeconds: durationSec, active: true)
        try manager.save(state)

        let label = DurationParser.format(durationSec)
        print("\(ANSI.green)🔇 Focus mode started\(ANSI.reset) for \(label). Inbox items will queue. Good luck!")

        // Wait for timer to expire, then prompt
        try await waitForExpiry(seconds: durationSec, manager: manager)
    }

    // MARK: - Private helpers

    private func waitForExpiry(seconds: Double, manager: FocusManager) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            let remaining = deadline.timeIntervalSinceNow
            let sleepDur = min(remaining, 1.0)
            if sleepDur <= 0 { break }
            try await Task.sleep(for: .seconds(sleepDur))
            // Re-check: user may have stopped focus from another terminal
            guard let s = try? manager.load(), s.active else { return }
        }

        // Timer expired
        print("\n\(ANSI.bold)\(ANSI.yellow)⏰ Focus time is up!\(ANSI.reset) Want more time? [Y/n] ", terminator: "")
        fflush(stdout)

        if let response = readLine()?.trimmingCharacters(in: .whitespaces).lowercased(),
           response == "" || response == "y" || response == "yes" {
            let extended = FocusState(startedAt: Date(), durationSeconds: seconds, active: true)
            try manager.save(extended)
            let label = DurationParser.format(seconds)
            print("\(ANSI.green)🔇 Extended focus for another \(label). You've got this!\(ANSI.reset)")
            try await waitForExpiry(seconds: seconds, manager: manager)
        } else {
            try manager.delete()
            print("\(ANSI.cyan)Focus mode ended.\(ANSI.reset) Time for a ☕ break — you earned it!")
        }
    }
}
