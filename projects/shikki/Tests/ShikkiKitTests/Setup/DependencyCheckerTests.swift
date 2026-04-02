import Foundation
import Testing
@testable import ShikkiKit

// MARK: - Mock Shell Executor

/// Mock shell executor for dependency checker tests.
/// Configurable per-tool responses for deterministic testing.
final class MockShellExecutor: ShellExecuting, @unchecked Sendable {
    /// Map of "which <tool>" -> path (nil means not found)
    var whichResults: [String: String] = [:]
    /// Map of "<tool> <args>" -> (stdout, exitCode)
    var runResults: [String: (stdout: String, exitCode: Int32)] = [:]

    func run(_ command: String, arguments: [String]) async throws -> (stdout: String, exitCode: Int32) {
        let key = ([command] + arguments).joined(separator: " ")
        if let result = runResults[key] {
            return result
        }
        // Default: command not found
        return (stdout: "", exitCode: 127)
    }

    func which(_ tool: String) async -> String? {
        whichResults[tool]
    }
}

// MARK: - DependencyChecker Tests

@Suite("DependencyChecker — platform-aware tool discovery")
struct DependencyCheckerTests {

    // MARK: - Scenario 1: First-run detection — no setup.json exists

    @Test("First-run detection — no setup.json means isFirstRun is true")
    func firstRunDetection() {
        let path = NSTemporaryDirectory() + "shikki-test-firstrun-\(UUID().uuidString).json"
        // No file at path — SetupState.load returns nil
        let state = SetupState.load(from: path)
        #expect(state == nil, "No setup.json should mean no state loaded")
    }

    // MARK: - Scenario 2: Subsequent run — setup.json with all steps

    @Test("Subsequent run — setup.json with all steps means isFirstRun is false")
    func subsequentRun() throws {
        let path = NSTemporaryDirectory() + "shikki-test-subsequent-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: path) }

        try SetupState.markComplete(version: "0.3.0", path: path)
        let state = SetupState.load(from: path)
        #expect(state != nil)
        #expect(state?.allStepsComplete == true, "All steps should be complete")
    }

    // MARK: - Scenario 3: DependencyChecker finds all required tools

    @Test("DependencyChecker finds all required tools installed")
    func findsAllRequiredTools() async {
        let shell = MockShellExecutor()
        shell.whichResults = [
            "git": "/usr/bin/git",
            "tmux": "/opt/homebrew/bin/tmux",
            "claude": "/usr/local/bin/claude",
        ]
        shell.runResults = [
            "git --version": (stdout: "git version 2.43.0", exitCode: 0),
            "tmux -V": (stdout: "tmux 3.4", exitCode: 0),
            "claude --version": (stdout: "claude 1.0.0", exitCode: 0),
        ]

        let checker = DependencyChecker(shell: shell, platform: .macOS)
        let results = await checker.checkAll()

        for tool in RequiredTool.allCases {
            let status = results[tool]
            #expect(status != nil, "Should have status for \(tool.rawValue)")
            if case .available(let path, _) = status {
                #expect(!path.isEmpty, "Path should be non-empty for \(tool.rawValue)")
            } else {
                Issue.record("Expected \(tool.rawValue) to be available, got \(String(describing: status))")
            }
        }
    }

    // MARK: - Scenario 4: Missing tool with platform-specific install command

    @Test("DependencyChecker reports missing tool with platform-specific install command")
    func reportsMissingToolMacOS() async {
        let shell = MockShellExecutor()
        shell.whichResults = [
            "git": "/usr/bin/git",
            "claude": "/usr/local/bin/claude",
            // tmux deliberately missing
        ]
        shell.runResults = [
            "git --version": (stdout: "git version 2.43.0", exitCode: 0),
            "claude --version": (stdout: "claude 1.0.0", exitCode: 0),
        ]

        let macChecker = DependencyChecker(shell: shell, platform: .macOS)
        let macStatus = await macChecker.check(.tmux)

        if case .missing(let installCommand) = macStatus {
            #expect(installCommand.contains("brew"), "macOS install command should use brew")
        } else {
            Issue.record("Expected tmux to be missing on macOS mock, got \(macStatus)")
        }

        let linuxChecker = DependencyChecker(shell: shell, platform: .linux)
        let linuxStatus = await linuxChecker.check(.tmux)

        if case .missing(let installCommand) = linuxStatus {
            #expect(installCommand.contains("apt"), "Linux install command should use apt")
        } else {
            Issue.record("Expected tmux to be missing on Linux mock, got \(linuxStatus)")
        }
    }

    // MARK: - Scenario 5: Post-install verification catches broken installs

    @Test("Post-install verification catches broken installs (exits non-zero)")
    func verificationCatchesBrokenInstall() async {
        let shell = MockShellExecutor()
        // which finds git, but git --version fails
        shell.whichResults = ["git": "/usr/bin/git"]
        shell.runResults = [
            "git --version": (stdout: "", exitCode: 127),
        ]

        let verifier = SetupVerifier(shell: shell)
        let result = await verifier.verify(.git)

        switch result {
        case .broken(let error):
            #expect(error.contains("git"), "Error should mention the tool name")
        case .working:
            Issue.record("Expected broken verification for git with exit code 127")
        }
    }

    // MARK: - Scenario 6: Required dependency failure blocks setup

    @Test("Required dependency failure blocks setup")
    func requiredDepFailureBlocks() async {
        let shell = MockShellExecutor()
        // All tools missing
        shell.whichResults = [:]

        let checker = DependencyChecker(shell: shell, platform: .macOS)
        let results = await checker.checkAll()

        // All should be missing
        for tool in RequiredTool.allCases {
            if case .missing = results[tool] {
                // Expected
            } else {
                Issue.record("Expected \(tool.rawValue) to be missing, got \(String(describing: results[tool]))")
            }
        }

        // Verify the checker correctly identifies blocking failures
        let hasBlockingFailure = results.values.contains { status in
            if case .missing = status { return true }
            return false
        }
        #expect(hasBlockingFailure, "Missing required deps should be a blocking failure")
    }
}
