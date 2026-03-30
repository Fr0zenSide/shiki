import Foundation
import Testing
@testable import ShikkiMCP

@Suite("ShikkiDB Client")
struct ShikkiDBClientTests {

    @Test("dataSyncWrite builds correct POST request via mock")
    func dataSyncWriteViaMock() async throws {
        let mock = MockDBClient()
        mock.dataSyncResult = .object(["id": .string("saved-123")])

        let result = try await mock.dataSyncWrite(
            type: "decision",
            scope: "shikki",
            data: ["question": .string("test")]
        )

        #expect(mock.lastWriteType == "decision")
        #expect(mock.lastWriteScope == "shikki")
        #expect(result["id"]?.stringValue == "saved-123")
    }

    @Test("HTTP 422 returns validation error — NOT silent failure")
    func http422ReturnsError() async {
        let mock = MockDBClient()
        mock.shouldThrow = .httpError(statusCode: 422, body: "{\"error\":\"Missing field\"}")

        do {
            _ = try await mock.dataSyncWrite(type: "test", scope: "shikki", data: [:])
            Issue.record("Should have thrown")
        } catch let error as ShikkiDBError {
            if case .httpError(let code, let body) = error {
                #expect(code == 422)
                #expect(body.contains("Missing field"))
            } else {
                Issue.record("Expected httpError, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("HTTP 500 returns server error")
    func http500ReturnsError() async {
        let mock = MockDBClient()
        mock.shouldThrow = .httpError(statusCode: 500, body: "Internal server error")

        do {
            _ = try await mock.memoriesSearch(query: "test", projectIds: nil, types: nil, limit: 10)
            Issue.record("Should have thrown")
        } catch let error as ShikkiDBError {
            if case .httpError(let code, _) = error {
                #expect(code == 500)
            } else {
                Issue.record("Expected httpError")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Connection refused returns clear error message")
    func connectionRefusedError() async {
        let mock = MockDBClient()
        mock.shouldThrow = .connectionRefused(underlying: "Could not connect to the server")

        do {
            _ = try await mock.healthCheck()
            Issue.record("Should have thrown")
        } catch let error as ShikkiDBError {
            let description = error.description
            #expect(description.contains("Connection refused"))
            #expect(description.contains("ShikkiDB running"))
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("healthCheck returns true when healthy")
    func healthCheckHealthy() async throws {
        let mock = MockDBClient()
        mock.healthResult = true
        let result = try await mock.healthCheck()
        #expect(result == true)
    }

    @Test("healthCheck returns false when unhealthy")
    func healthCheckUnhealthy() async throws {
        let mock = MockDBClient()
        mock.healthResult = false
        let result = try await mock.healthCheck()
        #expect(result == false)
    }

    @Test("ShikkiDBError descriptions are human-readable")
    func errorDescriptions() {
        let errors: [(ShikkiDBError, String)] = [
            (.httpError(statusCode: 404, body: "Not found"), "HTTP 404"),
            (.connectionRefused(underlying: "timeout"), "Connection refused"),
            (.invalidURL("bad://url"), "Invalid URL"),
            (.decodingError("bad json"), "Decoding error"),
            (.unexpectedError("oops"), "Unexpected error"),
            (.retriesExhausted(lastError: "timeout", attempts: 3), "Retries exhausted"),
        ]

        for (error, expected) in errors {
            #expect(error.description.contains(expected))
        }
    }

    @Test("ShikkiDBError transient classification")
    func errorTransientClassification() {
        // Transient errors should be retryable
        #expect(ShikkiDBError.connectionRefused(underlying: "timeout").isTransient == true)
        #expect(ShikkiDBError.httpError(statusCode: 500, body: "").isTransient == true)
        #expect(ShikkiDBError.httpError(statusCode: 502, body: "").isTransient == true)
        #expect(ShikkiDBError.httpError(statusCode: 503, body: "").isTransient == true)
        #expect(ShikkiDBError.httpError(statusCode: 429, body: "").isTransient == true)

        // Non-transient errors should NOT be retried
        #expect(ShikkiDBError.httpError(statusCode: 400, body: "").isTransient == false)
        #expect(ShikkiDBError.httpError(statusCode: 404, body: "").isTransient == false)
        #expect(ShikkiDBError.httpError(statusCode: 422, body: "").isTransient == false)
        #expect(ShikkiDBError.invalidURL("bad").isTransient == false)
        #expect(ShikkiDBError.decodingError("bad").isTransient == false)
        #expect(ShikkiDBError.unexpectedError("oops").isTransient == false)
        #expect(ShikkiDBError.retriesExhausted(lastError: "x", attempts: 3).isTransient == false)
    }

    @Test("Project ID resolution for known projects")
    func projectIdResolution() {
        #expect(ShikkiDBClient.resolveProjectId("shikki") == "80c27043-5282-4814-b79d-5e6d3903cbc9")
        #expect(ShikkiDBClient.resolveProjectId("shiki") == "80c27043-5282-4814-b79d-5e6d3903cbc9")
        #expect(ShikkiDBClient.resolveProjectId("maya") == "bb9e4385-f087-4f65-8251-470f14230c3c")
        #expect(ShikkiDBClient.resolveProjectId("research") == "1b6da95d-6a93-4048-a975-f20e7885e669")
    }

    @Test("Project ID resolution is case-insensitive")
    func projectIdResolutionCaseInsensitive() {
        #expect(ShikkiDBClient.resolveProjectId("SHIKKI") == "80c27043-5282-4814-b79d-5e6d3903cbc9")
        #expect(ShikkiDBClient.resolveProjectId("Maya") == "bb9e4385-f087-4f65-8251-470f14230c3c")
    }

    @Test("Project ID resolution returns nil for unknown projects")
    func projectIdResolutionUnknown() {
        #expect(ShikkiDBClient.resolveProjectId("unknown_project") == nil)
        #expect(ShikkiDBClient.resolveProjectId("") == nil)
    }

    @Test("RetryConfig delay calculation")
    func retryConfigDelay() {
        let config = RetryConfig(maxAttempts: 5, baseDelayMs: 100, maxDelayMs: 2000)
        #expect(config.delay(forAttempt: 0) == 0)
        #expect(config.delay(forAttempt: 1) == 100)
        #expect(config.delay(forAttempt: 2) == 200)
        #expect(config.delay(forAttempt: 3) == 400)
        #expect(config.delay(forAttempt: 4) == 800)
    }

    @Test("RetryConfig caps at maxDelay")
    func retryConfigMaxDelay() {
        let config = RetryConfig(maxAttempts: 10, baseDelayMs: 500, maxDelayMs: 1000)
        #expect(config.delay(forAttempt: 5) == 1000)
        #expect(config.delay(forAttempt: 10) == 1000)
    }

    @Test("RetryConfig.none has single attempt")
    func retryConfigNone() {
        #expect(RetryConfig.none.maxAttempts == 1)
        #expect(RetryConfig.none.baseDelayMs == 0)
    }

    @Test("RetryConfig.default has 3 attempts")
    func retryConfigDefault() {
        #expect(RetryConfig.default.maxAttempts == 3)
        #expect(RetryConfig.default.baseDelayMs == 200)
        #expect(RetryConfig.default.maxDelayMs == 2000)
    }
}
