import Foundation
import Testing
@testable import ShikkiKit

@Suite("NATSEventRenderer")
struct NATSEventRendererTests {

    // MARK: - Helpers

    private func makeEvent(
        type: EventType = .heartbeat,
        scope: EventScope = .project(slug: "maya"),
        payload: [String: EventValue] = [:],
        metadata: EventMetadata? = nil
    ) -> ShikkiEvent {
        ShikkiEvent(source: .orchestrator, type: type, scope: scope, payload: payload, metadata: metadata)
    }

    // MARK: - Compact Format

    @Test("Compact format renders one-line ANSI output")
    func compactFormatRendersOneLine() {
        let renderer = NATSEventRenderer(format: .compact, minLevel: .noise)
        let event = makeEvent(type: .companyDispatched, payload: ["title": .string("fix-auth")])

        let line = renderer.render(event)
        #expect(!line.isEmpty)
        #expect(line.contains("maya"))
        #expect(line.contains("dispatch"))
        #expect(!line.contains("\n"))  // Single line
    }

    @Test("Compact format adds red prefix for critical events")
    func compactCriticalPrefix() {
        let renderer = NATSEventRenderer(format: .compact, minLevel: .noise)
        let event = makeEvent(type: .redFlag, payload: ["message": .string("data loss detected")])

        let line = renderer.render(event)
        // Critical events get bold+red `!` prefix
        #expect(line.contains("\(ANSI.bold)\(ANSI.red)!"))
    }

    @Test("Compact format adds green prefix for milestone events")
    func compactMilestonePrefix() {
        let renderer = NATSEventRenderer(format: .compact, minLevel: .noise)
        let event = makeEvent(type: .shipCompleted)

        let line = renderer.render(event)
        // Milestone events get green `*` prefix
        #expect(line.contains("\(ANSI.green)*"))
    }

    @Test("Compact format dims noise events")
    func compactDimsNoise() {
        let renderer = NATSEventRenderer(format: .compact, minLevel: .noise)
        let event = makeEvent(type: .heartbeat)

        let line = renderer.render(event)
        // Noise events are wrapped in dim
        #expect(line.hasPrefix(ANSI.dim))
    }

    // MARK: - Detail Format

    @Test("Detail format renders multi-line output with payload")
    func detailFormatRendersMultiLine() {
        let renderer = NATSEventRenderer(format: .detail, minLevel: .noise)
        let event = makeEvent(
            type: .companyDispatched,
            payload: ["title": .string("fix-auth"), "priority": .int(1)],
            metadata: EventMetadata(branch: "feature/auth", commitHash: "abc123def456")
        )

        let output = renderer.render(event)
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)

        // Should have multiple lines: header + payload keys + metadata
        #expect(lines.count >= 3)
        #expect(output.contains("maya"))
        #expect(output.contains("title:"))
        #expect(output.contains("fix-auth"))
        #expect(output.contains("branch:"))
        #expect(output.contains("feature/auth"))
        #expect(output.contains("commit:"))
        #expect(output.contains("abc123de"))  // Truncated to 8 chars
    }

    @Test("Detail format shows significance badge")
    func detailFormatShowsBadge() {
        let renderer = NATSEventRenderer(format: .detail, minLevel: .noise)
        let event = makeEvent(type: .budgetExhausted)

        let output = renderer.render(event)
        #expect(output.contains("[ALERT]"))
    }

    // MARK: - JSON Format

    @Test("JSON format outputs valid JSON")
    func jsonFormatOutputsValidJSON() {
        let renderer = NATSEventRenderer(format: .json, minLevel: .noise)
        let event = makeEvent(type: .heartbeat)

        let line = renderer.render(event)
        let data = Data(line.utf8)
        let parsed = try? JSONSerialization.jsonObject(with: data)
        #expect(parsed != nil)
        #expect(line.contains(event.id.uuidString))
    }

    @Test("JSON format ignores significance level filter")
    func jsonFormatIgnoresNothing() {
        // JSON mode should still respect level filtering
        let renderer = NATSEventRenderer(format: .json, minLevel: .milestone)
        let noiseEvent = makeEvent(type: .heartbeat)  // noise level

        let line = renderer.render(noiseEvent)
        #expect(line.isEmpty)

        let milestoneEvent = makeEvent(type: .shipCompleted)
        let msLine = renderer.render(milestoneEvent)
        #expect(!msLine.isEmpty)
    }

    // MARK: - Significance Filtering

    @Test("Events below minimum level produce empty string")
    func filtersBelowMinLevel() {
        let renderer = NATSEventRenderer(format: .compact, minLevel: .milestone)

        let noiseEvent = makeEvent(type: .heartbeat)
        #expect(renderer.render(noiseEvent).isEmpty)

        let bgEvent = makeEvent(type: .codeChange)
        #expect(renderer.render(bgEvent).isEmpty)

        let progressEvent = makeEvent(type: .sessionStart)
        #expect(renderer.render(progressEvent).isEmpty)

        // Milestone should pass
        let milestoneEvent = makeEvent(type: .shipCompleted)
        #expect(!renderer.render(milestoneEvent).isEmpty)
    }

    @Test("Noise minimum level passes everything")
    func noiseMinLevelPassesAll() {
        let renderer = NATSEventRenderer(format: .compact, minLevel: .noise)

        let noiseEvent = makeEvent(type: .heartbeat)
        #expect(!renderer.render(noiseEvent).isEmpty)

        let criticalEvent = makeEvent(type: .redFlag)
        #expect(!renderer.render(criticalEvent).isEmpty)
    }

    // MARK: - Replay Styling

    @Test("Replay renders with dim ANSI prefix")
    func replayRendersWithDim() {
        let renderer = NATSEventRenderer(format: .compact, minLevel: .noise)
        let event = makeEvent(type: .sessionStart)

        let normalLine = renderer.render(event)
        let replayLine = renderer.renderReplay(event)

        #expect(replayLine.hasPrefix(ANSI.dim))
        // Replay line should be longer than normal (dim prefix + reset suffix)
        #expect(replayLine.count > normalLine.count)
    }

    @Test("Replay in JSON mode returns raw JSON without dim styling")
    func replayJSONModeNoDim() {
        let renderer = NATSEventRenderer(format: .json, minLevel: .noise)
        let event = makeEvent(type: .heartbeat)

        let replayLine = renderer.renderReplay(event)
        // JSON replay should NOT have ANSI codes
        #expect(!replayLine.contains(ANSI.dim))
        // Should still be valid JSON
        let data = Data(replayLine.utf8)
        #expect((try? JSONSerialization.jsonObject(with: data)) != nil)
    }

    // MARK: - Company Color Determinism

    @Test("Company colors are deterministic across renders")
    func companyColorDeterminism() {
        let color1 = ANSIEventRenderer.colorForCompany("maya")
        let color2 = ANSIEventRenderer.colorForCompany("maya")
        #expect(color1 == color2)

        // Different companies get different colors
        let shikiColor = ANSIEventRenderer.colorForCompany("shiki")
        #expect(color1 != shikiColor)
    }

    // MARK: - EventSignificance CLI Parsing

    @Test("EventSignificance parses from CLI strings")
    func significanceFromCLIString() {
        #expect(EventSignificance(cliString: "noise") == .noise)
        #expect(EventSignificance(cliString: "NOISE") == .noise)
        #expect(EventSignificance(cliString: "background") == .background)
        #expect(EventSignificance(cliString: "bg") == .background)
        #expect(EventSignificance(cliString: "progress") == .progress)
        #expect(EventSignificance(cliString: "milestone") == .milestone)
        #expect(EventSignificance(cliString: "decision") == .decision)
        #expect(EventSignificance(cliString: "alert") == .alert)
        #expect(EventSignificance(cliString: "critical") == .critical)
        #expect(EventSignificance(cliString: "unknown") == nil)
    }
}
