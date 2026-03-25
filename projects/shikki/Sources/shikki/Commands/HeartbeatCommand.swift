import ArgumentParser
import ShikkiKit
import Foundation

/// The orchestrator heartbeat loop — runs inside the tmux orchestrator tab.
/// This is an internal command; users run `shiki start` which launches this in tmux.
struct HeartbeatCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "heartbeat",
        abstract: "Run the orchestrator heartbeat loop (internal — launched by 'start')"
    )

    @Option(name: .long, help: "Loop interval in seconds")
    var interval: Int = 60

    @Option(name: .long, help: "Backend URL")
    var url: String = "http://localhost:3900"

    @Option(name: .long, help: "Workspace root path")
    var workspace: String = "."

    @Option(name: .long, help: "Tmux session name")
    var session: String = "shiki"

    @Flag(name: .long, help: "Disable push notifications")
    var noNotify: Bool = false

    func run() async throws {
        let workspacePath: String
        if workspace == "." {
            workspacePath = FileManager.default.currentDirectoryPath
        } else {
            workspacePath = workspace
        }

        let client = BackendClient(baseURL: url)
        let launcher = TmuxProcessLauncher(session: session, workspacePath: workspacePath)
        let notifier: NotificationSender = noNotify ? NoOpNotificationSender() : NtfyNotificationSender()

        print("\u{1B}[1m\u{1B}[36mShiki Orchestrator\u{1B}[0m — heartbeat loop")
        print("  Backend:   \(url)")
        print("  Workspace: \(workspacePath)")
        print("  Interval:  \(interval)s")
        print("  Notify:    \(noNotify ? "disabled" : "ntfy")")
        print()

        let loop = HeartbeatLoop(
            client: client,
            launcher: launcher,
            notifier: notifier,
            interval: .seconds(interval)
        )

        await loop.run()
    }
}
