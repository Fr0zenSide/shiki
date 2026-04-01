import Foundation
import Testing
@testable import ShikkiKit

@Suite("SpecAnnotationParser")
struct SpecAnnotationParserTests {

    let parser = SpecAnnotationParser()

    // MARK: - Basic Parsing

    @Test("parses a single open annotation")
    func singleAnnotation() {
        let markdown = """
        ## 8. TUI Output

        <!-- @note @Daimyo 2026-03-31 -->
        <!-- Change | to !! for failure count. More attention. -->
        <!-- status: open -->

        Some body text here.
        """
        let annotations = parser.parse(content: markdown)
        #expect(annotations.count == 1)
        #expect(annotations[0].who == "@Daimyo")
        #expect(annotations[0].date == "2026-03-31")
        #expect(annotations[0].content == "Change | to !! for failure count. More attention.")
        #expect(annotations[0].status == .open)
    }

    // MARK: - Multiple Annotations

    @Test("parses multiple annotations in one file")
    func multipleAnnotations() {
        let markdown = """
        ## 8. TUI Output

        <!-- @note @Daimyo 2026-03-31 -->
        <!-- Change | to !! for failure count. -->
        <!-- status: applied -->

        <!-- @note @Ronin pending -->
        <!-- What if logger buffer overflows during a 10min E2E test? -->
        <!-- status: open -->
        """
        let annotations = parser.parse(content: markdown)
        #expect(annotations.count == 2)
        #expect(annotations[0].who == "@Daimyo")
        #expect(annotations[0].status == .applied)
        #expect(annotations[1].who == "@Ronin")
        #expect(annotations[1].date == nil)
        #expect(annotations[1].status == .open)
    }

    // MARK: - Open Notes Filter

    @Test("filters only open notes")
    func openNotesFilter() {
        let markdown = """
        <!-- @note @Daimyo 2026-03-31 -->
        <!-- Fixed this. -->
        <!-- status: resolved -->

        <!-- @note @Ronin pending -->
        <!-- Needs review. -->
        <!-- status: open -->

        <!-- @note @Hanami 2026-03-30 -->
        <!-- Applied the UX change. -->
        <!-- status: applied -->
        """
        let open = parser.openNotes(in: markdown)
        #expect(open.count == 1)
        #expect(open[0].who == "@Ronin")
    }

    // MARK: - All Annotation Statuses

    @Test("parses all three status types")
    func allStatuses() {
        for status in AnnotationStatus.allCases {
            let markdown = """
            <!-- @note @Test 2026-01-01 -->
            <!-- Content -->
            <!-- status: \(status.rawValue) -->
            """
            let annotations = parser.parse(content: markdown)
            #expect(annotations.count == 1)
            #expect(annotations[0].status == status)
        }
    }

    // MARK: - Default Status

    @Test("defaults to open when no status line")
    func defaultStatus() {
        let markdown = """
        <!-- @note @Daimyo 2026-03-31 -->
        <!-- A note without explicit status. -->

        Some text.
        """
        let annotations = parser.parse(content: markdown)
        #expect(annotations.count == 1)
        #expect(annotations[0].status == .open)
    }

    // MARK: - Multi-Line Content

    @Test("captures multiple content lines")
    func multiLineContent() {
        let markdown = """
        <!-- @note @Sensei 2026-03-31 -->
        <!-- First line of the note. -->
        <!-- Second line with more detail. -->
        <!-- Third line with a recommendation. -->
        <!-- status: open -->
        """
        let annotations = parser.parse(content: markdown)
        #expect(annotations.count == 1)
        #expect(annotations[0].content.contains("First line"))
        #expect(annotations[0].content.contains("Second line"))
        #expect(annotations[0].content.contains("Third line"))
    }

    // MARK: - No Annotations

    @Test("returns empty for markdown without annotations")
    func noAnnotations() {
        let markdown = """
        ## 1. Problem

        Regular markdown with no annotations.

        ## 2. Solution

        Just text.
        """
        let annotations = parser.parse(content: markdown)
        #expect(annotations.isEmpty)
    }

    // MARK: - Edge Cases

    @Test("handles annotation at end of file without trailing newline")
    func annotationAtEOF() {
        let markdown = "<!-- @note @Katana 2026-03-31 -->\n<!-- Security concern. -->\n<!-- status: open -->"
        let annotations = parser.parse(content: markdown)
        #expect(annotations.count == 1)
        #expect(annotations[0].who == "@Katana")
        #expect(annotations[0].content == "Security concern.")
    }
}
