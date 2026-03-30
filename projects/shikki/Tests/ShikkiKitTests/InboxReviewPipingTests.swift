import Foundation
import Testing
@testable import ShikkiKit

@Suite("Inbox-Review piping — BR-I-01, BR-I-02, BR-I-05")
struct InboxReviewPipingTests {

    @Test("BR-I-01: prNumbers extracts PR numbers from inbox sorted by urgency")
    func prNumbersFromInbox() async throws {
        let source = MockInboxDataSource(sourceType: .pr, items: [
            InboxItem(id: "pr:42", type: .pr, title: "Fix #42", age: 3600, urgencyScore: 20),
            InboxItem(id: "pr:15", type: .pr, title: "Feature #15", age: 7200, urgencyScore: 60),
            InboxItem(id: "pr:30", type: .pr, title: "Refactor #30", age: 1800, urgencyScore: 40),
        ])

        let manager = InboxManager(sources: [source])
        let numbers = try await manager.prNumbers()

        // Should contain all 3 PR numbers
        #expect(numbers.count == 3)
        // Sorted by urgency (highest first): 15 (60), 30 (40), 42 (20)
        #expect(numbers[0] == 15)
        #expect(numbers[1] == 30)
        #expect(numbers[2] == 42)
    }

    @Test("BR-I-05: markValidated returns validated status for PR items")
    func markValidatedReturnStatus() async throws {
        let manager = InboxManager(sources: [
            MockInboxDataSource(sourceType: .pr, items: []),
        ])

        let status = manager.markValidated("pr:42")
        #expect(status == .validated)
    }

    @Test("InboxItem.prNumber extracts number from PR items only")
    func prNumberExtraction() {
        let pr = InboxItem(id: "pr:42", type: .pr, title: "PR", age: 0, urgencyScore: 0)
        #expect(pr.prNumber == 42)

        let decision = InboxItem(id: "decision:abc-123", type: .decision, title: "Q", age: 0, urgencyScore: 0)
        #expect(decision.prNumber == nil)

        let prBad = InboxItem(id: "pr:not-a-number", type: .pr, title: "Bad", age: 0, urgencyScore: 0)
        #expect(prBad.prNumber == nil)
    }
}
