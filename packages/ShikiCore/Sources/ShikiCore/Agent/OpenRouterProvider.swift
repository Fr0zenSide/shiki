import Foundation
import Logging

/// HTTP-based provider for OpenRouter (OpenAI-compatible API).
/// Routes prompts to any model available on OpenRouter — Claude, Gemini, Llama, etc.
public actor OpenRouterProvider: AgentProvider {
    public nonisolated let name = "openrouter"

    private let apiKey: String
    private let baseURL: String
    private let session: URLSession
    private let logger = Logger(label: "shiki.core.openrouter-provider")
    private var _sessionSpend: Double = 0
    private var currentTask: Task<AgentResult, any Error>?

    public var currentSessionSpend: Double { _sessionSpend }

    /// - Parameters:
    ///   - apiKey: OpenRouter API key. Falls back to `OPENROUTER_API_KEY` env var.
    ///   - baseURL: API base URL (default: OpenRouter production).
    ///   - session: URLSession for dependency injection in tests.
    public init(
        apiKey: String? = nil,
        baseURL: String = "https://openrouter.ai/api/v1",
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey ?? ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"] ?? ""
        self.baseURL = baseURL
        self.session = session
    }

    public func dispatch(
        prompt: String,
        workingDirectory: URL,
        options: AgentOptions
    ) async throws -> AgentResult {
        guard !apiKey.isEmpty else {
            throw AgentProviderError.authenticationFailed(provider: name)
        }

        let task = Task { [apiKey, baseURL, session, name] () -> AgentResult in
            let clock = ContinuousClock()
            let start = clock.now

            let url = URL(string: "\(baseURL)/chat/completions")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

            let body = Self.buildRequestBody(prompt: prompt, options: options)
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AgentProviderError.invalidResponse(provider: name, detail: "Non-HTTP response")
            }

            switch httpResponse.statusCode {
            case 200...299:
                break
            case 401:
                throw AgentProviderError.authenticationFailed(provider: name)
            case 429:
                let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                    .flatMap(Double.init)
                throw AgentProviderError.rateLimited(retryAfterSeconds: retryAfter)
            default:
                let body = String(data: data, encoding: .utf8) ?? "<binary>"
                throw AgentProviderError.invalidResponse(
                    provider: name,
                    detail: "HTTP \(httpResponse.statusCode): \(body)"
                )
            }

            return try Self.parseResponse(data: data, start: start, clock: clock, provider: name)
        }
        currentTask = task
        let result = try await task.value
        currentTask = nil

        // Accumulate spend from tokens
        if let tokens = result.tokensUsed {
            // Rough estimate: $0.001 per 1K tokens (varies by model, but good default)
            _sessionSpend += Double(tokens) / 1000.0 * 0.001
        }

        return result
    }

    public func cancel() async {
        currentTask?.cancel()
        currentTask = nil
    }

    // MARK: - Internal Helpers

    nonisolated static func buildRequestBody(prompt: String, options: AgentOptions) -> [String: Any] {
        var body: [String: Any] = [
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        body["model"] = options.model ?? "anthropic/claude-sonnet-4"

        if let maxTokens = options.maxTokens {
            body["max_tokens"] = maxTokens
        }

        if options.outputFormat == .json {
            body["response_format"] = ["type": "json_object"]
        }

        return body
    }

    nonisolated static func parseResponse(
        data: Data,
        start: ContinuousClock.Instant,
        clock: ContinuousClock,
        provider: String
    ) throws -> AgentResult {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AgentProviderError.invalidResponse(provider: provider, detail: "Invalid JSON")
        }

        // Extract content from choices[0].message.content
        let output: String
        if let choices = json["choices"] as? [[String: Any]],
           let first = choices.first,
           let message = first["message"] as? [String: Any],
           let content = message["content"] as? String {
            output = content
        } else {
            throw AgentProviderError.invalidResponse(provider: provider, detail: "Missing choices[0].message.content")
        }

        // Extract token usage
        let tokensUsed: Int?
        if let usage = json["usage"] as? [String: Any],
           let total = usage["total_tokens"] as? Int {
            tokensUsed = total
        } else {
            tokensUsed = nil
        }

        let elapsed = clock.now - start
        let duration = Duration.nanoseconds(
            Int64(elapsed.components.seconds) * 1_000_000_000
            + Int64(elapsed.components.attoseconds / 1_000_000_000)
        )

        return AgentResult(output: output, exitCode: 0, tokensUsed: tokensUsed, duration: duration)
    }
}
