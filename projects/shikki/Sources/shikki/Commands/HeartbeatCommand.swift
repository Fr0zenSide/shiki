import ArgumentParser
import ShikkiKit
import Foundation
import Logging

/// The orchestrator heartbeat loop — runs inside the tmux orchestrator tab.
/// This is an internal command; users run `shiki start` which launches this in tmux.
///
/// As of Wave 1, this launches ShikkiKernel which manages individual services
/// (HealthMonitor, DispatchService, SessionSupervisor) instead of running
/// HeartbeatLoop's monolithic tick directly.
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

    @Flag(name: .long, help: "Use legacy HeartbeatLoop instead of ShikkiKernel")
    var legacy: Bool = false

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

        let logger = Logger(label: "shikki.heartbeat-command")

        print("\u{1B}[1m\u{1B}[36mShiki Orchestrator\u{1B}[0m — heartbeat loop")
        print("  Backend:   \(url)")
        print("  Workspace: \(workspacePath)")
        print("  Interval:  \(interval)s")
        print("  Notify:    \(noNotify ? "disabled" : "ntfy")")
        print()

        // Legacy mode: run HeartbeatLoop directly (backward compat)
        if legacy {
            logger.info("Starting in legacy mode (HeartbeatLoop)")
            let loop = HeartbeatLoop(
                client: client,
                launcher: launcher,
                notifier: notifier,
                interval: .seconds(interval)
            )
            await loop.run()
            return
        }

        // Build the HeartbeatLoop (services delegate to it during transition)
        let loop = HeartbeatLoop(
            client: client,
            launcher: launcher,
            notifier: notifier,
            interval: .seconds(interval)
        )

        // Build managed services
        let registry = SessionRegistry(
            discoverer: TmuxDiscoverer(),
            journal: SessionJournal()
        )
        let snapshotProvider = BackendSnapshotProvider(client: client, registry: registry)

        let services: [any ManagedService] = [
            HealthMonitor(client: client),
            DispatchService(heartbeatLoop: loop),
            SessionSupervisor(heartbeatLoop: loop),
        ]

        let kernel = ShikkiKernel(
            services: services,
            snapshotProvider: snapshotProvider
        )

        logger.info("Starting ShikkiKernel with \(services.count) services")
        await kernel.run()
    }
}
