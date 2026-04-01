import Testing
import Foundation
@testable import ShikkiKit

// MARK: - SpecFrontmatterService Tests

@Suite("SpecFrontmatterService")
struct SpecFrontmatterServiceTests {

    let service = SpecFrontmatterService()

    // MARK: - Frontmatter Parsing

    @Test("Parse minimal frontmatter — title and status")
    func parseMinimalFrontmatter() {
        let content = """
        ---
        title: "Test Runner Spec"
        status: draft
        ---
        # Test Runner

        Some content.
        """
        let metadata = service.parse(content: content, filename: "test-runner.md")
        #expect(metadata != nil)
        #expect(metadata?.title == "Test Runner Spec")
        #expect(metadata?.status == .draft)
        #expect(metadata?.filename == "test-runner.md")
    }

    @Test("Parse full frontmatter — all fields")
    func parseFullFrontmatter() {
        let content = """
        ---
        title: "ShikkiTestRunner"
        status: validated
        progress: 14/14
        priority: P0
        project: shikki
        created: 2026-03-31
        updated: 2026-03-31
        authors: "@shi full team + @Daimyo"
        reviewers:
          - who: "@Daimyo"
            date: 2026-03-31
            verdict: validated
            anchor: null
            notes: "Added agent SQLite handoff"
          - who: "@Ronin"
            date: null
            verdict: pending
        depends-on:
          - moto-dns-for-code.md
        relates-to:
          - shiki-scoped-testing.md
        tags: [testing, infrastructure]
        ---
        # ShikkiTestRunner
        """
        let metadata = service.parse(content: content)
        #expect(metadata != nil)
        #expect(metadata?.status == .validated)
        #expect(metadata?.progress == "14/14")
        #expect(metadata?.priority == "P0")
        #expect(metadata?.project == "shikki")
        #expect(metadata?.reviewers.count == 2)
        #expect(metadata?.reviewers[0].who == "@Daimyo")
        #expect(metadata?.reviewers[0].verdict == .validated)
        #expect(metadata?.reviewers[0].notes == "Added agent SQLite handoff")
        #expect(metadata?.reviewers[1].who == "@Ronin")
        #expect(metadata?.reviewers[1].verdict == .pending)
        #expect(metadata?.reviewers[1].date == nil)
        #expect(metadata?.dependsOn?.count == 1)
        #expect(metadata?.relatesTo?.count == 1)
        #expect(metadata?.tags?.count == 2)
    }

    @Test("Parse returns nil for content without frontmatter")
    func parseNoFrontmatter() {
        let content = "# Just a heading\n\nSome content."
        let metadata = service.parse(content: content)
        #expect(metadata == nil)
    }

    @Test("Parse returns nil for content without title")
    func parseNoTitle() {
        let content = """
        ---
        status: draft
        ---
        # Heading
        """
        let metadata = service.parse(content: content)
        #expect(metadata == nil)
    }

    @Test("Parse reviewers with partial verdict and anchor")
    func parsePartialReviewer() {
        let content = """
        ---
        title: "Mesh Protocol"
        status: partial
        progress: 5/8
        reviewers:
          - who: "@Daimyo"
            date: 2026-03-31
            verdict: partial
            anchor: "#8-tui-output"
            sections_validated: [1, 2, 3, 4, 5, 6, 7]
            sections_rework: [8]
            notes: "Sections 1-7 approved. Section 8: change | to !!"
        ---
        # Mesh Protocol
        """
        let metadata = service.parse(content: content)
        #expect(metadata?.status == .partial)
        #expect(metadata?.reviewers.count == 1)
        let reviewer = metadata?.reviewers[0]
        #expect(reviewer?.verdict == .partial)
        #expect(reviewer?.anchor == "#8-tui-output")
        #expect(reviewer?.sectionsValidated == [1, 2, 3, 4, 5, 6, 7])
        #expect(reviewer?.sectionsRework == [8])
    }

    // MARK: - Section Counting

    @Test("Count sections — markdown headings")
    func countSections() {
        let content = """
        ---
        title: "Test"
        status: draft
        ---
        # Main Title

        ## 1. Problem

        Some text.

        ## 2. Solution

        More text.

        ## 3. Implementation

        ### 3.1 Details

        ## 4. Testing
        """
        let count = service.countSections(in: content)
        #expect(count == 4, "Should count 4 ## headings, not ### or #")
    }

    @Test("Count sections — empty content")
    func countSectionsEmpty() {
        let count = service.countSections(in: "")
        #expect(count == 0)
    }

    // MARK: - Anchor Resolution

    @Test("Find anchor line — exact heading match")
    func findAnchorLine() {
        let content = """
        # Title

        ## 1. Problem

        text

        ## 2. Solution

        text

        ## 8. TUI Output

        text
        """
        let line = service.findAnchorLine(in: content, anchor: "#8-tui-output")
        #expect(line == 11)
    }

    @Test("Find anchor line — returns nil for non-existent anchor")
    func findAnchorLineNotFound() {
        let content = """
        # Title

        ## 1. Problem
        """
        let line = service.findAnchorLine(in: content, anchor: "#99-nonexistent")
        #expect(line == nil)
    }

    @Test("Find anchor line — with hash prefix stripped")
    func findAnchorLineWithHash() {
        let content = "## 3. Implementation\n\ntext"
        let line = service.findAnchorLine(in: content, anchor: "#3-implementation")
        #expect(line == 1)
    }

    // MARK: - Frontmatter Writing

    @Test("Update frontmatter — replaces existing")
    func updateExistingFrontmatter() {
        let content = """
        ---
        title: "Test Spec"
        status: draft
        ---
        # Test Spec

        Content here.
        """
        let metadata = SpecMetadata(title: "Test Spec", status: .review)
        let updated = service.updateFrontmatter(in: content, with: metadata)

        #expect(updated.contains("status: review"))
        #expect(updated.contains("# Test Spec"))
        #expect(updated.contains("Content here."))
    }

    @Test("Update frontmatter — prepends when none exists")
    func prependFrontmatter() {
        let content = "# Test Spec\n\nContent here."
        let metadata = SpecMetadata(title: "Test Spec", status: .draft)
        let updated = service.updateFrontmatter(in: content, with: metadata)

        #expect(updated.hasPrefix("---\n"))
        #expect(updated.contains("status: draft"))
        #expect(updated.contains("# Test Spec"))
    }

    // MARK: - Status Transitions (draft -> review -> validated)

    @Test("Full lifecycle: draft -> review -> partial -> validated")
    func fullLifecycleTransition() {
        let initialContent = """
        ---
        title: "Lifecycle Test"
        status: draft
        progress: 0/3
        ---

        ## 1. Section One

        ## 2. Section Two

        ## 3. Section Three
        """

        // Step 1: draft -> review
        var metadata = service.parse(content: initialContent)!
        #expect(metadata.status.canTransition(to: .review))
        metadata.status = .review
        metadata.reviewers = [SpecReviewer(who: "@Daimyo", date: "2026-03-31", verdict: .reading)]
        let reviewContent = service.updateFrontmatter(in: initialContent, with: metadata)

        // Step 2: review -> partial
        var reviewMeta = service.parse(content: reviewContent)!
        #expect(reviewMeta.status.canTransition(to: .partial))
        reviewMeta.status = .partial
        reviewMeta.progress = "2/3"
        reviewMeta.reviewers[0].verdict = .partial
        reviewMeta.reviewers[0].anchor = "#3-section-three"
        reviewMeta.reviewers[0].sectionsValidated = [1, 2]
        reviewMeta.reviewers[0].sectionsRework = [3]
        let partialContent = service.updateFrontmatter(in: reviewContent, with: reviewMeta)

        // Step 3: partial -> validated
        var partialMeta = service.parse(content: partialContent)!
        #expect(partialMeta.status.canTransition(to: .validated))
        partialMeta.status = .validated
        partialMeta.progress = "3/3"
        partialMeta.reviewers[0].verdict = .validated
        partialMeta.reviewers[0].anchor = nil
        partialMeta.reviewers[0].sectionsValidated = [1, 2, 3]
        partialMeta.reviewers[0].sectionsRework = nil
        let validatedContent = service.updateFrontmatter(in: partialContent, with: partialMeta)

        let finalMeta = service.parse(content: validatedContent)!
        #expect(finalMeta.status == .validated)
        #expect(finalMeta.progress == "3/3")
        #expect(finalMeta.reviewers[0].verdict == .validated)
        #expect(finalMeta.reviewers[0].anchor == nil)
    }

    // MARK: - Formatting

    @Test("Format list entry — validated spec")
    func formatListEntryValidated() {
        let meta = SpecMetadata(
            title: "Test Runner",
            status: .validated,
            progress: "14/14",
            reviewers: [
                SpecReviewer(who: "@Daimyo", date: "2026-03-31", verdict: .validated),
            ],
            filename: "shikki-test-runner.md"
        )
        let line = SpecFrontmatterService.formatListEntry(meta)
        #expect(line.contains("[validated]"))
        #expect(line.contains("shikki-test-runner.md"))
        #expect(line.contains("14/14"))
        #expect(line.contains("@Daimyo"))
    }

    @Test("Format list entry — draft spec with no reviewer")
    func formatListEntryDraft() {
        let meta = SpecMetadata(
            title: "Creative Studio",
            status: .draft,
            progress: "0/6",
            filename: "shikki-creative-studio.md"
        )
        let line = SpecFrontmatterService.formatListEntry(meta)
        #expect(line.contains("[draft]"))
        #expect(line.contains("shikki-creative-studio.md"))
        #expect(line.contains("\u{2014}")) // em dash for no reviewer
    }

    @Test("Format progress summary")
    func formatProgressSummary() {
        let specs = [
            SpecMetadata(title: "A", status: .validated),
            SpecMetadata(title: "B", status: .validated),
            SpecMetadata(title: "C", status: .draft),
            SpecMetadata(title: "D", status: .partial),
        ]
        let summary = SpecFrontmatterService.formatProgressSummary(specs)
        #expect(summary.contains("Total specs:     4"))
        #expect(summary.contains("Validated:       2"))
        #expect(summary.contains("Draft:           1"))
        #expect(summary.contains("Partial:         1"))
        #expect(summary.contains("50%")) // 2/4 validated
    }

    // MARK: - Heading Slug

    @Test("Heading slugification")
    func slugifyHeading() {
        #expect(service.slugifyHeading("8. TUI Output") == "8-tui-output")
        #expect(service.slugifyHeading("3. Implementation") == "3-implementation")
        #expect(service.slugifyHeading("Problem Statement") == "problem-statement")
    }

    // MARK: - Serialization Round-trip

    @Test("YAML serialization round-trip preserves data")
    func yamlRoundTrip() {
        let original = SpecMetadata(
            title: "Round Trip Test",
            status: .partial,
            progress: "5/8",
            priority: "P1",
            project: "shikki",
            created: "2026-03-30",
            updated: "2026-03-31",
            authors: "@Daimyo",
            reviewers: [
                SpecReviewer(
                    who: "@Daimyo",
                    date: "2026-03-31",
                    verdict: .partial,
                    anchor: "#8-tui-output",
                    notes: "Needs rework on section 8"
                ),
            ],
            dependsOn: ["dep-a.md"],
            relatesTo: ["rel-b.md"],
            tags: ["testing", "infra"]
        )

        let yaml = service.serializeToYAML(original)
        let parsed = service.parseYAML(yaml)

        #expect(parsed?.title == original.title)
        #expect(parsed?.status == original.status)
        #expect(parsed?.progress == original.progress)
        #expect(parsed?.priority == original.priority)
        #expect(parsed?.reviewers.count == 1)
        #expect(parsed?.reviewers[0].who == "@Daimyo")
        #expect(parsed?.reviewers[0].verdict == .partial)
        #expect(parsed?.reviewers[0].anchor == "#8-tui-output")
        #expect(parsed?.dependsOn == ["dep-a.md"])
        #expect(parsed?.tags == ["testing", "infra"])
    }
}
