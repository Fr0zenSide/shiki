import Testing
import Foundation
@testable import ShikkiCore

// MARK: - Mock URLProtocol

/// Shared mock URL protocol for HTTP-based provider tests.
/// All tests using this MUST be inside the same .serialized suite.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (Data, HTTPURLResponse))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        do {
            let (data, response) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

func makeMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

func makeSuccessResponse(url: String, content: String = "Hello", tokens: Int = 100) -> (Data, HTTPURLResponse) {
    let json: [String: Any] = [
        "choices": [["message": ["content": content]]],
        "usage": ["total_tokens": tokens]
    ]
    let data = try! JSONSerialization.data(withJSONObject: json)
    let response = HTTPURLResponse(url: URL(string: url)!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    return (data, response)
}

// All HTTP-mock tests in one serialized suite to avoid MockURLProtocol handler races.
@Suite("HTTP Provider Tests", .serialized)
struct HTTPProviderTests {

    // MARK: - OpenRouterProvider

    @Test("OpenRouter: request includes correct URL, method, and headers")
    func openRouterRequestBuilding() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return makeSuccessResponse(url: request.url!.absoluteString)
        }

        let provider = OpenRouterProvider(
            apiKey: "test-key",
            baseURL: "https://mock.openrouter.ai/api/v1",
            session: makeMockSession()
        )
        _ = try await provider.dispatch(
            prompt: "test",
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            options: AgentOptions()
        )

        let req = try #require(capturedRequest)
        #expect(req.url?.absoluteString == "https://mock.openrouter.ai/api/v1/chat/completions")
        #expect(req.httpMethod == "POST")
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        #expect(req.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test("OpenRouter: request body contains model and prompt")
    func openRouterRequestBody() async throws {
        var capturedBody: [String: Any]?
        MockURLProtocol.requestHandler = { request in
            // URLSession may nil out httpBody; read from httpBodyStream as fallback
            let data: Data?
            if let body = request.httpBody {
                data = body
            } else if let stream = request.httpBodyStream {
                stream.open()
                var buffer = Data()
                let chunk = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
                defer { chunk.deallocate() }
                while stream.hasBytesAvailable {
                    let read = stream.read(chunk, maxLength: 4096)
                    if read > 0 { buffer.append(chunk, count: read) }
                    else { break }
                }
                stream.close()
                data = buffer
            } else {
                data = nil
            }
            if let data {
                capturedBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            }
            return makeSuccessResponse(url: request.url!.absoluteString)
        }

        let provider = OpenRouterProvider(
            apiKey: "test-key",
            baseURL: "https://mock.openrouter.ai/api/v1",
            session: makeMockSession()
        )
        _ = try await provider.dispatch(
            prompt: "hello world",
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            options: AgentOptions(model: "google/gemini-flash")
        )

        let body = try #require(capturedBody)
        #expect(body["model"] as? String == "google/gemini-flash")
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages.first?["content"] == "hello world")
    }

    @Test("OpenRouter: parses token usage from response")
    func openRouterTokenParsing() async throws {
        MockURLProtocol.requestHandler = { request in
            return makeSuccessResponse(url: request.url!.absoluteString, content: "result", tokens: 2500)
        }

        let provider = OpenRouterProvider(
            apiKey: "test-key",
            baseURL: "https://mock.openrouter.ai/api/v1",
            session: makeMockSession()
        )
        let result = try await provider.dispatch(
            prompt: "test",
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            options: AgentOptions()
        )

        #expect(result.output == "result")
        #expect(result.tokensUsed == 2500)
        #expect(result.exitCode == 0)
    }

    @Test("OpenRouter: spend accumulates across dispatches")
    func openRouterSpendAccumulation() async throws {
        MockURLProtocol.requestHandler = { request in
            return makeSuccessResponse(url: request.url!.absoluteString, tokens: 1000)
        }

        let provider = OpenRouterProvider(
            apiKey: "test-key",
            baseURL: "https://mock.openrouter.ai/api/v1",
            session: makeMockSession()
        )
        _ = try await provider.dispatch(prompt: "a", workingDirectory: URL(fileURLWithPath: "/tmp"), options: AgentOptions())
        _ = try await provider.dispatch(prompt: "b", workingDirectory: URL(fileURLWithPath: "/tmp"), options: AgentOptions())

        let spend = await provider.currentSessionSpend
        #expect(spend > 0)
    }

    @Test("OpenRouter: 401 maps to authenticationFailed")
    func openRouterAuthError() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        }

        let provider = OpenRouterProvider(
            apiKey: "bad-key",
            baseURL: "https://mock.openrouter.ai/api/v1",
            session: makeMockSession()
        )
        await #expect(throws: AgentProviderError.authenticationFailed(provider: "openrouter")) {
            try await provider.dispatch(prompt: "test", workingDirectory: URL(fileURLWithPath: "/tmp"), options: AgentOptions())
        }
    }

    @Test("OpenRouter: 429 maps to rateLimited")
    func openRouterRateLimitError() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 429, httpVersion: nil,
                headerFields: ["Retry-After": "30"]
            )!
            return (Data(), response)
        }

        let provider = OpenRouterProvider(
            apiKey: "test-key",
            baseURL: "https://mock.openrouter.ai/api/v1",
            session: makeMockSession()
        )
        await #expect(throws: AgentProviderError.rateLimited(retryAfterSeconds: 30)) {
            try await provider.dispatch(prompt: "test", workingDirectory: URL(fileURLWithPath: "/tmp"), options: AgentOptions())
        }
    }

    // MARK: - LocalProvider

    @Test("Local: request targets localhost with correct path")
    func localRequestToLocalhost() async throws {
        var capturedURL: URL?
        MockURLProtocol.requestHandler = { request in
            capturedURL = request.url
            let json: [String: Any] = [
                "choices": [["message": ["content": "local result"]]],
                "usage": ["total_tokens": 50]
            ]
            let data = try! JSONSerialization.data(withJSONObject: json)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }

        let provider = LocalProvider(baseURL: "http://127.0.0.1:9999", session: makeMockSession())
        let result = try await provider.dispatch(
            prompt: "test",
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            options: AgentOptions()
        )

        #expect(capturedURL?.absoluteString == "http://127.0.0.1:9999/v1/chat/completions")
        #expect(result.output == "local result")
    }

    @Test("Local: spend is always zero")
    func localZeroSpend() async throws {
        MockURLProtocol.requestHandler = { request in
            let json: [String: Any] = [
                "choices": [["message": ["content": "ok"]]],
                "usage": ["total_tokens": 5000]
            ]
            let data = try! JSONSerialization.data(withJSONObject: json)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }

        let provider = LocalProvider(baseURL: "http://127.0.0.1:9999", session: makeMockSession())
        _ = try await provider.dispatch(prompt: "test", workingDirectory: URL(fileURLWithPath: "/tmp"), options: AgentOptions())

        let spend = await provider.currentSessionSpend
        #expect(spend == 0)
    }

    @Test("Local: health check failure throws unavailable")
    func localHealthCheckFailure() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        }

        let provider = LocalProvider(baseURL: "http://127.0.0.1:9999", session: makeMockSession())
        await #expect(throws: AgentProviderError.unavailable(provider: "local")) {
            try await provider.dispatch(prompt: "test", workingDirectory: URL(fileURLWithPath: "/tmp"), options: AgentOptions())
        }
    }

    @Test("Local: provider name is 'local'")
    func localProviderName() async {
        let provider = LocalProvider()
        #expect(provider.name == "local")
    }
}
