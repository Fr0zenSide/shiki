import Foundation
import Testing
@testable import ShikiCore

@Suite("DecisionQueue")
struct DecisionQueueTests {

    @Test("Enqueue and retrieve pending decisions")
    func enqueuePending() async {
        let queue = DecisionQueue()
        let item = DecisionItem(
            featureId: "feat-1",
            tier: .t1,
            question: "Which API pattern?",
            options: ["REST", "GraphQL"]
        )
        let id = await queue.enqueue(item)
        let pending = await queue.pending(featureId: "feat-1")
        #expect(pending.count == 1)
        #expect(pending[0].id == id)
        #expect(pending[0].question == "Which API pattern?")
    }

    @Test("Answer clears pending status")
    func answerClearsPending() async {
        let queue = DecisionQueue()
        let item = DecisionItem(featureId: "feat-1", tier: .t1, question: "Deploy strategy?")
        let id = await queue.enqueue(item)

        let answered = await queue.answer(id: id, answer: "Blue-green")
        #expect(answered)

        let pending = await queue.pending(featureId: "feat-1")
        #expect(pending.isEmpty)

        let all = await queue.all(featureId: "feat-1")
        #expect(all.count == 1)
        #expect(all[0].answer == "Blue-green")
    }

    @Test("T1 blockers block the feature, T2 do not")
    func blockerTiers() async {
        let queue = DecisionQueue()

        let t1 = DecisionItem(featureId: "feat-1", tier: .t1, question: "Critical decision")
        let t2 = DecisionItem(featureId: "feat-1", tier: .t2, question: "Nice to have")

        await queue.enqueue(t1)
        await queue.enqueue(t2)

        #expect(await queue.isBlocked(featureId: "feat-1"))
        #expect(await queue.blockers(featureId: "feat-1").count == 1)

        // Answer the T1 blocker
        _ = await queue.answer(id: t1.id, answer: "Go with option A")
        #expect(await !queue.isBlocked(featureId: "feat-1"))

        // T2 still pending but not a blocker
        #expect(await queue.pending(featureId: "feat-1").count == 1)
    }

    @Test("Answer nonexistent ID returns false")
    func answerNonexistent() async {
        let queue = DecisionQueue()
        let result = await queue.answer(id: "nonexistent", answer: "something")
        #expect(!result)
    }

    @Test("Pending count tracks all features")
    func pendingCountAcrossFeatures() async {
        let queue = DecisionQueue()
        await queue.enqueue(DecisionItem(featureId: "feat-1", tier: .t1, question: "Q1"))
        await queue.enqueue(DecisionItem(featureId: "feat-2", tier: .t2, question: "Q2"))
        await queue.enqueue(DecisionItem(featureId: "feat-1", tier: .t1, question: "Q3"))

        #expect(await queue.pendingCount == 3)
    }

    @Test("DecisionItem is Codable")
    func codableRoundTrip() throws {
        let item = DecisionItem(
            featureId: "feat-1",
            tier: .t1,
            question: "Architecture?",
            context: "We need to decide",
            options: ["MVVM", "MVC"]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(item)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DecisionItem.self, from: data)

        #expect(decoded.id == item.id)
        #expect(decoded.featureId == item.featureId)
        #expect(decoded.tier == item.tier)
        #expect(decoded.question == item.question)
        #expect(decoded.context == item.context)
        #expect(decoded.options == item.options)
    }

    @Test("DecisionTier ordering: T1 < T2")
    func tierOrdering() {
        #expect(DecisionTier.t1 < DecisionTier.t2)
    }
}
