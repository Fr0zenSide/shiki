import ArgumentParser

@main
struct ShikiCtl: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "shiki",
        abstract: "Shiki orchestrator — launch, monitor, and control your multi-project system",
        version: "0.2.0",
        subcommands: [
            StartupCommand.self,
            StopCommand.self,
            RestartCommand.self,
            AttachCommand.self,
            StatusCommand.self,
            BoardCommand.self,
            HistoryCommand.self,
            HeartbeatCommand.self,
            WakeCommand.self,
            PauseCommand.self,
            DecideCommand.self,
            ReportCommand.self,
            PRCommand.self,
            DoctorCommand.self,
            DashboardCommand.self,
        ]
    )
}
