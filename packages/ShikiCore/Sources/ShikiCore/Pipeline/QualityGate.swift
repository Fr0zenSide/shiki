import Foundation

/// Runs tests and verifies they pass.
public struct QualityGate: PipelineGate {
    public let name = "Quality"
    public let index: Int

    public init(index: Int) {
        self.index = index
    }

    public func evaluate(context: PipelineContext) async throws -> PipelineGateResult {
        let result = try await context.shell("swift test 2>&1")
        if result.exitCode != 0 {
            return .fail(reason: "Tests failed")
        }
        return .pass(detail: "Tests passed")
    }
}
