import Testing
import Foundation
@testable import ShikiMCP

@Suite("ShikiDB Client")
struct ShikiDBClientTests {

    @Test("dataSyncWrite builds correct POST request via mock")
    func dataSyncWriteViaMock() async throws {
        let mock = MockDBClient()
        mock.dataSyncResult = .object(["id": .string("saved-123")])

        let result = try await mock.dataSyncWrite(
            type: "decision",
            scope: "shiki",
            data: ["question": .string("test")]
        )

        #expect(mock.lastWriteType == "decision")
        #expect(mock.lastWriteScope == "shiki")
        #expect(result["id"]?.stringValue == "saved-123")
    }

    @Test("HTTP 422 returns validation error — NOT silent failure")
    func http422ReturnsError() async {
        let mock = MockDBClient()
        mock.shouldThrow = .httpError(statusCode: 422, body: "{\"error\":\"Missing field\"}")

        do {
            _ = try await mock.dataSyncWrite(type: "test", scope: "shiki", data: [:])
            Issue.record("Should have thrown")
        } catch let error as ShikiDBError {
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
        } catch let error as ShikiDBError {
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
        } catch let error as ShikiDBError {
            let description = error.description
            #expect(description.contains("Connection refused"))
            #expect(description.contains("ShikiDB running"))
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

    @Test("ShikiDBError descriptions are human-readable")
    func errorDescriptions() {
        let errors: [(ShikiDBError, String)] = [
            (.httpError(statusCode: 404, body: "Not found"), "HTTP 404"),
            (.connectionRefused(underlying: "timeout"), "Connection refused"),
            (.invalidURL("bad://url"), "Invalid URL"),
            (.decodingError("bad json"), "Decoding error"),
            (.unexpectedError("oops"), "Unexpected error"),
        ]

        for (error, expected) in errors {
            #expect(error.description.contains(expected))
        }
    }
}
