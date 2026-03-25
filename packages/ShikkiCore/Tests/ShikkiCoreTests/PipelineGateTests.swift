import Testing
import Foundation
@testable import ShikkiCore

@Suite("Pipeline Gates")
struct PipelineGateTests {

    // MARK: - Helpers

    struct MockContext: PipelineContext {
        let isDryRun = false
        let featureId: String
        let projectRoot: URL
        let shellHandler: @Sendable (String) async throws -> PipelineShellResult

        func shell(_ command: String) async throws -> PipelineShellResult {
            try await shellHandler(command)
        }
    }

    // MARK: - SpecGate

    @Test("SpecGate passes when spec file exists with content")
    func specGatePassesWithContent() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shiki-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Create features dir with a spec file > 50 lines
        let featuresDir = tmpDir.appendingPathComponent("features")
        try FileManager.default.createDirectory(at: featuresDir, withIntermediateDirectories: true)
        let specContent = (0..<60).map { "Line \($0): spec content here" }.joined(separator: "\n")
        try specContent.write(to: featuresDir.appendingPathComponent("test-feature.md"), atomically: true, encoding: .utf8)

        let context = MockContext(
            featureId: "test-feature",
            projectRoot: tmpDir,
            shellHandler: { _ in PipelineShellResult(stdout: "", stderr: "", exitCode: 0) }
        )
        let gate = SpecGate(index: 0)
        let result = try await gate.evaluate(context: context)
        #expect(result.passed)
    }

    @Test("SpecGate fails when spec file missing")
    func specGateFailsMissing() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shiki-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let context = MockContext(
            featureId: "nonexistent",
            projectRoot: tmpDir,
            shellHandler: { _ in PipelineShellResult(stdout: "", stderr: "", exitCode: 0) }
        )
        let gate = SpecGate(index: 0)
        let result = try await gate.evaluate(context: context)
        #expect(!result.passed)
    }

    // MARK: - BuildGate

    @Test("BuildGate passes on zero exit code")
    func buildGatePassesOnZero() async throws {
        let context = MockContext(
            featureId: "test-feature",
            projectRoot: URL(fileURLWithPath: "/tmp"),
            shellHandler: { _ in PipelineShellResult(stdout: "Build complete!", stderr: "", exitCode: 0) }
        )
        let gate = BuildGate(index: 1)
        let result = try await gate.evaluate(context: context)
        #expect(result.passed)
    }

    // MARK: - QualityGate

    @Test("QualityGate fails on non-zero exit code")
    func qualityGateFailsOnNonZero() async throws {
        let context = MockContext(
            featureId: "test-feature",
            projectRoot: URL(fileURLWithPath: "/tmp"),
            shellHandler: { _ in PipelineShellResult(stdout: "", stderr: "Test failed", exitCode: 1) }
        )
        let gate = QualityGate(index: 2)
        let result = try await gate.evaluate(context: context)
        #expect(!result.passed)
    }
}
