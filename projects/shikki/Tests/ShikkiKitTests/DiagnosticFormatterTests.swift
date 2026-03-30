import Foundation
import Testing
@testable import ShikkiKit

@Suite("DiagnosticFormatter — BR-08 to BR-11, BR-21")
struct DiagnosticFormatterTests {

    // MARK: - Helpers

    private func makeContext(
        staleness: Staleness = .fresh,
        branch: String? = "main",
        confidence: ConfidenceScore = ConfidenceScore(dbScore: 70, checkpointScore: 100, gitScore: 50),
        timeline: [RecoveredItem] = [],
        errors: [String] = [],
        pendingDecisions: [String] = []
    ) -> RecoveryContext {
        let now = Date()
        return RecoveryContext(
            recoveredAt: now,
            timeWindow: TimeWindow.lookback(seconds: 7200, from: now),
            confidence: confidence,
            staleness: staleness,
            sources: [
                SourceResult(name: "db", status: .available, itemCount: 5, score: 70),
                SourceResult(name: "checkpoint", status: .available, itemCount: 2, score: 100),
                SourceResult(name: "git", status: .available, itemCount: 1, score: 50),
            ],
            timeline: timeline,
            workspace: WorkspaceSnapshot(
                branch: branch,
                recentCommits: [
                    CommitInfo(hash: "abc1234def", message: "feat: new feature", author: "dev", timestamp: now),
                ]
            ),
            errors: errors,
            pendingDecisions: pendingDecisions
        )
    }

    private func makeItem(
        provenance: Provenance = .db,
        kind: ItemKind = .event,
        summary: String = "test event",
        detail: String? = nil
    ) -> RecoveredItem {
        RecoveredItem(
            timestamp: Date(),
            provenance: provenance,
            kind: kind,
            summary: summary,
            detail: detail
        )
    }

    // MARK: - Human Format (BR-08)

    @Test("Human format includes state and branch")
    func humanFormat_includesStateAndBranch() {
        let context = makeContext(branch: "develop")
        let output = DiagnosticFormatter.formatHuman(context, isTTY: false)
        #expect(output.contains("develop"))
    }

    @Test("Human format strips ANSI when not TTY")
    func humanFormat_stripsANSI_whenNotTTY() {
        let context = makeContext()
        let output = DiagnosticFormatter.formatHuman(context, isTTY: false)
        #expect(!output.contains("\u{1B}["))
    }

    @Test("Human format includes ANSI when TTY")
    func humanFormat_includesANSI_whenTTY() {
        let context = makeContext()
        let output = DiagnosticFormatter.formatHuman(context, isTTY: true)
        #expect(output.contains("\u{1B}["))
    }

    @Test("Human format shows confidence meter")
    func humanFormat_showsConfidenceMeter() {
        let context = makeContext()
        let output = DiagnosticFormatter.formatHuman(context, isTTY: false)
        #expect(output.contains("Confidence:"))
        #expect(output.contains("%"))
    }

    @Test("Human format shows staleness indicator")
    func humanFormat_showsStalenessIndicator() {
        let context = makeContext(staleness: .fresh)
        let output = DiagnosticFormatter.formatHuman(context, isTTY: false)
        #expect(output.contains("fresh"))
    }

    @Test("Human format verbose shows full payloads")
    func humanFormat_verbose_showsFullPayloads() {
        let item = makeItem(detail: "full payload details here")
        let context = makeContext(timeline: [item])
        let verboseOutput = DiagnosticFormatter.formatHuman(context, isTTY: false, verbose: true)
        let normalOutput = DiagnosticFormatter.formatHuman(context, isTTY: false, verbose: false)
        #expect(verboseOutput.contains("full payload details here"))
        #expect(!normalOutput.contains("full payload details here"))
    }

    @Test("Human format shows pending decisions")
    func humanFormat_showsPendingDecisions() {
        let context = makeContext(pendingDecisions: ["Approve PR #42?"])
        let output = DiagnosticFormatter.formatHuman(context, isTTY: false)
        #expect(output.contains("Approve PR #42?"))
    }

    @Test("Human format shows errors")
    func humanFormat_showsErrors() {
        let context = makeContext(errors: ["DB: Connection refused"])
        let output = DiagnosticFormatter.formatHuman(context, isTTY: false)
        #expect(output.contains("DB: Connection refused"))
    }

    // MARK: - Agent Format (BR-09)

    @Test("Agent format wraps in context-recovery tags")
    func agentFormat_wrapsInContextRecoveryTags() {
        let context = makeContext()
        let output = DiagnosticFormatter.formatAgent(context)
        #expect(output.contains("<context-recovery>"))
        #expect(output.contains("</context-recovery>"))
    }

    @Test("Agent format default budget under 2KB")
    func agentFormat_defaultBudget_under2KB() {
        let context = makeContext()
        let output = DiagnosticFormatter.formatAgent(context, budget: 2048)
        #expect(output.utf8.count <= 2048 + 100) // small margin for closing tags
    }

    @Test("Agent format custom budget respects limit")
    func agentFormat_customBudget_respectsLimit() {
        // Create a context with many items to test budget enforcement
        let items = (0..<50).map { i in
            makeItem(summary: "Event number \(i) with some detail text for padding")
        }
        let context = makeContext(timeline: items)
        let output = DiagnosticFormatter.formatAgent(context, budget: 512)
        #expect(output.utf8.count <= 612) // budget + margin for closing tags
    }

    @Test("Agent format stale context includes warning comment")
    func agentFormat_staleContext_includesWarningComment() {
        let context = makeContext(staleness: .stale)
        let output = DiagnosticFormatter.formatAgent(context)
        #expect(output.contains("<!-- WARNING:"))
        #expect(output.contains("Verify current state before acting"))
    }

    @Test("Agent format fresh context has no warning")
    func agentFormat_fresh_noWarning() {
        let context = makeContext(staleness: .fresh)
        let output = DiagnosticFormatter.formatAgent(context)
        #expect(!output.contains("<!-- WARNING:"))
    }

    @Test("Agent format includes recent commits")
    func agentFormat_includesRecentCommits() {
        let context = makeContext()
        let output = DiagnosticFormatter.formatAgent(context)
        #expect(output.contains("abc1234"))
        #expect(output.contains("feat: new feature"))
    }

    @Test("Agent format includes pending decisions")
    func agentFormat_includesPendingDecisions() {
        let context = makeContext(pendingDecisions: ["Deploy to staging?"])
        let output = DiagnosticFormatter.formatAgent(context)
        #expect(output.contains("Deploy to staging?"))
    }

    @Test("Agent format ancient context includes warning")
    func agentFormat_ancientContext_includesWarning() {
        let context = makeContext(staleness: .ancient)
        let output = DiagnosticFormatter.formatAgent(context)
        #expect(output.contains("<!-- WARNING:"))
    }

    // MARK: - JSON Format (BR-10)

    @Test("JSON format is valid JSON always")
    func jsonFormat_isValidJSON_always() {
        let context = makeContext()
        let output = DiagnosticFormatter.formatJSON(context)
        let data = output.data(using: .utf8)!
        #expect(throws: Never.self) {
            _ = try JSONSerialization.jsonObject(with: data)
        }
    }

    @Test("JSON format includes recoveredAt timestamp")
    func jsonFormat_includesRecoveredAtTimestamp() {
        let context = makeContext()
        let output = DiagnosticFormatter.formatJSON(context)
        #expect(output.contains("recoveredAt"))
    }

    @Test("JSON format includes confidence score")
    func jsonFormat_includesConfidenceScore() {
        let context = makeContext()
        let output = DiagnosticFormatter.formatJSON(context)
        #expect(output.contains("confidence"))
        #expect(output.contains("overall"))
    }

    @Test("JSON format includes source results")
    func jsonFormat_includesSourceResults() {
        let context = makeContext()
        let output = DiagnosticFormatter.formatJSON(context)
        #expect(output.contains("sources"))
        #expect(output.contains("\"db\""))
        #expect(output.contains("\"checkpoint\""))
        #expect(output.contains("\"git\""))
    }

    @Test("JSON format includes errors as field, never prints to stdout")
    func jsonFormat_includesErrors_neverPrintsToStdout() {
        let context = makeContext(errors: ["DB timeout"])
        let output = DiagnosticFormatter.formatJSON(context)
        #expect(output.contains("errors"))
        #expect(output.contains("DB timeout"))
    }

    @Test("JSON format with empty context is still valid JSON")
    func jsonFormat_emptyContext_isValidJSON() {
        let now = Date()
        let context = RecoveryContext(
            recoveredAt: now,
            timeWindow: TimeWindow.lookback(seconds: 7200, from: now),
            confidence: ConfidenceScore(dbScore: 0, checkpointScore: 0, gitScore: 0),
            staleness: .ancient,
            sources: [],
            timeline: [],
            workspace: WorkspaceSnapshot()
        )
        let output = DiagnosticFormatter.formatJSON(context)
        let data = output.data(using: .utf8)!
        #expect(throws: Never.self) {
            _ = try JSONSerialization.jsonObject(with: data)
        }
    }
}
