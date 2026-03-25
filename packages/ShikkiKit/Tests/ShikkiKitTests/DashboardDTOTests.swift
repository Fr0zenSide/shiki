import Testing
import Foundation
@testable import ShikkiKit

@Suite("Dashboard DTOs")
struct DashboardDTOTests {

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

    // MARK: - DashboardSummary

    @Test("DashboardSummary decodes from server JSON with snake_case")
    func test_dashboardSummary_decodesFromServerJSON() throws {
        let json = """
        {
            "active_sessions": 3,
            "active_agents": 5,
            "total_agents": 42,
            "prs_created": 10,
            "decisions_count": 8,
            "messages_count": 200,
            "recent_events_24h": 150
        }
        """

        let summary = try Self.decoder.decode(DashboardSummary.self, from: Data(json.utf8))
        #expect(summary.activeSessions == 3)
        #expect(summary.activeAgents == 5)
        #expect(summary.totalAgents == 42)
        #expect(summary.prsCreated == 10)
        #expect(summary.recentEvents24h == 150)
    }

    @Test("DashboardSummary round-trips")
    func test_dashboardSummary_roundTrips() throws {
        let summary = DashboardSummary(
            activeSessions: 2,
            activeAgents: 4,
            totalAgents: 30,
            prsCreated: 7,
            decisionsCount: 5,
            messagesCount: 100,
            recentEvents24h: 50
        )

        let data = try Self.encoder.encode(summary)
        let decoded = try Self.decoder.decode(DashboardSummary.self, from: data)
        #expect(decoded == summary)
    }

    // MARK: - Health responses

    @Test("HealthResponse decodes from server JSON")
    func test_healthResponse_decodesFromServerJSON() throws {
        let json = """
        {
            "status": "ok",
            "version": "3.1.0",
            "uptime": { "ms": 60000, "human": "1m 0s" },
            "services": {
                "database": { "connected": true },
                "ollama": { "connected": false }
            },
            "timestamp": "2026-03-09T12:00:00Z"
        }
        """

        let health = try Self.decoder.decode(HealthResponse.self, from: Data(json.utf8))
        #expect(health.status == "ok")
        #expect(health.version == "3.1.0")
        #expect(health.uptime.ms == 60000)
        #expect(health.services.database.connected == true)
        #expect(health.services.ollama.connected == false)
    }

    // MARK: - DailyPerformanceDTO

    @Test("DailyPerformanceDTO round-trips")
    func test_dailyPerformanceDTO_roundTrips() throws {
        let perf = DailyPerformanceDTO(
            bucket: Date(),
            model: "claude-opus-4",
            apiCalls: 100,
            totalTokens: 50000,
            totalCostUsd: 2.50,
            avgDurationMs: 1200.5
        )

        let data = try Self.encoder.encode(perf)
        let decoded = try Self.decoder.decode(DailyPerformanceDTO.self, from: data)
        #expect(decoded.model == "claude-opus-4")
        #expect(decoded.apiCalls == 100)
        #expect(decoded.totalCostUsd == 2.50)
    }

    // MARK: - AgentCostLeaderboardDTO

    @Test("AgentCostLeaderboardDTO round-trips")
    func test_agentCostLeaderboardDTO_roundTrips() throws {
        let entry = AgentCostLeaderboardDTO(
            handle: "@Sensei",
            model: "claude-opus-4",
            totalCostUsd: 15.42,
            totalTokens: 120000,
            apiCalls: 350
        )

        let data = try Self.encoder.encode(entry)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"total_cost_usd\""))
        #expect(json.contains("\"api_calls\""))

        let decoded = try Self.decoder.decode(AgentCostLeaderboardDTO.self, from: data)
        #expect(decoded.handle == "@Sensei")
        #expect(decoded.totalCostUsd == 15.42)
    }

    // MARK: - BackupStatusDTO

    @Test("BackupStatusDTO decodes from server JSON")
    func test_backupStatusDTO_decodesFromServerJSON() throws {
        let json = """
        {
            "database": {
                "memories": 500,
                "events": 1200,
                "chats": 300,
                "agents": 40,
                "sessions": 15,
                "decisions": 10,
                "git_events": 25,
                "metrics": 800
            },
            "backup_script": "scripts/backup-db.sh",
            "restore_script": "scripts/restore-db.sh",
            "backup_dir": "backups/",
            "retention_days": 14,
            "timestamp": "2026-03-09T12:00:00Z"
        }
        """

        let status = try Self.decoder.decode(BackupStatusDTO.self, from: Data(json.utf8))
        #expect(status.database.memories == 500)
        #expect(status.database.gitEvents == 25)
        #expect(status.retentionDays == 14)
    }
}
