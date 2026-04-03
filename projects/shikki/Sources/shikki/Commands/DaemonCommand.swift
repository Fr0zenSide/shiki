import ArgumentParser
import Foundation
import ShikkiKit

// MARK: - DaemonCommand

/// Run Shikki kernel as a headless daemon.
///
/// Persistent mode (default): full service set — NATS, health, events,
/// sessions, stale detection, scheduled tasks. Runs until SIGTERM/SIGINT.
///
/// Scheduled mode: lightweight — only task scheduler and stale detector.
/// Suitable for cron-triggered invocations.
struct DaemonCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "daemon",
        abstract: "Run Shikki kernel as a headless daemon"
    )

    @Option(name: .long, help: "Daemon mode: persistent (default) or scheduled")
    var mode: String = "persistent"

    @Option(name: .long, help: "Backend URL")
    var url: String = "http://localhost:3900"

    @Flag(name: .long, help: "Run in background (fork) [not yet implemented]")
    var background: Bool = false

    @Flag(name: .long, help: "Install as system service (launchd/systemd) [not yet implemented]")
    var install: Bool = false

    @Flag(name: .long, help: "Uninstall system service [not yet implemented]")
    var uninstall: Bool = false

    func run() async throws {
        // Wave 1: --install, --uninstall, --background are stubs
        if install {
            print("Error: --install is not yet implemented (Wave 2)")
            throw ExitCode.failure
        }
        if uninstall {
            print("Error: --uninstall is not yet implemented (Wave 2)")
            throw ExitCode.failure
        }
        if background {
            print("Error: --background is not yet implemented (Wave 2)")
            throw ExitCode.failure
        }

        let pidManager = DaemonPIDManager()

        // Check not already running
        if pidManager.isRunning() {
            let pid = pidManager.readPID() ?? 0
            print("Daemon already running (PID: \(pid))")
            throw ExitCode.failure
        }

        // Clean stale PID if needed
        _ = pidManager.cleanStale()

        // Acquire PID
        try pidManager.acquire()

        // Register signal handler for clean shutdown
        let shutdownRequested = installDaemonSignalHandlers(pidManager: pidManager)

        // Create services based on mode
        let config = DaemonConfig(backendURL: url)
        let services: [any ManagedService]
        if mode == "scheduled" {
            services = DaemonServiceFactory.createScheduledServices(config: config)
        } else {
            services = DaemonServiceFactory.createPersistentServices(config: config)
        }

        // Create kernel and run
        let client = BackendClient(baseURL: url)
        let snapshotProvider = DaemonSnapshotProvider(client: client)
        let kernel = ShikkiKernel(
            services: services,
            snapshotProvider: snapshotProvider
        )

        let pid = ProcessInfo.processInfo.processIdentifier
        print("Daemon started (PID: \(pid), mode: \(mode), services: \(services.count))")

        // Run until cancelled or signal received
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await kernel.run()
            }
            group.addTask {
                // Wait for shutdown signal
                for await _ in shutdownRequested {
                    await kernel.shutdown()
                    break
                }
            }

            // Wait for kernel to finish
            await group.next()
            group.cancelAll()
        }

        // Clean up on exit
        pidManager.release()
        print("Daemon stopped")
    }
}

// MARK: - Signal Handling

/// Install SIGTERM and SIGINT handlers for clean daemon shutdown.
/// Returns an AsyncStream that yields when a termination signal is received.
private func installDaemonSignalHandlers(pidManager: DaemonPIDManager) -> AsyncStream<Void> {
    AsyncStream { continuation in
        // Use DispatchSource for signal handling (reliable, no C callback limitations)
        let sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)

        // Ignore default signal handling so DispatchSource receives them
        signal(SIGTERM, SIG_IGN)
        signal(SIGINT, SIG_IGN)

        sigterm.setEventHandler {
            pidManager.release()
            continuation.yield()
            continuation.finish()
        }
        sigint.setEventHandler {
            pidManager.release()
            continuation.yield()
            continuation.finish()
        }

        sigterm.resume()
        sigint.resume()

        continuation.onTermination = { @Sendable _ in
            sigterm.cancel()
            sigint.cancel()
        }
    }
}
