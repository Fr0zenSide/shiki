import Foundation
import Testing
@testable import ShikkiKit

@Suite("ShikkiEvent model")
struct ShikkiEventTests {

    @Test("Event has unique ID and timestamp")
    func eventHasIdAndTimestamp() {
        let event = ShikkiEvent(
            source: .orchestrator,
            type: .heartbeat,
            scope: .global
        )
        let event2 = ShikkiEvent(
            source: .orchestrator,
            type: .heartbeat,
            scope: .global
        )
        #expect(event.id != event2.id)
    }

    @Test("Event is Codable round-trip")
    func eventCodable() throws {
        let event = ShikkiEvent(
            source: .agent(id: "sess-1", name: "fix-agent"),
            type: .codeChange,
            scope: .pr(number: 5),
            payload: ["file": .string("ProcessCleanup.swift"), "insertions": .int(12)],
            metadata: EventMetadata(branch: "feature/wave2", commitHash: "abc123")
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(event)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ShikkiEvent.self, from: data)

        #expect(decoded.id == event.id)
        #expect(decoded.type == .codeChange)
        #expect(decoded.payload["file"] == .string("ProcessCleanup.swift"))
        #expect(decoded.payload["insertions"] == .int(12))
        #expect(decoded.metadata?.branch == "feature/wave2")
    }

    @Test("EventSource variants encode correctly")
    func eventSourceVariants() throws {
        let sources: [EventSource] = [
            .agent(id: "s1", name: "claude"),
            .human(id: "jeoffrey"),
            .orchestrator,
            .process(name: "shiki-pr"),
            .system,
        ]
        let encoder = JSONEncoder()
        for source in sources {
            let data = try encoder.encode(source)
            let decoded = try JSONDecoder().decode(EventSource.self, from: data)
            #expect(decoded == source)
        }
    }

    @Test("EventScope variants encode correctly")
    func eventScopeVariants() throws {
        let scopes: [EventScope] = [
            .global,
            .session(id: "sess-1"),
            .project(slug: "maya"),
            .pr(number: 6),
            .file(path: "Sources/Foo.swift"),
        ]
        let encoder = JSONEncoder()
        for scope in scopes {
            let data = try encoder.encode(scope)
            let decoded = try JSONDecoder().decode(EventScope.self, from: data)
            #expect(decoded == scope)
        }
    }
}

@Suite("InProcessEventBus pub/sub")
struct InProcessEventBusTests {

    @Test("Publish delivers to subscriber")
    func publishDelivers() async throws {
        let bus = InProcessEventBus()
        let stream = await bus.subscribe(filter: .all)
        let event = ShikkiEvent(source: .orchestrator, type: .heartbeat, scope: .global)

        await bus.publish(event)

        var received: ShikkiEvent?
        for await e in stream {
            received = e
            break
        }
        #expect(received?.id == event.id)
    }

    @Test("Filter by event type")
    func filterByType() async throws {
        let bus = InProcessEventBus()
        let filter = EventFilter(types: [.heartbeat])
        let stream = await bus.subscribe(filter: filter)

        // Publish non-matching event
        await bus.publish(ShikkiEvent(source: .orchestrator, type: .sessionStart, scope: .global))
        // Publish matching event
        let matching = ShikkiEvent(source: .orchestrator, type: .heartbeat, scope: .global)
        await bus.publish(matching)

        var received: ShikkiEvent?
        for await e in stream {
            received = e
            break
        }
        #expect(received?.type == .heartbeat)
    }

    @Test("Filter by scope")
    func filterByScope() async throws {
        let bus = InProcessEventBus()
        let filter = EventFilter(scopes: [.pr(number: 6)])
        let stream = await bus.subscribe(filter: filter)

        // Non-matching scope
        await bus.publish(ShikkiEvent(source: .system, type: .codeChange, scope: .pr(number: 5)))
        // Matching scope
        let matching = ShikkiEvent(source: .system, type: .codeChange, scope: .pr(number: 6))
        await bus.publish(matching)

        var received: ShikkiEvent?
        for await e in stream {
            received = e
            break
        }
        #expect(received?.id == matching.id)
    }

    @Test("Multiple subscribers each get the event")
    func multipleSubscribers() async throws {
        let bus = InProcessEventBus()
        let stream1 = await bus.subscribe(filter: .all)
        let stream2 = await bus.subscribe(filter: .all)

        let event = ShikkiEvent(source: .orchestrator, type: .heartbeat, scope: .global)
        await bus.publish(event)

        var r1: ShikkiEvent?
        for await e in stream1 { r1 = e; break }
        var r2: ShikkiEvent?
        for await e in stream2 { r2 = e; break }

        #expect(r1?.id == event.id)
        #expect(r2?.id == event.id)
    }

    @Test("Unsubscribe stops delivery")
    func unsubscribe() async throws {
        let bus = InProcessEventBus()
        let (stream, subId) = await bus.subscribeWithId(filter: .all)

        await bus.unsubscribe(subId)

        // Publish after unsubscribe
        await bus.publish(ShikkiEvent(source: .system, type: .heartbeat, scope: .global))

        // Stream should be finished
        var count = 0
        for await _ in stream {
            count += 1
        }
        #expect(count == 0)
    }

    @Test("Filter matches all when no constraints")
    func filterAllMatches() {
        let filter = EventFilter.all
        let event = ShikkiEvent(source: .agent(id: "x", name: nil), type: .codeChange, scope: .pr(number: 1))
        #expect(filter.matches(event))
    }

    @Test("Filter rejects non-matching type")
    func filterRejectsType() {
        let filter = EventFilter(types: [.heartbeat])
        let event = ShikkiEvent(source: .orchestrator, type: .codeChange, scope: .global)
        #expect(!filter.matches(event))
    }
}
