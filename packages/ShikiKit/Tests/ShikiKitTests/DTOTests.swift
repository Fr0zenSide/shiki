import Testing
import Foundation
@testable import ShikiKit

@Suite("Project/Session/Agent DTOs")
struct ProjectSessionAgentDTOTests {

    // MARK: - Helpers

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

    // MARK: - ProjectDTO

    @Test("ProjectDTO encodes to expected JSON with snake_case keys")
    func test_projectDTO_encodesToExpectedJSON() throws {
        let id = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let date = ISO8601DateFormatter().date(from: "2026-03-09T00:00:00Z")!
        let project = ProjectDTO(
            id: id,
            slug: "shiki",
            name: "Shiki",
            description: "AI orchestration platform",
            repoUrl: "https://github.com/example/shiki",
            createdAt: date,
            updatedAt: date,
            metadata: [:]
        )

        let data = try Self.encoder.encode(project)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"repo_url\""))
        #expect(json.contains("\"created_at\""))
        #expect(json.contains("\"updated_at\""))
        #expect(json.contains("\"shiki\""))
    }

    @Test("ProjectDTO decodes from server JSON with snake_case keys")
    func test_projectDTO_decodesFromServerJSON() throws {
        let json = """
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "slug": "shiki",
            "name": "Shiki",
            "description": "AI orchestration",
            "repo_url": "https://github.com/example/shiki",
            "created_at": "2026-03-09T00:00:00Z",
            "updated_at": "2026-03-09T00:00:00Z",
            "metadata": {}
        }
        """

        let project = try Self.decoder.decode(ProjectDTO.self, from: Data(json.utf8))

        #expect(project.slug == "shiki")
        #expect(project.name == "Shiki")
        #expect(project.repoUrl == "https://github.com/example/shiki")
        #expect(project.description == "AI orchestration")
    }

    // MARK: - SessionDTO

    @Test("SessionDTO round-trips through JSON")
    func test_sessionDTO_roundTrips() throws {
        let session = SessionDTO(
            id: UUID(),
            projectId: UUID(),
            name: "Test Session",
            branch: "feature/test",
            status: .active
        )

        let data = try Self.encoder.encode(session)
        let decoded = try Self.decoder.decode(SessionDTO.self, from: data)

        #expect(decoded.name == session.name)
        #expect(decoded.branch == session.branch)
        #expect(decoded.status == .active)
        #expect(decoded.projectId == session.projectId)
    }

    // MARK: - AgentDTO

    // MARK: - AgentEventDTO

    @Test("AgentEventDTO round-trips through JSON")
    func test_agentEventDTO_roundTrips() throws {
        let event = AgentEventDTO(
            agentId: UUID(),
            sessionId: UUID(),
            projectId: UUID(),
            eventType: "phase_complete",
            payload: ["phase": .string("synthesis")],
            progressPct: 75,
            message: "Phase completed"
        )

        let data = try Self.encoder.encode(event)
        let decoded = try Self.decoder.decode(AgentEventDTO.self, from: data)

        #expect(decoded.eventType == "phase_complete")
        #expect(decoded.progressPct == 75)
        #expect(decoded.message == "Phase completed")
        #expect(decoded.payload["phase"] == .string("synthesis"))
    }

    @Test("AgentDTO round-trips with all fields")
    func test_agentDTO_roundTrips() throws {
        let agent = AgentDTO(
            id: UUID(),
            sessionId: UUID(),
            projectId: UUID(),
            handle: "@Sensei",
            role: "CTO",
            model: "claude-opus-4",
            status: .running,
            parentId: UUID()
        )

        let data = try Self.encoder.encode(agent)
        let decoded = try Self.decoder.decode(AgentDTO.self, from: data)

        #expect(decoded.handle == "@Sensei")
        #expect(decoded.role == "CTO")
        #expect(decoded.status == .running)
        #expect(decoded.parentId == agent.parentId)
    }
}
