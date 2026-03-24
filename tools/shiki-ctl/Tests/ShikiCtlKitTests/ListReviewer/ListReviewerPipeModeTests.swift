import Testing
import Foundation
@testable import ShikiCtlKit

/// BR-L-06: Pipe mode — detect non-TTY, output JSON or count instead of interactive TUI.
@Suite("ListReviewer Pipe Mode — BR-L-06")
struct ListReviewerPipeModeTests {

    // MARK: - Helpers

    private func sampleItems() -> [ListItem] {
        [
            ListItem(id: "pr-1", title: "Fix crash", status: .pending,
                     metadata: ["company": "maya", "priority": "P0"]),
            ListItem(id: "pr-2", title: "Add feature", status: .inReview,
                     metadata: ["company": "shikki", "priority": "P1"]),
            ListItem(id: "pr-3", title: "Cleanup", status: .validated,
                     metadata: ["company": "maya"]),
        ]
    }

    private func makeConfig() -> ListReviewerConfig {
        ListReviewerConfig(title: "Pipe Test", listId: "pipe-test")
    }

    // MARK: - Tests

    @Test("JSON output is valid JSON with expected structure — BR-L-06")
    func jsonOutputIsValidJSON() {
        let items = sampleItems()
        let output = PipeOutput.json(items: items, config: makeConfig())

        // Parse as JSON
        let data = output.data(using: .utf8)!
        let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(parsed != nil)
        #expect(parsed?["title"] as? String == "Pipe Test")

        let jsonItems = parsed?["items"] as? [[String: Any]]
        #expect(jsonItems?.count == 3)

        // Check first item has expected fields
        let first = jsonItems?.first
        #expect(first?["id"] as? String == "pr-1")
        #expect(first?["status"] as? String == "pending")
        #expect(first?["urgency"] as? String != nil)

        let progress = parsed?["progress"] as? [String: Any]
        #expect(progress?["total"] as? Int == 3)
        #expect(progress?["reviewed"] as? Int == 1)
    }

    @Test("Count output is a single number — BR-L-06")
    func countOutputIsSingleNumber() {
        let items = sampleItems()
        let output = PipeOutput.count(items: items)

        // Should be "3\n"
        #expect(output.trimmingCharacters(in: .whitespacesAndNewlines) == "3")

        // Verify it matches the regex ^\d+\n$
        let matches = output.range(of: #"^\d+\n$"#, options: .regularExpression) != nil
        #expect(matches)
    }

    @Test("Plain output has no ANSI escape sequences — BR-L-06")
    func plainOutputHasNoANSI() {
        let items = sampleItems()
        let output = PipeOutput.plain(items: items, config: makeConfig())

        // No ESC character should appear
        #expect(!output.contains("\u{1B}"))

        // Should still contain readable content
        #expect(output.contains("Pipe Test"))
        #expect(output.contains("Fix crash"))
        #expect(output.contains("Add feature"))
    }
}
