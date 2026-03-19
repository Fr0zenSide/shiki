import Foundation

// MARK: - PRFixAgent

/// Spawns a fix agent in a worktree to address review issues.
/// Uses the `.fix` persona with scoped file access.
public struct PRFixAgent: Sendable {
    public let prNumber: Int
    public let workspacePath: String
    public let provider: AgentProvider

    public init(prNumber: Int, workspacePath: String, provider: AgentProvider) {
        self.prNumber = prNumber
        self.workspacePath = workspacePath
        self.provider = provider
    }

    /// Build the context string for the fix agent.
    public func buildContext(
        state: PRReviewState,
        filePath: String,
        issue: String
    ) -> String {
        let verdicts = state.verdictCounts()
        return """
        ## Fix Context — PR #\(prNumber)

        **File:** \(filePath)
        **Issue:** \(issue)

        **Review State:**
        - Approved: \(verdicts.approved)
        - Comments: \(verdicts.comment)
        - Changes Requested: \(verdicts.requestChanges)

        Fix the issue described above. Stay within scope — only modify \(filePath) \
        and its direct dependencies. Run tests after fixing.
        """
    }

    /// Build the agent config for launching a fix agent.
    public func agentConfig(filePath: String, issue: String) -> AgentConfig {
        provider.buildConfig(
            persona: .fix,
            taskTitle: "Fix: \(issue) in \(filePath)",
            companySlug: "pr-\(prNumber)"
        )
    }
}
