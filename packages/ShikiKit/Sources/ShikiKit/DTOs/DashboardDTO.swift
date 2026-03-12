import Foundation

/// Response from /api/dashboard/summary.
public struct DashboardSummary: Codable, Equatable, Sendable {
    public let activeSessions: Int
    public let activeAgents: Int
    public let totalAgents: Int
    public let prsCreated: Int
    public let decisionsCount: Int
    public let messagesCount: Int
    public let recentEvents24h: Int

    public init(
        activeSessions: Int,
        activeAgents: Int,
        totalAgents: Int,
        prsCreated: Int,
        decisionsCount: Int,
        messagesCount: Int,
        recentEvents24h: Int
    ) {
        self.activeSessions = activeSessions
        self.activeAgents = activeAgents
        self.totalAgents = totalAgents
        self.prsCreated = prsCreated
        self.decisionsCount = decisionsCount
        self.messagesCount = messagesCount
        self.recentEvents24h = recentEvents24h
    }

    enum CodingKeys: String, CodingKey {
        case activeSessions = "active_sessions"
        case activeAgents = "active_agents"
        case totalAgents = "total_agents"
        case prsCreated = "prs_created"
        case decisionsCount = "decisions_count"
        case messagesCount = "messages_count"
        case recentEvents24h = "recent_events_24h"
    }
}

/// Row from daily_performance continuous aggregate.
public struct DailyPerformanceDTO: Codable, Equatable, Sendable {
    public let bucket: Date
    public let model: String?
    public let apiCalls: Int
    public let totalTokens: Int
    public let totalCostUsd: Double
    public let avgDurationMs: Double

    public init(
        bucket: Date,
        model: String? = nil,
        apiCalls: Int,
        totalTokens: Int,
        totalCostUsd: Double,
        avgDurationMs: Double
    ) {
        self.bucket = bucket
        self.model = model
        self.apiCalls = apiCalls
        self.totalTokens = totalTokens
        self.totalCostUsd = totalCostUsd
        self.avgDurationMs = avgDurationMs
    }

    enum CodingKeys: String, CodingKey {
        case bucket, model
        case apiCalls = "api_calls"
        case totalTokens = "total_tokens"
        case totalCostUsd = "total_cost_usd"
        case avgDurationMs = "avg_duration_ms"
    }
}

/// Row from agent_activity_hourly continuous aggregate.
public struct HourlyActivityDTO: Codable, Equatable, Sendable {
    public let bucket: Date
    public let eventType: String
    public let count: Int

    public init(bucket: Date, eventType: String, count: Int) {
        self.bucket = bucket
        self.eventType = eventType
        self.count = count
    }

    enum CodingKeys: String, CodingKey {
        case bucket, count
        case eventType = "event_type"
    }
}

/// Row from agent_cost_leaderboard view.
public struct AgentCostLeaderboardDTO: Codable, Equatable, Sendable {
    public let handle: String
    public let model: String?
    public let totalCostUsd: Double
    public let totalTokens: Int
    public let apiCalls: Int

    public init(
        handle: String,
        model: String? = nil,
        totalCostUsd: Double,
        totalTokens: Int,
        apiCalls: Int
    ) {
        self.handle = handle
        self.model = model
        self.totalCostUsd = totalCostUsd
        self.totalTokens = totalTokens
        self.apiCalls = apiCalls
    }

    enum CodingKeys: String, CodingKey {
        case handle, model
        case totalCostUsd = "total_cost_usd"
        case totalTokens = "total_tokens"
        case apiCalls = "api_calls"
    }
}

/// Row from daily_git_activity continuous aggregate.
public struct DailyGitActivityDTO: Codable, Equatable, Sendable {
    public let bucket: Date
    public let eventType: String
    public let eventCount: Int
    public let totalAdditions: Int
    public let totalDeletions: Int
    public let totalFilesChanged: Int

    public init(
        bucket: Date,
        eventType: String,
        eventCount: Int,
        totalAdditions: Int,
        totalDeletions: Int,
        totalFilesChanged: Int
    ) {
        self.bucket = bucket
        self.eventType = eventType
        self.eventCount = eventCount
        self.totalAdditions = totalAdditions
        self.totalDeletions = totalDeletions
        self.totalFilesChanged = totalFilesChanged
    }

    enum CodingKeys: String, CodingKey {
        case bucket
        case eventType = "event_type"
        case eventCount = "event_count"
        case totalAdditions = "total_additions"
        case totalDeletions = "total_deletions"
        case totalFilesChanged = "total_files_changed"
    }
}

/// Response from /api/admin/backup-status.
public struct BackupStatusDTO: Codable, Equatable, Sendable {
    public let database: DatabaseCounts
    public let backupScript: String
    public let restoreScript: String
    public let backupDir: String
    public let retentionDays: Int
    public let timestamp: String

    public init(
        database: DatabaseCounts,
        backupScript: String = "scripts/backup-db.sh",
        restoreScript: String = "scripts/restore-db.sh",
        backupDir: String = "backups/",
        retentionDays: Int = 14,
        timestamp: String
    ) {
        self.database = database
        self.backupScript = backupScript
        self.restoreScript = restoreScript
        self.backupDir = backupDir
        self.retentionDays = retentionDays
        self.timestamp = timestamp
    }

    enum CodingKeys: String, CodingKey {
        case database, timestamp
        case backupScript = "backup_script"
        case restoreScript = "restore_script"
        case backupDir = "backup_dir"
        case retentionDays = "retention_days"
    }
}

/// Database table counts for backup-status.
public struct DatabaseCounts: Codable, Equatable, Sendable {
    public let memories: Int
    public let events: Int
    public let chats: Int
    public let agents: Int
    public let sessions: Int
    public let decisions: Int
    public let gitEvents: Int
    public let metrics: Int

    public init(
        memories: Int,
        events: Int,
        chats: Int,
        agents: Int,
        sessions: Int,
        decisions: Int,
        gitEvents: Int,
        metrics: Int
    ) {
        self.memories = memories
        self.events = events
        self.chats = chats
        self.agents = agents
        self.sessions = sessions
        self.decisions = decisions
        self.gitEvents = gitEvents
        self.metrics = metrics
    }

    enum CodingKeys: String, CodingKey {
        case memories, events, chats, agents, sessions, decisions, metrics
        case gitEvents = "git_events"
    }
}

/// Health check response from /health.
public struct HealthResponse: Codable, Equatable, Sendable {
    public let status: String
    public let version: String
    public let uptime: UptimeInfo
    public let services: HealthServices
    public let timestamp: String

    public init(
        status: String,
        version: String,
        uptime: UptimeInfo,
        services: HealthServices,
        timestamp: String
    ) {
        self.status = status
        self.version = version
        self.uptime = uptime
        self.services = services
        self.timestamp = timestamp
    }
}

/// Uptime info nested in health response.
public struct UptimeInfo: Codable, Equatable, Sendable {
    public let ms: Int
    public let human: String

    public init(ms: Int, human: String) {
        self.ms = ms
        self.human = human
    }
}

/// Services status nested in health response.
public struct HealthServices: Codable, Equatable, Sendable {
    public let database: DatabaseHealth
    public let ollama: OllamaHealth
    public let websocket: WebSocketHealth?

    public init(database: DatabaseHealth, ollama: OllamaHealth, websocket: WebSocketHealth? = nil) {
        self.database = database
        self.ollama = ollama
        self.websocket = websocket
    }
}

/// Database health info.
public struct DatabaseHealth: Codable, Equatable, Sendable {
    public let connected: Bool
    public let pool: [String: AnyCodable]?

    public init(connected: Bool, pool: [String: AnyCodable]? = nil) {
        self.connected = connected
        self.pool = pool
    }
}

/// Ollama/embedding service health.
public struct OllamaHealth: Codable, Equatable, Sendable {
    public let connected: Bool

    public init(connected: Bool) {
        self.connected = connected
    }
}

/// WebSocket stats.
public struct WebSocketHealth: Codable, Equatable, Sendable {
    public let connections: Int
    public let channels: Int

    public init(connections: Int, channels: Int) {
        self.connections = connections
        self.channels = channels
    }
}

/// Full health response from /health/full.
public struct HealthFullResponse: Codable, Equatable, Sendable {
    public let status: String
    public let version: String
    public let uptime: UptimeInfo
    public let services: HealthFullServices
    public let memory: MemoryStats
    public let pipelines: PipelineStats
    public let projects: Int
    public let radar: RadarStats
    public let agents: [AgentRosterEntry]
    public let commands: [CommandEntry]
    public let timestamp: String

    public init(
        status: String,
        version: String,
        uptime: UptimeInfo,
        services: HealthFullServices,
        memory: MemoryStats,
        pipelines: PipelineStats,
        projects: Int,
        radar: RadarStats,
        agents: [AgentRosterEntry],
        commands: [CommandEntry],
        timestamp: String
    ) {
        self.status = status
        self.version = version
        self.uptime = uptime
        self.services = services
        self.memory = memory
        self.pipelines = pipelines
        self.projects = projects
        self.radar = radar
        self.agents = agents
        self.commands = commands
        self.timestamp = timestamp
    }
}

/// Services in full health response (simpler shape).
public struct HealthFullServices: Codable, Equatable, Sendable {
    public let database: Bool
    public let embeddings: Bool

    public init(database: Bool, embeddings: Bool) {
        self.database = database
        self.embeddings = embeddings
    }
}

/// Memory statistics in full health.
public struct MemoryStats: Codable, Equatable, Sendable {
    public let total: Int
    public let withEmbedding: Int
    public let categories: [String: Int]
    public let sources: Int

    public init(total: Int, withEmbedding: Int, categories: [String: Int], sources: Int) {
        self.total = total
        self.withEmbedding = withEmbedding
        self.categories = categories
        self.sources = sources
    }

    enum CodingKeys: String, CodingKey {
        case total, categories, sources
        case withEmbedding = "with_embedding"
    }
}

/// Pipeline statistics in full health.
public struct PipelineStats: Codable, Equatable, Sendable {
    public let total: Int
    public let running: Int
    public let completed: Int
    public let failed: Int

    public init(total: Int, running: Int, completed: Int, failed: Int) {
        self.total = total
        self.running = running
        self.completed = completed
        self.failed = failed
    }
}

/// Radar stats in full health.
public struct RadarStats: Codable, Equatable, Sendable {
    public let watchedRepos: Int

    public init(watchedRepos: Int) {
        self.watchedRepos = watchedRepos
    }

    enum CodingKeys: String, CodingKey {
        case watchedRepos = "watched_repos"
    }
}

/// Agent roster entry in full health.
public struct AgentRosterEntry: Codable, Equatable, Sendable {
    public let handle: String
    public let alias: String
    public let role: String

    public init(handle: String, alias: String, role: String) {
        self.handle = handle
        self.alias = alias
        self.role = role
    }
}

/// Command entry in full health.
public struct CommandEntry: Codable, Equatable, Sendable {
    public let name: String
    public let desc: String

    public init(name: String, desc: String) {
        self.name = name
        self.desc = desc
    }
}
