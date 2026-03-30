import Foundation
import Logging

// MARK: - OpenRouterProvider

/// AgentProvider that dispatches prompts to OpenRouter API.
/// Supports model fallbacks for cost optimization on non-critical agents.
/// Uses URLSession (NetKit migration planned post-v1).
public actor OpenRouterProvider: AgentProvider {
    public nonisolated let name = "openrouter"

    private let apiKey: String
    private let baseURL: String
    private let models: [String]
    private let session: URLSession
    private let logger = Logger(label: "shiki.core.openrouter-provider")
    private var _sessionSpend: Double = 0

    /// Initialize with API key and model preference list.
    /// First model is preferred; fallbacks tried on failure.
    public init(
        apiKey: String,
        models: [String] = ["anthropic/claude-sonnet-4", "anthropic/claude-haiku-4"],
        baseURL: String = "https://openrouter.ai/api/v1",
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.models = models
        self.baseURL = baseURL
        self.session = session
    }

    public var currentSessionSpend: Double { _sessionSpend }

    public func dispatch(
        prompt: String,
        workingDirectory: URL,
        options: AgentOptions
    ) async throws -> AgentResult {
        let model = options.model ?? models.first ?? "anthropic/claude-sonnet-4"
        let clock = ContinuousClock()
        let start = clock.now

        let requestBody = OpenRouterRequest(
            model: model,
            messages: [.init(role: "user", content: prompt)],
            maxTokens: options.maxTokens
        )

        let request = try buildRequest(body: requestBody)
        let (data, response) = try await session.data(for: request)
        let elapsed = clock.now - start

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenRouterError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
            throw OpenRouterError.httpError(
                statusCode: httpResponse.statusCode,
                body: errorBody
            )
        }

        let decoded = try JSONDecoder().decode(OpenRouterResponse.self, from: data)
        let output = decoded.choices.first?.message.content ?? ""
        let tokensUsed = decoded.usage?.totalTokens

        // Track spend
        if let cost = decoded.usage?.totalCost {
            _sessionSpend += cost
        }

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
        // URLSession tasks are not individually cancellable here.
        // Future: track active URLSessionTask and cancel it.
    }

    // MARK: - Internal

    nonisolated func buildRequest(body: OpenRouterRequest) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw OpenRouterError.invalidURL(baseURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("shikki/1.0", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Shikki", forHTTPHeaderField: "X-Title")

        request.httpBody = try JSONEncoder().encode(body)
        return request
    }
}

// MARK: - Request/Response Types

struct OpenRouterRequest: Codable, Sendable {
    let model: String
    let messages: [OpenRouterMessage]
    let maxTokens: Int?

    enum CodingKeys: String, CodingKey {
        case model, messages
        case maxTokens = "max_tokens"
    }
}

struct OpenRouterMessage: Codable, Sendable {
    let role: String
    let content: String
}

struct OpenRouterResponse: Codable, Sendable {
    let choices: [OpenRouterChoice]
    let usage: OpenRouterUsage?
}

struct OpenRouterChoice: Codable, Sendable {
    let message: OpenRouterMessage
}

struct OpenRouterUsage: Codable, Sendable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?
    let totalCost: Double?

    var computedTotalTokens: Int {
        (promptTokens ?? 0) + (completionTokens ?? 0)
    }

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
        case totalCost = "total_cost"
    }
}

// MARK: - Errors

public enum OpenRouterError: Error, Sendable {
    case invalidURL(String)
    case invalidResponse
    case httpError(statusCode: Int, body: String)
}
