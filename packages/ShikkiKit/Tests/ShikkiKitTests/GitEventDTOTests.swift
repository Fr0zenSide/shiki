import Testing
import Foundation
@testable import ShikkiKit

@Suite("GitEvent DTOs")
struct GitEventDTOTests {

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

    // MARK: - PrCreatedInput

    @Test("PrCreatedInput round-trips through JSON with snake_case keys")
    func test_prCreatedInput_roundTrips() throws {
        let input = PrCreatedInput(
            projectId: UUID(),
            prUrl: "https://github.com/example/shiki/pull/42",
            title: "feat: add new DTO types",
            branch: "feature/dtos"
        )

        let data = try Self.encoder.encode(input)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"pr_url\""))
        #expect(json.contains("\"project_id\""))
        #expect(json.contains("\"base_branch\""))

        let decoded = try Self.decoder.decode(PrCreatedInput.self, from: data)
        #expect(decoded.prUrl == input.prUrl)
        #expect(decoded.title == input.title)
        #expect(decoded.baseBranch == "main")
    }

    @Test("PrCreatedInput validates required fields")
    func test_prCreatedInput_validatesRequiredFields() {
        let invalid = PrCreatedInput(
            projectId: UUID(),
            prUrl: "",
            title: "Some PR",
            branch: "feature/test"
        )
        #expect(throws: ShikkiValidationError.self) {
            try invalid.validate()
        }
    }

    @Test("PrCreatedInput rejects empty title")
    func test_prCreatedInput_rejectsEmptyTitle() {
        let invalid = PrCreatedInput(
            projectId: UUID(),
            prUrl: "https://github.com/example/shiki/pull/1",
            title: "  ",
            branch: "feature/test"
        )
        #expect(throws: ShikkiValidationError.self) {
            try invalid.validate()
        }
    }

    // MARK: - GitEventDTO

    @Test("GitEventDTO round-trips through JSON")
    func test_gitEventDTO_roundTrips() throws {
        let event = GitEventDTO(
            projectId: UUID(),
            eventType: "pr_created",
            ref: "feature/new-dtos",
            commitMsg: "feat: add DTO types"
        )

        let data = try Self.encoder.encode(event)
        let decoded = try Self.decoder.decode(GitEventDTO.self, from: data)

        #expect(decoded.eventType == "pr_created")
        #expect(decoded.ref == "feature/new-dtos")
        #expect(decoded.commitMsg == "feat: add DTO types")
    }

    @Test("GitEventDTO decodes from server JSON")
    func test_gitEventDTO_decodesFromServerJSON() throws {
        let json = """
        {
            "occurred_at": "2026-03-09T12:00:00Z",
            "project_id": "11111111-1111-1111-1111-111111111111",
            "session_id": null,
            "agent_id": null,
            "event_type": "pr_created",
            "ref": "feature/test",
            "commit_msg": "feat: test",
            "metadata": {}
        }
        """

        let event = try Self.decoder.decode(GitEventDTO.self, from: Data(json.utf8))
        #expect(event.eventType == "pr_created")
        #expect(event.ref == "feature/test")
        #expect(event.sessionId == nil)
    }
}
