import Foundation

/// The 10-step Shikki production process — spec to ship.
/// BR-07b: This is a protocol in ShikiCore, not just a markdown file.
///
/// Steps:
///   1. /spec "feature name" -> 8-phase spec pipeline
///   2. @Daimyo validates -> one-shot approval
///   3. Orchestrator dispatches -> sub-agents in project contexts
///   4. Sub-agents implement (TPDD) -> test first, code second
///   5. Sub-agents /pre-pr -> 9-gate quality pipeline
///   6. Sub-agents create PRs -> epic branches per project
///   7. Orchestrator collects -> /pre-pr --autofix on epics
///   8. @Daimyo /review -> interactive code review
///   9. Merge to develop -> via gh pr merge
///  10. /ship -> 8-gate release pipeline
public protocol ShikkiFlowProtocol: Sendable {
    /// 1. Generate a spec file from a feature name.
    func spec(featureName: String) async throws -> String

    /// 2. Validate the spec (via @Daimyo or automated checks).
    func validate(specPath: String) async throws -> Bool

    /// 3. Dispatch sub-agents to implement the spec.
    func dispatch(specPath: String) async throws -> [String]

    /// 4+5. Monitor sub-agent progress via event stream.
    func monitor(agentIds: [String]) async -> AsyncStream<DispatchEvent>

    /// 6. Collect results from all sub-agents.
    func collect(agentIds: [String]) async throws -> FlowResult

    /// 7. Run /pre-pr --autofix on the epic branch.
    func prePR(epicBranch: String) async throws -> PrePRResult

    /// 8. Review a PR (interactive or automated).
    func review(prNumber: Int) async throws -> ReviewDecision

    /// 9. Merge a PR to develop.
    func merge(prNumber: Int) async throws

    /// 10. Ship a release through the 8-gate pipeline.
    func ship(target: String, why: String) async throws -> ShipResult

    /// Generate a summary report.
    func report(result: FlowResult) async -> String
}

// MARK: - FlowResult

/// Outcome of a complete Shikki flow (spec to pre-PR).
public struct FlowResult: Codable, Sendable {
    public let specPath: String
    public let agentIds: [String]
    public let totalTests: Int
    public let totalFilesChanged: Int
    public let prNumbers: [Int]
    public let blockers: [String]
    public let success: Bool

    public init(
        specPath: String,
        agentIds: [String],
        totalTests: Int,
        totalFilesChanged: Int,
        prNumbers: [Int],
        blockers: [String] = [],
        success: Bool
    ) {
        self.specPath = specPath
        self.agentIds = agentIds
        self.totalTests = totalTests
        self.totalFilesChanged = totalFilesChanged
        self.prNumbers = prNumbers
        self.blockers = blockers
        self.success = success
    }
}

// MARK: - PrePRResult

/// Outcome of the /pre-pr --autofix phase.
public struct PrePRResult: Codable, Sendable {
    public let epicBranch: String
    public let gatesPassed: Int
    public let gatesTotal: Int
    public let autoFixesApplied: Int
    public let remainingIssues: [String]

    public var allGatesPassed: Bool { gatesPassed == gatesTotal }

    public init(
        epicBranch: String,
        gatesPassed: Int,
        gatesTotal: Int,
        autoFixesApplied: Int,
        remainingIssues: [String] = []
    ) {
        self.epicBranch = epicBranch
        self.gatesPassed = gatesPassed
        self.gatesTotal = gatesTotal
        self.autoFixesApplied = autoFixesApplied
        self.remainingIssues = remainingIssues
    }
}

// MARK: - ReviewDecision

/// The outcome of a PR review step.
public enum ReviewDecision: String, Codable, Sendable {
    case approve
    case requestChanges
    case comment
}

// MARK: - ShipResult

/// Outcome of the /ship release pipeline.
public struct ShipResult: Codable, Sendable {
    public let target: String
    public let version: String?
    public let gatesPassed: Int
    public let gatesTotal: Int
    public let success: Bool

    public init(
        target: String,
        version: String? = nil,
        gatesPassed: Int,
        gatesTotal: Int,
        success: Bool
    ) {
        self.target = target
        self.version = version
        self.gatesPassed = gatesPassed
        self.gatesTotal = gatesTotal
        self.success = success
    }
}
