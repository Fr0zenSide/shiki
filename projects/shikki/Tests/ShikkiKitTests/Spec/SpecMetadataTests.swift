import Testing
@testable import ShikkiKit

// MARK: - SpecLifecycleStatus Tests

@Suite("SpecLifecycleStatus")
struct SpecLifecycleStatusTests {

    @Test("All lifecycle states have markers")
    func allStatesHaveMarkers() {
        for status in SpecLifecycleStatus.allCases {
            #expect(!status.marker.isEmpty, "Marker for \(status) should not be empty")
        }
    }

    @Test("Draft can transition to review")
    func draftToReview() {
        #expect(SpecLifecycleStatus.draft.canTransition(to: .review))
    }

    @Test("Review can transition to validated")
    func reviewToValidated() {
        #expect(SpecLifecycleStatus.review.canTransition(to: .validated))
    }

    @Test("Review can transition to partial")
    func reviewToPartial() {
        #expect(SpecLifecycleStatus.review.canTransition(to: .partial))
    }

    @Test("Validated can transition to implementing")
    func validatedToImplementing() {
        #expect(SpecLifecycleStatus.validated.canTransition(to: .implementing))
    }

    @Test("Validated can transition to rejected")
    func validatedToRejected() {
        #expect(SpecLifecycleStatus.validated.canTransition(to: .rejected))
    }

    @Test("Outdated is terminal — no forward transitions")
    func outdatedIsTerminal() {
        #expect(SpecLifecycleStatus.outdated.validTransitions.isEmpty)
    }

    @Test("Invalid transition: draft cannot go directly to shipped")
    func draftCannotShip() {
        #expect(!SpecLifecycleStatus.draft.canTransition(to: .shipped))
    }

    @Test("Any state can transition to outdated (except outdated itself)")
    func anyToOutdated() {
        for status in SpecLifecycleStatus.allCases where status != .outdated {
            #expect(status.canTransition(to: .outdated), "\(status) should be able to transition to outdated")
        }
    }
}

// MARK: - SpecMetadata Tests

@Suite("SpecMetadata")
struct SpecMetadataModelTests {

    @Test("Progress parsing — valid format")
    func progressParsing() {
        let meta = SpecMetadata(title: "Test", progress: "5/10")
        let parsed = meta.progressParsed
        #expect(parsed?.reviewed == 5)
        #expect(parsed?.total == 10)
    }

    @Test("Progress parsing — nil when not set")
    func progressParsingNil() {
        let meta = SpecMetadata(title: "Test")
        #expect(meta.progressParsed == nil)
    }

    @Test("Progress parsing — invalid format returns nil")
    func progressParsingInvalid() {
        let meta = SpecMetadata(title: "Test", progress: "invalid")
        #expect(meta.progressParsed == nil)
    }

    @Test("Primary reviewer — picks first non-pending")
    func primaryReviewer() {
        let meta = SpecMetadata(
            title: "Test",
            reviewers: [
                SpecReviewer(who: "@Ronin", verdict: .pending),
                SpecReviewer(who: "@Daimyo", verdict: .validated),
            ]
        )
        #expect(meta.primaryReviewer?.who == "@Daimyo")
    }

    @Test("Primary reviewer — falls back to first if all pending")
    func primaryReviewerFallback() {
        let meta = SpecMetadata(
            title: "Test",
            reviewers: [
                SpecReviewer(who: "@Ronin", verdict: .pending),
                SpecReviewer(who: "@Daimyo", verdict: .pending),
            ]
        )
        #expect(meta.primaryReviewer?.who == "@Ronin")
    }

    @Test("Latest review date — picks most recent")
    func latestReviewDate() {
        let meta = SpecMetadata(
            title: "Test",
            reviewers: [
                SpecReviewer(who: "@Ronin", date: "2026-03-28"),
                SpecReviewer(who: "@Daimyo", date: "2026-03-31"),
            ]
        )
        #expect(meta.latestReviewDate == "2026-03-31")
    }
}
