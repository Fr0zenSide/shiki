import Foundation
import Testing
@testable import ShikiCore

@Suite("OpenRouterProvider")
struct OpenRouterProviderTests {

    @Test("Provider name is 'openrouter'")
    func providerName() {
        let provider = OpenRouterProvider(apiKey: "test-key")
        #expect(provider.name == "openrouter")
    }

    @Test("Build request includes auth header and model")
    func buildRequest() throws {
        let provider = OpenRouterProvider(
            apiKey: "sk-test-123",
            models: ["anthropic/claude-sonnet-4"]
        )

        let body = OpenRouterRequest(
            model: "anthropic/claude-sonnet-4",
            messages: [.init(role: "user", content: "Hello")],
            maxTokens: 1000
        )

        let request = try provider.buildRequest(body: body)

        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test-123")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "X-Title") == "Shikki")
        #expect(request.url?.absoluteString == "https://openrouter.ai/api/v1/chat/completions")
    }

    @Test("Request body encodes correctly")
    func requestEncoding() throws {
        let body = OpenRouterRequest(
            model: "anthropic/claude-sonnet-4",
            messages: [.init(role: "user", content: "Test prompt")],
            maxTokens: 2000
        )

        let data = try JSONEncoder().encode(body)
        let decoded = try JSONDecoder().decode(OpenRouterRequest.self, from: data)

        #expect(decoded.model == "anthropic/claude-sonnet-4")
        #expect(decoded.messages.count == 1)
        #expect(decoded.messages[0].content == "Test prompt")
        #expect(decoded.maxTokens == 2000)
    }

    @Test("Response decodes correctly with usage data")
    func responseDecoding() throws {
        let json = """
        {
            "choices": [
                {
                    "message": {
                        "role": "assistant",
                        "content": "Hello! How can I help?"
                    }
                }
            ],
            "usage": {
                "prompt_tokens": 10,
                "completion_tokens": 20,
                "total_tokens": 30,
                "total_cost": 0.0005
            }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(OpenRouterResponse.self, from: json)
        #expect(response.choices.count == 1)
        #expect(response.choices[0].message.content == "Hello! How can I help?")
        #expect(response.usage?.totalTokens == 30)
        #expect(response.usage?.totalCost == 0.0005)
    }

    @Test("Session spend starts at zero")
    func initialSpend() async {
        let provider = OpenRouterProvider(apiKey: "test")
        let spend = await provider.currentSessionSpend
        #expect(spend == 0.0)
    }

    @Test("Custom base URL is respected")
    func customBaseURL() throws {
        let provider = OpenRouterProvider(
            apiKey: "key",
            baseURL: "http://localhost:8080"
        )

        let body = OpenRouterRequest(
            model: "test-model",
            messages: [.init(role: "user", content: "Hi")],
            maxTokens: nil
        )

        let request = try provider.buildRequest(body: body)
        #expect(request.url?.absoluteString == "http://localhost:8080/chat/completions")
    }
}
