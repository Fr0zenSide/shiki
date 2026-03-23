import Foundation

// MARK: - Protocol

/// Agent dispatch protocol. Implementations wrap specific AI CLI tools (claude, openrouter, etc.).
/// Types are prefixed with `AgentProvider` to avoid collisions when ShikiCore is composed
/// with ShikiMCP or shiki-ctl in a single binary.
public protocol AgentProvider: Sendable {
    var name: String { get }
    func dispatch(prompt: String, workingDirectory: URL, options: AgentProviderOptions) async throws -> AgentProviderResult
    func cancel() async

    /// Current session spend in USD. Providers parse this from their
    /// respective APIs or status output.
    var currentSessionSpend: Double { get async }
}

// MARK: - Options

public struct AgentProviderOptions: Sendable {
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

public struct AgentProviderResult: Sendable {
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
