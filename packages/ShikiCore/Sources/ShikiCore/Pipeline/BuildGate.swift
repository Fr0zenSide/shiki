import Foundation

/// Verifies the project builds successfully.
public struct BuildGate: PipelineGate {
    public let name = "Build"
    public let index: Int

    public init(index: Int) {
        self.index = index
    }

    public func evaluate(context: PipelineContext) async throws -> PipelineGateResult {
        let result = try await context.shell("swift build 2>&1")
        if result.exitCode != 0 {
            return .fail(reason: "Build failed: \(result.stderr)")
        }
        return .pass(detail: "Build succeeded")
    }
}
