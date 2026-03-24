import Foundation
import Logging

/// HTTP-based provider for local LLM servers (LM Studio, Ollama).
/// Connects to an OpenAI-compatible endpoint on localhost.
/// `currentSessionSpend` is always 0 — local inference is free.
public actor LocalProvider: AgentProvider {
    public nonisolated let name = "local"

    private let baseURL: String
    private let session: URLSession
    private let logger = Logger(label: "shiki.core.local-provider")
    private var currentTask: Task<AgentResult, any Error>?

    /// Local providers cost nothing.
    public var currentSessionSpend: Double { 0 }

    /// - Parameters:
    ///   - baseURL: Local server URL (default: LM Studio at 127.0.0.1:1234).
    ///   - session: URLSession for dependency injection in tests.
    public init(
        baseURL: String = "http://127.0.0.1:1234",
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    public func dispatch(
        prompt: String,
        workingDirectory: URL,
        options: AgentOptions
    ) async throws -> AgentResult {
        // Health check — fail fast if server is down
        try await healthCheck()

        let task = Task { [baseURL, session, name] () -> AgentResult in
            let clock = ContinuousClock()
            let start = clock.now

            let url = URL(string: "\(baseURL)/v1/chat/completions")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let body = OpenRouterProvider.buildRequestBody(prompt: prompt, options: options)
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw AgentProviderError.invalidResponse(
                    provider: name,
                    detail: "HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)"
                )
            }

            return try OpenRouterProvider.parseResponse(
                data: data, start: start, clock: clock, provider: name
            )
        }
        currentTask = task
        let result = try await task.value
        currentTask = nil
        return result
    }

    public func cancel() async {
        currentTask?.cancel()
        currentTask = nil
    }

    // MARK: - Health Check

    /// Verify the local server is reachable by hitting GET /v1/models.
    /// Throws `AgentProviderError.unavailable` if unreachable.
    public func healthCheck() async throws {
        let url = URL(string: "\(baseURL)/v1/models")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 3

        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw AgentProviderError.unavailable(provider: name)
            }
        } catch is AgentProviderError {
            throw AgentProviderError.unavailable(provider: name)
        } catch {
            throw AgentProviderError.unavailable(provider: name)
        }
    }
}
