import Foundation
import Testing
@testable import ShikiCtlKit

@Suite("UrgencyCalculator — score formula validation")
struct UrgencyCalculatorTests {

    @Test("ageWeight brackets: <1h=0, 1-4h=10, 4-12h=20, 12-24h=30, >24h=40")
    func ageWeightBrackets() {
        #expect(UrgencyCalculator.ageWeight(0) == 0)
        #expect(UrgencyCalculator.ageWeight(1800) == 0)         // 30min
        #expect(UrgencyCalculator.ageWeight(3600) == 10)        // 1h
        #expect(UrgencyCalculator.ageWeight(7200) == 10)        // 2h
        #expect(UrgencyCalculator.ageWeight(14400) == 20)       // 4h
        #expect(UrgencyCalculator.ageWeight(43200) == 30)       // 12h
        #expect(UrgencyCalculator.ageWeight(86400) == 40)       // 24h
        #expect(UrgencyCalculator.ageWeight(172800) == 40)      // 48h
    }

    @Test("prPriorityWeight: 1-5 files=5, 6-20=15, 20+=30")
    func prPriorityWeight() {
        #expect(UrgencyCalculator.prPriorityWeight(filesChanged: 1) == 5)
        #expect(UrgencyCalculator.prPriorityWeight(filesChanged: 5) == 5)
        #expect(UrgencyCalculator.prPriorityWeight(filesChanged: 6) == 15)
        #expect(UrgencyCalculator.prPriorityWeight(filesChanged: 19) == 15)
        #expect(UrgencyCalculator.prPriorityWeight(filesChanged: 20) == 30)
        #expect(UrgencyCalculator.prPriorityWeight(filesChanged: 100) == 30)
    }

    @Test("decisionPriorityWeight: T1=30, T2=20, T3=10")
    func decisionPriorityWeight() {
        #expect(UrgencyCalculator.decisionPriorityWeight(tier: 1) == 30)
        #expect(UrgencyCalculator.decisionPriorityWeight(tier: 2) == 20)
        #expect(UrgencyCalculator.decisionPriorityWeight(tier: 3) == 10)
    }

    @Test("composite score capped at 100")
    func scoreCap() {
        // Max possible: ageWeight(40) + priorityWeight(30) + blocking(30) = 100
        let score = UrgencyCalculator.score(age: 172800, priorityWeight: 30, isBlocking: true)
        #expect(score == 100)

        // Min possible
        let minScore = UrgencyCalculator.score(age: 0, priorityWeight: 0, isBlocking: false)
        #expect(minScore == 0)
    }

    @Test("sourceId parsing from composite id")
    func sourceIdParsing() {
        let pr = InboxItem(id: "pr:42", type: .pr, title: "T", age: 0, urgencyScore: 0)
        #expect(pr.sourceId == "42")

        let decision = InboxItem(id: "decision:abc-123", type: .decision, title: "T", age: 0, urgencyScore: 0)
        #expect(decision.sourceId == "abc-123")

        let noColon = InboxItem(id: "bare", type: .task, title: "T", age: 0, urgencyScore: 0)
        #expect(noColon.sourceId == "bare")
    }
}
