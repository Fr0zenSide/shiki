import Foundation
import Testing
@testable import ShikkiKit

// MARK: - Report Generation Tests

@Suite("AgentReportGenerator — Generation")
struct AgentReportGenerationTests {

    @Test("Generate report with basic fields")
    func basicReport() {
        let generator = AgentReportGenerator()
        let now = Date()
        let report = generator.generate(
            sessionId: "maya:spm-wave3",
            persona: .implement,
            companySlug: "maya",
            taskTitle: "SPM wave 3",
            startedAt: now.addingTimeInterval(-7200),
            endedAt: now,
            filesChanged: 9,
            testsAdded: 31,
            beforeState: "0 session types",
            afterState: "3 files, 31 tests"
        )

        #expect(report.sessionId == "maya:spm-wave3")
        #expect(report.persona == .implement)
        #expect(report.companySlug == "maya")
        #expect(report.duration >= 7199 && report.duration <= 7201)
        #expect(report.filesChanged == 9)
        #expect(report.testsAdded == 31)
        #expect(report.status == .completed)
    }

    @Test("Key decisions extracted from high-impact/high-confidence decisions")
    func keyDecisionsExtracted() {
        let generator = AgentReportGenerator()
        let decisions = [
            DecisionEvent(
                sessionId: "test", category: .architecture,
                question: "Actor or class?", choice: "Actor",
                rationale: "Thread-safe by default",
                impact: .architecture, confidence: 0.95
            ),
            DecisionEvent(
                sessionId: "test", category: .implementation,
                question: "Tab size?", choice: "4 spaces",
                rationale: "Style guide says so",
                impact: .implementation, confidence: 0.5
            ),
        ]

        let report = generator.generate(
            sessionId: "test", persona: .implement,
            companySlug: "test", taskTitle: "Task",
            startedAt: Date().addingTimeInterval(-60),
            decisions: decisions
        )

        // Architecture decision included (impact = .architecture)
        #expect(report.keyDecisions.count == 1)
        #expect(report.keyDecisions[0].contains("Actor"))
    }

    @Test("Low-confidence decisions generate red flags")
    func lowConfidenceRedFlags() {
        let generator = AgentReportGenerator()
        let decisions = [
            DecisionEvent(
                sessionId: "test", category: .tradeOff,
                question: "Use untested library?", choice: "Yes",
                rationale: "Seems ok",
                impact: .implementation, confidence: 0.3
            ),
        ]

        let report = generator.generate(
            sessionId: "test", persona: .implement,
            companySlug: "test", taskTitle: "Task",
            startedAt: Date().addingTimeInterval(-60),
            decisions: decisions,
            redFlags: ["Manual red flag"]
        )

        #expect(report.redFlags.count == 2) // 1 manual + 1 low-confidence
        #expect(report.redFlags.contains { $0.contains("Manual red flag") })
        #expect(report.redFlags.contains { $0.contains("Low-confidence") })
    }

    @Test("Empty before/after states get default values")
    func defaultStates() {
        let generator = AgentReportGenerator()
        let report = generator.generate(
            sessionId: "test", persona: .implement,
            companySlug: "test", taskTitle: "Task",
            startedAt: Date().addingTimeInterval(-60)
        )
        #expect(report.beforeState == "no prior state")
        #expect(report.afterState == "session ended")
    }

    @Test("Report status propagated correctly")
    func statusPropagated() {
        let generator = AgentReportGenerator()

        for status in [AgentReportStatus.running, .blocked, .completed, .failed] {
            let report = generator.generate(
                sessionId: "test", persona: .implement,
                companySlug: "test", taskTitle: "Task",
                startedAt: Date().addingTimeInterval(-60),
                status: status
            )
            #expect(report.status == status)
        }
    }
}

// MARK: - Report to Event Conversion

@Suite("AgentReportGenerator — Event Conversion")
struct AgentReportEventTests {

    @Test("Report converts to ShikkiEvent with correct type")
    func convertToEvent() {
        let generator = AgentReportGenerator()
        let report = generator.generate(
            sessionId: "maya:wave3", persona: .implement,
            companySlug: "maya", taskTitle: "Wave 3",
            startedAt: Date().addingTimeInterval(-3600),
            filesChanged: 5, testsAdded: 10
        )

        let event = generator.toEvent(report)
        #expect(event.type == .agentReportGenerated)
        #expect(event.payload["sessionId"]?.stringValue == "maya:wave3")
        #expect(event.payload["persona"]?.stringValue == "implement")
        #expect(event.payload["filesChanged"]?.intValue == 5)
        #expect(event.payload["testsAdded"]?.intValue == 10)
        #expect(event.metadata?.tags?.contains("agent-report") == true)
    }

    @Test("Event scope is project with company slug")
    func eventScope() {
        let generator = AgentReportGenerator()
        let report = generator.generate(
            sessionId: "test", persona: .verify,
            companySlug: "wabisabi", taskTitle: "Verify",
            startedAt: Date().addingTimeInterval(-60)
        )

        let event = generator.toEvent(report)
        if case .project(let slug) = event.scope {
            #expect(slug == "wabisabi")
        } else {
            Issue.record("Expected project scope")
        }
    }
}

// MARK: - Report Rendering Tests

@Suite("AgentReportCard — TUI Rendering")
struct AgentReportRenderingTests {

    @Test("Expanded TUI rendering includes all sections")
    func expandedRendering() {
        let report = AgentReportCard(
            sessionId: "maya:wave3", persona: .implement,
            companySlug: "maya", taskTitle: "Wave 3",
            duration: 7200, beforeState: "empty",
            afterState: "3 files", filesChanged: 9,
            testsAdded: 31, keyDecisions: ["Actor over class"],
            redFlags: [], status: .completed
        )

        let output = report.renderTUI(expanded: true)
        #expect(output.contains("maya:wave3"))
        #expect(output.contains("Before: empty"))
        #expect(output.contains("After:  3 files"))
        #expect(output.contains("9 files changed"))
        #expect(output.contains("Actor over class"))
    }

    @Test("Collapsed TUI rendering is compact")
    func collapsedRendering() {
        let report = AgentReportCard(
            sessionId: "maya:wave3", persona: .implement,
            companySlug: "maya", taskTitle: "Wave 3",
            duration: 7200, beforeState: "empty",
            afterState: "3 files", filesChanged: 9,
            testsAdded: 31, keyDecisions: ["Actor over class"],
            redFlags: [], status: .completed
        )

        let output = report.renderTUI(expanded: false)
        #expect(output.contains("maya:wave3"))
        #expect(!output.contains("Before:"))
    }

    @Test("Red flags shown in collapsed view when present")
    func collapsedWithRedFlags() {
        let report = AgentReportCard(
            sessionId: "test", persona: .implement,
            companySlug: "test", taskTitle: "Task",
            duration: 60, beforeState: "", afterState: "",
            filesChanged: 0, testsAdded: 0, keyDecisions: [],
            redFlags: ["Something wrong"], status: .running
        )

        let output = report.renderTUI(expanded: false)
        #expect(output.contains("1 red flag"))
    }

    @Test("Duration formatted as hours and minutes")
    func durationFormatting() {
        let short = AgentReportCard(
            sessionId: "test", persona: .implement,
            companySlug: "test", taskTitle: "Task",
            duration: 1500, beforeState: "", afterState: "",
            filesChanged: 0, testsAdded: 0, keyDecisions: [],
            redFlags: [], status: .completed
        )
        let shortOutput = short.renderTUI()
        #expect(shortOutput.contains("25m"))

        let long = AgentReportCard(
            sessionId: "test", persona: .implement,
            companySlug: "test", taskTitle: "Task",
            duration: 7980, beforeState: "", afterState: "",
            filesChanged: 0, testsAdded: 0, keyDecisions: [],
            redFlags: [], status: .completed
        )
        let longOutput = long.renderTUI()
        #expect(longOutput.contains("2h 13m"))
    }

    @Test("Markdown rendering includes all fields")
    func markdownRendering() {
        let report = AgentReportCard(
            sessionId: "maya:wave3", persona: .implement,
            companySlug: "maya", taskTitle: "Wave 3",
            duration: 7200, beforeState: "empty",
            afterState: "3 files", filesChanged: 9,
            testsAdded: 31, keyDecisions: ["Actor over class"],
            redFlags: ["Warning"], status: .completed
        )

        let md = report.renderMarkdown()
        #expect(md.contains("# Agent Report: maya:wave3"))
        #expect(md.contains("| Persona | implement |"))
        #expect(md.contains("**Before**: empty"))
        #expect(md.contains("**After**: 3 files"))
        #expect(md.contains("Actor over class"))
        #expect(md.contains("Warning"))
    }
}

// MARK: - Report Status Ordering Tests

@Suite("AgentReportStatus — Ordering")
struct AgentReportStatusOrderingTests {

    @Test("Running < blocked < completed < failed")
    func statusOrdering() {
        #expect(AgentReportStatus.running < .blocked)
        #expect(AgentReportStatus.blocked < .completed)
        #expect(AgentReportStatus.completed < .failed)
    }
}
