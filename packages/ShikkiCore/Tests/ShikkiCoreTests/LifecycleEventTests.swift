import Testing
import Foundation
@testable import ShikkiCore

@Suite("LifecycleEvent")
struct LifecycleEventTests {

    @Test("lifecycleStarted creates correct payload")
    func lifecycleStartedPayload() {
        let event = CoreEvent.lifecycleStarted(featureId: "feat-1", branch: "feature/test")
        #expect(event.type == .lifecycleStarted)
        #expect(event.featureId == "feat-1")
        #expect(event.data["branch"] == "feature/test")
    }

    @Test("stateTransitioned includes from and to")
    func stateTransitionedPayload() {
        let event = CoreEvent.stateTransitioned(
            featureId: "feat-2",
            from: .idle,
            to: .specDrafting
        )
        #expect(event.type == .stateTransitioned)
        #expect(event.featureId == "feat-2")
        #expect(event.data["from"] == "idle")
        #expect(event.data["to"] == "specDrafting")
    }

    @Test("Event payload is Codable round-trip")
    func codableRoundTrip() throws {
        let event = CoreEvent.lifecycleStarted(featureId: "feat-3", branch: "main")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(event)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(LifecycleEventPayload.self, from: data)

        #expect(decoded.type == .lifecycleStarted)
        #expect(decoded.featureId == "feat-3")
        #expect(decoded.data["branch"] == "main")
    }
}
