import Foundation

/// All Shiki API route path constants and their HTTP methods.
/// Mirrors the route definitions in routes.ts for compile-time safety.
public enum ShikkiRoutes: Sendable {

    // MARK: - Health

    public static let health = "/health"
    public static let healthFull = "/health/full"

    // MARK: - Projects

    public static let projects = "/api/projects"

    // MARK: - Sessions

    public static let sessions = "/api/sessions"
    public static let sessionsActive = "/api/sessions/active"

    // MARK: - Agents

    public static let agents = "/api/agents"
    public static let agentUpdate = "/api/agent-update"
    public static let agentEvents = "/api/agent-events"

    // MARK: - Performance

    public static let statsUpdate = "/api/stats-update"

    // MARK: - Memories

    public static let memories = "/api/memories"
    public static let memoriesSearch = "/api/memories/search"
    public static let memoriesSources = "/api/memories/sources"

    // MARK: - Chat

    public static let chatMessage = "/api/chat-message"
    public static let chatMessages = "/api/chat-messages"

    // MARK: - Data Sync

    public static let dataSync = "/api/data-sync"

    // MARK: - Git Events

    public static let prCreated = "/api/pr-created"
    public static let gitEvents = "/api/git-events"

    // MARK: - Dashboard

    public static let dashboardSummary = "/api/dashboard/summary"
    public static let dashboardPerformance = "/api/dashboard/performance"
    public static let dashboardActivity = "/api/dashboard/activity"
    public static let dashboardCosts = "/api/dashboard/costs"
    public static let dashboardGit = "/api/dashboard/git"

    // MARK: - Ingestion

    public static let ingest = "/api/ingest"
    public static let ingestSources = "/api/ingest/sources"

    /// Returns the path for a specific ingest source by ID.
    public static func ingestSource(_ id: UUID) -> String {
        "/api/ingest/sources/\(id.uuidString.lowercased())"
    }

    /// Returns the path for re-ingesting a source by ID.
    public static func ingestReingest(_ id: UUID) -> String {
        "/api/ingest/reingest/\(id.uuidString.lowercased())"
    }

    // MARK: - Radar

    public static let radarWatchlist = "/api/radar/watchlist"
    public static let radarScan = "/api/radar/scan"
    public static let radarScans = "/api/radar/scans"
    public static let radarDigestLatest = "/api/radar/digest/latest"
    public static let radarIngest = "/api/radar/ingest"

    /// Returns the path for a specific radar watchlist item by ID.
    public static func radarWatchlistItem(_ id: UUID) -> String {
        "/api/radar/watchlist/\(id.uuidString.lowercased())"
    }

    /// Returns the path for scan results by run ID.
    public static func radarScanResults(_ runId: UUID) -> String {
        "/api/radar/scans/\(runId.uuidString.lowercased())"
    }

    /// Returns the path for a specific radar digest by run ID.
    public static func radarDigest(_ runId: UUID) -> String {
        "/api/radar/digest/\(runId.uuidString.lowercased())"
    }

    // MARK: - Pipelines

    public static let pipelines = "/api/pipelines"
    public static let pipelinesLatest = "/api/pipelines/latest"

    /// Returns the path for a specific pipeline run by ID.
    public static func pipelineRun(_ id: UUID) -> String {
        "/api/pipelines/\(id.uuidString.lowercased())"
    }

    /// Returns the path for pipeline checkpoints.
    public static func pipelineCheckpoints(_ runId: UUID) -> String {
        "/api/pipelines/\(runId.uuidString.lowercased())/checkpoints"
    }

    /// Returns the path for a specific checkpoint by phase.
    public static func pipelineCheckpoint(_ runId: UUID, phase: String) -> String {
        "/api/pipelines/\(runId.uuidString.lowercased())/checkpoints/\(phase)"
    }

    /// Returns the path for resuming a pipeline.
    public static func pipelineResume(_ runId: UUID) -> String {
        "/api/pipelines/\(runId.uuidString.lowercased())/resume"
    }

    /// Returns the path for evaluating pipeline routing.
    public static func pipelineRoute(_ runId: UUID) -> String {
        "/api/pipelines/\(runId.uuidString.lowercased())/route"
    }

    // MARK: - Pipeline Rules

    public static let pipelineRules = "/api/pipeline-rules"

    /// Returns the path for a specific pipeline rule by ID.
    public static func pipelineRule(_ id: UUID) -> String {
        "/api/pipeline-rules/\(id.uuidString.lowercased())"
    }

    // MARK: - Admin

    public static let adminBackupStatus = "/api/admin/backup-status"
}
