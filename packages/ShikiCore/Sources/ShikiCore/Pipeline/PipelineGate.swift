import Foundation

// MARK: - Gate Protocol

public protocol PipelineGate: Sendable {
    var name: String { get }
    var index: Int { get }
    func evaluate(context: PipelineContext) async throws -> PipelineGateResult
}

// MARK: - Gate Result

public enum PipelineGateResult: Sendable {
    case pass(detail: String?)
    case warn(reason: String)
    case fail(reason: String)

    public var passed: Bool {
        switch self {
        case .pass, .warn: return true
        case .fail: return false
        }
    }
}

// MARK: - Pipeline Context

public protocol PipelineContext: Sendable {
    var isDryRun: Bool { get }
    var featureId: String { get }
    var projectRoot: URL { get }
    func shell(_ command: String) async throws -> PipelineShellResult
}

// MARK: - Shell Result

public struct PipelineShellResult: Sendable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32

    public init(stdout: String, stderr: String, exitCode: Int32) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }
}
