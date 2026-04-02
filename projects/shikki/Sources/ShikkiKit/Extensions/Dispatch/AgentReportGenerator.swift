import Foundation

// MARK: - AgentReportGenerator

/// Builds AgentReportCard from journal entries, decision events, and session metadata.
/// Pure data aggregation — no side effects, no network calls.
public struct AgentReportGenerator: Sendable {

    public init() {}

    /// Build a report card from session data.
    public func generate(
        sessionId: String,
        persona: AgentPersona,
        companySlug: String,
        taskTitle: String,
        startedAt: Date,
        endedAt: Date = Date(),
        decisions: [DecisionEvent] = [],
        checkpoints: [SessionCheckpoint] = [],
        filesChanged: Int = 0,
        testsAdded: Int = 0,
        beforeState: String = "",
        afterState: String = "",
        contextResets: Int = 0,
        questionsAsked: Int = 0,
        blockersHit: Int = 0,
        watchdogTriggers: Int = 0,
        redFlags: [String] = [],
        status: AgentReportStatus = .completed
    ) -> AgentReportCard {
        let duration = endedAt.timeIntervalSince(startedAt)

        let keyDecisions = decisions
            .filter { $0.impact == .architecture || $0.confidence >= 0.8 }
            .map { "\($0.choice) (\($0.rationale.prefix(60)))" }

        let effectiveRedFlags = redFlags + decisions
            .filter { $0.confidence < 0.5 }
            .map { "Low-confidence decision: \($0.question)" }

        return AgentReportCard(
            sessionId: sessionId,
            persona: persona,
            companySlug: companySlug,
            taskTitle: taskTitle,
            duration: duration,
            beforeState: beforeState.isEmpty ? "no prior state" : beforeState,
            afterState: afterState.isEmpty ? "session ended" : afterState,
            filesChanged: filesChanged,
            testsAdded: testsAdded,
            keyDecisions: keyDecisions,
            redFlags: effectiveRedFlags,
            status: status
        )
    }

    /// Build a report from DecisionJournal + SessionJournal data.
    public func generateFromJournals(
        sessionId: String,
        persona: AgentPersona,
        companySlug: String,
        taskTitle: String,
        startedAt: Date,
        decisionJournal: DecisionJournal,
        sessionJournal: SessionJournal,
        status: AgentReportStatus = .completed
    ) async -> AgentReportCard {
        let decisions = (try? await decisionJournal.loadDecisions(sessionId: sessionId)) ?? []
        let checkpoints = (try? await sessionJournal.loadCheckpoints(sessionId: sessionId)) ?? []

        let contextResets = checkpoints.filter {
            $0.metadata?["reapReason"]?.contains("compaction") == true
        }.count

        let blockersHit = decisions.filter { $0.category == .scope }.count

        return generate(
            sessionId: sessionId,
            persona: persona,
            companySlug: companySlug,
            taskTitle: taskTitle,
            startedAt: startedAt,
            decisions: decisions,
            checkpoints: checkpoints,
            contextResets: contextResets,
            blockersHit: blockersHit,
            status: status
        )
    }

    /// Convert an AgentReportCard to a ShikkiEvent for EventBus publishing.
    public func toEvent(_ report: AgentReportCard) -> ShikkiEvent {
        ShikkiEvent(
            source: .agent(id: report.sessionId, name: report.persona.rawValue),
            type: .agentReportGenerated,
            scope: .project(slug: report.companySlug),
            payload: [
                "sessionId": .string(report.sessionId),
                "persona": .string(report.persona.rawValue),
                "taskTitle": .string(report.taskTitle),
                "duration": .double(report.duration),
                "filesChanged": .int(report.filesChanged),
                "testsAdded": .int(report.testsAdded),
                "status": .string("\(report.status)"),
                "keyDecisions": .int(report.keyDecisions.count),
                "redFlags": .int(report.redFlags.count),
            ],
            metadata: EventMetadata(
                duration: report.duration,
                tags: ["agent-report"]
            )
        )
    }
}

// MARK: - AgentReportCard Rendering Extensions

extension AgentReportCard {

    /// Render as a formatted TUI string.
    public func renderTUI(expanded: Bool = true) -> String {
        let reset = "\u{1B}[0m"
        let bold = "\u{1B}[1m"
        let dim = "\u{1B}[2m"
        let statusIcon = renderStatusIcon()
        let durationStr = formatDuration(duration)

        var lines: [String] = []

        // Header
        let expandIcon = expanded ? "\u{25BC}" : "\u{25BA}"
        lines.append("\(expandIcon) \(bold)\(sessionId)\(reset) (\(persona.rawValue)) \u{2014} \(durationStr) \u{2014} \(statusIcon)")

        guard expanded else {
            if status == .running {
                lines.append("  Current: \(taskTitle)")
            }
            if !redFlags.isEmpty {
                lines.append("  \u{1B}[31m\u{25B2} \(redFlags.count) red flag(s)\(reset)")
            }
            return lines.joined(separator: "\n")
        }

        // Before/After
        lines.append("  Before: \(beforeState)")
        lines.append("  After:  \(afterState)")

        // Files + Tests
        if filesChanged > 0 || testsAdded > 0 {
            var metrics: [String] = []
            if filesChanged > 0 { metrics.append("\(filesChanged) files changed") }
            if testsAdded > 0 { metrics.append("\(testsAdded) tests added") }
            lines.append("  \(metrics.joined(separator: " | "))")
        }

        // Key Decisions
        if !keyDecisions.isEmpty {
            lines.append("  \(bold)Key Decisions:\(reset)")
            for decision in keyDecisions.prefix(5) {
                lines.append("    \u{25C6} \(decision)")
            }
        }

        // Red Flags
        if !redFlags.isEmpty {
            lines.append("  \u{1B}[31m\(bold)Red Flags:\(reset)")
            for flag in redFlags {
                lines.append("    \u{1B}[31m\u{25B2} \(flag)\(reset)")
            }
        }

        // Health
        lines.append("  \(dim)Status: \(status)\(reset)")

        return lines.joined(separator: "\n")
    }

    /// Render as markdown for file persistence.
    public func renderMarkdown() -> String {
        let durationStr = formatDuration(duration)
        var md = """
        # Agent Report: \(sessionId)

        | Field | Value |
        |-------|-------|
        | Persona | \(persona.rawValue) |
        | Company | \(companySlug) |
        | Task | \(taskTitle) |
        | Duration | \(durationStr) |
        | Status | \(status) |

        ## State Change
        - **Before**: \(beforeState)
        - **After**: \(afterState)

        ## Metrics
        - Files changed: \(filesChanged)
        - Tests added: \(testsAdded)

        """

        if !keyDecisions.isEmpty {
            md += "## Key Decisions\n"
            for decision in keyDecisions {
                md += "- \(decision)\n"
            }
            md += "\n"
        }

        if !redFlags.isEmpty {
            md += "## Red Flags\n"
            for flag in redFlags {
                md += "- \u{26A0}\u{FE0F} \(flag)\n"
            }
            md += "\n"
        }

        return md
    }

    // MARK: - Private Helpers

    private func renderStatusIcon() -> String {
        switch status {
        case .running: "\u{1B}[36mRUNNING\u{1B}[0m"
        case .blocked: "\u{1B}[33mBLOCKED\u{1B}[0m"
        case .completed: "\u{1B}[32mDONE\u{1B}[0m"
        case .failed: "\u{1B}[31mFAILED\u{1B}[0m"
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
