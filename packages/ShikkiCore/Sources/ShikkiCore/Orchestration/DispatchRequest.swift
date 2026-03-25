import Foundation

/// A request to dispatch a sub-agent into a project context.
/// Carries everything the sub-agent needs to work in isolation.
public struct DispatchRequest: Codable, Sendable, Identifiable {
    public var id: String { agentId + "-" + branch }

    public let agentId: String
    public let project: String          // "projects/Maya/"
    public let branch: String           // "epic/maya-animations"
    public let baseBranch: String       // "develop"
    public let specPath: String         // "features/maya-animations-v1.md"
    public let testScope: TestScope?
    public let successCriteria: [String]

    public init(
        agentId: String,
        project: String,
        branch: String,
        baseBranch: String,
        specPath: String,
        testScope: TestScope? = nil,
        successCriteria: [String] = []
    ) {
        self.agentId = agentId
        self.project = project
        self.branch = branch
        self.baseBranch = baseBranch
        self.specPath = specPath
        self.testScope = testScope
        self.successCriteria = successCriteria
    }
}
