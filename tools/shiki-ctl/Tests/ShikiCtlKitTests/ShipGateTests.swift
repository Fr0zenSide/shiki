import Foundation
import Testing
@testable import ShikiCtlKit

// MARK: - Mock ShipContext

/// Mock context for testing gates without shell side effects.
actor MockShipContext: ShipContext {
    let isDryRun: Bool
    let branch: String
    let target: String
    let projectRoot: URL
    private var _shellResponses: [String: ShellResult] = [:]
    private var _emittedEvents: [ShikiEvent] = []
    private var _shellCalls: [String] = []

    var emittedEvents: [ShikiEvent] {
        _emittedEvents
    }

    var shellCalls: [String] {
        _shellCalls
    }

    init(
        isDryRun: Bool = false,
        branch: String = "feature/test",
        target: String = "develop",
        projectRoot: URL = URL(fileURLWithPath: "/tmp/test-project")
    ) {
        self.isDryRun = isDryRun
        self.branch = branch
        self.target = target
        self.projectRoot = projectRoot
    }

    func stubShell(_ command: String, result: ShellResult) {
        _shellResponses[command] = result
    }

    func shell(_ command: String) async throws -> ShellResult {
        _shellCalls.append(command)
        let result = _shellResponses.first(where: { command.contains($0.key) })?.value
            ?? ShellResult(stdout: "", stderr: "", exitCode: 0)
        return result
    }

    func emit(_ event: ShikiEvent) async {
        _emittedEvents.append(event)
    }
}

// MARK: - CleanBranchGate Tests

@Suite("Ship Gate — CleanBranch")
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

@Suite("Ship Gate — Test")
struct TestGateTests {

    @Test("Tests pass returns pass")
    func testsPassPasses() async throws {
        let ctx = MockShipContext()
        await ctx.stubShell("swift test", result: ShellResult(
            stdout: "Test Suite 'All tests' passed at 2026-03-19.\nExecuted 42 tests, with 0 failures",
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
            stdout: "Test Suite 'All tests' failed at 2026-03-19.\nExecuted 42 tests, with 3 failures",
            stderr: "",
            exitCode: 1
        ))

        let gate = TestGate()
        let result = try await gate.evaluate(context: ctx)

        guard case .fail(let reason) = result else {
            Issue.record("Expected .fail, got \(result)")
            return
        }
        #expect(reason.contains("fail") || reason.contains("test"))
    }
}

// MARK: - CoverageGate Tests

@Suite("Ship Gate — Coverage")
struct CoverageGateTests {

    @Test("Above threshold passes")
    func aboveThresholdPasses() async throws {
        let ctx = MockShipContext()
        // CoverageGate with no injected currentCoverage will try to run shell command
        // which returns empty in mock -> "coverage unavailable" -> pass
        // Instead, inject coverage directly
        let gate = CoverageGate(threshold: 80.0, currentCoverage: 90.0, previousCoverage: 85.0)

        let result = try await gate.evaluate(context: ctx)

        guard case .pass = result else {
            Issue.record("Expected .pass, got \(result)")
            return
        }
    }

    @Test("Below threshold warns but passes")
    func belowThresholdWarns() async throws {
        let ctx = MockShipContext()
        let gate = CoverageGate(threshold: 80.0, currentCoverage: 75.0, previousCoverage: 76.0)

        let result = try await gate.evaluate(context: ctx)

        guard case .warn(let reason) = result else {
            Issue.record("Expected .warn, got \(result)")
            return
        }
        #expect(reason.contains("75") || reason.contains("below") || reason.contains("coverage"))
    }

    @Test("Drop more than 5% emits risk warning")
    func dropMoreThan5PercentEmitsRisk() async throws {
        let ctx = MockShipContext()
        let gate = CoverageGate(threshold: 80.0, currentCoverage: 82.0, previousCoverage: 90.0)

        let result = try await gate.evaluate(context: ctx)

        guard case .warn(let reason) = result else {
            Issue.record("Expected .warn, got \(result)")
            return
        }
        #expect(reason.contains("drop") || reason.contains("decrease") || reason.lowercased().contains("risk"))
    }
}

// MARK: - RiskGate Tests

@Suite("Ship Gate — Risk")
struct RiskGateTests {

    @Test("Risk gate always passes with informational score")
    func riskGateAlwaysPasses() async throws {
        let ctx = MockShipContext()
        await ctx.stubShell("git diff --stat", result: ShellResult(
            stdout: " src/main.swift | 10 +++++++---\n src/lib.swift  | 5 +++++\n 2 files changed, 12 insertions(+), 3 deletions(-)\n",
            stderr: "",
            exitCode: 0
        ))

        let gate = RiskGate()
        let result = try await gate.evaluate(context: ctx)

        guard case .pass(let detail) = result else {
            Issue.record("Expected .pass, got \(result)")
            return
        }
        #expect(detail != nil)
    }
}

// MARK: - PRGate Tests

@Suite("Ship Gate — PR")
struct PRGateTests {

    @Test("Target main rejects with error")
    func targetMainRejects() async throws {
        let ctx = MockShipContext(target: "main")
        let gate = PRGate()

        let result = try await gate.evaluate(context: ctx)

        guard case .fail(let reason) = result else {
            Issue.record("Expected .fail, got \(result)")
            return
        }
        #expect(reason.contains("main") || reason.contains("git flow") || reason.contains("develop"))
    }

    @Test("Target develop passes")
    func targetDevelopPasses() async throws {
        let ctx = MockShipContext(isDryRun: true, target: "develop")
        let gate = PRGate()

        let result = try await gate.evaluate(context: ctx)

        guard case .pass = result else {
            Issue.record("Expected .pass, got \(result)")
            return
        }
    }

    @Test("Target epic/* passes")
    func targetEpicPasses() async throws {
        let ctx = MockShipContext(isDryRun: true, target: "epic/shikki-v1")
        let gate = PRGate()

        let result = try await gate.evaluate(context: ctx)

        guard case .pass = result else {
            Issue.record("Expected .pass, got \(result)")
            return
        }
    }

    @Test("Target story/* passes")
    func targetStoryPasses() async throws {
        let ctx = MockShipContext(isDryRun: true, target: "story/swift-platform-migration")
        let gate = PRGate()

        let result = try await gate.evaluate(context: ctx)

        guard case .pass = result else {
            Issue.record("Expected .pass, got \(result)")
            return
        }
    }
}

// MARK: - VersionBumpGate Tests

@Suite("Ship Gate — VersionBump")
struct VersionBumpGateTests {

    @Test("Delegates to VersionBumper")
    func delegatesToBumper() async throws {
        let ctx = MockShipContext()
        await ctx.stubShell("git describe", result: ShellResult(stdout: "v1.0.0", stderr: "", exitCode: 0))
        await ctx.stubShell("git log", result: ShellResult(stdout: "feat: add ship command\nfix: typo\n", stderr: "", exitCode: 0))

        let gate = VersionBumpGate()
        let result = try await gate.evaluate(context: ctx)

        guard case .pass(let detail) = result else {
            Issue.record("Expected .pass, got \(result)")
            return
        }
        #expect(detail != nil)
        #expect(detail?.contains("1.1.0") == true)
    }
}
