import ArgumentParser
import Darwin
import Foundation
import ShikkiKit

/// Stop the running Shikki daemon process.
///
/// Sends SIGTERM for graceful shutdown, waits up to 10 seconds,
/// then escalates to SIGKILL if the process does not exit.
struct DaemonStopCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "daemon-stop",
        abstract: "Stop the running Shikki daemon"
    )

    @Option(name: .long, help: "Path to the daemon PID file")
    var pidFile: String?

    func run() async throws {
        let pidManager = DaemonPIDManager(pidPath: pidFile)

        guard let pid = pidManager.readPID() else {
            print("Daemon not running (no PID file)")
            return
        }

        guard pidManager.isRunning() else {
            print("Stale PID file (process \(pid) dead), cleaning up")
            pidManager.cleanStale()
            return
        }

        // Graceful shutdown
        print("Stopping daemon (PID: \(pid))...")
        Darwin.kill(pid, SIGTERM)

        // Wait up to 10 seconds (100 x 100ms)
        for _ in 0..<100 {
            try await Task.sleep(for: .milliseconds(100))
            if !pidManager.isRunning() {
                print("Daemon stopped (PID: \(pid))")
                return
            }
        }

        // Escalate to SIGKILL
        print("Daemon didn't stop gracefully, sending SIGKILL...")
        Darwin.kill(pid, SIGKILL)
        try await Task.sleep(for: .milliseconds(500))
        pidManager.cleanStale()
        print("Daemon killed (PID: \(pid))")
    }
}
