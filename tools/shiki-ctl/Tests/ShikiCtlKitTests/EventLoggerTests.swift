import Testing
import Foundation
@testable import ShikiCtlKit

@Suite("EventLogger")
struct EventLoggerTests {

    // MARK: - Event Parsing

    @Test("Parse ShikiEvent from valid JSON via WebSocketEventTransport")
    func parseEventFromJSON() {
        let event = ShikiEvent(
            source: .orchestrator,
            type: .companyDispatched,
            scope: .project(slug: "maya"),
            payload: ["title": .string("fix-auth")]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try! encoder.encode(event)

        // Parse with no filter (accept all)
        let parsed = WebSocketEventTransport.parseEvent(from: data, channel: "")
        #expect(parsed != nil)
        #expect(parsed?.type == .companyDispatched)
        #expect(parsed?.payload["title"]?.stringValue == "fix-auth")
    }

    @Test("Parse event filters by company slug")
    func parseEventFiltersByCompany() {
        let event = ShikiEvent(
            source: .orchestrator,
            type: .companyDispatched,
            scope: .project(slug: "maya"),
            payload: [:]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try! encoder.encode(event)

        // Should pass maya filter
        let passed = WebSocketEventTransport.parseEvent(from: data, channel: "maya")
        #expect(passed != nil)

        // Should fail wabisabi filter
        let filtered = WebSocketEventTransport.parseEvent(from: data, channel: "wabisabi")
        #expect(filtered == nil)
    }

    @Test("Parse rejects malformed JSON gracefully")
    func parseMalformedJSON() {
        let garbage = Data("not json at all".utf8)
        let result = WebSocketEventTransport.parseEvent(from: garbage, channel: "")
        #expect(result == nil)
    }

    // MARK: - ANSI Rendering

    @Test("ANSIEventRenderer formats event with timestamp, uuid8, company, type, summary")
    func ansiRendererFormatsEvent() {
        let event = ShikiEvent(
            source: .orchestrator,
            type: .companyDispatched,
            scope: .project(slug: "maya"),
            payload: ["title": .string("fix-auth")]
        )

        let renderer = ANSIEventRenderer()
        let line = renderer.render(event)

        // Should contain the first 8 chars of the UUID
        let uuid8 = String(event.id.uuidString.prefix(8)).lowercased()
        #expect(line.contains(uuid8))

        // Should contain company name
        #expect(line.contains("maya"))

        // Should contain event type label
        #expect(line.contains("dispatch"))

        // Should contain payload summary
        #expect(line.contains("fix-auth"))
    }

    @Test("ANSIEventRenderer assigns deterministic colors per company")
    func companyColorDeterminism() {
        let color1 = ANSIEventRenderer.colorForCompany("maya")
        let color2 = ANSIEventRenderer.colorForCompany("maya")
        #expect(color1 == color2)

        // Named companies have distinct colors
        let mayaColor = ANSIEventRenderer.colorForCompany("maya")
        let shikiColor = ANSIEventRenderer.colorForCompany("shiki")
        #expect(mayaColor != shikiColor)
    }

    @Test("ANSIEventRenderer highlights PASSED/FAILED keywords")
    func keywordHighlighting() {
        let renderer = ANSIEventRenderer()

        let passEvent = ShikiEvent(
            source: .system,
            type: .shipGatePassed,
            scope: .project(slug: "shiki"),
            payload: ["gate": .string("CleanBranch")]
        )
        let passLine = renderer.render(passEvent)
        // Should contain green ANSI around PASSED
        #expect(passLine.contains("\u{1B}[32mPASSED\u{1B}[0m"))

        let failEvent = ShikiEvent(
            source: .system,
            type: .shipGateFailed,
            scope: .project(slug: "shiki"),
            payload: ["gate": .string("TestSuite")]
        )
        let failLine = renderer.render(failEvent)
        // Should contain red ANSI around FAILED
        #expect(failLine.contains("\u{1B}[31mFAILED\u{1B}[0m"))
    }

    // MARK: - JSON Rendering

    @Test("JSONEventRenderer outputs valid JSON")
    func jsonRendererOutputsValidJSON() {
        let event = ShikiEvent(
            source: .orchestrator,
            type: .heartbeat,
            scope: .global
        )

        let renderer = JSONEventRenderer()
        let line = renderer.render(event)

        // Should be valid JSON
        let data = Data(line.utf8)
        let parsed = try? JSONSerialization.jsonObject(with: data)
        #expect(parsed != nil)

        // Should contain the event ID
        #expect(line.contains(event.id.uuidString))
    }

    // MARK: - Backoff

    @Test("Exponential backoff increases delay and caps at max")
    func exponentialBackoff() {
        let d1 = WebSocketEventTransport.backoffDelay(attempt: 1, max: .seconds(30))
        let d2 = WebSocketEventTransport.backoffDelay(attempt: 2, max: .seconds(30))
        let d3 = WebSocketEventTransport.backoffDelay(attempt: 3, max: .seconds(30))
        let d10 = WebSocketEventTransport.backoffDelay(attempt: 10, max: .seconds(30))

        // Should increase
        #expect(d1 < d2)
        #expect(d2 < d3)

        // Should cap at max
        #expect(d10 == .seconds(30))
    }

    // MARK: - MockEventTransport

    @Test("MockEventTransport delivers events to subscribers")
    func mockTransportDeliversEvents() async {
        let transport = MockEventTransport()
        let event = ShikiEvent(
            source: .orchestrator,
            type: .heartbeat,
            scope: .global
        )

        let stream = transport.subscribe(to: "")

        // Emit after a brief delay to let subscription register
        Task {
            try? await Task.sleep(for: .milliseconds(50))
            await transport.emit(event)
            try? await Task.sleep(for: .milliseconds(50))
            await transport.disconnect()
        }

        var received: [ShikiEvent] = []
        for await e in stream {
            received.append(e)
        }

        #expect(received.count == 1)
        #expect(received.first?.type == .heartbeat)
    }

    @Test("MockEventTransport records disconnect")
    func mockTransportRecordsDisconnect() async {
        let transport = MockEventTransport()
        #expect(await transport.disconnectCalled == false)
        await transport.disconnect()
        #expect(await transport.disconnectCalled == true)
    }

    // MARK: - Scope Formatting

    @Test("ANSIEventRenderer formats all scope types")
    func scopeFormatting() {
        let renderer = ANSIEventRenderer()

        #expect(renderer.formatScope(.global) == "global")
        #expect(renderer.formatScope(.project(slug: "maya")) == "maya")
        #expect(renderer.formatScope(.pr(number: 42)) == "PR#42")
        #expect(renderer.formatScope(.session(id: "maya:fix-auth")) == "fix-auth")
        #expect(renderer.formatScope(.file(path: "/src/main.swift")) == "main.swift")
    }

    // MARK: - Type Formatting

    @Test("ANSIEventRenderer formats all event types to short labels")
    func typeFormatting() {
        let renderer = ANSIEventRenderer()

        #expect(renderer.formatType(.sessionStart) == "session")
        #expect(renderer.formatType(.companyDispatched) == "dispatch")
        #expect(renderer.formatType(.heartbeat) == "heartbeat")
        #expect(renderer.formatType(.decisionPending) == "decision")
        #expect(renderer.formatType(.shipGatePassed) == "ship")
        #expect(renderer.formatType(.testRun) == "test")
        #expect(renderer.formatType(.buildResult) == "build")
        #expect(renderer.formatType(.custom("myEvent")) == "myEvent")
    }
}
