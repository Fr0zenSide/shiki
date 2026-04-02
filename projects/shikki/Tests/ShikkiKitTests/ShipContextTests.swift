import Foundation
import Testing
@testable import ShikkiKit

// MARK: - shellEscape Tests

@Suite("shellEscape")
struct ShellEscapeTests {

    @Test("Simple string wrapped in single quotes")
    func simpleString() {
        let result = shellEscape("hello")
        #expect(result == "'hello'")
    }

    @Test("String with single quote is escaped")
    func singleQuoteEscaped() {
        let result = shellEscape("it's")
        #expect(result == "'it'\\''s'")
    }

    @Test("String with multiple single quotes")
    func multipleSingleQuotes() {
        let result = shellEscape("it's a 'test'")
        #expect(result == "'it'\\''s a '\\''test'\\'''")
    }

    @Test("Empty string produces empty quotes")
    func emptyString() {
        let result = shellEscape("")
        #expect(result == "''")
    }

    @Test("String with spaces is safely quoted")
    func stringWithSpaces() {
        let result = shellEscape("hello world")
        #expect(result == "'hello world'")
    }

    @Test("String with special shell characters is safely quoted")
    func specialShellChars() {
        let result = shellEscape("$HOME && rm -rf /")
        #expect(result == "'$HOME && rm -rf /'")
    }

    @Test("Path with spaces")
    func pathWithSpaces() {
        let result = shellEscape("/Users/dev/My Project/file.swift")
        #expect(result == "'/Users/dev/My Project/file.swift'")
    }

    @Test("String with backticks")
    func backticks() {
        let result = shellEscape("`whoami`")
        #expect(result == "'`whoami`'")
    }

    @Test("String with newlines")
    func newlines() {
        let result = shellEscape("line1\nline2")
        #expect(result == "'line1\nline2'")
    }
}

// MARK: - ShellResult Tests

@Suite("ShellResult")
struct ShellResultTests {

    @Test("ShellResult stores all fields")
    func shellResultFields() {
        let result = ShellResult(stdout: "output", stderr: "error", exitCode: 1)
        #expect(result.stdout == "output")
        #expect(result.stderr == "error")
        #expect(result.exitCode == 1)
    }

    @Test("ShellResult with zero exit code")
    func successExitCode() {
        let result = ShellResult(stdout: "ok", stderr: "", exitCode: 0)
        #expect(result.exitCode == 0)
    }

    @Test("ShellResult with empty output")
    func emptyOutput() {
        let result = ShellResult(stdout: "", stderr: "", exitCode: 0)
        #expect(result.stdout.isEmpty)
        #expect(result.stderr.isEmpty)
    }
}

// MARK: - GateResult Tests

@Suite("GateResult")
struct GateResultTests {

    @Test("Pass with detail")
    func passWithDetail() {
        let result = GateResult.pass(detail: "All good")
        if case .pass(let detail) = result {
            #expect(detail == "All good")
        } else {
            Issue.record("Expected .pass")
        }
    }

    @Test("Pass with nil detail")
    func passNilDetail() {
        let result = GateResult.pass(detail: nil)
        if case .pass(let detail) = result {
            #expect(detail == nil)
        } else {
            Issue.record("Expected .pass")
        }
    }

    @Test("Warn with reason")
    func warnWithReason() {
        let result = GateResult.warn(reason: "Consider fixing")
        if case .warn(let reason) = result {
            #expect(reason == "Consider fixing")
        } else {
            Issue.record("Expected .warn")
        }
    }

    @Test("Fail with reason")
    func failWithReason() {
        let result = GateResult.fail(reason: "Tests broken")
        if case .fail(let reason) = result {
            #expect(reason == "Tests broken")
        } else {
            Issue.record("Expected .fail")
        }
    }
}

// MARK: - RealShipContext Tests

@Suite("RealShipContext")
struct RealShipContextTests {

    @Test("Properties are set correctly")
    func propertiesSet() {
        let ctx = RealShipContext(
            branch: "feature/test",
            target: "develop",
            projectRoot: URL(fileURLWithPath: "/tmp/project")
        )
        #expect(ctx.branch == "feature/test")
        #expect(ctx.target == "develop")
        #expect(ctx.projectRoot.path == "/tmp/project")
        #expect(ctx.isDryRun == false)
    }

    @Test("Shell executes echo command")
    func shellExecutesEcho() async throws {
        let ctx = RealShipContext(
            branch: "test",
            target: "develop",
            projectRoot: URL(fileURLWithPath: NSTemporaryDirectory())
        )
        let result = try await ctx.shell("echo 'hello world'")
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "hello world")
        #expect(result.exitCode == 0)
    }

    @Test("Shell captures stdout and stderr separately")
    func shellCapturesStreams() async throws {
        let ctx = RealShipContext(
            branch: "test",
            target: "develop",
            projectRoot: URL(fileURLWithPath: NSTemporaryDirectory())
        )
        let result = try await ctx.shell("echo 'out' && echo 'err' >&2")
        #expect(result.stdout.contains("out"))
        #expect(result.stderr.contains("err"))
        #expect(result.exitCode == 0)
    }

    @Test("Shell returns non-zero exit code for failing command")
    func shellNonZeroExitCode() async throws {
        let ctx = RealShipContext(
            branch: "test",
            target: "develop",
            projectRoot: URL(fileURLWithPath: NSTemporaryDirectory())
        )
        let result = try await ctx.shell("exit 42")
        #expect(result.exitCode == 42)
    }

    @Test("Shell runs in project root directory")
    func shellRunsInProjectRoot() async throws {
        let tempDir = NSTemporaryDirectory() + "ship-ctx-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let ctx = RealShipContext(
            branch: "test",
            target: "develop",
            projectRoot: URL(fileURLWithPath: tempDir)
        )
        let result = try await ctx.shell("pwd")
        let pwd = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        // Resolve symlinks for comparison (macOS /tmp -> /private/tmp)
        let resolvedPwd = URL(fileURLWithPath: pwd).resolvingSymlinksInPath().path
        let resolvedTempDir = URL(fileURLWithPath: tempDir).resolvingSymlinksInPath().path
        #expect(resolvedPwd == resolvedTempDir)
    }
}

// MARK: - DryRunShipContext Tests

@Suite("DryRunShipContext")
struct DryRunShipContextTests {

    @Test("isDryRun is true")
    func isDryRunTrue() async {
        let ctx = DryRunShipContext(
            branch: "test",
            target: "develop",
            projectRoot: URL(fileURLWithPath: "/tmp")
        )
        #expect(await ctx.isDryRun == true)
    }

    @Test("Properties are stored correctly")
    func propertiesStored() async {
        let ctx = DryRunShipContext(
            branch: "feature/x",
            target: "develop",
            projectRoot: URL(fileURLWithPath: "/tmp/project")
        )
        #expect(await ctx.branch == "feature/x")
        #expect(await ctx.target == "develop")
        #expect(await ctx.projectRoot.path == "/tmp/project")
    }

    @Test("Shell captures commands without executing")
    func shellCapturesWithoutExecuting() async throws {
        let ctx = DryRunShipContext(
            branch: "test",
            target: "develop",
            projectRoot: URL(fileURLWithPath: "/tmp")
        )
        let _ = try await ctx.shell("rm -rf /")
        let _ = try await ctx.shell("git push --force")
        let _ = try await ctx.shell("swift test")

        let commands = await ctx.capturedCommands
        #expect(commands.count == 3)
        #expect(commands[0] == "rm -rf /")
        #expect(commands[1] == "git push --force")
        #expect(commands[2] == "swift test")
    }

    @Test("Shell returns empty successful result")
    func shellReturnsEmptySuccess() async throws {
        let ctx = DryRunShipContext(
            branch: "test",
            target: "develop",
            projectRoot: URL(fileURLWithPath: "/tmp")
        )
        let result = try await ctx.shell("any command")
        #expect(result.stdout == "")
        #expect(result.stderr == "")
        #expect(result.exitCode == 0)
    }

    @Test("Captured commands accumulate in order")
    func commandsAccumulateInOrder() async throws {
        let ctx = DryRunShipContext(
            branch: "test",
            target: "develop",
            projectRoot: URL(fileURLWithPath: "/tmp")
        )
        for i in 0..<5 {
            let _ = try await ctx.shell("command-\(i)")
        }
        let commands = await ctx.capturedCommands
        #expect(commands == ["command-0", "command-1", "command-2", "command-3", "command-4"])
    }

    @Test("Initially no captured commands")
    func initiallyEmpty() async {
        let ctx = DryRunShipContext(
            branch: "test",
            target: "develop",
            projectRoot: URL(fileURLWithPath: "/tmp")
        )
        let commands = await ctx.capturedCommands
        #expect(commands.isEmpty)
    }
}

// MARK: - ShipResult Tests

@Suite("ShipResult")
struct ShipResultTests {

    @Test("Successful result")
    func successfulResult() {
        let result = ShipResult(success: true)
        #expect(result.success)
        #expect(result.failedGate == nil)
        #expect(result.failureReason == nil)
        #expect(result.warnings.isEmpty)
    }

    @Test("Failed result with gate info")
    func failedResult() {
        let result = ShipResult(
            success: false,
            failedGate: "TestGate",
            failureReason: "3 tests failed"
        )
        #expect(!result.success)
        #expect(result.failedGate == "TestGate")
        #expect(result.failureReason == "3 tests failed")
    }

    @Test("Result with warnings")
    func resultWithWarnings() {
        let result = ShipResult(
            success: true,
            warnings: ["No linter found", "2 TODO markers"]
        )
        #expect(result.success)
        #expect(result.warnings.count == 2)
    }
}
