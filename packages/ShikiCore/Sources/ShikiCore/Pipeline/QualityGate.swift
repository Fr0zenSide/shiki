import Foundation

/// Runs tests and verifies they pass.
/// When a TestScope is provided, runs scoped tests only (TPDD).
/// Without a scope, falls back to full `swift test`.
public struct QualityGate: PipelineGate {
    public let name = "Quality"
    public let index: Int
    public let testScope: TestScope?

    public init(index: Int, testScope: TestScope? = nil) {
        self.index = index
        self.testScope = testScope
    }

    public func evaluate(context: PipelineContext) async throws -> PipelineGateResult {
        let command: String
        if let scope = testScope {
            command = scope.runCommand + " 2>&1"
        } else {
            command = "swift test 2>&1"
        }

        let result = try await context.shell(command)
        if result.exitCode != 0 {
            return .fail(reason: "Tests failed")
        }

        if let scope = testScope {
            return .pass(detail: "Scoped tests passed (\(scope.filterPattern))")
        }
        return .pass(detail: "Tests passed")
    }
}
