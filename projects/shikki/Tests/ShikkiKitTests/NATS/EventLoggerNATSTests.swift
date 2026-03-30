import Foundation
import Testing
@testable import ShikkiKit

// MARK: - Thread-safe line collector

private final class LineCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var _lines: [String] = []

    var lines: [String] {
        lock.withLock { _lines }
    }

    func append(_ line: String) {
        lock.withLock { _lines.append(line) }
    }
}

@Suite("EventLoggerNATS")
struct EventLoggerNATSTests {

    // MARK: - Helpers

    private func makeEvent(
        type: EventType = .heartbeat,
        scope: EventScope = .project(slug: "maya"),
        payload: [String: EventValue] = [:]
    ) -> ShikkiEvent {
        ShikkiEvent(source: .orchestrator, type: type, scope: scope, payload: payload)
    }

    private func encodeEvent(_ event: ShikkiEvent) -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try! encoder.encode(event)
    }

    // MARK: - Subscription Tests

    @Test("Logger subscribes to NATS and receives events")
    func loggerSubscribesAndReceives() async throws {
        let mock = MockNATSClient()
        let renderer = NATSEventRenderer(format: .compact, minLevel: .noise)
        let logger = EventLoggerNATS(nats: mock, renderer: renderer)

        let collector = LineCollector()
        await logger.setLineCallback { line in collector.append(line) }

        try await logger.start(filter: nil)

        // Give subscription time to register
        try await Task.sleep(for: .milliseconds(50))

        // Publish an event through the mock
        let event = makeEvent(type: .companyDispatched, payload: ["title": .string("fix-auth")])
        let data = encodeEvent(event)
        try await mock.publish(subject: "shikki.events.maya.orchestration", data: data)

        try await Task.sleep(for: .milliseconds(100))

        #expect(await logger.count >= 1)
        #expect(!collector.lines.isEmpty)
        #expect(collector.lines.first?.contains("maya") == true)

        await logger.stop()
    }

    @Test("Logger filters by company when filter is provided")
    func loggerFiltersByCompany() async throws {
        let mock = MockNATSClient()
        let renderer = NATSEventRenderer(format: .compact, minLevel: .noise)
        let logger = EventLoggerNATS(nats: mock, renderer: renderer)

        let collector = LineCollector()
        await logger.setLineCallback { line in collector.append(line) }

        // Subscribe to maya only
        try await logger.start(filter: "maya")

        try await Task.sleep(for: .milliseconds(50))

        // Verify the mock received the correct subscription subject
        let subs = await mock.subscribedSubjects
        #expect(subs.contains("shikki.events.maya.>"))

        await logger.stop()
    }

    @Test("Logger deserializes NATSMessage data into ShikkiEvent")
    func loggerDeserializesEvents() async throws {
        let event = makeEvent(type: .shipCompleted, scope: .project(slug: "shiki"))
        let data = encodeEvent(event)
        let message = NATSMessage(subject: "shikki.events.shiki.ship", data: data)

        let decoded = NATSEventTransport.decodeEvent(from: message)
        #expect(decoded != nil)
        #expect(decoded?.type == .shipCompleted)
        #expect(decoded?.id == event.id)
    }

    @Test("Logger ignores malformed messages without crashing")
    func loggerIgnoresMalformedMessages() async throws {
        let garbage = NATSMessage(subject: "shikki.events.maya.lifecycle", data: Data("not json".utf8))
        let decoded = NATSEventTransport.decodeEvent(from: garbage)
        #expect(decoded == nil)
    }

    @Test("Logger replay renders events with dim styling")
    func loggerReplayRendersWithDimStyling() async throws {
        let mock = MockNATSClient()
        let renderer = NATSEventRenderer(format: .compact, minLevel: .noise)
        let logger = EventLoggerNATS(nats: mock, renderer: renderer)

        let events = [
            makeEvent(type: .sessionStart, scope: .project(slug: "maya")),
            makeEvent(type: .companyDispatched, scope: .project(slug: "shiki"), payload: ["title": .string("test")]),
        ]

        let replayLines = await logger.renderReplay(events: events)
        #expect(replayLines.count == 2)

        // Replay lines should start with dim ANSI code
        for line in replayLines {
            #expect(line.hasPrefix(ANSI.dim))
        }
    }

    @Test("Logger stop cancels the subscription task")
    func loggerStopCancelsTask() async throws {
        let mock = MockNATSClient()
        let logger = EventLoggerNATS(nats: mock)

        try await logger.start()
        #expect(await logger.isRunning)

        await logger.stop()
        // After stop, the mock should be disconnected
        #expect(await mock.isConnected == false)
    }

    @Test("Logger connects automatically if not already connected")
    func loggerAutoConnects() async throws {
        let mock = MockNATSClient()
        #expect(await mock.isConnected == false)

        let logger = EventLoggerNATS(nats: mock)
        try await logger.start()

        #expect(await mock.isConnected == true)

        await logger.stop()
    }
}

// MARK: - Helper extension for tests

extension EventLoggerNATS {
    func setLineCallback(_ callback: @escaping @Sendable (String) -> Void) {
        self.onLine = callback
    }
}
