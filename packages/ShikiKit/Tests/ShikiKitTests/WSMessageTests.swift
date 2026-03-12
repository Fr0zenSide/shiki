import Testing
import Foundation
@testable import ShikiKit

@Suite("WebSocket Messages + Channels + Routes")
struct WSMessageTests {

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private static let decoder = JSONDecoder()

    // MARK: - WSMessage subscribe

    @Test("WSMessage subscribe encodes to expected format")
    func test_wsSubscribeMessage_encodesToExpectedFormat() throws {
        let message = WSMessage.subscribe(channel: "project:11111111-1111-1111-1111-111111111111")

        let data = try Self.encoder.encode(message)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"type\":\"subscribe\""))
        #expect(json.contains("\"channel\":\"project:11111111-1111-1111-1111-111111111111\""))
    }

    @Test("WSMessage subscribe round-trips")
    func test_wsSubscribeMessage_roundTrips() throws {
        let original = WSMessage.subscribe(channel: "project:abc")

        let data = try Self.encoder.encode(original)
        let decoded = try Self.decoder.decode(WSMessage.self, from: data)

        #expect(decoded == original)
    }

    // MARK: - WSMessage unsubscribe

    @Test("WSMessage unsubscribe encodes to expected format")
    func test_wsUnsubscribeMessage_encodesToExpectedFormat() throws {
        let message = WSMessage.unsubscribe(channel: "project:22222222-2222-2222-2222-222222222222")

        let data = try Self.encoder.encode(message)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"type\":\"unsubscribe\""))
        #expect(json.contains("\"channel\""))
    }

    // MARK: - WSMessage chat

    @Test("WSMessage chat encodes all fields")
    func test_wsChatMessage_encodesAllFields() throws {
        let sessionId = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let projectId = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let agentId = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!

        let payload = WSChatPayload(
            sessionId: sessionId,
            projectId: projectId,
            agentId: agentId,
            role: .assistant,
            content: "Hello from @Sensei"
        )
        let message = WSMessage.chat(payload)

        let data = try Self.encoder.encode(message)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"type\":\"chat\""))
        #expect(json.contains("\"session_id\""))
        #expect(json.contains("\"project_id\""))
        #expect(json.contains("\"agent_id\""))
        #expect(json.contains("\"role\":\"assistant\""))
        #expect(json.contains("Hello from @Sensei"))

        let decoded = try Self.decoder.decode(WSMessage.self, from: data)
        #expect(decoded == message)
    }

    @Test("WSMessage rejects unknown type")
    func test_wsMessage_rejectsUnknownType() {
        let json = """
        { "type": "unknown_type", "data": "something" }
        """
        #expect(throws: DecodingError.self) {
            _ = try Self.decoder.decode(WSMessage.self, from: Data(json.utf8))
        }
    }

    // MARK: - WSChannel

    @Test("WSChannel.project generates correct channel string")
    func test_wsChannel_project() {
        let id = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let channel = WSChannel.project(id)
        #expect(channel == "project:11111111-1111-1111-1111-111111111111")
    }

    @Test("WSChannel.extractId parses UUID from channel")
    func test_wsChannel_extractId() {
        let id = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let channel = "project:\(id.uuidString.lowercased())"
        let extracted = WSChannel.extractId(from: channel)
        #expect(extracted == id)
    }

    @Test("WSChannel.extractId returns nil for invalid format")
    func test_wsChannel_extractIdReturnsNilForInvalid() {
        #expect(WSChannel.extractId(from: "invalid") == nil)
        #expect(WSChannel.extractId(from: "project:not-a-uuid") == nil)
    }

    @Test("WSChannel.prefix extracts correct prefix")
    func test_wsChannel_prefix() {
        #expect(WSChannel.prefix(of: "project:abc") == "project")
        #expect(WSChannel.prefix(of: "session:xyz") == "session")
        #expect(WSChannel.prefix(of: "nocolon") == nil)
    }

    // MARK: - ShikiRoutes

    @Test("ShikiRoutes static paths match Deno routes")
    func test_shikiRoutes_staticPaths() {
        #expect(ShikiRoutes.health == "/health")
        #expect(ShikiRoutes.healthFull == "/health/full")
        #expect(ShikiRoutes.projects == "/api/projects")
        #expect(ShikiRoutes.sessions == "/api/sessions")
        #expect(ShikiRoutes.sessionsActive == "/api/sessions/active")
        #expect(ShikiRoutes.agents == "/api/agents")
        #expect(ShikiRoutes.agentUpdate == "/api/agent-update")
        #expect(ShikiRoutes.agentEvents == "/api/agent-events")
        #expect(ShikiRoutes.statsUpdate == "/api/stats-update")
        #expect(ShikiRoutes.memories == "/api/memories")
        #expect(ShikiRoutes.memoriesSearch == "/api/memories/search")
        #expect(ShikiRoutes.memoriesSources == "/api/memories/sources")
        #expect(ShikiRoutes.chatMessage == "/api/chat-message")
        #expect(ShikiRoutes.chatMessages == "/api/chat-messages")
        #expect(ShikiRoutes.dataSync == "/api/data-sync")
        #expect(ShikiRoutes.prCreated == "/api/pr-created")
        #expect(ShikiRoutes.gitEvents == "/api/git-events")
        #expect(ShikiRoutes.dashboardSummary == "/api/dashboard/summary")
        #expect(ShikiRoutes.dashboardPerformance == "/api/dashboard/performance")
        #expect(ShikiRoutes.dashboardActivity == "/api/dashboard/activity")
        #expect(ShikiRoutes.dashboardCosts == "/api/dashboard/costs")
        #expect(ShikiRoutes.dashboardGit == "/api/dashboard/git")
        #expect(ShikiRoutes.ingest == "/api/ingest")
        #expect(ShikiRoutes.ingestSources == "/api/ingest/sources")
        #expect(ShikiRoutes.radarWatchlist == "/api/radar/watchlist")
        #expect(ShikiRoutes.radarScan == "/api/radar/scan")
        #expect(ShikiRoutes.radarScans == "/api/radar/scans")
        #expect(ShikiRoutes.radarDigestLatest == "/api/radar/digest/latest")
        #expect(ShikiRoutes.radarIngest == "/api/radar/ingest")
        #expect(ShikiRoutes.pipelines == "/api/pipelines")
        #expect(ShikiRoutes.pipelinesLatest == "/api/pipelines/latest")
        #expect(ShikiRoutes.pipelineRules == "/api/pipeline-rules")
        #expect(ShikiRoutes.adminBackupStatus == "/api/admin/backup-status")
    }

    @Test("ShikiRoutes dynamic paths generate correct URLs")
    func test_shikiRoutes_dynamicPaths() {
        let id = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

        #expect(ShikiRoutes.pipelineRun(id) == "/api/pipelines/11111111-1111-1111-1111-111111111111")
        #expect(ShikiRoutes.pipelineCheckpoints(id) == "/api/pipelines/11111111-1111-1111-1111-111111111111/checkpoints")
        #expect(ShikiRoutes.pipelineCheckpoint(id, phase: "synthesis") == "/api/pipelines/11111111-1111-1111-1111-111111111111/checkpoints/synthesis")
        #expect(ShikiRoutes.pipelineResume(id) == "/api/pipelines/11111111-1111-1111-1111-111111111111/resume")
        #expect(ShikiRoutes.pipelineRoute(id) == "/api/pipelines/11111111-1111-1111-1111-111111111111/route")
        #expect(ShikiRoutes.pipelineRule(id) == "/api/pipeline-rules/11111111-1111-1111-1111-111111111111")
        #expect(ShikiRoutes.ingestSource(id) == "/api/ingest/sources/11111111-1111-1111-1111-111111111111")
        #expect(ShikiRoutes.ingestReingest(id) == "/api/ingest/reingest/11111111-1111-1111-1111-111111111111")
        #expect(ShikiRoutes.radarWatchlistItem(id) == "/api/radar/watchlist/11111111-1111-1111-1111-111111111111")
        #expect(ShikiRoutes.radarScanResults(id) == "/api/radar/scans/11111111-1111-1111-1111-111111111111")
        #expect(ShikiRoutes.radarDigest(id) == "/api/radar/digest/11111111-1111-1111-1111-111111111111")
    }
}
