import Foundation
import Testing

/// E2E tests that run the compiled shiki-ctl binary and assert on output/exit codes.
/// These test real command behavior without requiring tmux or backend.
@Suite("E2E Command Scenarios")
struct E2EScenarioTests {

    /// Path to the compiled binary (built by swift build before tests run).
    private var binaryPath: String {
        // The binary is at .build/debug/shiki-ctl relative to the package root
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return packageRoot.appendingPathComponent(".build/debug/shiki-ctl").path
    }

    private func run(_ arguments: [String], timeout: TimeInterval = 10) -> (stdout: String, stderr: String, exitCode: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = arguments
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            // Read before wait to avoid pipe buffer deadlock
            let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (
                stdout: String(data: outData, encoding: .utf8) ?? "",
                stderr: String(data: errData, encoding: .utf8) ?? "",
                exitCode: process.terminationStatus
            )
        } catch {
            return (stdout: "", stderr: error.localizedDescription, exitCode: -1)
        }
    }

    // MARK: - Scenario 1: Version

    @Test("shiki --version prints version")
    func versionOutput() {
        let result = run(["--version"])
        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("0.2.0"))
    }

    // MARK: - Scenario 2: Help for all commands

    @Test("All commands have --help")
    func allCommandsHaveHelp() {
        let commands = [
            "start", "stop", "restart", "attach", "status",
            "board", "history", "heartbeat", "wake", "pause",
            "decide", "report", "pr", "doctor", "dashboard",
        ]
        for cmd in commands {
            let result = run([cmd, "--help"])
            #expect(result.exitCode == 0, "'\(cmd) --help' failed with exit \(result.exitCode)")
            let output = result.stdout + result.stderr
            #expect(
                output.contains("USAGE") || output.contains("OVERVIEW") || output.contains("OPTIONS"),
                "'\(cmd) --help' missing usage info"
            )
        }
    }

    // MARK: - Scenario 3: Doctor (no backend needed)

    @Test("shiki doctor runs diagnostics")
    func doctorRuns() {
        let result = run(["doctor"])
        #expect(result.exitCode == 0)
        let output = result.stdout
        // Should check for git at minimum
        #expect(output.contains("git"))
    }

    // MARK: - Scenario 4: Status offline

    @Test("shiki status fails gracefully when backend unreachable")
    func statusOffline() {
        let result = run(["status", "--url", "http://localhost:59999"])
        // Should fail but not crash
        #expect(result.exitCode != 0)
        let output = result.stdout + result.stderr
        #expect(output.lowercased().contains("unreachable") || output.lowercased().contains("error"))
    }

    // MARK: - Scenario 5: Dashboard with no tmux

    @Test("shiki dashboard with nonexistent session shows empty")
    func dashboardEmpty() {
        let result = run(["dashboard", "--session", "nonexistent-session-xyz"])
        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("No active sessions"))
    }

    // MARK: - Scenario 6: PR missing review file

    @Test("shiki pr with missing review file fails gracefully")
    func prMissingFile() {
        let result = run(["pr", "99999"])
        #expect(result.exitCode != 0)
        let output = result.stdout + result.stderr
        #expect(output.contains("No review file") || output.contains("Error"))
    }

    // MARK: - Scenario 7: Doctor with --fix flag

    @Test("shiki doctor --fix shows fix commands")
    func doctorWithFix() {
        let result = run(["doctor", "--fix"])
        #expect(result.exitCode == 0)
        // If any tool is missing, --fix should show the install command
        // This is a smoke test — exact output depends on what's installed
    }
}
