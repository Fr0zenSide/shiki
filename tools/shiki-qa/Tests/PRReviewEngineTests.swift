import Foundation
import Testing
@testable import ShikiCtlKit

@Suite("PRReviewEngine")
struct PRReviewEngineTests {

    static func makeReview() -> PRReview {
        PRReview(
            title: "Test PR",
            branch: "feature/test",
            filesChanged: 5,
            testsInfo: "10/10 green",
            sections: [
                ReviewSection(
                    index: 1,
                    title: "First",
                    body: "Body of first section",
                    questions: [
                        ReviewQuestion(text: "Is this OK?"),
                        ReviewQuestion(text: "Should we refactor?"),
                    ]
                ),
                ReviewSection(
                    index: 2,
                    title: "Second",
                    body: "Body of second section",
                    questions: [
                        ReviewQuestion(text: "Performance acceptable?"),
                    ]
                ),
                ReviewSection(
                    index: 3,
                    title: "Third",
                    body: "Body of third section with no questions",
                    questions: []
                ),
            ],
            checklist: ["Section 1 OK", "Section 2 OK", "Overall OK"]
        )
    }

    @Test("Initial state is modeSelection")
    func initialState() {
        let engine = PRReviewEngine(review: Self.makeReview())
        guard case .modeSelection = engine.currentScreen else {
            Issue.record("Expected modeSelection, got \(engine.currentScreen)")
            return
        }
    }

    @Test("Mode selection Enter transitions to sectionList")
    func modeSelectionToSectionList() {
        var engine = PRReviewEngine(review: Self.makeReview())
        engine.handle(key: .enter)
        guard case .sectionList = engine.currentScreen else {
            Issue.record("Expected sectionList, got \(engine.currentScreen)")
            return
        }
    }

    @Test("Section list Enter opens section view")
    func sectionListToSectionView() {
        var engine = PRReviewEngine(review: Self.makeReview())
        engine.handle(key: .enter) // → sectionList
        engine.handle(key: .enter) // → sectionView(0)
        guard case .sectionView(let idx) = engine.currentScreen else {
            Issue.record("Expected sectionView, got \(engine.currentScreen)")
            return
        }
        #expect(idx == 0)
    }

    @Test("Arrow navigation moves selection in section list")
    func arrowNavigation() {
        var engine = PRReviewEngine(review: Self.makeReview())
        engine.handle(key: .enter) // → sectionList
        #expect(engine.selectedIndex == 0)
        engine.handle(key: .down)
        #expect(engine.selectedIndex == 1)
        engine.handle(key: .down)
        #expect(engine.selectedIndex == 2)
        engine.handle(key: .down) // should clamp
        #expect(engine.selectedIndex == 2)
        engine.handle(key: .up)
        #expect(engine.selectedIndex == 1)
    }

    @Test("Escape from sectionView returns to sectionList")
    func escapeFromSectionView() {
        var engine = PRReviewEngine(review: Self.makeReview())
        engine.handle(key: .enter) // → sectionList
        engine.handle(key: .enter) // → sectionView(0)
        engine.handle(key: .escape) // → sectionList
        guard case .sectionList = engine.currentScreen else {
            Issue.record("Expected sectionList, got \(engine.currentScreen)")
            return
        }
    }

    @Test("Verdict sets section verdict and returns to list")
    func verdictSetsAndReturns() {
        var engine = PRReviewEngine(review: Self.makeReview())
        engine.handle(key: .enter) // → sectionList
        engine.handle(key: .enter) // → sectionView(0)
        engine.handle(key: .char("a")) // approve section
        guard case .sectionList = engine.currentScreen else {
            Issue.record("Expected sectionList after verdict, got \(engine.currentScreen)")
            return
        }
        #expect(engine.state.verdicts[0] == .approved)
    }

    @Test("Verdict options: a=approve, c=comment, r=request-changes")
    func verdictKeys() {
        var engine = PRReviewEngine(review: Self.makeReview())
        engine.handle(key: .enter) // → sectionList

        // Section 0: approve
        engine.handle(key: .enter)
        engine.handle(key: .char("a"))
        #expect(engine.state.verdicts[0] == .approved)

        // Section 1: request changes
        engine.handle(key: .down)
        engine.handle(key: .enter)
        engine.handle(key: .char("r"))
        #expect(engine.state.verdicts[1] == .requestChanges)

        // Section 2: comment
        engine.handle(key: .down)
        engine.handle(key: .enter)
        engine.handle(key: .char("c"))
        #expect(engine.state.verdicts[2] == .comment)
    }

    @Test("Summary screen accessible via 's' from section list")
    func summaryScreen() {
        var engine = PRReviewEngine(review: Self.makeReview())
        engine.handle(key: .enter) // → sectionList
        engine.handle(key: .char("s")) // → summary
        guard case .summary = engine.currentScreen else {
            Issue.record("Expected summary, got \(engine.currentScreen)")
            return
        }
    }

    @Test("Quit from summary transitions to done")
    func quitFromSummary() {
        var engine = PRReviewEngine(review: Self.makeReview())
        engine.handle(key: .enter)
        engine.handle(key: .char("s"))
        engine.handle(key: .char("q"))
        guard case .done = engine.currentScreen else {
            Issue.record("Expected done, got \(engine.currentScreen)")
            return
        }
    }

    @Test("State is Codable for persistence")
    func stateCodable() throws {
        var state = PRReviewState(sectionCount: 3)
        state.verdicts[0] = .approved
        state.verdicts[1] = .requestChanges
        state.currentSectionIndex = 1

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(PRReviewState.self, from: data)

        #expect(decoded.verdicts[0] == .approved)
        #expect(decoded.verdicts[1] == .requestChanges)
        #expect(decoded.verdicts[2] == nil)
        #expect(decoded.currentSectionIndex == 1)
    }

    @Test("Quick mode skips to section list immediately")
    func quickMode() {
        let engine = PRReviewEngine(review: Self.makeReview(), quickMode: true)
        guard case .sectionList = engine.currentScreen else {
            Issue.record("Expected sectionList in quick mode, got \(engine.currentScreen)")
            return
        }
    }

    @Test("Resume restores state")
    func resume() {
        var state = PRReviewState(sectionCount: 3)
        state.verdicts[0] = .approved
        state.currentSectionIndex = 1
        let engine = PRReviewEngine(review: Self.makeReview(), state: state)
        guard case .sectionList = engine.currentScreen else {
            Issue.record("Expected sectionList on resume, got \(engine.currentScreen)")
            return
        }
        #expect(engine.state.verdicts[0] == .approved)
        #expect(engine.selectedIndex == 1)
    }
}
