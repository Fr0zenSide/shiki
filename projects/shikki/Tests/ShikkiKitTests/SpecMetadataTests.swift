import Foundation
import Testing
@testable import ShikkiKit

@Suite("SpecMetadata")
struct SpecMetadataTests {

    // MARK: - Lifecycle State Machine

    @Test("draft can transition to review")
    func draftToReview() {
        #expect(SpecLifecycle.draft.canTransition(to: .review))
    }

    @Test("draft cannot skip to validated")
    func draftCannotSkipToValidated() {
        #expect(!SpecLifecycle.draft.canTransition(to: .validated))
    }

    @Test("validated can transition to implementing or rejected")
    func validatedTransitions() {
        #expect(SpecLifecycle.validated.canTransition(to: .implementing))
        #expect(SpecLifecycle.validated.canTransition(to: .rejected))
    }

    @Test("any state can transition to outdated except outdated itself")
    func outdatedTransition() {
        for state in SpecLifecycle.allCases where state != .outdated {
            #expect(state.canTransition(to: .outdated), "\(state) should be able to transition to outdated")
        }
        #expect(!SpecLifecycle.outdated.canTransition(to: .outdated))
    }

    @Test("outdated is terminal — no transitions out")
    func outdatedTerminal() {
        #expect(SpecLifecycle.outdated.validTransitions.isEmpty)
    }

    @Test("rejected can only go to outdated")
    func rejectedTransitions() {
        #expect(SpecLifecycle.rejected.validTransitions == [.outdated])
    }

    // MARK: - ReviewerVerdict

    @Test("all reviewer verdicts are distinct raw values")
    func reviewerVerdictRawValues() {
        let rawValues = ReviewerVerdict.allCases.map(\.rawValue)
        #expect(Set(rawValues).count == rawValues.count)
    }

    // MARK: - SpecMetadata Init Defaults

    @Test("default init provides sensible defaults")
    func defaultInit() {
        let meta = SpecMetadata(title: "Test")
        #expect(meta.status == .draft)
        #expect(meta.progress == nil)
        #expect(meta.reviewers.isEmpty)
        #expect(meta.tags.isEmpty)
        #expect(meta.totalSections == 0)
    }
}
