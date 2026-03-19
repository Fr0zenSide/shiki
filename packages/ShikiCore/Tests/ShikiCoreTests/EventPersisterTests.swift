import Testing
import Foundation
@testable import ShikiCore

@Suite("EventPersister")
struct EventPersisterTests {

    @Test("Persist event builds correct HTTP request")
    func persistBuildsCorrectRequest() async throws {
        let persister = EventPersister(dbURL: "http://localhost:3900")
        let event = CoreEvent.lifecycleStarted(featureId: "feat-1", branch: "feature/test")

        let request = try await persister.buildRequest(for: event)

        #expect(request.url?.absoluteString == "http://localhost:3900/api/data-sync")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.httpBody != nil)
    }

    @Test("DB unavailable logs warning and continues (no crash)")
    func dbUnavailableDoesNotCrash() async throws {
        // Point to an unreachable URL
        let persister = EventPersister(dbURL: "http://127.0.0.1:1")
        let event = CoreEvent.lifecycleStarted(featureId: "feat-1", branch: "test")

        // This must NOT throw — graceful degradation
        await persister.persist(event)
        // If we reach here, the test passes (no crash)
    }
}
