import Foundation

/// TPDD: Test Plan Driven Development
/// Describes what to test before building.
public struct TestPlan: Codable, Sendable {
    public let featureId: String
    public var scenarios: [TestScenario]
    public var concerns: [TestConcern]
    public var coverageTarget: Int  // percentage

    public init(
        featureId: String,
        scenarios: [TestScenario] = [],
        concerns: [TestConcern] = [],
        coverageTarget: Int = 80
    ) {
        self.featureId = featureId
        self.scenarios = scenarios
        self.concerns = concerns
        self.coverageTarget = coverageTarget
    }
}

public struct TestScenario: Codable, Sendable {
    public let name: String
    public let when: String
    public let then: String
    public var status: TestStatus

    public init(name: String, when: String, then: String, status: TestStatus = .pending) {
        self.name = name
        self.when = when
        self.then = then
        self.status = status
    }
}

public struct TestConcern: Codable, Sendable {
    public let question: String
    public let expectation: String
    public let edgeCase: String?

    public init(question: String, expectation: String, edgeCase: String? = nil) {
        self.question = question
        self.expectation = expectation
        self.edgeCase = edgeCase
    }
}

public enum TestStatus: String, Codable, Sendable {
    case pending
    case passing
    case failing
}
