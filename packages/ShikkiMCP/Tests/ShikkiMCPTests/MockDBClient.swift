import Foundation
@testable import ShikkiMCP

/// Mock ShikkiDB client for testing tool logic without network calls
final class MockDBClient: ShikkiDBClientProtocol, @unchecked Sendable {
    var dataSyncResult: JSONValue = .object(["id": .string("mock-id-123")])
    var searchResult: JSONValue = .array([])
    var healthResult: Bool = true
    var shouldThrow: ShikkiDBError?

    // Capture last calls for assertions
    var lastWriteType: String?
    var lastWriteScope: String?
    var lastWriteData: [String: JSONValue]?
    var lastWriteProjectId: String?
    var lastSearchQuery: String?
    var lastSearchProjectIds: [String]?
    var lastSearchTypes: [String]?
    var lastSearchLimit: Int?

    // Call counters for retry testing
    var writeCallCount: Int = 0
    var searchCallCount: Int = 0
    var healthCallCount: Int = 0

    // Configurable failure sequence: throw for first N calls, then succeed
    var failForFirstNCalls: Int = 0

    func dataSyncWrite(type: String, scope: String, data: [String: JSONValue], projectId: String? = nil) async throws -> JSONValue {
        writeCallCount += 1
        lastWriteType = type
        lastWriteScope = scope
        lastWriteData = data
        lastWriteProjectId = projectId

        if writeCallCount <= failForFirstNCalls {
            throw shouldThrow ?? ShikkiDBError.connectionRefused(underlying: "mock transient failure")
        }

        if let error = shouldThrow { throw error }
        return dataSyncResult
    }

    func memoriesSearch(query: String, projectIds: [String]?, types: [String]?, limit: Int) async throws -> JSONValue {
        searchCallCount += 1
        lastSearchQuery = query
        lastSearchProjectIds = projectIds
        lastSearchTypes = types
        lastSearchLimit = limit

        if searchCallCount <= failForFirstNCalls {
            throw shouldThrow ?? ShikkiDBError.connectionRefused(underlying: "mock transient failure")
        }

        if let error = shouldThrow { throw error }
        return searchResult
    }

    func healthCheck() async throws -> Bool {
        healthCallCount += 1
        if let error = shouldThrow { throw error }
        return healthResult
    }

    func reset() {
        dataSyncResult = .object(["id": .string("mock-id-123")])
        searchResult = .array([])
        healthResult = true
        shouldThrow = nil
        lastWriteType = nil
        lastWriteScope = nil
        lastWriteData = nil
        lastWriteProjectId = nil
        lastSearchQuery = nil
        lastSearchProjectIds = nil
        lastSearchTypes = nil
        lastSearchLimit = nil
        writeCallCount = 0
        searchCallCount = 0
        healthCallCount = 0
        failForFirstNCalls = 0
    }
}
