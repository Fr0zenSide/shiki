import Foundation
import Logging

// MARK: - LocalProvider

/// AgentProvider for on-device inference via MLX or similar local engines.
/// Stub implementation for future expansion — dispatches prompts to a local
/// HTTP endpoint (e.g., LM Studio, Ollama, or native MLX server).
public actor LocalProvider: AgentProvider {
    public nonisolated let name = "local"

    private let endpoint: String
    private let modelName: String
    private let session: URLSession
    private let logger = Logger(label: "shiki.core.local-provider")
    private var _sessionSpend: Double = 0

    /// Initialize with local server endpoint.
    /// Default: LM Studio at localhost:1234 (per infrastructure config).
    public init(
        endpoint: String = "http://127.0.0.1:1234",
        modelName: String = "local-model",
        session: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.modelName = modelName
        self.session = session
    }

    /// Local inference has zero monetary cost.
    public var currentSessionSpend: Double { 0.0 }

    public func dispatch(
        prompt: String,
        workingDirectory: URL,
        options: AgentOptions
    ) async throws -> AgentResult {
        let clock = ContinuousClock()
        let start = clock.now

        let requestBody = LocalCompletionRequest(
            model: options.model ?? modelName,
            messages: [.init(role: "user", content: prompt)],
            maxTokens: options.maxTokens ?? 4096
        )

        let request = try buildRequest(body: requestBody)
        let (data, response) = try await session.data(for: request)
        let elapsed = clock.now - start

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LocalProviderError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
            throw LocalProviderError.httpError(
                statusCode: httpResponse.statusCode,
                body: errorBody
            )
        }

        let decoded = try JSONDecoder().decode(LocalCompletionResponse.self, from: data)
        let output = decoded.choices.first?.message.content ?? ""
        let tokensUsed = decoded.usage?.totalTokens

        let duration = Duration.nanoseconds(
            Int64(elapsed.components.seconds) * 1_000_000_000
                + Int64(elapsed.components.attoseconds / 1_000_000_000)
        )

        return AgentResult(
            output: output,
            exitCode: 0,
            tokensUsed: tokensUsed,
            duration: duration
        )
    }

    public func cancel() async {
        // Local inference cancellation not yet supported.
    }

    // MARK: - Internal

    nonisolated func buildRequest(body: LocalCompletionRequest) throws -> URLRequest {
        guard let url = URL(string: "\(endpoint)/v1/chat/completions") else {
            throw LocalProviderError.invalidURL(endpoint)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }
}

// MARK: - Request/Response Types

struct LocalCompletionRequest: Codable, Sendable {
    let model: String
    let messages: [LocalMessage]
    let maxTokens: Int

    enum CodingKeys: String, CodingKey {
        case model, messages
        case maxTokens = "max_tokens"
    }
}

struct LocalMessage: Codable, Sendable {
    let role: String
    let content: String
}

struct LocalCompletionResponse: Codable, Sendable {
    let choices: [LocalChoice]
    let usage: LocalUsage?
}

struct LocalChoice: Codable, Sendable {
    let message: LocalMessage
}

struct LocalUsage: Codable, Sendable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

// MARK: - Errors

public enum LocalProviderError: Error, Sendable {
    case invalidURL(String)
    case invalidResponse
    case httpError(statusCode: Int, body: String)
}
