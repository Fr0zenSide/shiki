import ArgumentParser
import Foundation
import ShikkiKit

/// Graceful stop with configurable countdown and Esc cancel.
/// BR-12: RUNNING→STOPPING. No-op if IDLE.
/// BR-13: Default countdown 3s, configurable 0-60.
/// BR-14: --countdown 0 skips countdown.
/// BR-15: Each tick shows what's being saved.
/// BR-16: Esc cancels, returns to RUNNING.
/// BR-17: Non-TTY disables Esc.
/// BR-18: Double stop is no-op.
struct ShikkiStopCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stop",
        abstract: "Graceful shutdown with countdown (Esc to cancel)"
    )

    @Option(name: .long, help: "Countdown seconds before shutdown (0-60, default 3)")
    var countdown: Int = CountdownTimer.defaultCountdown

    @Option(name: .long, help: "Tmux session name")
    var session: String = "shikki"

    func run() async throws {
        let checkpointManager = CheckpointManager()
        let lockfileManager = LockfileManager()
        let dbSync = DBSyncClient()
        let detector = StateDetector(sessionName: session)

        let engine = ShikkiEngine(
            detector: detector,
            checkpointManager: checkpointManager,
            lockfileManager: lockfileManager,
            dbSync: dbSync
        )

        // Build checkpoint from current state
        let checkpoint = Checkpoint(
            timestamp: Date(),
            hostname: ProcessInfo.processInfo.hostName,
            fsmState: .stopping,
            tmuxLayout: nil, // TODO: capture from tmux in PR C
            sessionStats: nil, // TODO: capture stats in PR C
            contextSnippet: nil,
            dbSynced: false
        )

        // BR-15: Tick messages
        let tickMessages = [
            "Saving session context...",
            "Writing checkpoint...",
            "Closing session...",
        ]

        let isInteractive = isatty(STDIN_FILENO) == 1
        let keyReader: (any KeyReading)? = isInteractive ? TerminalKeyReader() : nil

        // BR-17: Non-TTY warning
        if !isInteractive {
            print("Non-interactive terminal — Esc cancel unavailable.")
        }

        let timer = CountdownTimer(
            isInteractive: isInteractive,
            keyReader: keyReader,
            onTick: { remaining in
                let msgIndex = min(tickMessages.count - 1, max(0, tickMessages.count - remaining))
                let msg = tickMessages[msgIndex]
                print("\r\u{1B}[K  T-\(remaining) \(msg)", terminator: "")
                fflush(stdout)
            },
            sleepDuration: .seconds(1)
        )

        let result = try await engine.stop(
            checkpoint: checkpoint,
            countdown: countdown,
            timer: timer
        )

        switch result {
        case .stopped:
            // Kill tmux session
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["tmux", "kill-session", "-t", session]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
            print("\n  \u{1B}[32mStopped.\u{1B}[0m")

        case .cancelled:
            print("\n  Stop cancelled. Session continues.")

        case .nothingRunning:
            print("  \u{1B}[2mNo session running.\u{1B}[0m")

        case .alreadyStopping:
            print("  \u{1B}[2mStop already in progress.\u{1B}[0m")
        }
    }
}
