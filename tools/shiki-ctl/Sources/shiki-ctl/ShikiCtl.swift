import ArgumentParser

@main
struct ShikiCtl: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "shiki-ctl",
        abstract: "Shiki orchestrator control plane",
        version: "0.1.0",
        subcommands: [
            StartCommand.self,
            StatusCommand.self,
            BoardCommand.self,
            HistoryCommand.self,
            WakeCommand.self,
            PauseCommand.self,
            DecideCommand.self,
            ReportCommand.self,
        ]
    )
}
