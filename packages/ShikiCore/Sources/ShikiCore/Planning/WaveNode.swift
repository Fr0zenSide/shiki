import Foundation

public struct WaveNode: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let branch: String
    public let baseBranch: String
    public var files: [String]
    public var testCount: Int
    public var status: WaveStatus
    public var dependsOn: [String]  // wave IDs

    public init(
        id: String,
        name: String,
        branch: String,
        baseBranch: String,
        files: [String] = [],
        testCount: Int = 0,
        status: WaveStatus = .pending,
        dependsOn: [String] = []
    ) {
        self.id = id
        self.name = name
        self.branch = branch
        self.baseBranch = baseBranch
        self.files = files
        self.testCount = testCount
        self.status = status
        self.dependsOn = dependsOn
    }
}

public enum WaveStatus: String, Codable, Sendable {
    case pending
    case inProgress
    case done
    case failed
    case blocked
}
