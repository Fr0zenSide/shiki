import Foundation
import Testing
@testable import ShikkiKit

// MARK: - CleanBranchGate Tests

@Suite("Ship Gate -- CleanBranch")
struct CleanBranchGateTests {

    @Test("Dirty working tree fails")
    func dirtyWorkingTreeFails() async throws {
        let ctx = MockShipContext()
        await ctx.stubShell("git status --porcelain", result: ShellResult(
            stdout: " M src/main.swift\n?? src/new.swift\n",
            stderr: "",
            exitCode: 0
        ))

        let gate = CleanBranchGate()
        let result = try await gate.evaluate(context: ctx)

        guard case .fail(let reason) = result else {
            Issue.record("Expected .fail, got \(result)")
            return
        }
        #expect(reason.contains("dirty") || reason.contains("uncommitted") || reason.contains("clean"))
    }

    @Test("Clean tree passes")
    func cleanTreePasses() async throws {
        let ctx = MockShipContext()
        await ctx.stubShell("git status --porcelain", result: ShellResult(
            stdout: "",
            stderr: "",
            exitCode: 0
        ))

        let gate = CleanBranchGate()
        let result = try await gate.evaluate(context: ctx)

        guard case .pass = result else {
            Issue.record("Expected .pass, got \(result)")
            return
        }
    }
}

// MARK: - TestGate Tests

@Suite("Ship Gate -- Test")
struct TestGateTests {

    @Test("Tests pass returns pass")
    func testsPassPasses() async throws {
        let ctx = MockShipContext()
        await ctx.stubShell("swift test", result: ShellResult(
            stdout: "Test Suite 'All tests' passed.\nExecuted 42 tests, with 0 failures",
            stderr: "",
            exitCode: 0
        ))

        let gate = TestGate()
        let result = try await gate.evaluate(context: ctx)

        guard case .pass = result else {
            Issue.record("Expected .pass, got \(result)")
            return
        }
    }

    @Test("Tests fail returns hard fail")
    func testsFailFailsHard() async throws {
        let ctx = MockShipContext()
        await ctx.stubShell("swift test", result: ShellResult(
            stdout: "Test Suite 'All tests' failed.\nExecuted 42 tests, with 3 failures",
            stderr: "",
            exitCode: 1
        ))

        let gate = TestGate()
        let result = try await gate.evaluate(context: ctx)

        guard case .fail(let reason) = result else {
            Issue.record("Expected .fail, got \(result)")
            return
        }
        #expect(reason.lowercased().contains("fail") || reason.contains("test"))
    }
}

// MARK: - LintGate Tests

@Suite("Ship Gate -- Lint")
struct LintGateTests {

    @Test("No linter available warns and skips")
    func noLinterAvailableWarns() async throws {
        let ctx = MockShipContext()
        await ctx.stubShell("which swiftlint", result: ShellResult(
            stdout: "", stderr: "", exitCode: 1
        ))

        let gate = LintGate()
        let result = try await gate.evaluate(context: ctx)

        guard case .warn(let reason) = result else {
            Issue.record("Expected .warn, got \(result)")
            return
        }
        #expect(reason.lowercased().contains("no linter") || reason.lowercased().contains("skipped"))
    }

    @Test("Lint errors cause failure")
    func lintErrorsCauseFail() async throws {
        let ctx = MockShipContext()
        await ctx.stubShell("which swiftlint", result: ShellResult(
            stdout: "/usr/local/bin/swiftlint", stderr: "", exitCode: 0
        ))
        await ctx.stubShell("swiftlint lint", result: ShellResult(
            stdout: "file.swift:10:1: error: trailing whitespace\nfile.swift:20:1: error: line length",
            stderr: "",
            exitCode: 2
        ))

        let gate = LintGate()
        let result = try await gate.evaluate(context: ctx)

        guard case .fail(let reason) = result else {
            Issue.record("Expected .fail, got \(result)")
            return
        }
        #expect(reason.contains("2 lint errors"))
    }
}

// MARK: - BuildGate Tests

@Suite("Ship Gate -- Build")
struct BuildGateTests {

    @Test("Build success passes")
    func buildSuccessPasses() async throws {
        let ctx = MockShipContext()
        await ctx.stubShell("swift build", result: ShellResult(
            stdout: "Build complete!", stderr: "", exitCode: 0
        ))

        let gate = BuildGate()
        let result = try await gate.evaluate(context: ctx)

        guard case .pass(let detail) = result else {
            Issue.record("Expected .pass, got \(result)")
            return
        }
        #expect(detail?.lowercased().contains("release") == true || detail?.lowercased().contains("build") == true)
    }

    @Test("Build failure fails hard")
    func buildFailureFails() async throws {
        let ctx = MockShipContext()
        await ctx.stubShell("swift build", result: ShellResult(
            stdout: "", stderr: "error: cannot find module", exitCode: 1
        ))

        let gate = BuildGate()
        let result = try await gate.evaluate(context: ctx)

        guard case .fail = result else {
            Issue.record("Expected .fail, got \(result)")
            return
        }
    }
}

// MARK: - ChangelogGate Tests

@Suite("Ship Gate -- Changelog")
struct ChangelogGateTests {

    @Test("Generates changelog from conventional commits")
    func generatesChangelog() async throws {
        let ctx = MockShipContext()
        await ctx.stubShell("git describe", result: ShellResult(
            stdout: "v1.0.0", stderr: "", exitCode: 0
        ))
        await ctx.stubShell("git log", result: ShellResult(
            stdout: "feat: add splash screen\nfix: typo in readme\n",
            stderr: "", exitCode: 0
        ))

        let gate = ChangelogGate()
        let result = try await gate.evaluate(context: ctx)

        guard case .pass(let detail) = result else {
            Issue.record("Expected .pass, got \(result)")
            return
        }
        #expect(detail?.contains("2 commits") == true)
    }

    @Test("No commits warns")
    func noCommitsWarns() async throws {
        let ctx = MockShipContext()
        await ctx.stubShell("git describe", result: ShellResult(
            stdout: "v1.0.0", stderr: "", exitCode: 0
        ))
        await ctx.stubShell("git log", result: ShellResult(
            stdout: "", stderr: "", exitCode: 0
        ))

        let gate = ChangelogGate()
        let result = try await gate.evaluate(context: ctx)

        guard case .warn(let reason) = result else {
            Issue.record("Expected .warn, got \(result)")
            return
        }
        #expect(reason.contains("No commits"))
    }
}

// MARK: - VersionBumpGate Tests

@Suite("Ship Gate -- VersionBump")
struct VersionBumpGateTests {

    @Test("Delegates to VersionBumper")
    func delegatesToBumper() async throws {
        let ctx = MockShipContext()
        await ctx.stubShell("git describe", result: ShellResult(
            stdout: "v1.0.0", stderr: "", exitCode: 0
        ))
        await ctx.stubShell("git log", result: ShellResult(
            stdout: "feat: add ship command\nfix: typo\n", stderr: "", exitCode: 0
        ))

        let gate = VersionBumpGate()
        let result = try await gate.evaluate(context: ctx)

        guard case .pass(let detail) = result else {
            Issue.record("Expected .pass, got \(result)")
            return
        }
        #expect(detail?.contains("1.1.0") == true)
    }
}

// MARK: - TagGate Tests

@Suite("Ship Gate -- Tag")
struct TagGateTests {

    @Test("Dry run does not create tag")
    func dryRunNoTag() async throws {
        let ctx = MockShipContext(isDryRun: true)
        await ctx.stubShell("git describe", result: ShellResult(
            stdout: "v1.0.0", stderr: "", exitCode: 0
        ))
        await ctx.stubShell("git log", result: ShellResult(
            stdout: "fix: typo\n", stderr: "", exitCode: 0
        ))

        let gate = TagGate()
        let result = try await gate.evaluate(context: ctx)

        guard case .pass(let detail) = result else {
            Issue.record("Expected .pass, got \(result)")
            return
        }
        #expect(detail?.contains("dry-run") == true)
    }
}

// MARK: - PushGate Tests

@Suite("Ship Gate -- Push")
struct PushGateTests {

    @Test("Target main rejects with error")
    func targetMainRejects() async throws {
        let ctx = MockShipContext(target: "main")
        let gate = PushGate()

        let result = try await gate.evaluate(context: ctx)

        guard case .fail(let reason) = result else {
            Issue.record("Expected .fail, got \(result)")
            return
        }
        #expect(reason.contains("main") || reason.contains("git flow") || reason.contains("develop"))
    }

    @Test("Target develop in dry-run passes")
    func targetDevelopDryRunPasses() async throws {
        let ctx = MockShipContext(isDryRun: true, target: "develop")
        let gate = PushGate()

        let result = try await gate.evaluate(context: ctx)

        guard case .pass(let detail) = result else {
            Issue.record("Expected .pass, got \(result)")
            return
        }
        #expect(detail?.contains("dry-run") == true)
    }

    @Test("Invalid branch name rejected")
    func invalidBranchNameRejected() async throws {
        let ctx = MockShipContext(branch: "feature/test; rm -rf /")
        let gate = PushGate()

        let result = try await gate.evaluate(context: ctx)

        guard case .fail(let reason) = result else {
            Issue.record("Expected .fail, got \(result)")
            return
        }
        #expect(reason.contains("Invalid"))
    }
}
