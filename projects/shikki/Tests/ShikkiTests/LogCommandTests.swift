import ArgumentParser
import Foundation
import Testing
@testable import ShikkiKit

@Suite("LogCommand Routing")
struct LogCommandTests {

    // MARK: - NATSRenderFormat

    @Test("NATSRenderFormat parses from raw value strings")
    func renderFormatParsing() {
        #expect(NATSRenderFormat(rawValue: "compact") == .compact)
        #expect(NATSRenderFormat(rawValue: "detail") == .detail)
        #expect(NATSRenderFormat(rawValue: "json") == .json)
        #expect(NATSRenderFormat(rawValue: "invalid") == nil)
    }

    // MARK: - EventSignificance CLI parsing

    @Test("Significance level parses from CLI strings (case-insensitive)")
    func levelParsing() {
        #expect(EventSignificance(cliString: "noise") == .noise)
        #expect(EventSignificance(cliString: "MILESTONE") == .milestone)
        #expect(EventSignificance(cliString: "Critical") == .critical)
        #expect(EventSignificance(cliString: "bg") == .background)
        #expect(EventSignificance(cliString: "garbage") == nil)
    }

    // MARK: - Channel to Subject Mapping

    @Test("Filter flag maps to correct NATS subject")
    func filterFlagMapping() {
        // No filter → all events
        #expect(NATSEventTransport.channelToSubject("") == "shikki.events.>")

        // Company filter
        #expect(NATSEventTransport.channelToSubject("maya") == "shikki.events.maya.>")

        // Company + type filter
        #expect(NATSEventTransport.channelToSubject("maya.agent") == "shikki.events.maya.agent")
    }

    // MARK: - NATSEventRenderer Integration

    @Test("JSON flag produces valid JSON output via NATSEventRenderer")
    func jsonFlagProducesJSON() {
        let renderer = NATSEventRenderer(format: .json, minLevel: .noise)
        let event = ShikkiEvent(
            source: .orchestrator,
            type: .heartbeat,
            scope: .global
        )

        let line = renderer.render(event)
        let data = Data(line.utf8)
        #expect((try? JSONSerialization.jsonObject(with: data)) != nil)
    }

    @Test("Level filter skips events below threshold")
    func levelFilterSkipsLowEvents() {
        let renderer = NATSEventRenderer(format: .compact, minLevel: .alert)

        let noiseEvent = ShikkiEvent(source: .system, type: .heartbeat, scope: .global)
        #expect(renderer.render(noiseEvent).isEmpty)

        let alertEvent = ShikkiEvent(source: .system, type: .budgetExhausted, scope: .project(slug: "maya"))
        #expect(!renderer.render(alertEvent).isEmpty)
    }

    @Test("Replay events render with dim styling")
    func replayEventsDim() {
        let renderer = NATSEventRenderer(format: .compact, minLevel: .noise)
        let event = ShikkiEvent(source: .orchestrator, type: .sessionStart, scope: .project(slug: "maya"))

        let replayLine = renderer.renderReplay(event)
        #expect(replayLine.hasPrefix(ANSI.dim))
    }
}
