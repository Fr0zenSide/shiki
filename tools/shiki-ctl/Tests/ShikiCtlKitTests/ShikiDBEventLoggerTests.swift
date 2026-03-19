import Foundation
import Testing
@testable import ShikiCtlKit

// MARK: - Mock Persister

final class MockEventPersister: EventPersister, @unchecked Sendable {
    var persistedEvents: [ShikiEvent] = []
    var shouldFail = false

    func persist(_ event: ShikiEvent) async throws {
        if shouldFail { throw MockPersisterError.failed }
        persistedEvents.append(event)
    }

    enum MockPersisterError: Error { case failed }
}

// MARK: - Tests

@Suite("ShikiDBEventLogger")
struct ShikiDBEventLoggerTests {

    @Test("Logger persists events from bus")
    func loggerPersistsEvents() async throws {
        let bus = InProcessEventBus()
        let persister = MockEventPersister()
        let logger = ShikiDBEventLogger(persister: persister)

        await logger.start(bus: bus)

        let event = ShikiEvent(source: .orchestrator, type: .heartbeat, scope: .global)
        await bus.publish(event)

        // Give the async pipeline time to process
        try await Task.sleep(for: .milliseconds(50))

        #expect(persister.persistedEvents.count == 1)
        #expect(persister.persistedEvents[0].id == event.id)

        await logger.stop()
    }

    @Test("Logger continues on persistence failure (best-effort)")
    func loggerContinuesOnFailure() async throws {
        let bus = InProcessEventBus()
        let persister = MockEventPersister()
        persister.shouldFail = true
        let logger = ShikiDBEventLogger(persister: persister)

        await logger.start(bus: bus)

        // Publish event that will fail to persist
        await bus.publish(ShikiEvent(source: .system, type: .heartbeat, scope: .global))
        try await Task.sleep(for: .milliseconds(50))

        // Should not crash, events just don't persist
        #expect(persister.persistedEvents.isEmpty)

        // Now succeed
        persister.shouldFail = false
        let event2 = ShikiEvent(source: .system, type: .sessionStart, scope: .global)
        await bus.publish(event2)
        try await Task.sleep(for: .milliseconds(50))

        #expect(persister.persistedEvents.count == 1)
        #expect(persister.persistedEvents[0].id == event2.id)

        await logger.stop()
    }

    @Test("Stop cancels the logger task")
    func stopCancelsTask() async throws {
        let bus = InProcessEventBus()
        let persister = MockEventPersister()
        let logger = ShikiDBEventLogger(persister: persister)

        await logger.start(bus: bus)

        // Publish one event to confirm it works
        await bus.publish(ShikiEvent(source: .system, type: .heartbeat, scope: .global))
        try await Task.sleep(for: .milliseconds(50))
        let countBefore = persister.persistedEvents.count

        await logger.stop()
        try await Task.sleep(for: .milliseconds(50))

        // Publish after stop — count should not increase
        await bus.publish(ShikiEvent(source: .system, type: .sessionStart, scope: .global))
        try await Task.sleep(for: .milliseconds(50))

        #expect(persister.persistedEvents.count == countBefore)
    }
}
