import Testing
import Foundation
@testable import ShikkiKit

@Suite("Memory DTOs + Validation")
struct MemoryDTOTests {

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    @Test("MemoryInput validates required fields")
    func test_memoryInput_validatesRequiredFields() throws {
        let valid = MemoryInput(
            projectId: UUID(),
            content: "Some knowledge",
            category: "general",
            importance: 5.0
        )
        // Should not throw
        try valid.validate()
    }

    @Test("MemoryInput rejects empty content")
    func test_memoryInput_rejectsEmptyContent() {
        let invalid = MemoryInput(
            projectId: UUID(),
            content: "",
            category: "general"
        )
        #expect(throws: ShikkiValidationError.self) {
            try invalid.validate()
        }
    }

    @Test("MemorySearchInput rejects negative limit")
    func test_memorySearchInput_rejectsNegativeLimit() {
        let invalid = MemorySearchInput(
            query: "test query",
            projectId: UUID(),
            limit: -1
        )
        #expect(throws: ShikkiValidationError.self) {
            try invalid.validate()
        }
    }

    @Test("MemorySearchRequest encodes all fields")
    func test_memorySearchRequest_encodesAllFields() throws {
        let projectId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let input = MemorySearchInput(
            query: "architecture patterns",
            projectId: projectId,
            limit: 20,
            threshold: 0.8
        )

        let data = try Self.encoder.encode(input)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"query\""))
        #expect(json.contains("\"project_id\""))
        #expect(json.contains("\"limit\""))
        #expect(json.contains("\"threshold\""))
        #expect(json.contains("architecture patterns"))
    }

    @Test("MemorySearchResult round-trips")
    func test_memorySearchResult_roundTrips() throws {
        let result = MemorySearchResult(
            id: UUID(),
            projectId: UUID(),
            content: "Test memory",
            category: "testing",
            importance: 3.0,
            similarity: 0.95,
            createdAt: Date()
        )

        let data = try Self.encoder.encode(result)
        let decoded = try Self.decoder.decode(MemorySearchResult.self, from: data)

        #expect(decoded.content == "Test memory")
        #expect(decoded.similarity == 0.95)
        #expect(decoded.category == "testing")
    }
}
