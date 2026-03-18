import Foundation
import Testing
@testable import ShikiCtlKit

// MARK: - Observatory Engine Tests

@Suite("Observatory Engine — Screen Navigation")
struct ObservatoryScreenTests {

    @Test("Initial screen is timeline")
    func initialScreenIsTimeline() {
        let engine = ObservatoryEngine()
        #expect(engine.currentTab == .timeline)
    }

    @Test("Tab cycles through all tabs")
    func tabCycles() {
        var engine = ObservatoryEngine()
        #expect(engine.currentTab == .timeline)
        engine.nextTab()
        #expect(engine.currentTab == .decisions)
        engine.nextTab()
        #expect(engine.currentTab == .questions)
        engine.nextTab()
        #expect(engine.currentTab == .reports)
        engine.nextTab()
        #expect(engine.currentTab == .timeline) // wraps
    }

    @Test("Arrow navigation moves selection")
    func arrowNavigation() {
        var engine = ObservatoryEngine()
        engine.addTimelineEntry(ObservatoryEntry(
            timestamp: Date(), icon: "◆", significance: .decision,
            title: "Plan validated", detail: "v3.1 plan"
        ))
        engine.addTimelineEntry(ObservatoryEntry(
            timestamp: Date(), icon: "●", significance: .progress,
            title: "Tests green", detail: "271 passed"
        ))
        #expect(engine.selectedIndex == 0)
        engine.moveDown()
        #expect(engine.selectedIndex == 1)
        engine.moveUp()
        #expect(engine.selectedIndex == 0)
        engine.moveUp() // clamp at 0
        #expect(engine.selectedIndex == 0)
    }
}

@Suite("Observatory Engine — Timeline")
struct ObservatoryTimelineTests {

    @Test("Timeline entries sorted by timestamp descending")
    func timelineSorted() {
        var engine = ObservatoryEngine()
        let old = ObservatoryEntry(
            timestamp: Date().addingTimeInterval(-60), icon: "○",
            significance: .progress, title: "Old event", detail: ""
        )
        let recent = ObservatoryEntry(
            timestamp: Date(), icon: "◆",
            significance: .decision, title: "Recent event", detail: ""
        )
        engine.addTimelineEntry(old)
        engine.addTimelineEntry(recent)

        let entries = engine.timelineEntries
        #expect(entries[0].title == "Recent event") // most recent first
    }

    @Test("Only significant events in timeline (no noise)")
    func noNoiseInTimeline() {
        var engine = ObservatoryEngine()
        engine.addTimelineEntry(ObservatoryEntry(
            timestamp: Date(), icon: "○", significance: .noise,
            title: "Heartbeat", detail: ""
        ))
        engine.addTimelineEntry(ObservatoryEntry(
            timestamp: Date(), icon: "◆", significance: .decision,
            title: "Decision", detail: ""
        ))

        let entries = engine.timelineEntries
        #expect(entries.count == 1) // noise filtered
        #expect(entries[0].title == "Decision")
    }

    @Test("Timeline from RouterEnvelope")
    func timelineFromEnvelope() {
        let event = ShikiEvent(source: .orchestrator, type: .sessionStart, scope: .session(id: "test"))
        let envelope = RouterEnvelope(
            event: event, significance: .progress,
            displayHint: .timeline, context: EnrichmentContext()
        )
        let entry = ObservatoryEntry.from(envelope: envelope)
        #expect(entry.significance == .progress)
        #expect(entry.title.contains("sessionStart"))
    }
}

@Suite("Observatory Engine — Reports")
struct ObservatoryReportTests {

    @Test("Add and retrieve agent reports")
    func agentReports() {
        var engine = ObservatoryEngine()
        let report = AgentReportCard(
            sessionId: "maya:spm-wave3", persona: .implement,
            companySlug: "maya", taskTitle: "SPM wave 3",
            duration: 7200, beforeState: "0 session types",
            afterState: "3 files, 31 tests", filesChanged: 9,
            testsAdded: 31, keyDecisions: ["Actor over class", "JSONL over SQLite"],
            redFlags: [], status: .completed
        )
        engine.addReport(report)

        #expect(engine.reports.count == 1)
        #expect(engine.reports[0].sessionId == "maya:spm-wave3")
    }

    @Test("Reports sorted by status (running first, then completed)")
    func reportsSorted() {
        var engine = ObservatoryEngine()
        engine.addReport(AgentReportCard(
            sessionId: "done-1", persona: .implement, companySlug: "a",
            taskTitle: "Done", duration: 100, beforeState: "", afterState: "",
            filesChanged: 0, testsAdded: 0, keyDecisions: [], redFlags: [],
            status: .completed
        ))
        engine.addReport(AgentReportCard(
            sessionId: "running-1", persona: .implement, companySlug: "b",
            taskTitle: "Running", duration: 50, beforeState: "", afterState: "",
            filesChanged: 0, testsAdded: 0, keyDecisions: [], redFlags: [],
            status: .running
        ))

        #expect(engine.reports[0].status == .running)
        #expect(engine.reports[1].status == .completed)
    }
}

@Suite("Observatory Engine — Questions")
struct ObservatoryQuestionTests {

    @Test("Pending questions tracked")
    func pendingQuestions() {
        var engine = ObservatoryEngine()
        engine.addQuestion(PendingQuestion(
            sessionId: "maya:task", question: "Use 5min or 3min threshold?",
            context: "Building SessionRegistry", askedAt: Date()
        ))
        #expect(engine.pendingQuestions.count == 1)
    }

    @Test("Answer removes question")
    func answerRemovesQuestion() {
        var engine = ObservatoryEngine()
        engine.addQuestion(PendingQuestion(
            sessionId: "maya:task", question: "Actor or class?",
            context: "Designing lifecycle", askedAt: Date()
        ))
        engine.answerQuestion(at: 0, answer: "Actor — thread-safe")
        #expect(engine.pendingQuestions.isEmpty)
        #expect(engine.answeredQuestions.count == 1)
    }
}

@Suite("Observatory Engine — Heatmap")
struct ObservatoryHeatmapTests {

    @Test("Heatmap icon for each significance level")
    func heatmapIcons() {
        #expect(ObservatoryHeatmap.icon(for: .critical) == "▲▲")
        #expect(ObservatoryHeatmap.icon(for: .alert) == "▲")
        #expect(ObservatoryHeatmap.icon(for: .decision) == "●")
        #expect(ObservatoryHeatmap.icon(for: .progress) == "○")
        #expect(ObservatoryHeatmap.icon(for: .noise) == "·")
    }

    @Test("Heatmap color for significance")
    func heatmapColors() {
        let critical = ObservatoryHeatmap.color(for: .critical)
        #expect(critical.contains("31")) // red ANSI
        let progress = ObservatoryHeatmap.color(for: .progress)
        #expect(progress.contains("36")) // cyan ANSI
    }
}
