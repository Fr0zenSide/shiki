import Foundation

/// Validates that a feature spec file exists and has sufficient content.
public struct SpecGate: PipelineGate {
    public let name = "Spec"
    public let index: Int

    public init(index: Int) {
        self.index = index
    }

    public func evaluate(context: PipelineContext) async throws -> PipelineGateResult {
        let specPath = context.projectRoot
            .appendingPathComponent("features")
            .appendingPathComponent("\(context.featureId).md")

        guard FileManager.default.fileExists(atPath: specPath.path) else {
            return .fail(reason: "Spec file not found: features/\(context.featureId).md")
        }

        let content = try String(contentsOf: specPath, encoding: .utf8)
        let lineCount = content.components(separatedBy: "\n").count

        if lineCount < 50 {
            return .warn(reason: "Spec has only \(lineCount) lines (recommend >50)")
        }

        return .pass(detail: "Spec found with \(lineCount) lines")
    }
}
