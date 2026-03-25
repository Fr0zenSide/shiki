import Testing
import Foundation
@testable import ShikkiKit

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

    // MARK: - ShikkiRoutes

    @Test("ShikkiRoutes static paths match Deno routes")
    func test_shikiRoutes_staticPaths() {
        #expect(ShikkiRoutes.health == "/health")
        #expect(ShikkiRoutes.healthFull == "/health/full")
        #expect(ShikkiRoutes.projects == "/api/projects")
        #expect(ShikkiRoutes.sessions == "/api/sessions")
        #expect(ShikkiRoutes.sessionsActive == "/api/sessions/active")
        #expect(ShikkiRoutes.agents == "/api/agents")
        #expect(ShikkiRoutes.agentUpdate == "/api/agent-update")
        #expect(ShikkiRoutes.agentEvents == "/api/agent-events")
        #expect(ShikkiRoutes.statsUpdate == "/api/stats-update")
        #expect(ShikkiRoutes.memories == "/api/memories")
        #expect(ShikkiRoutes.memoriesSearch == "/api/memories/search")
        #expect(ShikkiRoutes.memoriesSources == "/api/memories/sources")
        #expect(ShikkiRoutes.chatMessage == "/api/chat-message")
        #expect(ShikkiRoutes.chatMessages == "/api/chat-messages")
        #expect(ShikkiRoutes.dataSync == "/api/data-sync")
        #expect(ShikkiRoutes.prCreated == "/api/pr-created")
        #expect(ShikkiRoutes.gitEvents == "/api/git-events")
        #expect(ShikkiRoutes.dashboardSummary == "/api/dashboard/summary")
        #expect(ShikkiRoutes.dashboardPerformance == "/api/dashboard/performance")
        #expect(ShikkiRoutes.dashboardActivity == "/api/dashboard/activity")
        #expect(ShikkiRoutes.dashboardCosts == "/api/dashboard/costs")
        #expect(ShikkiRoutes.dashboardGit == "/api/dashboard/git")
        #expect(ShikkiRoutes.ingest == "/api/ingest")
        #expect(ShikkiRoutes.ingestSources == "/api/ingest/sources")
        #expect(ShikkiRoutes.radarWatchlist == "/api/radar/watchlist")
        #expect(ShikkiRoutes.radarScan == "/api/radar/scan")
        #expect(ShikkiRoutes.radarScans == "/api/radar/scans")
        #expect(ShikkiRoutes.radarDigestLatest == "/api/radar/digest/latest")
        #expect(ShikkiRoutes.radarIngest == "/api/radar/ingest")
        #expect(ShikkiRoutes.pipelines == "/api/pipelines")
        #expect(ShikkiRoutes.pipelinesLatest == "/api/pipelines/latest")
        #expect(ShikkiRoutes.pipelineRules == "/api/pipeline-rules")
        #expect(ShikkiRoutes.adminBackupStatus == "/api/admin/backup-status")
    }

    @Test("ShikkiRoutes dynamic paths generate correct URLs")
    func test_shikiRoutes_dynamicPaths() {
        let id = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

        #expect(ShikkiRoutes.pipelineRun(id) == "/api/pipelines/11111111-1111-1111-1111-111111111111")
        #expect(ShikkiRoutes.pipelineCheckpoints(id) == "/api/pipelines/11111111-1111-1111-1111-111111111111/checkpoints")
        #expect(ShikkiRoutes.pipelineCheckpoint(id, phase: "synthesis") == "/api/pipelines/11111111-1111-1111-1111-111111111111/checkpoints/synthesis")
        #expect(ShikkiRoutes.pipelineResume(id) == "/api/pipelines/11111111-1111-1111-1111-111111111111/resume")
        #expect(ShikkiRoutes.pipelineRoute(id) == "/api/pipelines/11111111-1111-1111-1111-111111111111/route")
        #expect(ShikkiRoutes.pipelineRule(id) == "/api/pipeline-rules/11111111-1111-1111-1111-111111111111")
        #expect(ShikkiRoutes.ingestSource(id) == "/api/ingest/sources/11111111-1111-1111-1111-111111111111")
        #expect(ShikkiRoutes.ingestReingest(id) == "/api/ingest/reingest/11111111-1111-1111-1111-111111111111")
        #expect(ShikkiRoutes.radarWatchlistItem(id) == "/api/radar/watchlist/11111111-1111-1111-1111-111111111111")
        #expect(ShikkiRoutes.radarScanResults(id) == "/api/radar/scans/11111111-1111-1111-1111-111111111111")
        #expect(ShikkiRoutes.radarDigest(id) == "/api/radar/digest/11111111-1111-1111-1111-111111111111")
    }
}
