import Testing
@testable import ShikiCtlKit

@Suite("PRReviewParser")
struct PRReviewParserTests {

    static let fixtureMarkdown = """
    # PR #5 Review — feat(shiki-ctl): v0.2.0 CLI migration + orchestrator fixes

    > **Branch**: `feature/cli-core-architecture` → `develop`
    > **Files**: 28 changed, +3,010 / -767
    > **Tests**: 52/52 green, 13 suites
    > **Pre-PR**: All gates passed (1 fix iteration on Gate 1b)

    ---

    ## Review Sections

    Navigate with your editor's heading jumps.

    ### Section 1: Architecture Overview

    | Layer | Role | Files |
    |-------|------|-------|
    | **Commands** | CLI entry points | 7 files |

    **Key design decision**: Commands are thin.

    ---

    ### Section 2: Critical Path — Ghost Process Cleanup

    **The bug**: `shiki stop` killed the tmux session but orphaned processes survived.

    **Review questions**:
    - [ ] Is `usleep(500_000)` acceptable for SIGTERM→SIGKILL wait?
    - [ ] Should `findOrphanedClaudeProcesses` also look for `xcodebuild`?
    - [ ] Is the self-PID filter sufficient?

    ---

    ### Section 3: Smart Stale Relaunch

    **Review questions**:
    - [ ] Is the budget check correct?
    - [ ] Should there be a cooldown?

    ---

    ## Reviewer Checklist

    - [ ] **Section 2**: ProcessCleanup logic is correct
    - [ ] **Section 3**: Smart stale relaunch conditions are complete
    - [ ] **Overall**: Ready to merge to develop
    """

    @Test("Parses PR metadata from header block")
    func parsesMetadata() throws {
        let review = try PRReviewParser.parse(Self.fixtureMarkdown)
        #expect(review.title.contains("v0.2.0"))
        #expect(review.branch == "feature/cli-core-architecture")
        #expect(review.filesChanged == 28)
        #expect(review.testsInfo == "52/52 green, 13 suites")
    }

    @Test("Parses all sections from headings")
    func parsesSections() throws {
        let review = try PRReviewParser.parse(Self.fixtureMarkdown)
        #expect(review.sections.count == 3)
        #expect(review.sections[0].title == "Architecture Overview")
        #expect(review.sections[1].title == "Critical Path — Ghost Process Cleanup")
        #expect(review.sections[2].title == "Smart Stale Relaunch")
    }

    @Test("Extracts review questions as checkboxes")
    func extractsQuestions() throws {
        let review = try PRReviewParser.parse(Self.fixtureMarkdown)
        #expect(review.sections[1].questions.count == 3)
        #expect(review.sections[1].questions[0].text.contains("usleep"))
        #expect(review.sections[2].questions.count == 2)
    }

    @Test("Sections without questions have empty array")
    func noQuestionsSection() throws {
        let review = try PRReviewParser.parse(Self.fixtureMarkdown)
        #expect(review.sections[0].questions.isEmpty)
    }

    @Test("Parses reviewer checklist items")
    func parsesChecklist() throws {
        let review = try PRReviewParser.parse(Self.fixtureMarkdown)
        #expect(review.checklist.count == 3)
        #expect(review.checklist[0].contains("Section 2"))
        #expect(review.checklist[2].contains("Overall"))
    }

    @Test("Section body contains content between headings")
    func sectionBody() throws {
        let review = try PRReviewParser.parse(Self.fixtureMarkdown)
        #expect(review.sections[1].body.contains("orphaned processes"))
    }

    @Test("Throws on empty input")
    func throwsOnEmpty() {
        #expect(throws: PRReviewParserError.self) {
            try PRReviewParser.parse("")
        }
    }
}
