import Foundation
import os
import Testing
@testable import ShikkiKit

// MARK: - MockReviewProvider State

/// Thread-safe state for MockReviewProvider using OSAllocatedUnfairLock (macOS 14+).
private struct MockReviewState: Sendable {
    var ctoReviewResult: ReviewResult?
    var slopScanResult: SlopScanResult?
    var shouldThrow = false
    var ctoReviewCallCount = 0
    var slopScanCallCount = 0
}

// MARK: - MockReviewProvider

/// Mock ReviewProvider for testing LLM-backed gates without actual LLM calls.
final class MockReviewProvider: ReviewProvider, Sendable {
    private let state = OSAllocatedUnfairLock(initialState: MockReviewState())

    var ctoReviewCallCount: Int {
        state.withLock { $0.ctoReviewCallCount }
    }

    var slopScanCallCount: Int {
        state.withLock { $0.slopScanCallCount }
    }

    func configureCtoReview(_ result: ReviewResult) {
        state.withLock { $0.ctoReviewResult = result }
    }

    func configureSlopScan(_ result: SlopScanResult) {
        state.withLock { $0.slopScanResult = result }
    }

    func configureShouldThrow(_ shouldThrow: Bool) {
        state.withLock { $0.shouldThrow = shouldThrow }
    }

    func runCtoReview(diff: String, featureSpec: String?) async throws -> ReviewResult {
        let (shouldThrow, result) = state.withLock { state -> (Bool, ReviewResult) in
            state.ctoReviewCallCount += 1
            let result = state.ctoReviewResult
                ?? ReviewResult(passed: true, findings: [], summary: "Clean")
            return (state.shouldThrow, result)
        }

        if shouldThrow {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "LLM unavailable"])
        }
        return result
    }

    func runSlopScan(sources: [String]) async throws -> SlopScanResult {
        let (shouldThrow, result) = state.withLock { state -> (Bool, SlopScanResult) in
            state.slopScanCallCount += 1
            let result = state.slopScanResult
                ?? SlopScanResult(clean: true, markers: [], summary: "Clean")
            return (state.shouldThrow, result)
        }

        if shouldThrow {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "LLM unavailable"])
        }
        return result
    }
}

// MARK: - CtoReviewGate Tests

@Suite("Pre-PR Gate -- CtoReview")
struct CtoReviewGateTests {

    @Test("Clean review passes")
    func cleanReviewPasses() async throws {
        let ctx = MockShipContext()
        await ctx.stubShell("git diff", result: ShellResult(
            stdout: "+ func newFeature() { }", stderr: "", exitCode: 0
        ))
        await ctx.stubShell("git branch", result: ShellResult(
            stdout: "feature/test\n", stderr: "", exitCode: 0
        ))

        let provider = MockReviewProvider()
        provider.configureCtoReview(
            ReviewResult(passed: true, findings: [], summary: "No issues found")
        )

        let gate = CtoReviewGate(reviewProvider: provider)
        let result = try await gate.evaluate(context: ctx)

        guard case .pass(let detail) = result else {
            Issue.record("Expected .pass, got \(result)")
            return
        }
        #expect(detail?.contains("clean") == true)
        #expect(provider.ctoReviewCallCount == 1)
    }

    @Test("Critical findings cause failure")
    func criticalFindingsFail() async throws {
        let ctx = MockShipContext()
        await ctx.stubShell("git diff", result: ShellResult(
            stdout: "+ func broken() { }", stderr: "", exitCode: 0
        ))
        await ctx.stubShell("git branch", result: ShellResult(
            stdout: "feature/test\n", stderr: "", exitCode: 0
        ))

        let provider = MockReviewProvider()
        provider.configureCtoReview(
            ReviewResult(
                passed: false,
                findings: [
                    ReviewFinding(severity: .critical, file: "Foo.swift", line: 42, message: "Race condition in async call"),
                ],
                summary: "1 critical issue"
            )
        )

        let gate = CtoReviewGate(reviewProvider: provider)
        let result = try await gate.evaluate(context: ctx)

        guard case .fail(let reason) = result else {
            Issue.record("Expected .fail, got \(result)")
            return
        }
        #expect(reason.contains("critical"))
        #expect(reason.contains("Race condition"))
    }

    @Test("Warnings pass with detail")
    func warningsPassWithDetail() async throws {
        let ctx = MockShipContext()
        await ctx.stubShell("git diff", result: ShellResult(
            stdout: "+ func feature() { }", stderr: "", exitCode: 0
        ))
        await ctx.stubShell("git branch", result: ShellResult(
            stdout: "feature/test\n", stderr: "", exitCode: 0
        ))

        let provider = MockReviewProvider()
        provider.configureCtoReview(
            ReviewResult(
                passed: true,
                findings: [
                    ReviewFinding(severity: .warning, message: "Consider adding documentation"),
                    ReviewFinding(severity: .warning, message: "Magic number on line 12"),
                ],
                summary: "2 warnings"
            )
        )

        let gate = CtoReviewGate(reviewProvider: provider)
        let result = try await gate.evaluate(context: ctx)

        guard case .pass(let detail) = result else {
            Issue.record("Expected .pass, got \(result)")
            return
        }
        #expect(detail?.contains("2 warning") == true)
    }

    @Test("Empty diff warns and skips")
    func emptyDiffWarns() async throws {
        let ctx = MockShipContext()
        await ctx.stubShell("git diff", result: ShellResult(
            stdout: "", stderr: "", exitCode: 0
        ))

        let provider = MockReviewProvider()
        let gate = CtoReviewGate(reviewProvider: provider)
        let result = try await gate.evaluate(context: ctx)

        guard case .warn(let reason) = result else {
            Issue.record("Expected .warn, got \(result)")
            return
        }
        #expect(reason.contains("No diff"))
        #expect(provider.ctoReviewCallCount == 0)
    }

    @Test("Review not passed without criticals still fails")
    func reviewNotPassedFails() async throws {
        let ctx = MockShipContext()
        await ctx.stubShell("git diff", result: ShellResult(
            stdout: "+ code here", stderr: "", exitCode: 0
        ))
        await ctx.stubShell("git branch", result: ShellResult(
            stdout: "feature/test\n", stderr: "", exitCode: 0
        ))

        let provider = MockReviewProvider()
        provider.configureCtoReview(
            ReviewResult(passed: false, findings: [], summary: "Architecture concerns")
        )

        let gate = CtoReviewGate(reviewProvider: provider)
        let result = try await gate.evaluate(context: ctx)

        guard case .fail(let reason) = result else {
            Issue.record("Expected .fail, got \(result)")
            return
        }
        #expect(reason.contains("Architecture concerns"))
    }
}

// MARK: - SlopScanGate Tests

@Suite("Pre-PR Gate -- SlopScan")
struct SlopScanGateTests {

    @Test("Clean scan passes")
    func cleanScanPasses() async throws {
        let ctx = MockShipContext()
        await ctx.stubShell("git diff --name-only", result: ShellResult(
            stdout: "Sources/Feature.swift\n", stderr: "", exitCode: 0
        ))
        await ctx.stubShell("cat", result: ShellResult(
            stdout: "func realCode() { }", stderr: "", exitCode: 0
        ))

        let provider = MockReviewProvider()
        provider.configureSlopScan(
            SlopScanResult(clean: true, markers: [], summary: "No AI slop found")
        )

        let gate = SlopScanGate(reviewProvider: provider)
        let result = try await gate.evaluate(context: ctx)

        guard case .pass(let detail) = result else {
            Issue.record("Expected .pass, got \(result)")
            return
        }
        #expect(detail?.contains("clean") == true || detail?.contains("1 file") == true)
    }

    @Test("Slop markers found cause failure")
    func slopMarkersFoundFail() async throws {
        let ctx = MockShipContext()
        await ctx.stubShell("git diff --name-only", result: ShellResult(
            stdout: "Sources/Bad.swift\n", stderr: "", exitCode: 0
        ))
        await ctx.stubShell("cat", result: ShellResult(
            stdout: "// TODO: implement this properly", stderr: "", exitCode: 0
        ))

        let provider = MockReviewProvider()
        provider.configureSlopScan(
            SlopScanResult(
                clean: false,
                markers: [
                    SlopMarker(file: "Bad.swift", line: 1, pattern: "placeholder_comment", context: "TODO: implement"),
                ],
                summary: "1 marker found"
            )
        )

        let gate = SlopScanGate(reviewProvider: provider)
        let result = try await gate.evaluate(context: ctx)

        guard case .fail(let reason) = result else {
            Issue.record("Expected .fail, got \(result)")
            return
        }
        #expect(reason.contains("slop marker"))
        #expect(reason.contains("Bad.swift"))
    }

    @Test("No changed source files skips scan")
    func noSourceFilesSkips() async throws {
        let ctx = MockShipContext()
        await ctx.stubShell("git diff --name-only", result: ShellResult(
            stdout: "", stderr: "", exitCode: 0
        ))

        let provider = MockReviewProvider()
        let gate = SlopScanGate(reviewProvider: provider)
        let result = try await gate.evaluate(context: ctx)

        guard case .pass(let detail) = result else {
            Issue.record("Expected .pass, got \(result)")
            return
        }
        #expect(detail?.contains("No source files") == true)
        #expect(provider.slopScanCallCount == 0)
    }
}

// MARK: - TestValidationGate Tests

@Suite("Pre-PR Gate -- TestValidation")
struct TestValidationGateTests {

    @Test("Tests pass returns pass with count")
    func testsPassWithCount() async throws {
        let ctx = MockShipContext()
        await ctx.stubShell("swift test", result: ShellResult(
            stdout: "Test Suite passed.\nExecuted 42 tests, with 0 failures",
            stderr: "",
            exitCode: 0
        ))

        let gate = TestValidationGate()
        let result = try await gate.evaluate(context: ctx)

        guard case .pass(let detail) = result else {
            Issue.record("Expected .pass, got \(result)")
            return
        }
        #expect(detail?.contains("42 tests passed") == true)
    }

    @Test("Test failure returns fail")
    func testFailureReturnsFail() async throws {
        let ctx = MockShipContext()
        await ctx.stubShell("swift test", result: ShellResult(
            stdout: "Test Suite failed.\nExecuted 42 tests, with 3 failures",
            stderr: "",
            exitCode: 1
        ))

        let gate = TestValidationGate()
        let result = try await gate.evaluate(context: ctx)

        guard case .fail(let reason) = result else {
            Issue.record("Expected .fail, got \(result)")
            return
        }
        #expect(reason.contains("fail") || reason.contains("exit code"))
    }

    @Test("Empty test suite fails")
    func emptyTestSuiteFails() async throws {
        let ctx = MockShipContext()
        await ctx.stubShell("swift test", result: ShellResult(
            stdout: "Executed 0 tests, with 0 failures",
            stderr: "",
            exitCode: 0
        ))

        let gate = TestValidationGate()
        let result = try await gate.evaluate(context: ctx)

        guard case .fail(let reason) = result else {
            Issue.record("Expected .fail, got \(result)")
            return
        }
        #expect(reason.contains("empty") || reason.contains("0 tests"))
    }

    @Test("Custom test command used when provided")
    func customTestCommandUsed() async throws {
        let ctx = MockShipContext()
        await ctx.stubShell("npm test", result: ShellResult(
            stdout: "42 tests passed", stderr: "", exitCode: 0
        ))

        let gate = TestValidationGate(testCommand: "npm test")
        let result = try await gate.evaluate(context: ctx)

        guard case .pass = result else {
            Issue.record("Expected .pass, got \(result)")
            return
        }
        let calls = await ctx.shellCalls
        #expect(calls.contains(where: { $0.contains("npm test") }))
    }

    @Test("Swift Testing format parsed correctly")
    func swiftTestingFormatParsed() async throws {
        let ctx = MockShipContext()
        await ctx.stubShell("swift test", result: ShellResult(
            stdout: "Test run completed: 128 tests passed, 0 failed",
            stderr: "",
            exitCode: 0
        ))

        let gate = TestValidationGate()
        let result = try await gate.evaluate(context: ctx)

        guard case .pass(let detail) = result else {
            Issue.record("Expected .pass, got \(result)")
            return
        }
        #expect(detail?.contains("128 tests passed") == true)
    }
}

// MARK: - LintValidationGate Tests

@Suite("Pre-PR Gate -- LintValidation")
struct LintValidationGateTests {

    @Test("No linter warns but passes")
    func noLinterWarns() async throws {
        let ctx = MockShipContext()
        await ctx.stubShell("which swiftlint", result: ShellResult(
            stdout: "", stderr: "", exitCode: 1
        ))
        await ctx.stubShell("git diff --name-only", result: ShellResult(
            stdout: "", stderr: "", exitCode: 0
        ))

        let gate = LintValidationGate()
        let result = try await gate.evaluate(context: ctx)

        guard case .warn(let reason) = result else {
            Issue.record("Expected .warn, got \(result)")
            return
        }
        #expect(reason.contains("No linter"))
    }

    @Test("Lint errors cause failure")
    func lintErrorsFail() async throws {
        let ctx = MockShipContext()
        await ctx.stubShell("which swiftlint", result: ShellResult(
            stdout: "/usr/local/bin/swiftlint", stderr: "", exitCode: 0
        ))
        await ctx.stubShell("swiftlint lint", result: ShellResult(
            stdout: "file.swift:10:1: error: force_cast\nfile.swift:20:1: error: force_try",
            stderr: "",
            exitCode: 2
        ))

        let gate = LintValidationGate()
        let result = try await gate.evaluate(context: ctx)

        guard case .fail(let reason) = result else {
            Issue.record("Expected .fail, got \(result)")
            return
        }
        #expect(reason.contains("2 lint error"))
    }

    @Test("Clean lint passes")
    func cleanLintPasses() async throws {
        let ctx = MockShipContext()
        await ctx.stubShell("which swiftlint", result: ShellResult(
            stdout: "/usr/local/bin/swiftlint", stderr: "", exitCode: 0
        ))
        await ctx.stubShell("swiftlint lint", result: ShellResult(
            stdout: "", stderr: "", exitCode: 0
        ))
        await ctx.stubShell("git diff --name-only", result: ShellResult(
            stdout: "", stderr: "", exitCode: 0
        ))

        let gate = LintValidationGate()
        let result = try await gate.evaluate(context: ctx)

        guard case .pass(let detail) = result else {
            Issue.record("Expected .pass, got \(result)")
            return
        }
        #expect(detail?.contains("clean") == true)
    }

    @Test("TODO markers reported as warning")
    func todoMarkersWarn() async throws {
        let ctx = MockShipContext()
        await ctx.stubShell("which swiftlint", result: ShellResult(
            stdout: "/usr/local/bin/swiftlint", stderr: "", exitCode: 0
        ))
        await ctx.stubShell("swiftlint lint", result: ShellResult(
            stdout: "", stderr: "", exitCode: 0
        ))
        await ctx.stubShell("git diff --name-only", result: ShellResult(
            stdout: "Sources/Feature.swift\n", stderr: "", exitCode: 0
        ))
        await ctx.stubShell("grep", result: ShellResult(
            stdout: "3\n", stderr: "", exitCode: 0
        ))

        let gate = LintValidationGate()
        let result = try await gate.evaluate(context: ctx)

        guard case .warn(let reason) = result else {
            Issue.record("Expected .warn, got \(result)")
            return
        }
        #expect(reason.contains("TODO") || reason.contains("FIXME") || reason.contains("marker"))
    }
}

// MARK: - PrePRStatusStore Tests

@Suite("PrePRStatusStore")
struct PrePRStatusStoreTests {

    @Test("Save and load round-trips correctly")
    func saveAndLoadRoundTrips() throws {
        let tempPath = NSTemporaryDirectory() + "pre-pr-status-\(UUID().uuidString).json"
        let store = PrePRStatusStore(path: tempPath)
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        let status = PrePRStatus(
            passed: true,
            timestamp: Date(),
            branch: "feature/test",
            gateResults: [
                PrePRGateRecord(gate: "CtoReview", passed: true, detail: "Clean"),
                PrePRGateRecord(gate: "TestValidation", passed: true, detail: "42 tests"),
            ]
        )

        try store.save(status)
        let loaded = try store.load()

        #expect(loaded != nil)
        #expect(loaded?.passed == true)
        #expect(loaded?.branch == "feature/test")
        #expect(loaded?.gateResults.count == 2)
    }

    @Test("Load returns nil when file missing")
    func loadReturnsNilWhenMissing() throws {
        let store = PrePRStatusStore(path: "/tmp/nonexistent-\(UUID().uuidString).json")
        let loaded = try store.load()
        #expect(loaded == nil)
    }

    @Test("Clear removes the file")
    func clearRemovesFile() throws {
        let tempPath = NSTemporaryDirectory() + "pre-pr-status-clear-\(UUID().uuidString).json"
        let store = PrePRStatusStore(path: tempPath)
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        let status = PrePRStatus(
            passed: true,
            timestamp: Date(),
            branch: "feature/test",
            gateResults: []
        )
        try store.save(status)
        #expect(FileManager.default.fileExists(atPath: tempPath))

        try store.clear()
        #expect(!FileManager.default.fileExists(atPath: tempPath))
    }
}

// MARK: - PrePRStatus Tests

@Suite("PrePRStatus -- Validation")
struct PrePRStatusValidationTests {

    @Test("Valid status on same branch within time window")
    func validStatusSameBranch() {
        let status = PrePRStatus(
            passed: true,
            timestamp: Date(),
            branch: "feature/test",
            gateResults: []
        )
        #expect(status.isValid(forBranch: "feature/test"))
    }

    @Test("Invalid when branch differs")
    func invalidWhenBranchDiffers() {
        let status = PrePRStatus(
            passed: true,
            timestamp: Date(),
            branch: "feature/old",
            gateResults: []
        )
        #expect(!status.isValid(forBranch: "feature/new"))
    }

    @Test("Invalid when not passed")
    func invalidWhenNotPassed() {
        let status = PrePRStatus(
            passed: false,
            timestamp: Date(),
            branch: "feature/test",
            gateResults: []
        )
        #expect(!status.isValid(forBranch: "feature/test"))
    }

    @Test("Invalid when expired")
    func invalidWhenExpired() {
        let status = PrePRStatus(
            passed: true,
            timestamp: Date().addingTimeInterval(-7200), // 2 hours ago
            branch: "feature/test",
            gateResults: []
        )
        #expect(!status.isValid(forBranch: "feature/test", maxAge: 3600))
    }
}

// MARK: - PrePRRequiredGate Tests

@Suite("Pre-PR Gate -- PrePRRequired")
struct PrePRRequiredGateTests {

    @Test("Passes when status exists and is valid")
    func passesWhenValid() async throws {
        let tempPath = NSTemporaryDirectory() + "pre-pr-req-\(UUID().uuidString).json"
        let store = PrePRStatusStore(path: tempPath)
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        try store.save(PrePRStatus(
            passed: true,
            timestamp: Date(),
            branch: "feature/test",
            gateResults: [
                PrePRGateRecord(gate: "CtoReview", passed: true),
                PrePRGateRecord(gate: "TestValidation", passed: true),
            ]
        ))

        let ctx = MockShipContext()
        let gate = PrePRRequiredGate(statusStore: store)
        let result = try await gate.evaluate(context: ctx)

        guard case .pass(let detail) = result else {
            Issue.record("Expected .pass, got \(result)")
            return
        }
        #expect(detail?.contains("2/2") == true)
    }

    @Test("Fails when no status file exists")
    func failsWhenNoStatus() async throws {
        let store = PrePRStatusStore(path: "/tmp/nonexistent-\(UUID().uuidString).json")
        let ctx = MockShipContext()
        let gate = PrePRRequiredGate(statusStore: store)
        let result = try await gate.evaluate(context: ctx)

        guard case .fail(let reason) = result else {
            Issue.record("Expected .fail, got \(result)")
            return
        }
        #expect(reason.contains("shikki ship --pre-pr"))
    }

    @Test("Fails when branch mismatch")
    func failsOnBranchMismatch() async throws {
        let tempPath = NSTemporaryDirectory() + "pre-pr-req-br-\(UUID().uuidString).json"
        let store = PrePRStatusStore(path: tempPath)
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        try store.save(PrePRStatus(
            passed: true,
            timestamp: Date(),
            branch: "feature/old-branch",
            gateResults: []
        ))

        let ctx = MockShipContext(branch: "feature/new-branch")
        let gate = PrePRRequiredGate(statusStore: store)
        let result = try await gate.evaluate(context: ctx)

        guard case .fail(let reason) = result else {
            Issue.record("Expected .fail, got \(result)")
            return
        }
        #expect(reason.contains("feature/old-branch"))
        #expect(reason.contains("feature/new-branch"))
    }

    @Test("Fails when expired")
    func failsWhenExpired() async throws {
        let tempPath = NSTemporaryDirectory() + "pre-pr-req-exp-\(UUID().uuidString).json"
        let store = PrePRStatusStore(path: tempPath)
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        try store.save(PrePRStatus(
            passed: true,
            timestamp: Date().addingTimeInterval(-7200),
            branch: "feature/test",
            gateResults: []
        ))

        let ctx = MockShipContext()
        let gate = PrePRRequiredGate(statusStore: store)
        let result = try await gate.evaluate(context: ctx)

        guard case .fail(let reason) = result else {
            Issue.record("Expected .fail, got \(result)")
            return
        }
        #expect(reason.contains("expired"))
    }
}

// MARK: - Integration: Pre-PR Pipeline via ShipService

@Suite("Pre-PR Pipeline Integration")
struct PrePRPipelineIntegrationTests {

    @Test("Full pre-PR pipeline runs all gates in order")
    func fullPipelineRunsAllGates() async throws {
        let ctx = MockShipContext()
        await ctx.stubShell("git diff", result: ShellResult(
            stdout: "+ func feature() { }", stderr: "", exitCode: 0
        ))
        await ctx.stubShell("git branch", result: ShellResult(
            stdout: "feature/test\n", stderr: "", exitCode: 0
        ))
        await ctx.stubShell("git diff --name-only", result: ShellResult(
            stdout: "Sources/Feature.swift\n", stderr: "", exitCode: 0
        ))
        await ctx.stubShell("cat", result: ShellResult(
            stdout: "func feature() { }", stderr: "", exitCode: 0
        ))
        await ctx.stubShell("swift test", result: ShellResult(
            stdout: "Executed 42 tests, with 0 failures", stderr: "", exitCode: 0
        ))
        await ctx.stubShell("which swiftlint", result: ShellResult(
            stdout: "/usr/local/bin/swiftlint", stderr: "", exitCode: 0
        ))
        await ctx.stubShell("swiftlint lint", result: ShellResult(
            stdout: "", stderr: "", exitCode: 0
        ))
        await ctx.stubShell("grep", result: ShellResult(
            stdout: "0\n", stderr: "", exitCode: 0
        ))

        let provider = MockReviewProvider()
        provider.configureCtoReview(
            ReviewResult(passed: true, findings: [], summary: "Clean")
        )
        provider.configureSlopScan(
            SlopScanResult(clean: true, markers: [], summary: "Clean")
        )

        let gates: [any ShipGate] = [
            CtoReviewGate(reviewProvider: provider),
            SlopScanGate(reviewProvider: provider),
            TestValidationGate(),
            LintValidationGate(),
        ]

        let service = ShipService()
        let result = try await service.run(gates: gates, context: ctx)

        #expect(result.success)
        #expect(result.gateResults.count == 4)

        let events = await ctx.emittedEvents
        #expect(events.first?.type == .shipStarted)
        #expect(events.last?.type == .shipCompleted)
    }

    @Test("Pre-PR pipeline aborts on first failure")
    func pipelineAbortsOnFailure() async throws {
        let ctx = MockShipContext()
        await ctx.stubShell("git diff", result: ShellResult(
            stdout: "+ func broken() { }", stderr: "", exitCode: 0
        ))
        await ctx.stubShell("git branch", result: ShellResult(
            stdout: "feature/test\n", stderr: "", exitCode: 0
        ))

        let provider = MockReviewProvider()
        provider.configureCtoReview(
            ReviewResult(
                passed: false,
                findings: [
                    ReviewFinding(severity: .critical, message: "Security vulnerability"),
                ],
                summary: "Critical issue"
            )
        )

        let gates: [any ShipGate] = [
            CtoReviewGate(reviewProvider: provider),
            TestValidationGate(),
            LintValidationGate(),
        ]

        let service = ShipService()
        let result = try await service.run(gates: gates, context: ctx)

        #expect(!result.success)
        #expect(result.failedGate == "CtoReview")
        // TestValidation and LintValidation should not have run
        #expect(result.gateResults.count == 1)
    }
}
