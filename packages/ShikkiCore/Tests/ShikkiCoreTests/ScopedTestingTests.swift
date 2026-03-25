import Testing
import Foundation
@testable import ShikkiCore

@Suite("Scoped Testing — S1c")
struct ScopedTestingTests {

    // MARK: - TestScope

    @Test("TestScope builds correct swift test command")
    func testScopeRunCommand() {
        let scope = TestScope(
            packagePath: "projects/Maya",
            filterPattern: "AnimationTests",
            expectedNewTests: 23
        )
        #expect(scope.runCommand == #"swift test --package-path projects/Maya --filter "AnimationTests""#)
    }

    @Test("TestScope Codable round-trip")
    func testScopeCodable() throws {
        let scope = TestScope(
            packagePath: "packages/ShikkiCore",
            filterPattern: "DispatchProtocolTests|SpendTrackingTests",
            expectedNewTests: 10
        )

        let data = try JSONEncoder().encode(scope)
        let decoded = try JSONDecoder().decode(TestScope.self, from: data)

        #expect(decoded.packagePath == "packages/ShikkiCore")
        #expect(decoded.filterPattern == "DispatchProtocolTests|SpendTrackingTests")
        #expect(decoded.expectedNewTests == 10)
    }

    @Test("TestScope validates correctly")
    func testScopeValidation() {
        let valid = TestScope(packagePath: "p/", filterPattern: "Tests", expectedNewTests: 5)
        #expect(valid.isValid)

        let emptyPath = TestScope(packagePath: "", filterPattern: "Tests", expectedNewTests: 5)
        #expect(!emptyPath.isValid)

        let emptyFilter = TestScope(packagePath: "p/", filterPattern: "", expectedNewTests: 5)
        #expect(!emptyFilter.isValid)

        let zeroTests = TestScope(packagePath: "p/", filterPattern: "Tests", expectedNewTests: 0)
        #expect(!zeroTests.isValid)
    }

    // MARK: - WaveNode with TestScope

    @Test("WaveNode carries TestScope through Codable")
    func waveNodeWithTestScope() throws {
        let scope = TestScope(packagePath: ".", filterPattern: "MyTests", expectedNewTests: 12)
        let wave = WaveNode(
            id: "w1",
            name: "Wave 1",
            branch: "feature/x",
            baseBranch: "develop",
            testScope: scope
        )

        let data = try JSONEncoder().encode(wave)
        let decoded = try JSONDecoder().decode(WaveNode.self, from: data)

        #expect(decoded.testScope != nil)
        #expect(decoded.testScope?.filterPattern == "MyTests")
        #expect(decoded.testScope?.expectedNewTests == 12)
    }

    // MARK: - QualityGate with TestScope

    struct MockContext: PipelineContext {
        let isDryRun = false
        let featureId: String
        let projectRoot: URL
        let shellHandler: @Sendable (String) async throws -> PipelineShellResult

        func shell(_ command: String) async throws -> PipelineShellResult {
            try await shellHandler(command)
        }
    }

    @Test("QualityGate uses TestScope run command when provided")
    func qualityGateUsesScope() async throws {
        let scope = TestScope(packagePath: "projects/Maya", filterPattern: "AnimationTests", expectedNewTests: 23)
        nonisolated(unsafe) var capturedCommand = ""

        let context = MockContext(
            featureId: "test",
            projectRoot: URL(fileURLWithPath: "/tmp"),
            shellHandler: { command in
                capturedCommand = command
                return PipelineShellResult(stdout: "23 tests passed", stderr: "", exitCode: 0)
            }
        )

        let gate = QualityGate(index: 0, testScope: scope)
        let result = try await gate.evaluate(context: context)

        #expect(result.passed)
        #expect(capturedCommand.contains("--package-path projects/Maya"))
        #expect(capturedCommand.contains("--filter"))
        #expect(capturedCommand.contains("AnimationTests"))
    }

    @Test("QualityGate falls back to swift test without scope")
    func qualityGateFallback() async throws {
        nonisolated(unsafe) var capturedCommand = ""

        let context = MockContext(
            featureId: "test",
            projectRoot: URL(fileURLWithPath: "/tmp"),
            shellHandler: { command in
                capturedCommand = command
                return PipelineShellResult(stdout: "All tests passed", stderr: "", exitCode: 0)
            }
        )

        let gate = QualityGate(index: 0)
        _ = try await gate.evaluate(context: context)

        #expect(capturedCommand == "swift test 2>&1")
    }
}
