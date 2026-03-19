import Foundation

// MARK: - Protocol

public protocol AgentProvider: Sendable {
    var name: String { get }
    func dispatch(prompt: String, workingDirectory: URL, options: AgentOptions) async throws -> AgentResult
    func cancel() async
}

// MARK: - Options

public struct AgentOptions: Sendable {
    public let model: String?
    public let maxTokens: Int?
    public let outputFormat: OutputFormat
    public let allowedTools: [String]

    public enum OutputFormat: String, Sendable {
        case json
        case text
    }

    public init(
        model: String? = nil,
        maxTokens: Int? = nil,
        outputFormat: OutputFormat = .json,
        allowedTools: [String] = []
    ) {
        self.model = model
        self.maxTokens = maxTokens
        self.outputFormat = outputFormat
        self.allowedTools = allowedTools
    }
}

// MARK: - Result

public struct AgentResult: Sendable {
    public let output: String
    public let exitCode: Int32
    public let tokensUsed: Int?
    public let duration: Duration

    public init(output: String, exitCode: Int32, tokensUsed: Int?, duration: Duration) {
        self.output = output
        self.exitCode = exitCode
        self.tokensUsed = tokensUsed
        self.duration = duration
    }
}
