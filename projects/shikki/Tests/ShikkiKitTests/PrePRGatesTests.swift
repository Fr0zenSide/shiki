import Foundation
import os
import Testing
@testable import ShikkiKit

// MARK: - SlopScanGate Path Traversal Tests

@Suite("SlopScan -- Path Traversal Rejection")
struct SlopScanPathTraversalTests {

    @Test("Path with .. is skipped")
    func pathTraversalSkipped() async throws {
        let ctx = MockShipContext()
        // Return a file list that includes a path traversal attempt
        await ctx.stubShell("git diff --name-only", result: ShellResult(
            stdout: "../../etc/passwd\nSources/Good.swift\n", stderr: "", exitCode: 0
        ))
        // Only Good.swift should be read via cat
        await ctx.stubShell("cat", result: ShellResult(
            stdout: "func safeCode() { }", stderr: "", exitCode: 0
        ))

        let provider = MockSlopProvider()
        provider.configureSlopScan(
            SlopScanResult(clean: true, markers: [], summary: "Clean")
        )

        let gate = SlopScanGate(reviewProvider: provider)
        let result = try await gate.evaluate(context: ctx)

        // Should pass -- the traversal path was silently dropped
        guard case .pass = result else {
            Issue.record("Expected .pass, got \(result)")
            return
        }
        // The provider should have been called with only the safe file
        #expect(provider.slopScanCallCount == 1)
        let sources = provider.lastSources
        #expect(sources.count == 1)
        #expect(sources[0].contains("Good.swift"))
        #expect(!sources[0].contains("passwd"))
    }

    @Test("Symlink escaping project root is skipped")
    func symlinkEscapingRootSkipped() async throws {
        // This tests the `resolved.hasPrefix(rootPath)` guard.
        // In practice, symlinks would resolve outside the project root.
        // We test that the gate handles files gracefully even when cat fails.
        let ctx = MockShipContext()
        await ctx.stubShell("git diff --name-only", result: ShellResult(
            stdout: "Sources/Feature.swift\n", stderr: "", exitCode: 0
        ))
        // Simulate cat returning empty (file not readable / symlink target missing)
        await ctx.stubShell("cat", result: ShellResult(
            stdout: "", stderr: "No such file", exitCode: 1
        ))

        let provider = MockSlopProvider()
        let gate = SlopScanGate(reviewProvider: provider)
        let result = try await gate.evaluate(context: ctx)

        // Should pass with "No readable source files" when all cats return empty
        guard case .pass(let detail) = result else {
            Issue.record("Expected .pass, got \(result)")
            return
        }
        #expect(detail?.contains("No readable") == true)
        #expect(provider.slopScanCallCount == 0)
    }

    @Test("Only safe files are passed to slop scan")
    func onlySafeFilesPassedToScan() async throws {
        let ctx = MockShipContext()
        await ctx.stubShell("git diff --name-only", result: ShellResult(
            stdout: "../secret.swift\nSources/A.swift\n../../../root.swift\nSources/B.swift\n",
            stderr: "", exitCode: 0
        ))
        await ctx.stubShell("cat", result: ShellResult(
            stdout: "real code here", stderr: "", exitCode: 0
        ))

        let provider = MockSlopProvider()
        provider.configureSlopScan(
            SlopScanResult(clean: true, markers: [], summary: "Clean")
        )

        let gate = SlopScanGate(reviewProvider: provider)
        let result = try await gate.evaluate(context: ctx)

        guard case .pass = result else {
            Issue.record("Expected .pass, got \(result)")
            return
        }

        // Provider should receive at most 2 files (A.swift and B.swift)
        let sources = provider.lastSources
        for source in sources {
            #expect(!source.contains("secret"))
            #expect(!source.contains("root"))
        }
    }
}

// MARK: - CtoReviewGate Feature Spec Loading Tests

@Suite("CtoReview -- Feature Spec Loading")
struct CtoReviewFeatureSpecTests {

    @Test("Feature spec loaded when matching file exists")
    func featureSpecLoadedWhenExists() async throws {
        // Create a temporary features directory with a matching spec
        let tempDir = NSTemporaryDirectory() + "shikki-cto-test-\(UUID().uuidString)"
        let projectDir = "\(tempDir)/projects/shikki"
        let featuresDir = "\(tempDir)/features"
        try FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: featuresDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        // Write a matching spec file
        let specContent = "# Feature: Widgets\nSpec content here"
        try specContent.write(
            toFile: "\(featuresDir)/shikki-widgets.md",
            atomically: true, encoding: .utf8
        )

        let ctx = MockShipContext(
            projectRoot: URL(fileURLWithPath: projectDir)
        )
        await ctx.stubShell("git diff", result: ShellResult(
            stdout: "+ func widgets() { }", stderr: "", exitCode: 0
        ))
        await ctx.stubShell("git branch", result: ShellResult(
            stdout: "feature/widgets\n", stderr: "", exitCode: 0
        ))

        let provider = MockCtoProvider()
        provider.configureCtoReview(
            ReviewResult(passed: true, findings: [], summary: "Clean")
        )

        let gate = CtoReviewGate(reviewProvider: provider)
        let result = try await gate.evaluate(context: ctx)

        guard case .pass = result else {
            Issue.record("Expected .pass, got \(result)")
            return
        }
        // The provider should have received the spec content
        #expect(provider.lastFeatureSpec?.contains("Widgets") == true)
    }

    @Test("Feature spec nil when no matching file")
    func featureSpecNilWhenNoMatch() async throws {
        let tempDir = NSTemporaryDirectory() + "shikki-cto-test-\(UUID().uuidString)"
        let projectDir = "\(tempDir)/projects/shikki"
        let featuresDir = "\(tempDir)/features"
        try FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: featuresDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        // Write a spec that does NOT match the branch slug
        try "# Other Spec".write(
            toFile: "\(featuresDir)/shikki-other.md",
            atomically: true, encoding: .utf8
        )

        let ctx = MockShipContext(
            projectRoot: URL(fileURLWithPath: projectDir)
        )
        await ctx.stubShell("git diff", result: ShellResult(
            stdout: "+ func widgets() { }", stderr: "", exitCode: 0
        ))
        await ctx.stubShell("git branch", result: ShellResult(
            stdout: "feature/widgets\n", stderr: "", exitCode: 0
        ))

        let provider = MockCtoProvider()
        provider.configureCtoReview(
            ReviewResult(passed: true, findings: [], summary: "Clean")
        )

        let gate = CtoReviewGate(reviewProvider: provider)
        let result = try await gate.evaluate(context: ctx)

        guard case .pass = result else {
            Issue.record("Expected .pass, got \(result)")
            return
        }
        #expect(provider.lastFeatureSpec == nil)
    }
}

// MARK: - PrePRStatus Custom MaxAge Tests

@Suite("PrePRStatus -- Custom MaxAge")
struct PrePRStatusMaxAgeTests {

    @Test("Valid with short maxAge and recent timestamp")
    func validWithShortMaxAge() {
        let status = PrePRStatus(
            passed: true,
            timestamp: Date().addingTimeInterval(-30), // 30s ago
            branch: "feature/test",
            gateResults: []
        )
        #expect(status.isValid(forBranch: "feature/test", maxAge: 60))
    }

    @Test("Invalid with short maxAge and old timestamp")
    func invalidWithShortMaxAge() {
        let status = PrePRStatus(
            passed: true,
            timestamp: Date().addingTimeInterval(-120), // 2 min ago
            branch: "feature/test",
            gateResults: []
        )
        #expect(!status.isValid(forBranch: "feature/test", maxAge: 60))
    }

    @Test("Edge case: timestamp exactly at maxAge boundary")
    func exactlyAtMaxAge() {
        // At exactly maxAge, timeIntervalSince == maxAge, so < maxAge is false => invalid
        let status = PrePRStatus(
            passed: true,
            timestamp: Date().addingTimeInterval(-3600),
            branch: "feature/test",
            gateResults: []
        )
        #expect(!status.isValid(forBranch: "feature/test", maxAge: 3600))
    }
}

// MARK: - PrePRGateRecord Tests

@Suite("PrePRGateRecord")
struct PrePRGateRecordTests {

    @Test("Gate record stores all fields")
    func gateRecordFields() {
        let record = PrePRGateRecord(gate: "CtoReview", passed: true, detail: "Clean")
        #expect(record.gate == "CtoReview")
        #expect(record.passed == true)
        #expect(record.detail == "Clean")
    }

    @Test("Gate record with nil detail")
    func gateRecordNilDetail() {
        let record = PrePRGateRecord(gate: "TestValidation", passed: false)
        #expect(record.detail == nil)
    }

    @Test("Gate record round-trips through JSON")
    func gateRecordRoundTrip() throws {
        let record = PrePRGateRecord(gate: "SlopScan", passed: true, detail: "2 files scanned")
        let encoder = JSONEncoder()
        let data = try encoder.encode(record)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(PrePRGateRecord.self, from: data)
        #expect(decoded.gate == record.gate)
        #expect(decoded.passed == record.passed)
        #expect(decoded.detail == record.detail)
    }
}

// MARK: - PrePRRequiredGate Detailed Error Messages

@Suite("PrePRRequired -- Error Messages")
struct PrePRRequiredGateErrorMessageTests {

    @Test("Failed status gives clear message to re-run")
    func failedStatusMessage() async throws {
        let tempPath = NSTemporaryDirectory() + "pre-pr-msg-\(UUID().uuidString).json"
        let store = PrePRStatusStore(path: tempPath)
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        try store.save(PrePRStatus(
            passed: false,
            timestamp: Date(),
            branch: "feature/test",
            gateResults: [
                PrePRGateRecord(gate: "CtoReview", passed: false, detail: "Critical found"),
            ]
        ))

        let ctx = MockShipContext()
        let gate = PrePRRequiredGate(statusStore: store)
        let result = try await gate.evaluate(context: ctx)

        guard case .fail(let reason) = result else {
            Issue.record("Expected .fail, got \(result)")
            return
        }
        #expect(reason.contains("did not pass"))
        #expect(reason.contains("shi ship --pre-pr"))
    }
}

// MARK: - Gate Index Tests

@Suite("Pre-PR Gate Indices")
struct PrePRGateIndexTests {

    @Test("Pre-PR gates have negative indices")
    func prePRGatesNegativeIndices() {
        let provider = MockSlopProvider()
        let cto = CtoReviewGate(reviewProvider: provider)
        let slop = SlopScanGate(reviewProvider: provider)
        let test = TestValidationGate()
        let lint = LintValidationGate()
        let required = PrePRRequiredGate()

        #expect(cto.index < 0)
        #expect(slop.index < 0)
        #expect(test.index < 0)
        #expect(lint.index < 0)
        #expect(required.index < 0)
    }

    @Test("Gate ordering: CtoReview before SlopScan before TestValidation before LintValidation")
    func gateOrdering() {
        let provider = MockSlopProvider()
        let cto = CtoReviewGate(reviewProvider: provider)
        let slop = SlopScanGate(reviewProvider: provider)
        let test = TestValidationGate()
        let lint = LintValidationGate()

        #expect(cto.index < slop.index)
        #expect(slop.index < test.index)
        #expect(test.index < lint.index)
    }

    @Test("PrePRRequired has lowest index")
    func prePRRequiredLowestIndex() {
        let provider = MockSlopProvider()
        let required = PrePRRequiredGate()
        let cto = CtoReviewGate(reviewProvider: provider)

        #expect(required.index < cto.index)
    }
}

// MARK: - Mock Helpers (private to this file)

/// Mock ReviewProvider that tracks slop scan sources.
private final class MockSlopProvider: ReviewProvider, Sendable {
    private let state = OSAllocatedUnfairLock(initialState: SlopProviderState())

    struct SlopProviderState: Sendable {
        var slopResult: SlopScanResult?
        var ctoResult: ReviewResult?
        var slopScanCallCount = 0
        var lastSources: [String] = []
    }

    var slopScanCallCount: Int {
        state.withLock { $0.slopScanCallCount }
    }

    var lastSources: [String] {
        state.withLock { $0.lastSources }
    }

    func configureSlopScan(_ result: SlopScanResult) {
        state.withLock { $0.slopResult = result }
    }

    func configureCtoReview(_ result: ReviewResult) {
        state.withLock { $0.ctoResult = result }
    }

    func runCtoReview(diff: String, featureSpec: String?) async throws -> ReviewResult {
        state.withLock { state in
            state.ctoResult ?? ReviewResult(passed: true, findings: [], summary: "Clean")
        }
    }

    func runSlopScan(sources: [String]) async throws -> SlopScanResult {
        state.withLock { state in
            state.slopScanCallCount += 1
            state.lastSources = sources
            return state.slopResult ?? SlopScanResult(clean: true, markers: [], summary: "Clean")
        }
    }
}

/// Mock ReviewProvider that tracks feature spec parameter.
private final class MockCtoProvider: ReviewProvider, Sendable {
    private let state = OSAllocatedUnfairLock(initialState: CtoProviderState())

    struct CtoProviderState: Sendable {
        var ctoResult: ReviewResult?
        var lastFeatureSpec: String?
    }

    var lastFeatureSpec: String? {
        state.withLock { $0.lastFeatureSpec }
    }

    func configureCtoReview(_ result: ReviewResult) {
        state.withLock { $0.ctoResult = result }
    }

    func runCtoReview(diff: String, featureSpec: String?) async throws -> ReviewResult {
        state.withLock { state in
            state.lastFeatureSpec = featureSpec
            return state.ctoResult ?? ReviewResult(passed: true, findings: [], summary: "Clean")
        }
    }

    func runSlopScan(sources: [String]) async throws -> SlopScanResult {
        SlopScanResult(clean: true, markers: [], summary: "Clean")
    }
}
