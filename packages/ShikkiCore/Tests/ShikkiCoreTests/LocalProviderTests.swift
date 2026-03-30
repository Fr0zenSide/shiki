import Foundation
import Testing
@testable import ShikiCore

@Suite("LocalProvider")
struct LocalProviderTests {

    @Test("Provider name is 'local'")
    func providerName() {
        let provider = LocalProvider()
        #expect(provider.name == "local")
    }

    @Test("Session spend is always zero (local inference)")
    func zeroSpend() async {
        let provider = LocalProvider()
        let spend = await provider.currentSessionSpend
        #expect(spend == 0.0)
    }

    @Test("Build request targets local endpoint")
    func buildRequest() throws {
        let provider = LocalProvider(
            endpoint: "http://127.0.0.1:1234",
            modelName: "llama-3"
        )

        let body = LocalCompletionRequest(
            model: "llama-3",
            messages: [.init(role: "user", content: "Summarize this")],
            maxTokens: 4096
        )

        let request = try provider.buildRequest(body: body)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "http://127.0.0.1:1234/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        // No auth header for local inference
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("Response decodes correctly")
    func responseDecoding() throws {
        let json = """
        {
            "choices": [
                {
                    "message": {
                        "role": "assistant",
                        "content": "Local model response"
                    }
                }
            ],
            "usage": {
                "prompt_tokens": 5,
                "completion_tokens": 10,
                "total_tokens": 15
            }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(LocalCompletionResponse.self, from: json)
        #expect(response.choices.count == 1)
        #expect(response.choices[0].message.content == "Local model response")
        #expect(response.usage?.totalTokens == 15)
    }

    @Test("Custom endpoint is respected")
    func customEndpoint() throws {
        let provider = LocalProvider(endpoint: "http://192.168.1.100:8080")

        let body = LocalCompletionRequest(
            model: "phi-3",
            messages: [.init(role: "user", content: "Test")],
            maxTokens: 1000
        )

        let request = try provider.buildRequest(body: body)
        #expect(request.url?.absoluteString == "http://192.168.1.100:8080/v1/chat/completions")
    }
}
