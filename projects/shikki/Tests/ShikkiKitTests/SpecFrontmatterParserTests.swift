import Foundation
import Testing
@testable import ShikkiKit

@Suite("SpecFrontmatterParser")
struct SpecFrontmatterParserTests {

    let parser = SpecFrontmatterParser()

    // MARK: - Full Frontmatter

    @Test("parses complete frontmatter with all fields")
    func fullFrontmatter() throws {
        let spec = """
        ---
        title: "ShikkiTestRunner — Parallel Test Execution"
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
        tags: [testing, infrastructure, moto, sqlite]
        flsh:
          summary: "Test runner with Moto scoping, SQLite history, parallel execution"
          duration: 8m
          sections: 14
        ---

        ## 1. Problem

        Current testing is slow.

        ## 2. Solution

        Parallel execution with Moto scoping.
        """
        let meta = try parser.parse(content: spec)

        #expect(meta.title == "ShikkiTestRunner — Parallel Test Execution")
        #expect(meta.status == .validated)
        #expect(meta.progress == "14/14")
        #expect(meta.priority == "P0")
        #expect(meta.project == "shikki")
        #expect(meta.created == "2026-03-31")
        #expect(meta.updated == "2026-03-31")
        #expect(meta.authors == "@shi full team + @Daimyo")
        #expect(meta.reviewers.count == 2)
        #expect(meta.reviewers[0].who == "@Daimyo")
        #expect(meta.reviewers[0].verdict == .validated)
        #expect(meta.reviewers[0].anchor == nil)
        #expect(meta.reviewers[0].notes == "Added agent SQLite handoff")
        #expect(meta.reviewers[1].who == "@Ronin")
        #expect(meta.reviewers[1].verdict == .pending)
        #expect(meta.reviewers[1].date == nil)
        #expect(meta.dependsOn == ["moto-dns-for-code.md"])
        #expect(meta.relatesTo == ["shiki-scoped-testing.md"])
        #expect(meta.tags == ["testing", "infrastructure", "moto", "sqlite"])
        #expect(meta.flsh?.summary == "Test runner with Moto scoping, SQLite history, parallel execution")
        #expect(meta.flsh?.duration == "8m")
        #expect(meta.flsh?.sections == 14)
        #expect(meta.totalSections == 2)
    }

    // MARK: - Minimal Frontmatter

    @Test("parses minimal frontmatter with just title and status")
    func minimalFrontmatter() throws {
        let spec = """
        ---
        title: "Simple Feature"
        status: draft
        ---

        ## Overview

        Just a simple feature.
        """
        let meta = try parser.parse(content: spec)

        #expect(meta.title == "Simple Feature")
        #expect(meta.status == .draft)
        #expect(meta.progress == nil)
        #expect(meta.priority == nil)
        #expect(meta.project == nil)
        #expect(meta.reviewers.isEmpty)
        #expect(meta.dependsOn.isEmpty)
        #expect(meta.relatesTo.isEmpty)
        #expect(meta.tags.isEmpty)
        #expect(meta.flsh == nil)
        #expect(meta.totalSections == 1)
    }

    // MARK: - Lifecycle States

    @Test("validates all lifecycle states parse correctly")
    func allLifecycleStates() throws {
        for state in SpecLifecycle.allCases {
            let spec = """
            ---
            title: "Test"
            status: \(state.rawValue)
            ---
            """
            let meta = try parser.parse(content: spec)
            #expect(meta.status == state)
        }
    }

    @Test("rejects invalid lifecycle status")
    func invalidStatus() {
        let spec = """
        ---
        title: "Test"
        status: banana
        ---
        """
        #expect(throws: SpecFrontmatterError.self) {
            try parser.parse(content: spec)
        }
    }

    // MARK: - Progress Format

    @Test("validates progress format N/M")
    func progressFormat() throws {
        let spec = """
        ---
        title: "Test"
        status: partial
        progress: 5/14
        ---
        """
        let meta = try parser.parse(content: spec)
        #expect(meta.progress == "5/14")
    }

    @Test("rejects invalid progress format")
    func invalidProgressFormat() {
        let spec = """
        ---
        title: "Test"
        status: draft
        progress: five-of-ten
        ---
        """
        #expect(throws: SpecFrontmatterError.self) {
            try parser.parse(content: spec)
        }
    }

    @Test("rejects progress where N > M")
    func progressNGreaterThanM() {
        let spec = """
        ---
        title: "Test"
        status: draft
        progress: 15/10
        ---
        """
        #expect(throws: SpecFrontmatterError.self) {
            try parser.parse(content: spec)
        }
    }

    // MARK: - Reviewer Entries with Anchors

    @Test("parses reviewer entries with anchors and sections")
    func reviewerWithAnchors() throws {
        let spec = """
        ---
        title: "Feature"
        status: partial
        reviewers:
          - who: "@Daimyo"
            date: 2026-03-31
            verdict: partial
            anchor: "#8-tui-output"
            sections_validated: [1, 2, 3, 4, 5, 6, 7]
            sections_rework: [8]
            notes: "Sections 1-7 approved. Section 8: change | to !!"
        ---
        """
        let meta = try parser.parse(content: spec)
        #expect(meta.reviewers.count == 1)

        let reviewer = meta.reviewers[0]
        #expect(reviewer.who == "@Daimyo")
        #expect(reviewer.date == "2026-03-31")
        #expect(reviewer.verdict == .partial)
        #expect(reviewer.anchor == "#8-tui-output")
        #expect(reviewer.sectionsValidated == [1, 2, 3, 4, 5, 6, 7])
        #expect(reviewer.sectionsRework == [8])
        #expect(reviewer.notes == "Sections 1-7 approved. Section 8: change | to !!")
    }

    @Test("rejects anchor that does not start with #")
    func invalidAnchor() {
        let spec = """
        ---
        title: "Feature"
        status: review
        reviewers:
          - who: "@Daimyo"
            verdict: reading
            anchor: "section-8"
        ---
        """
        #expect(throws: SpecFrontmatterError.self) {
            try parser.parse(content: spec)
        }
    }

    // MARK: - Section Counting

    @Test("counts level-2 headings from body")
    func sectionCounting() throws {
        let spec = """
        ---
        title: "Multi Section"
        status: draft
        ---

        ## 1. Problem

        Text here.

        ## 2. Solution

        More text.

        ### 2.1 Sub-section

        Not counted.

        ## 3. Implementation

        Details.

        ## 4. Testing

        Tests go here.
        """
        let meta = try parser.parse(content: spec)
        #expect(meta.totalSections == 4)
    }

    // MARK: - Malformed YAML

    @Test("handles missing frontmatter gracefully")
    func noFrontmatter() {
        let spec = """
        # Just a Heading

        No frontmatter here.
        """
        #expect(throws: SpecFrontmatterError.self) {
            try parser.parse(content: spec)
        }
    }

    @Test("handles unclosed frontmatter gracefully")
    func unclosedFrontmatter() {
        let spec = """
        ---
        title: "Oops"
        status: draft
        """
        #expect(throws: SpecFrontmatterError.self) {
            try parser.parse(content: spec)
        }
    }

    @Test("handles missing title gracefully")
    func missingTitle() {
        let spec = """
        ---
        status: draft
        ---
        """
        #expect(throws: SpecFrontmatterError.self) {
            try parser.parse(content: spec)
        }
    }

    // MARK: - Flsh Block

    @Test("parses flsh block with all fields")
    func flshBlock() throws {
        let spec = """
        ---
        title: "Voice Spec"
        status: validated
        flsh:
          summary: "Quick summary for voice"
          duration: 5m
          sections: 10
        ---
        """
        let meta = try parser.parse(content: spec)
        #expect(meta.flsh?.summary == "Quick summary for voice")
        #expect(meta.flsh?.duration == "5m")
        #expect(meta.flsh?.sections == 10)
    }

    @Test("returns nil flsh when block is absent")
    func noFlshBlock() throws {
        let spec = """
        ---
        title: "No Voice"
        status: draft
        ---
        """
        let meta = try parser.parse(content: spec)
        #expect(meta.flsh == nil)
    }

    // MARK: - Tags

    @Test("parses inline bracket tags")
    func inlineTags() throws {
        let spec = """
        ---
        title: "Tagged"
        status: draft
        tags: [alpha, beta, gamma]
        ---
        """
        let meta = try parser.parse(content: spec)
        #expect(meta.tags == ["alpha", "beta", "gamma"])
    }

    // MARK: - Depends-On / Relates-To

    @Test("parses multiple depends-on entries")
    func multipleDependsOn() throws {
        let spec = """
        ---
        title: "Deps"
        status: draft
        depends-on:
          - spec-a.md
          - spec-b.md
          - spec-c.md
        ---
        """
        let meta = try parser.parse(content: spec)
        #expect(meta.dependsOn == ["spec-a.md", "spec-b.md", "spec-c.md"])
    }

    // MARK: - Default Status

    @Test("defaults to draft when status is missing")
    func defaultStatus() throws {
        let spec = """
        ---
        title: "No Status"
        ---
        """
        let meta = try parser.parse(content: spec)
        #expect(meta.status == .draft)
    }
}
