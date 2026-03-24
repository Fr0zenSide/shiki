import Testing
import Foundation
@testable import ShikiCtlKit

@Suite("DecideListReviewer")
struct DecideListReviewerTests {

    // MARK: - Helpers

    private func sampleDecision(
        id: String = "d1",
        companySlug: String = "maya",
        tier: Int = 1,
        question: String = "Which auth provider?",
        context: String? = "Blocks login flow",
        options: [String: AnyCodable]? = nil
    ) -> Decision {
        // Build JSON and decode to get a proper Decision
        var json: [String: Any] = [
            "id": id,
            "company_id": "c1",
            "tier": tier,
            "question": question,
            "answered": false,
            "created_at": "2026-03-24T10:00:00Z",
            "metadata": "{}",
            "company_slug": companySlug,
            "options": NSNull(),
        ]
        if let context = context {
            json["context"] = context
        }
        if let options = options {
            var optDict: [String: Any] = [:]
            for (k, v) in options {
                optDict[k] = v.value
            }
            json["options"] = optDict
        }
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(Decision.self, from: data)
    }

    // MARK: - Test 1: Decisions convert to ListItems

    @Test("Decisions convert to ListItems with correct title, subtitle, metadata")
    func decisionToListItem() {
        let decision = sampleDecision()
        let item = DecideListReviewer.toListItem(decision)

        #expect(item.id == "d1")
        #expect(item.title == "Which auth provider?")
        #expect(item.subtitle == "T1 \u{2022} maya")
        #expect(item.status == .pending)
        #expect(item.metadata["company"] == "maya")
        #expect(item.metadata["tier"] == "T1")
        #expect(item.metadata["context"] == "Blocks login flow")
    }

    // MARK: - Test 2: Company filter scopes correctly

    @Test("Company scope filters decisions to matching company only")
    func companyScopeFiltering() {
        let d1 = sampleDecision(id: "d1", companySlug: "maya", question: "Maya Q1")
        let d2 = sampleDecision(id: "d2", companySlug: "shiki", question: "Shiki Q1")
        let d3 = sampleDecision(id: "d3", companySlug: "maya", question: "Maya Q2")

        let allItems = DecideListReviewer.toListItems([d1, d2, d3])
        #expect(allItems.count == 3)

        let mayaOnly = DecideListReviewer.toListItems([d1, d2, d3], companyScope: "maya")
        #expect(mayaOnly.count == 2)
        #expect(mayaOnly.allSatisfy { $0.metadata["company"] == "maya" })

        let shikiOnly = DecideListReviewer.toListItems([d1, d2, d3], companyScope: "shiki")
        #expect(shikiOnly.count == 1)
        #expect(shikiOnly[0].metadata["company"] == "shiki")
    }

    // MARK: - Test 3: Progress persistence records actions

    @Test("Progress records actions and reflects in ListItem status")
    func progressPersistence() {
        var progress = DecideProgress()

        // Record an answered decision
        DecideListReviewer.recordAction(
            progress: &progress,
            decisionId: "d1",
            action: "answered",
            answer: "Use Apple Sign-In"
        )

        // Record a deferred decision
        DecideListReviewer.recordAction(
            progress: &progress,
            decisionId: "d2",
            action: "deferred"
        )

        // Record a dismissed decision
        DecideListReviewer.recordAction(
            progress: &progress,
            decisionId: "d3",
            action: "dismissed"
        )

        #expect(progress.reviewed.count == 3)
        #expect(progress.reviewed["d1"]?.action == "answered")
        #expect(progress.reviewed["d1"]?.answer == "Use Apple Sign-In")
        #expect(progress.reviewed["d2"]?.action == "deferred")
        #expect(progress.reviewed["d3"]?.action == "dismissed")

        // Verify status mapping
        let d1 = sampleDecision(id: "d1")
        let d2 = sampleDecision(id: "d2")
        let d3 = sampleDecision(id: "d3")

        let item1 = DecideListReviewer.toListItem(d1, progress: progress)
        let item2 = DecideListReviewer.toListItem(d2, progress: progress)
        let item3 = DecideListReviewer.toListItem(d3, progress: progress)

        #expect(item1.status == .validated)
        #expect(item2.status == .deferred)
        #expect(item3.status == .killed)

        // All are considered reviewed
        #expect(item1.status.isReviewed)
        #expect(item2.status.isReviewed)
        #expect(item3.status.isReviewed)
    }

    // MARK: - Test 4: Decide config has correct actions

    @Test("Decide config uses answer/defer/dismiss actions")
    func decideConfigActions() {
        let config = DecideListReviewer.makeConfig()

        #expect(config.title == "Pending Decisions")
        #expect(config.showProgress)
        #expect(config.actions.count == 5)

        let keys = config.actions.map(\.key)
        #expect(keys.contains("a"))  // answer
        #expect(keys.contains("d"))  // defer
        #expect(keys.contains("k"))  // dismiss
        #expect(keys.contains("n"))  // next
        #expect(keys.contains("q"))  // quit

        // answer is batchable
        let answerAction = config.actions.first { $0.key == "a" }
        #expect(answerAction?.batchable == true)

        // next is not batchable
        let nextAction = config.actions.first { $0.key == "n" }
        #expect(nextAction?.batchable == false)

        // Company-scoped title
        let scopedConfig = DecideListReviewer.makeConfig(companyScope: "maya")
        #expect(scopedConfig.title == "Pending Decisions [maya]")
    }
}
