import Foundation
import Testing
@testable import ShikkiKit

@Suite("InboxRenderer — Themed Inbox Output (Wave 4)")
struct InboxRendererTests {

    // MARK: - Test Helpers

    private func makeItem(
        type: InboxItem.ItemType,
        score: Int,
        title: String,
        subtitle: String? = nil,
        age: TimeInterval = 3600,
        companySlug: String? = "shikki"
    ) -> InboxItem {
        InboxItem(
            id: "\(type.rawValue):\(title)",
            type: type,
            title: title,
            subtitle: subtitle,
            age: age,
            companySlug: companySlug,
            urgencyScore: score
        )
    }

    // MARK: - Empty Inbox

    @Test("Empty inbox renders 'Inbox is empty' inside a box")
    func emptyInbox() {
        let result = InboxRenderer.render(items: [], plain: true)
        #expect(result.contains("Inbox is empty"))
        // Should still have box structure
        #expect(result.contains("+"))
        #expect(result.contains("-"))
    }

    // MARK: - Header Box

    @Test("Header box shows correct item counts per type")
    func headerBoxCounts() {
        let items = [
            makeItem(type: .spec, score: 80, title: "Spec A"),
            makeItem(type: .spec, score: 60, title: "Spec B"),
            makeItem(type: .pr, score: 50, title: "PR 1"),
            makeItem(type: .task, score: 30, title: "Task 1"),
            makeItem(type: .task, score: 20, title: "Task 2"),
            makeItem(type: .task, score: 10, title: "Task 3"),
            makeItem(type: .gate, score: 75, title: "Gate 1"),
        ]
        let result = InboxRenderer.render(items: items, branch: "develop", plain: true)
        let stripped = result
        // 7 items total
        #expect(stripped.contains("7 items"))
        // SP:2 PR:1 DC:0 TK:3 GT:1
        #expect(stripped.contains("SP:2"))
        #expect(stripped.contains("PR:1"))
        #expect(stripped.contains("DC:0"))
        #expect(stripped.contains("TK:3"))
        #expect(stripped.contains("GT:1"))
        // Branch name
        #expect(stripped.contains("develop"))
    }

    // MARK: - Urgency Zones

    @Test("Items grouped into urgency zones: hot, active, queued")
    func urgencyZoneGrouping() {
        let items = [
            makeItem(type: .spec, score: 85, title: "Hot Spec"),
            makeItem(type: .pr, score: 55, title: "Active PR"),
            makeItem(type: .task, score: 20, title: "Queued Task"),
        ]
        let result = InboxRenderer.render(items: items, plain: true)
        // All three zone headers present
        #expect(result.contains("Hot (70+)"))
        #expect(result.contains("Active (40-69)"))
        #expect(result.contains("Queued (<40)"))
        // Hot appears before Active, Active before Queued
        let hotIdx = result.range(of: "Hot (70+)")!.lowerBound
        let activeIdx = result.range(of: "Active (40-69)")!.lowerBound
        let queuedIdx = result.range(of: "Queued (<40)")!.lowerBound
        #expect(hotIdx < activeIdx)
        #expect(activeIdx < queuedIdx)
    }

    @Test("Empty zones are omitted")
    func emptyZonesOmitted() {
        let items = [
            makeItem(type: .spec, score: 85, title: "Hot Spec"),
            // No active or queued items
        ]
        let result = InboxRenderer.render(items: items, plain: true)
        #expect(result.contains("Hot (70+)"))
        #expect(!result.contains("Active (40-69)"))
        #expect(!result.contains("Queued (<40)"))
    }

    // MARK: - Type Badge

    @Test("Type badge renders correct 2-letter code")
    func typeBadgeCodes() {
        let specs = [makeItem(type: .spec, score: 50, title: "S")]
        let prs = [makeItem(type: .pr, score: 50, title: "P")]
        let decisions = [makeItem(type: .decision, score: 50, title: "D")]
        let tasks = [makeItem(type: .task, score: 50, title: "T")]
        let gates = [makeItem(type: .gate, score: 50, title: "G")]

        #expect(InboxRenderer.render(items: specs, plain: true).contains("SP"))
        #expect(InboxRenderer.render(items: prs, plain: true).contains("PR"))
        #expect(InboxRenderer.render(items: decisions, plain: true).contains("DC"))
        #expect(InboxRenderer.render(items: tasks, plain: true).contains("TK"))
        #expect(InboxRenderer.render(items: gates, plain: true).contains("GT"))
    }

    // MARK: - Urgency Bar

    @Test("Urgency bar has correct fill ratio: 80% score -> 6 filled + 2 empty at width 8")
    func urgencyBarFillRatio() {
        let items = [makeItem(type: .spec, score: 80, title: "Test")]
        let result = InboxRenderer.render(items: items, plain: true)
        // 80/100 * 8 = 6.4 -> 6 filled, 2 empty
        #expect(result.contains("██████░░"))
    }

    @Test("Urgency bar at 0 score is all empty")
    func urgencyBarZero() {
        let items = [makeItem(type: .task, score: 0, title: "Zero")]
        let result = InboxRenderer.render(items: items, plain: true)
        #expect(result.contains("░░░░░░░░"))
    }

    @Test("Urgency bar at 100 score is all filled")
    func urgencyBarFull() {
        let items = [makeItem(type: .gate, score: 100, title: "Full")]
        let result = InboxRenderer.render(items: items, plain: true)
        #expect(result.contains("████████"))
    }

    // MARK: - Plain Mode

    @Test("Plain mode strips all ANSI and uses ASCII box chars")
    func plainModeStripANSI() {
        let items = [makeItem(type: .spec, score: 50, title: "Test Item")]
        let result = InboxRenderer.render(items: items, plain: true)
        // No ANSI escape codes
        #expect(!result.contains("\u{1B}["))
        // ASCII box chars instead of Unicode
        #expect(result.contains("+"))
        #expect(result.contains("-"))
        #expect(result.contains("|"))
        #expect(!result.contains("╭"))
        #expect(!result.contains("╰"))
    }

    @Test("Colored mode includes ANSI escape codes")
    func coloredModeHasANSI() {
        let items = [makeItem(type: .spec, score: 50, title: "Test Item")]
        let result = InboxRenderer.render(items: items, plain: false)
        #expect(result.contains("\u{1B}["))
    }

    // MARK: - Footer

    @Test("Footer shows filter hints")
    func footerFilterHints() {
        let items = [makeItem(type: .spec, score: 50, title: "Test")]
        let result = InboxRenderer.render(items: items, plain: true)
        #expect(result.contains("--prs"))
        #expect(result.contains("--specs"))
        #expect(result.contains("--tasks"))
        #expect(result.contains("--sort"))
    }

    // MARK: - Subtitle

    @Test("Subtitle renders dimmed on next line when present")
    func subtitleRendering() {
        let items = [makeItem(type: .spec, score: 50, title: "Main Title", subtitle: "Some extra detail")]
        let result = InboxRenderer.render(items: items, plain: true)
        #expect(result.contains("Main Title"))
        #expect(result.contains("Some extra detail"))
    }

    // MARK: - Age Formatting

    @Test("Age formats correctly: hours and days")
    func ageFormatting() {
        let hourItem = makeItem(type: .task, score: 50, title: "Recent", age: 7200) // 2h
        let dayItem = makeItem(type: .task, score: 50, title: "Old", age: 259200)   // 3d
        let result = InboxRenderer.render(items: [hourItem, dayItem], plain: true)
        #expect(result.contains("(2h)"))
        #expect(result.contains("(3d)"))
    }

    // MARK: - Company Slug

    @Test("Company slug renders as bracketed tag")
    func companySlugTag() {
        let items = [makeItem(type: .spec, score: 50, title: "Test", companySlug: "shiki")]
        let result = InboxRenderer.render(items: items, plain: true)
        #expect(result.contains("[shiki]"))
    }
}
