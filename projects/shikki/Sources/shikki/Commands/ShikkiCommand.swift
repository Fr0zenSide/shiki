import ArgumentParser
import Foundation
import ShikkiKit

@main
struct ShikkiCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "shikki",
        abstract: "Shikki — unified orchestrator command. Auto-detects state: start, resume, or attach.",
        discussion: EmojiRenderer.renderHelpTable(),
        version: "shikki 0.3.0-pre",
        subcommands: [
            // New shikki stop with countdown
            ShikkiStopCommand.self,
            // Retained subcommands
            AgentReportsCommand.self,
            BacklogCommand.self,
            BoardCommand.self,
            DashboardCommand.self,
            DecideCommand.self,
            DecisionsCommand.self,
            InboxCommand.self,
            DoctorCommand.self,
            HeartbeatCommand.self,
            HistoryCommand.self,
            IngestCommand.self,
            LogCommand.self,
            MenuCommand.self,
            ObservatoryCommand.self,
            PauseCommand.self,
            PRCommand.self,
            // ReviewCommand.self, // TODO: rebase on top of PR #29 cleanup
            ReportCommand.self,
            CodirCommand.self,
            ContextCommand.self,
            FlywheelCommand.self,
            FocusCommand.self,
            RestartCommand.self,
            ScheduleCommand.self,
            UndoCommand.self,
            SearchCommand.self,
            ShipCommand.self,
            SpecCommand.self,
            StatusCommand.self,
            WakeCommand.self,
            WaveCommand.self,
            // Legacy: StartupCommand kept — ShikkiCommand delegates to it for layout creation
            // StopCommand kept — contains ShikkiCommandError used by StartupCommand
            // TODO: Extract layout logic to TmuxLayoutManager, then delete both
            StartupCommand.self,
            StopCommand.self,
        ]
    )

    // MARK: - Typo Correction (BR-41 to BR-44)

    /// Override main() to intercept unknown subcommands for typo correction.
    /// Note: ArgumentParser has built-in fuzzy matching for close matches (distance ~1).
    /// Our TypoCorrector adds hints for cases ArgumentParser can't auto-resolve.
    static func main() async {
        // BR-EM-01: Emoji pre-parser — rewrite emoji argv before ArgumentParser
        let rewrittenArgs = EmojiRouter.rewrite(CommandLine.arguments)
        do {
            var command = try parseAsRoot(rewrittenArgs.dropFirst().map { String($0) })
            if var asyncCommand = command as? AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
        } catch {
            // BR-41 to BR-44: Typo correction for unknown subcommands
            // Check if the first CLI arg looks like an unknown subcommand
            let args = Array(rewrittenArgs.dropFirst())
            if let firstArg = args.first,
               !firstArg.hasPrefix("-"),
               !Self.configuration.subcommands.contains(where: {
                   $0.configuration.commandName == firstArg
               }) {
                if let suggestion = TypoCorrector.suggest(firstArg) {
                    // BR-43: Never auto-execute stop (enforced by TypoCorrector)
                    print("Unknown command: '\(firstArg)'.")
                    print("  \u{1B}[2m↪ Did you mean `shikki \(suggestion.corrected)`?\u{1B}[0m")
                    _exit(1)
                }
            }

            // Default error handling
            Self.exit(withError: error)
        }
    }

    /// BR-08: No-args entry point. Detects state and acts.
    /// BR-09: IDLE + checkpoint → resume.
    /// BR-10: IDLE + no checkpoint → clean start.
    /// BR-11: Never prompts — deterministic dispatch.
    func run() async throws {
        let checkpointManager = CheckpointManager()
        let lockfileManager = LockfileManager()
        let dbSync = DBSyncClient()
        let detector = StateDetector()

        let engine = ShikkiEngine(
            detector: detector,
            checkpointManager: checkpointManager,
            lockfileManager: lockfileManager,
            dbSync: dbSync
        )

        // Run legacy migration on first invocation (BR-24)
        try checkpointManager.migrateLegacy()

        let action = try await engine.dispatch()

        switch action {
        case .startClean:
            // Acquire lockfile (BR-53)
            try lockfileManager.acquire()
            // Delegate to existing StartupCommand logic for now
            // (will be replaced by TmuxLayoutManager in PR C)
            var startup = try StartupCommand.parse([])
            try await startup.run()

        case .resume(let checkpoint):
            // BR-45: Show welcome back message
            WelcomeRenderer.render(checkpoint: checkpoint)

            // Acquire lockfile (BR-53)
            try lockfileManager.acquire()

            // Start session with checkpoint context
            // Pass context via environment or temp file for StartupCommand
            var startup = try StartupCommand.parse([])
            try await startup.run()

            // BR-23: Delete checkpoint after successful resume
            try engine.confirmResume()

        case .attach:
            // BR-08: Attach to existing tmux session
            let path = "/usr/bin/env"
            let args = ["env", "tmux", "attach-session", "-t", "shikki"]
            let cArgs = args.map { strdup($0) } + [nil]
            execv(path, cArgs)
            // Only reached if execv fails
            print("Failed to attach to shikki session. Is tmux running?")

        case .blocked:
            // BR-08: STOPPING → block
            print("Shikki is shutting down. Wait for stop to complete, or press Esc in the stop terminal.")
            throw ExitCode(1)
        }
    }
}
