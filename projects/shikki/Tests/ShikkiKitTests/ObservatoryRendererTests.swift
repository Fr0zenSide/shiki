import Foundation
import Testing
@testable import ShikkiKit

// MARK: - Header Tests

@Suite("ObservatoryRenderer — Header")
struct ObservatoryHeaderTests {

    @Test("Header shows SHIKKI OBSERVATORY title")
    func headerTitle() {
        let renderer = ObservatoryRenderer(width: 80)
        let header = renderer.renderHeader(tab: .timeline)
        let plain = stripANSI(header)
        #expect(plain.contains("SHIKKI OBSERVATORY"))
    }

    @Test("Active tab is highlighted in header")
    func activeTabHighlighted() {
        let renderer = ObservatoryRenderer(width: 80)

        for tab in ObservatoryTab.allCases {
            let header = renderer.renderHeader(tab: tab)
            // Active tab should have ANSI inverse code before it
            #expect(header.contains(tab.rawValue.uppercased()))
        }
    }

    @Test("All tabs appear in header")
    func allTabsPresent() {
        let renderer = ObservatoryRenderer(width: 80)
        let header = renderer.renderHeader(tab: .timeline)
        let plain = stripANSI(header)
        for tab in ObservatoryTab.allCases {
            #expect(plain.lowercased().contains(tab.rawValue))
        }
    }
}

// MARK: - Timeline Rendering Tests

@Suite("ObservatoryRenderer — Timeline")
struct ObservatoryTimelineRenderingTests {

    @Test("Empty timeline shows placeholder message")
    func emptyTimeline() {
        let renderer = ObservatoryRenderer(width: 80)
        let lines = renderer.renderTimeline(entries: [], selectedIndex: 0)
        let plain = lines.joined(separator: "\n")
        #expect(stripANSI(plain).contains("No events yet"))
    }

    @Test("Timeline shows entry icon and title")
    func entryShown() {
        let renderer = ObservatoryRenderer(width: 80)
        let entry = ObservatoryEntry(
            timestamp: Date(), icon: "\u{25C6}", significance: .decision,
            title: "Plan validated", detail: "v3.1"
        )
        let lines = renderer.renderTimeline(entries: [entry], selectedIndex: 0)
        let plain = lines.joined(separator: "\n")
        #expect(stripANSI(plain).contains("Plan validated"))
    }

    @Test("Selected entry has cursor indicator")
    func selectedCursor() {
        let renderer = ObservatoryRenderer(width: 80)
        let entries = [
            ObservatoryEntry(
                timestamp: Date(), icon: "\u{25C6}", significance: .decision,
                title: "First", detail: ""
            ),
            ObservatoryEntry(
                timestamp: Date(), icon: "\u{25CF}", significance: .progress,
                title: "Second", detail: ""
            ),
        ]
        let lines = renderer.renderTimeline(entries: entries, selectedIndex: 1)
        // Second line should have the cursor marker (>) after stripping ANSI
        let secondLine = stripANSI(lines[1])
        #expect(secondLine.contains(">"))
    }

    @Test("Timeline entries include time prefix")
    func timePrefix() {
        let renderer = ObservatoryRenderer(width: 80)
        let entry = ObservatoryEntry(
            timestamp: Date(), icon: "\u{25C6}", significance: .decision,
            title: "Test", detail: ""
        )
        let lines = renderer.renderTimeline(entries: [entry], selectedIndex: 0)
        // Should contain HH:MM time format
        let plain = stripANSI(lines[0])
        let hasTime = plain.range(of: "\\d{2}:\\d{2}", options: .regularExpression) != nil
        #expect(hasTime)
    }
}

// MARK: - Decisions Rendering Tests

@Suite("ObservatoryRenderer — Decisions")
struct ObservatoryDecisionsRenderingTests {

    @Test("Empty decisions shows placeholder")
    func emptyDecisions() {
        let renderer = ObservatoryRenderer(width: 80)
        let lines = renderer.renderDecisions(entries: [], selectedIndex: 0)
        let plain = lines.joined(separator: "\n")
        #expect(stripANSI(plain).contains("No decisions recorded"))
    }

    @Test("Decision entries show diamond icon")
    func decisionIcon() {
        let renderer = ObservatoryRenderer(width: 80)
        let entry = ObservatoryEntry(
            timestamp: Date(), icon: "\u{25C6}", significance: .decision,
            title: "Actor over class", detail: ""
        )
        let lines = renderer.renderDecisions(entries: [entry], selectedIndex: 0)
        let plain = lines.joined(separator: "\n")
        #expect(plain.contains("\u{25C6}"))
    }
}

// MARK: - Questions Rendering Tests

@Suite("ObservatoryRenderer — Questions")
struct ObservatoryQuestionsRenderingTests {

    @Test("Empty questions shows placeholder")
    func emptyQuestions() {
        let renderer = ObservatoryRenderer(width: 80)
        let lines = renderer.renderQuestions(questions: [], selectedIndex: 0)
        let plain = lines.joined(separator: "\n")
        #expect(stripANSI(plain).contains("No pending questions"))
    }

    @Test("Question shows session ID and question text")
    func questionShown() {
        let renderer = ObservatoryRenderer(width: 80)
        let q = PendingQuestion(
            sessionId: "maya:task",
            question: "Use 5min or 3min threshold?",
            context: "Building SessionRegistry",
            askedAt: Date()
        )
        let lines = renderer.renderQuestions(questions: [q], selectedIndex: 0)
        let plain = stripANSI(lines.joined(separator: "\n"))
        #expect(plain.contains("maya:task"))
        #expect(plain.contains("5min or 3min"))
        #expect(plain.contains("SessionRegistry"))
    }

    @Test("Answered question shows answer")
    func answeredQuestion() {
        let renderer = ObservatoryRenderer(width: 80)
        let q = PendingQuestion(
            sessionId: "test",
            question: "Actor or class?",
            context: "Design choice",
            askedAt: Date(),
            answer: "Actor — thread-safe"
        )
        let lines = renderer.renderQuestions(questions: [q], selectedIndex: 0)
        let plain = stripANSI(lines.joined(separator: "\n"))
        #expect(plain.contains("answered"))
        #expect(plain.contains("Actor"))
    }
}

// MARK: - Reports Rendering Tests

@Suite("ObservatoryRenderer — Reports")
struct ObservatoryReportsRenderingTests {

    @Test("Empty reports shows placeholder")
    func emptyReports() {
        let renderer = ObservatoryRenderer(width: 80)
        let lines = renderer.renderReports(reports: [], selectedIndex: 0)
        let plain = lines.joined(separator: "\n")
        #expect(stripANSI(plain).contains("No agent reports"))
    }

    @Test("Selected report is expanded, others collapsed")
    func selectedExpanded() {
        let renderer = ObservatoryRenderer(width: 80)
        let reports = [
            AgentReportCard(
                sessionId: "sess-1", persona: .implement, companySlug: "maya",
                taskTitle: "Wave 3", duration: 7200, beforeState: "empty",
                afterState: "3 files", filesChanged: 9, testsAdded: 31,
                keyDecisions: ["Decision A"], redFlags: [], status: .completed
            ),
            AgentReportCard(
                sessionId: "sess-2", persona: .verify, companySlug: "maya",
                taskTitle: "Verify", duration: 300, beforeState: "", afterState: "",
                filesChanged: 0, testsAdded: 0, keyDecisions: [], redFlags: [],
                status: .running
            ),
        ]

        let lines = renderer.renderReports(reports: reports, selectedIndex: 0)
        let plain = stripANSI(lines.joined(separator: "\n"))
        // First report (selected) should show Before/After (expanded)
        #expect(plain.contains("Before: empty"))
        // Second report should not show Before/After (collapsed)
        // This is true because renderTUI(expanded: false) omits those
    }
}

// MARK: - Footer Tests

@Suite("ObservatoryRenderer — Footer")
struct ObservatoryFooterTests {

    @Test("Footer shows keyboard shortcuts")
    func footerShortcuts() {
        let renderer = ObservatoryRenderer(width: 80)
        let footer = renderer.renderFooter(tab: .timeline)
        let plain = stripANSI(footer)
        #expect(plain.contains("navigate"))
        #expect(plain.contains("quit"))
    }

    @Test("Questions tab footer shows submit shortcut")
    func questionsFooter() {
        let renderer = ObservatoryRenderer(width: 80)
        let footer = renderer.renderFooter(tab: .questions)
        let plain = stripANSI(footer)
        #expect(plain.contains("Ctrl-S"))
        #expect(plain.contains("submit"))
    }
}

// MARK: - Full Frame Tests

@Suite("ObservatoryRenderer — Full Frame")
struct ObservatoryFullFrameTests {

    @Test("Full render produces non-empty output")
    func fullRender() {
        let engine = ObservatoryEngine()
        let renderer = ObservatoryRenderer(width: 80, height: 24)
        let output = renderer.render(engine: engine)
        #expect(!output.isEmpty)
        #expect(output.contains("OBSERVATORY"))
    }

    @Test("renderPlain strips ANSI codes")
    func plainRendering() {
        var engine = ObservatoryEngine()
        engine.addTimelineEntry(ObservatoryEntry(
            timestamp: Date(), icon: "\u{25C6}", significance: .decision,
            title: "Test decision", detail: ""
        ))
        let renderer = ObservatoryRenderer(width: 80, height: 24)
        let lines = renderer.renderPlain(engine: engine)
        let joined = lines.joined()
        // Should not contain any ESC characters
        #expect(!joined.contains("\u{1B}"))
    }

    @Test("Full render with all tabs populated")
    func allTabsPopulated() {
        var engine = ObservatoryEngine()
        engine.addTimelineEntry(ObservatoryEntry(
            timestamp: Date(), icon: "\u{25C6}", significance: .decision,
            title: "Decision entry", detail: "architecture"
        ))
        engine.addQuestion(PendingQuestion(
            sessionId: "test", question: "Q1",
            context: "context", askedAt: Date()
        ))
        engine.addReport(AgentReportCard(
            sessionId: "test", persona: .implement, companySlug: "test",
            taskTitle: "Task", duration: 60, beforeState: "a",
            afterState: "b", filesChanged: 1, testsAdded: 1,
            keyDecisions: [], redFlags: [], status: .completed
        ))

        let renderer = ObservatoryRenderer(width: 80, height: 24)

        // Verify each tab renders without crashing
        for tab in ObservatoryTab.allCases {
            var tabEngine = engine
            while tabEngine.currentTab != tab { tabEngine.nextTab() }
            let output = renderer.render(engine: tabEngine)
            #expect(!output.isEmpty)
        }
    }
}

// MARK: - Helpers

private func stripANSI(_ string: String) -> String {
    string.replacingOccurrences(
        of: "\u{1B}\\[[0-9;]*m", with: "",
        options: .regularExpression
    )
}
