import Foundation

/// The 8-step orchestration loop — compiled behavior, not just a markdown file.
/// BR-07: Orchestrator DNA is a protocol in ShikiCore.
///
/// Steps:
///   1. UNDERSTAND — What is the intent?
///   2. SCOPE — Which projects, packages, branches?
///   3. PLAN — Break into waves, assign test scopes
///   4. PRESENT — Show plan to @Daimyo for one-shot validation
///   5. DISPATCH — Launch sub-agents in parallel
///   6. MONITOR — Watch ShikkiDB for events
///   7. COLLECT — Aggregate results, run /pre-pr
///   8. REPORT — Summary, emit session_completed, suggest next
public protocol OrchestratorProtocol: Sendable {
    /// 1. Parse @Daimyo's intent into a structured plan.
    func understand(intent: String) async -> OrchestratorPlan

    /// 2+3. Scope projects and break into dispatchable requests.
    func scope(plan: OrchestratorPlan) async -> [DispatchRequest]

    /// 4. Render the plan as a human-readable summary for validation.
    func present(plan: OrchestratorPlan) async -> String

    /// 5. Launch sub-agents for each request. Returns agent IDs.
    func dispatch(requests: [DispatchRequest]) async throws -> [String]

    /// 6. Stream events from active sub-agents.
    func monitor(agentIds: [String]) async -> AsyncStream<DispatchEvent>

    /// 7. Collect and aggregate results from completed agents.
    func collect(agentIds: [String]) async throws -> OrchestratorResult

    /// 8. Generate a summary report for @Daimyo.
    func report(result: OrchestratorResult) async -> String
}

// MARK: - OrchestratorPlan

/// The structured output of the UNDERSTAND + SCOPE + PLAN phases.
public struct OrchestratorPlan: Codable, Sendable {
    public let intent: String
    public let projects: [String]
    public let waves: [WaveNode]
    public let estimatedCost: Double?
    public let createdAt: Date

    public init(
        intent: String,
        projects: [String],
        waves: [WaveNode],
        estimatedCost: Double? = nil,
        createdAt: Date = Date()
    ) {
        self.intent = intent
        self.projects = projects
        self.waves = waves
        self.estimatedCost = estimatedCost
        self.createdAt = createdAt
    }
}

// MARK: - OrchestratorResult

/// Aggregated outcome of a completed orchestration run.
public struct OrchestratorResult: Codable, Sendable {
    public let plan: OrchestratorPlan
    public let agentResults: [AgentSummary]
    public let totalTests: Int
    public let totalFilesChanged: Int
    public let prNumbers: [Int]
    public let success: Bool
    public let completedAt: Date

    public init(
        plan: OrchestratorPlan,
        agentResults: [AgentSummary],
        totalTests: Int,
        totalFilesChanged: Int,
        prNumbers: [Int],
        success: Bool,
        completedAt: Date = Date()
    ) {
        self.plan = plan
        self.agentResults = agentResults
        self.totalTests = totalTests
        self.totalFilesChanged = totalFilesChanged
        self.prNumbers = prNumbers
        self.success = success
        self.completedAt = completedAt
    }
}

// MARK: - AgentSummary

/// Summary of a single sub-agent's work.
public struct AgentSummary: Codable, Sendable {
    public let agentId: String
    public let project: String
    public let branch: String
    public let testsRun: Int
    public let testsPassed: Int
    public let filesChanged: Int
    public let prNumber: Int?
    public let blockers: [String]

    public init(
        agentId: String,
        project: String,
        branch: String,
        testsRun: Int,
        testsPassed: Int,
        filesChanged: Int,
        prNumber: Int? = nil,
        blockers: [String] = []
    ) {
        self.agentId = agentId
        self.project = project
        self.branch = branch
        self.testsRun = testsRun
        self.testsPassed = testsPassed
        self.filesChanged = filesChanged
        self.prNumber = prNumber
        self.blockers = blockers
    }
}
