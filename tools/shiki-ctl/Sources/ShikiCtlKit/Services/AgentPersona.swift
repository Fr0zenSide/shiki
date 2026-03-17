import Foundation

// MARK: - AgentPersona

/// Defines the role and tool constraints for a dispatched agent.
/// Tool removal IS prompt engineering — structurally preventing drift.
public enum AgentPersona: String, Codable, Sendable, CaseIterable {
    case investigate  // read-only + codebase search
    case implement    // full edit + build + test
    case verify       // read-only + test runner + diff checker
    case critique     // read-only + spec access
    case review       // read-only + PR context
    case fix          // edit + test + scoped files

    // MARK: - Capability Flags

    public var canRead: Bool { true }  // all personas can read

    public var canEdit: Bool {
        switch self {
        case .implement, .fix: true
        default: false
        }
    }

    public var canBuild: Bool {
        switch self {
        case .implement: true
        default: false
        }
    }

    public var canTest: Bool {
        switch self {
        case .implement, .verify, .fix: true
        default: false
        }
    }

    public var canSearch: Bool {
        switch self {
        case .investigate, .implement, .verify, .review, .fix: true
        case .critique: false
        }
    }

    // MARK: - Allowed Tools

    /// The explicit list of Claude Code tools this persona can use.
    public var allowedTools: Set<String> {
        var tools: Set<String> = ["Read", "Glob", "Grep"]  // baseline read tools

        if canEdit {
            tools.insert("Edit")
            tools.insert("Write")
        }
        if canBuild || canTest {
            tools.insert("Bash")
        }
        if canSearch {
            tools.insert("Agent")
        }

        return tools
    }

    // MARK: - System Prompt Overlay

    /// Additional system prompt injected for this persona.
    public var systemPromptOverlay: String {
        switch self {
        case .investigate:
            return """
            You are in **investigate** mode — read-only exploration.
            You MUST NOT edit, write, or create any files.
            Your job: search the codebase, read files, and report findings.
            """
        case .implement:
            return """
            You are in **implement** mode — full development access.
            Follow TDD: write failing test first, then implement.
            Run the full test suite after every change.
            """
        case .verify:
            return """
            You are in **verify** mode — validation only.
            You MUST NOT edit any source files.
            Your job: run tests, check the diff against the spec, report pass/fail.
            """
        case .critique:
            return """
            You are in **critique** mode — spec review only.
            You MUST NOT edit any files or run any commands.
            Your job: review the spec for feasibility, gaps, and risks.
            """
        case .review:
            return """
            You are in **review** mode — code review only.
            You MUST NOT edit any files.
            Your job: review the PR diff, identify issues, suggest improvements.
            """
        case .fix:
            return """
            You are in **fix** mode — targeted edit access.
            You can edit files and run tests, but stay within scope.
            Your job: fix the specific issues identified in the review.
            """
        }
    }
}

// MARK: - AgentProvider Protocol

/// Protocol for dispatching agents with persona constraints.
/// AI-provider agnostic — can be backed by Claude, GPT, local models, etc.
public protocol AgentProvider: Sendable {
    func buildConfig(
        persona: AgentPersona,
        taskTitle: String,
        companySlug: String
    ) -> AgentConfig
}

/// Configuration for launching an agent session.
public struct AgentConfig: Sendable {
    public let allowedTools: Set<String>
    public let systemPrompt: String
    public let persona: AgentPersona

    public init(allowedTools: Set<String>, systemPrompt: String, persona: AgentPersona) {
        self.allowedTools = allowedTools
        self.systemPrompt = systemPrompt
        self.persona = persona
    }
}

// MARK: - ClaudeCodeProvider

/// First implementation of AgentProvider — dispatches via Claude Code CLI.
public struct ClaudeCodeProvider: AgentProvider {
    let workspacePath: String

    public init(workspacePath: String) {
        self.workspacePath = workspacePath
    }

    public func buildConfig(
        persona: AgentPersona,
        taskTitle: String,
        companySlug: String
    ) -> AgentConfig {
        let systemPrompt = """
        \(persona.systemPromptOverlay)

        Task: \(taskTitle)
        Company: \(companySlug)
        Workspace: \(workspacePath)
        """

        return AgentConfig(
            allowedTools: persona.allowedTools,
            systemPrompt: systemPrompt,
            persona: persona
        )
    }
}
