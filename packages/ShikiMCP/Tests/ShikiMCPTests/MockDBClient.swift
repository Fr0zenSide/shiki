import Foundation
@testable import ShikiMCP

/// Mock ShikiDB client for testing tool logic without network calls
final class MockDBClient: ShikiDBClientProtocol, @unchecked Sendable {
    var dataSyncResult: JSONValue = .object(["id": .string("mock-id-123")])
    var searchResult: JSONValue = .array([])
    var healthResult: Bool = true
    var shouldThrow: ShikiDBError?

    // Capture last calls for assertions
    var lastWriteType: String?
    var lastWriteScope: String?
    var lastWriteData: [String: JSONValue]?
    var lastSearchQuery: String?
    var lastSearchProjectIds: [String]?
    var lastSearchTypes: [String]?
    var lastSearchLimit: Int?

    var lastWriteProjectId: String?

    func dataSyncWrite(type: String, scope: String, data: [String: JSONValue], projectId: String? = nil) async throws -> JSONValue {
        lastWriteType = type
        lastWriteScope = scope
        lastWriteData = data
        lastWriteProjectId = projectId
        if let error = shouldThrow { throw error }
        return dataSyncResult
    }

    func memoriesSearch(query: String, projectIds: [String]?, types: [String]?, limit: Int) async throws -> JSONValue {
        lastSearchQuery = query
        lastSearchProjectIds = projectIds
        lastSearchTypes = types
        lastSearchLimit = limit
        if let error = shouldThrow { throw error }
        return searchResult
    }

    func healthCheck() async throws -> Bool {
        if let error = shouldThrow { throw error }
        return healthResult
    }
}
