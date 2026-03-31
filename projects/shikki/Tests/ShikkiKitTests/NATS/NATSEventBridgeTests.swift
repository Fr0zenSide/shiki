import Foundation
import Testing
@testable import ShikkiKit

// MARK: - NATSTestPersister

/// Test double for EventPersister that records persisted events.
actor NATSTestPersister: EventPersister {
    private(set) var persistedEvents: [ShikkiEvent] = []
    var shouldThrow: Bool = false

    func persist(_ event: ShikkiEvent) async throws {
        if shouldThrow {
            throw NATSTestPersistError.simulatedFailure
        }
        persistedEvents.append(event)
    }

    func setShouldThrow(_ value: Bool) {
        shouldThrow = value
    }
}

enum NATSTestPersistError: Error {
    case simulatedFailure
}

// MARK: - NATSEventBridge Dual-Sink Tests

@Suite("NATSEventBridge — Dual Sink")
struct NATSEventBridgeDualSinkTests {

    @Test("Emit publishes to both NATS and DB")
    func emitDualSink() async throws {
        let nats = MockNATSClient()
        let persister = NATSTestPersister()
        let bridge = NATSEventBridge(nats: nats, persister: persister)

        try await nats.connect()

        let event = ShikkiEvent(
            source: .orchestrator,
            type: .shipStarted,
            scope: .project(slug: "maya")
        )

        await bridge.emit(event, company: "maya")

        // Verify NATS received the message
        let published = await nats.publishedMessages
        #expect(published.count == 1)
        #expect(published[0].subject == "shikki.events.maya.ship")

        // Verify DB received the event
        let persisted = await persister.persistedEvents
        #expect(persisted.count == 1)
        #expect(persisted[0].id == event.id)
    }

    @Test("Emit count is tracked")
    func emitCountTracked() async throws {
        let nats = MockNATSClient()
        let persister = NATSTestPersister()
        let bridge = NATSEventBridge(nats: nats, persister: persister)

        try await nats.connect()

        let event = ShikkiEvent(
            source: .system,
            type: .heartbeat,
            scope: .global
        )

        await bridge.emit(event, company: "global")
        await bridge.emit(event, company: "global")

        let count = await bridge.emitCount
        #expect(count == 2)
    }

    @Test("Emit without explicit company derives from scope")
    func emitDerivesCompanyFromScope() async throws {
        let nats = MockNATSClient()
        let persister = NATSTestPersister()
        let bridge = NATSEventBridge(nats: nats, persister: persister)

        try await nats.connect()

        let event = ShikkiEvent(
            source: .orchestrator,
            type: .codeGenStarted,
            scope: .project(slug: "wabisabi")
        )

        await bridge.emit(event)

        let published = await nats.publishedMessages
        #expect(published.count == 1)
        #expect(published[0].subject == "shikki.events.wabisabi.codegen")
    }

    @Test("Emit with global scope defaults to 'global' company")
    func emitGlobalScopeDefaults() async throws {
        let nats = MockNATSClient()
        let persister = NATSTestPersister()
        let bridge = NATSEventBridge(nats: nats, persister: persister)

        try await nats.connect()

        let event = ShikkiEvent(
            source: .system,
            type: .heartbeat,
            scope: .global
        )

        await bridge.emit(event)

        let published = await nats.publishedMessages
        #expect(published.count == 1)
        #expect(published[0].subject == "shikki.events.global.heartbeat")
    }
}

// MARK: - NATSEventBridge Failure Isolation Tests

@Suite("NATSEventBridge — Failure Isolation")
struct NATSEventBridgeFailureIsolationTests {

    @Test("NATS failure does not block DB persist")
    func natsFailureDoesNotBlockPersist() async throws {
        let nats = MockNATSClient()
        let persister = NATSTestPersister()
        let bridge = NATSEventBridge(nats: nats, persister: persister)

        // Connect then configure publish to fail
        try await nats.connect()
        await nats.setPublishError(.publishFailed("network down"))

        let event = ShikkiEvent(
            source: .orchestrator,
            type: .shipGatePassed,
            scope: .project(slug: "maya")
        )

        await bridge.emit(event, company: "maya")

        // NATS failed but DB should still have the event
        let persisted = await persister.persistedEvents
        #expect(persisted.count == 1)
        #expect(persisted[0].id == event.id)
    }

    @Test("DB failure does not block NATS publish")
    func persistFailureDoesNotBlockNATS() async throws {
        let nats = MockNATSClient()
        let persister = NATSTestPersister()
        let bridge = NATSEventBridge(nats: nats, persister: persister)

        try await nats.connect()
        await persister.setShouldThrow(true)

        let event = ShikkiEvent(
            source: .agent(id: "a1", name: "builder"),
            type: .codeGenAgentCompleted,
            scope: .project(slug: "shiki")
        )

        await bridge.emit(event, company: "shiki")

        // DB failed but NATS should still have the message
        let published = await nats.publishedMessages
        #expect(published.count == 1)
        #expect(published[0].subject == "shikki.events.shiki.codegen")

        // DB should have nothing
        let persisted = await persister.persistedEvents
        #expect(persisted.isEmpty)
    }

    @Test("Both sinks failing does not crash")
    func bothSinksFailingDoesNotCrash() async throws {
        let nats = MockNATSClient()
        let persister = NATSTestPersister()
        let bridge = NATSEventBridge(nats: nats, persister: persister)

        try await nats.connect()
        await nats.setPublishError(.publishFailed("down"))
        await persister.setShouldThrow(true)

        let event = ShikkiEvent(
            source: .system,
            type: .budgetExhausted,
            scope: .global
        )

        // This should not throw or crash
        await bridge.emit(event, company: "global")

        let count = await bridge.emitCount
        #expect(count == 1)
    }

    @Test("NATS not connected still persists to DB")
    func natsNotConnectedStillPersists() async throws {
        let nats = MockNATSClient()
        let persister = NATSTestPersister()
        let bridge = NATSEventBridge(nats: nats, persister: persister)

        // Don't connect — simulate nats-server not running

        let event = ShikkiEvent(
            source: .orchestrator,
            type: .companyDispatched,
            scope: .project(slug: "maya")
        )

        await bridge.emit(event, company: "maya")

        // DB should still have the event even though NATS was not connected
        let persisted = await persister.persistedEvents
        #expect(persisted.count == 1)
        #expect(persisted[0].id == event.id)
    }
}

// MARK: - NATSEventBridge Subject Routing Tests

@Suite("NATSEventBridge — Subject Routing")
struct NATSEventBridgeRoutingTests {

    @Test("Different event types route to correct NATS subjects")
    func eventTypesRouteCorrectly() async throws {
        let nats = MockNATSClient()
        let persister = NATSTestPersister()
        let bridge = NATSEventBridge(nats: nats, persister: persister)

        try await nats.connect()

        let events: [(EventType, String)] = [
            (.shipStarted, "shikki.events.maya.ship"),
            (.decisionPending, "shikki.events.maya.decision"),
            (.codeChange, "shikki.events.maya.code"),
            (.codeGenStarted, "shikki.events.maya.codegen"),
            (.scheduledTaskFired, "shikki.events.maya.scheduler"),
            (.decisionMade, "shikki.events.maya.decision"),
            (.prCacheBuilt, "shikki.events.maya.pr"),
            (.heartbeat, "shikki.events.maya.heartbeat"),
        ]

        for (eventType, expectedSubject) in events {
            let event = ShikkiEvent(
                source: .orchestrator,
                type: eventType,
                scope: .project(slug: "maya")
            )
            await bridge.emit(event, company: "maya")

            let published = await nats.publishedMessages
            let last = published.last!
            #expect(
                last.subject == expectedSubject,
                "Expected \(eventType) to route to \(expectedSubject), got \(last.subject)"
            )
        }
    }

    @Test("Published NATS data is valid JSON encoding of the event")
    func publishedDataIsValidJSON() async throws {
        let nats = MockNATSClient()
        let persister = NATSTestPersister()
        let bridge = NATSEventBridge(nats: nats, persister: persister)

        try await nats.connect()

        let event = ShikkiEvent(
            source: .orchestrator,
            type: .shipStarted,
            scope: .project(slug: "maya"),
            payload: ["gate": .string("CleanBranch")]
        )

        await bridge.emit(event, company: "maya")

        let published = await nats.publishedMessages
        #expect(published.count == 1)

        // The data should be decodable back to a ShikkiEvent
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ShikkiEvent.self, from: published[0].data)
        #expect(decoded.id == event.id)
        #expect(decoded.type == event.type)
        #expect(decoded.payload["gate"] == .string("CleanBranch"))
    }
}

// MARK: - NATSEventBridge Raw Publish Tests

@Suite("NATSEventBridge — Raw Publish")
struct NATSEventBridgeRawPublishTests {

    @Test("publishRaw sends data to NATS subject")
    func publishRawSendsData() async throws {
        let nats = MockNATSClient()
        let persister = NATSTestPersister()
        let bridge = NATSEventBridge(nats: nats, persister: persister)

        try await nats.connect()

        let heartbeat = Data("{\"node\":\"main\",\"ctx_pct\":42}".utf8)
        await bridge.publishRaw(
            subject: NATSSubjectMapper.discoveryAnnounce,
            data: heartbeat
        )

        let published = await nats.publishedMessages
        #expect(published.count == 1)
        #expect(published[0].subject == "shikki.discovery.announce")
        #expect(published[0].data == heartbeat)
    }

    @Test("publishRaw failure increments natsFailureCount")
    func publishRawFailureTracked() async throws {
        let nats = MockNATSClient()
        let persister = NATSTestPersister()
        let bridge = NATSEventBridge(nats: nats, persister: persister)

        try await nats.connect()
        await nats.setPublishError(.publishFailed("fail"))

        await bridge.publishRaw(subject: "test", data: Data())

        let failCount = await bridge.natsFailureCount
        #expect(failCount == 1)
    }
}
