/// Abstraction over process/session management for task sessions.
///
/// The dispatcher launches one session per **task** (not per company).
/// Each session runs in the task's `projectPath` directory with an autopilot prompt
/// that claims and works on that specific task.
///
/// Implementations:
/// - ``TmuxProcessLauncher``: creates tmux windows with dynamic naming and re-tiling.
/// - `AgentTeamsLauncher` (future): native Claude Agent Teams once session resumption stabilizes.
public protocol ProcessLauncher: Sendable {
    /// Launch a Claude session for a specific task.
    ///
    /// - Parameters:
    ///   - taskId: UUID of the task to work on (empty string for legacy/fallback launches).
    ///   - companyId: UUID of the owning company (used in heartbeat and task-claim payloads).
    ///   - companySlug: URL-safe company name (used in tmux window naming).
    ///   - title: Human-readable task title (truncated to ~15 chars for window name).
    ///   - projectPath: Relative path under `projects/` where Claude should `cd` into.
    func launchTaskSession(taskId: String, companyId: String, companySlug: String,
                           title: String, projectPath: String) async throws

    /// Legacy: launch a company-wide session. Default implementation delegates to ``launchTaskSession``.
    func launchCompanySession(companyId: String, slug: String, projectPath: String) async throws

    /// Check whether a session with the given slug (window name) is currently running.
    func isSessionRunning(slug: String) async -> Bool

    /// Kill the tmux window for the given session slug.
    func stopSession(slug: String) async throws

    /// Return the window names of all running task sessions (excludes `orchestrator` and `research`).
    func listRunningSessions() async -> [String]
}

// Default implementation for backward compat
public extension ProcessLauncher {
    func launchCompanySession(companyId: String, slug: String, projectPath: String) async throws {
        try await launchTaskSession(
            taskId: "",
            companyId: companyId,
            companySlug: slug,
            title: slug,
            projectPath: projectPath
        )
    }
}
