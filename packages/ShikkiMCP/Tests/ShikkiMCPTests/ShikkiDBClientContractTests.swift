import Foundation
import Testing
@testable import ShikkiMCP

@Suite("ShikkiDBClient Contract Tests")
struct ShikkiDBClientContractTests {

    /// Port 1 is always refused — gives us a real client against an unreachable host.
    private func unreachableClient() -> ShikkiDBClient {
        ShikkiDBClient(baseURL: "http://127.0.0.1:1", retryConfig: .none)
    }

    @Test("Real client throws connectionRefused for unreachable host")
    func connectionRefused() async throws {
        let client = unreachableClient()
        do {
            _ = try await client.dataSyncWrite(type: "test", scope: "test", data: [:])
            Issue.record("Should have thrown")
        } catch let error as ShikkiDBError {
            switch error {
            case .connectionRefused:
                break // expected
            default:
                Issue.record("Expected connectionRefused, got \(error)")
            }
        }
    }

    @Test("Real client builds valid URL without crashing")
    func urlBuilding() async throws {
        let client = unreachableClient()
        do {
            _ = try await client.healthCheck()
        } catch {
            // Expected to fail — just verifying no crash on URL construction
        }
        // If we got here, URL building works
    }

    @Test("Real client distinguishes connection error from HTTP error")
    func errorDiscrimination() async throws {
        let client = unreachableClient()

        // Connection refused should be .connectionRefused, NOT .httpError
        do {
            _ = try await client.memoriesSearch(query: "test", projectIds: nil, types: nil, limit: 5)
            Issue.record("Should have thrown")
        } catch let error as ShikkiDBError {
            switch error {
            case .connectionRefused:
                break // correct — connection refused is NOT an HTTP error
            case .httpError:
                Issue.record("Connection refused should be connectionRefused, not httpError")
            default:
                break // other error types acceptable (e.g. unexpectedError wrapping URLError)
            }
        }
    }

    @Test("Health check returns false for unreachable host")
    func healthCheckUnreachable() async throws {
        let client = unreachableClient()
        let healthy = try await client.healthCheck()
        #expect(!healthy)
    }
}
