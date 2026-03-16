import ArgumentParser
import Foundation

struct AttachCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "attach",
        abstract: "Attach to the running Shiki tmux session"
    )

    @Option(name: .long, help: "Tmux session name (defaults to workspace folder name)")
    var session: String = "shiki"

    func run() async throws {
        guard tmuxSessionExists(session) else {
            print("No session running. Run: shiki start")
            throw ExitCode(1)
        }

        // Replace current process with tmux attach
        let path = "/usr/bin/env"
        let args = ["env", "tmux", "attach-session", "-t", session]
        let cArgs = args.map { strdup($0) } + [nil]
        execv(path, cArgs)

        // If execv returns, it failed
        print("\u{1B}[31mFailed to attach to tmux session\u{1B}[0m")
        throw ExitCode(1)
    }

    private func tmuxSessionExists(_ name: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["tmux", "has-session", "-t", name]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
