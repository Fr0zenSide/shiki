import Testing
import Foundation
@testable import ShikiCore

@Suite("TestPlan")
struct TestPlanTests {

    @Test("TestPlan Codable round-trip")
    func codableRoundTrip() throws {
        let scenario = TestScenario(name: "Login flow", when: "user enters credentials", then: "session is created")
        let concern = TestConcern(question: "What if token expired?", expectation: "Refresh token used", edgeCase: "Both tokens expired")
        let plan = TestPlan(featureId: "feat-auth", scenarios: [scenario], concerns: [concern], coverageTarget: 90)

        let data = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(TestPlan.self, from: data)

        #expect(decoded.featureId == "feat-auth")
        #expect(decoded.scenarios.count == 1)
        #expect(decoded.scenarios[0].name == "Login flow")
        #expect(decoded.scenarios[0].status == .pending)
        #expect(decoded.concerns.count == 1)
        #expect(decoded.concerns[0].edgeCase == "Both tokens expired")
        #expect(decoded.coverageTarget == 90)
    }

    @Test("Scenarios track status correctly")
    func scenarioStatusTracking() {
        var scenario = TestScenario(name: "Test", when: "action", then: "result")
        #expect(scenario.status == .pending)

        scenario.status = .passing
        #expect(scenario.status == .passing)

        scenario.status = .failing
        #expect(scenario.status == .failing)
    }
}
