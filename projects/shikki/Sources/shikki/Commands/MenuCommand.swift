import ArgumentParser
import Foundation
import ShikkiKit

struct MenuCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "menu",
        abstract: "Show command grid for tmux display-popup"
    )

    func run() throws {
        print(MenuRenderer.renderGrid())

        // Read a single key from stdin (raw mode)
        guard let key = readSingleKey() else { return }

        // Esc or q → exit
        if key == "\u{1B}" || key == "q" { return }

        // Map key to command
        guard let command = MenuRenderer.commandForKey(key) else { return }

        // Execute the shiki subcommand via execv
        let shikiPath = resolveShikiBinary()
        execCommand(shikiPath, arguments: [shikiPath, command])
    }

    // MARK: - Terminal Helpers

    /// Read a single character in raw terminal mode.
    private func readSingleKey() -> String? {
        var oldTermios = termios()
        tcgetattr(STDIN_FILENO, &oldTermios)

        var raw = oldTermios
        raw.c_lflag &= ~(UInt(ECHO | ICANON))
        raw.c_cc.0 = 1  // VMIN — cannot subscript tuple by VMIN constant
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)

        defer { tcsetattr(STDIN_FILENO, TCSAFLUSH, &oldTermios) }

        var buf = [UInt8](repeating: 0, count: 4)
        let n = read(STDIN_FILENO, &buf, buf.count)
        guard n > 0 else { return nil }
        return String(bytes: buf[0..<n], encoding: .utf8)
    }

    /// Resolve the shiki binary path (same as the current process).
    private func resolveShikiBinary() -> String {
        let binaryPath = ProcessInfo.processInfo.arguments.first ?? "/usr/local/bin/shiki"
        return (binaryPath as NSString).resolvingSymlinksInPath
    }

    /// Replace the current process with a new command.
    private func execCommand(_ path: String, arguments: [String]) {
        let cArgs = arguments.map { strdup($0) } + [nil]
        defer { cArgs.forEach { free($0) } }
        execv(path, cArgs)
        // If execv returns, it failed
        fputs("Failed to exec: \(path)\n", stderr)
    }
}
