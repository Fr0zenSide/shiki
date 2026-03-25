import Foundation

// MARK: - HandoffContext

/// Serializable context passed between agents during handoffs.
public struct HandoffContext: Codable, Sendable {
    public let fromPersona: AgentPersona
    public let toPersona: AgentPersona
    public let specPath: String?
    public let changedFiles: [String]
    public let testResults: String?
    public let summary: String

    public init(
        fromPersona: AgentPersona, toPersona: AgentPersona,
        specPath: String? = nil, changedFiles: [String] = [],
        testResults: String? = nil, summary: String
    ) {
        self.fromPersona = fromPersona
        self.toPersona = toPersona
        self.specPath = specPath
        self.changedFiles = changedFiles
        self.testResults = testResults
        self.summary = summary
    }
}

// MARK: - HandoffChain

/// Defines the sequence of agent personas for a workflow.
public struct HandoffChain: Sendable {
    private let chain: [AgentPersona: AgentPersona]

    public init(chain: [AgentPersona: AgentPersona]) {
        self.chain = chain
    }

    /// Get the next persona after the current one, or nil if terminal.
    public func next(after persona: AgentPersona) -> AgentPersona? {
        chain[persona]
    }

    /// Standard chain: implement → verify → review.
    public static let standard = HandoffChain(chain: [
        .implement: .verify,
        .verify: .review,
    ])

    /// Fix chain: fix → verify.
    public static let fix = HandoffChain(chain: [
        .fix: .verify,
    ])

    /// Investigation chain: investigate → implement → verify → review.
    public static let full = HandoffChain(chain: [
        .investigate: .implement,
        .implement: .verify,
        .verify: .review,
    ])
}
