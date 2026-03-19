import Testing
import Foundation
@testable import ShikiCore

@Suite("Cross-Package Contract Tests")
struct CrossPackageContractTests {

    @Test("LifecycleEventPayload serializes to data-sync compatible JSON")
    func eventPayloadSchema() throws {
        let event = CoreEvent.lifecycleStarted(featureId: "test-feat", branch: "feat/test")
        let encoder = JSONEncoder()
        let data = try encoder.encode(event)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // ShikiMCP data-sync expects: type (string), featureId (string), timestamp (number), data (dict)
        #expect(json["type"] is String)
        #expect(json["featureId"] is String)
        // Default Date encoding is Double (timeIntervalSinceReferenceDate)
        #expect(json["timestamp"] is Double)
        #expect(json["data"] is [String: String])
    }

    @Test("gateEvaluated payload includes gate name and result")
    func gateEvaluatedSchema() throws {
        let event = CoreEvent.gateEvaluated(
            featureId: "test", gate: "TestGate", passed: true, detail: "all green"
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(event)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let eventData = json["data"] as! [String: String]

        #expect(eventData["gate"] == "TestGate")
        #expect(eventData["passed"] == "true")
        #expect(eventData["detail"] == "all green")
    }

    @Test("LifecycleCheckpoint round-trips through JSON without data loss")
    func checkpointRoundTrip() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let checkpoint = LifecycleCheckpoint(
            featureId: "contract-test",
            state: .building,
            timestamp: Date(),
            metadata: ["branch": "feat/x"],
            transitionHistory: [
                LifecycleTransition(
                    from: .idle, to: .specDrafting,
                    timestamp: Date(), actor: .system, reason: "start"
                )
            ]
        )
        let data = try encoder.encode(checkpoint)
        let decoded = try decoder.decode(LifecycleCheckpoint.self, from: data)

        #expect(decoded.featureId == "contract-test")
        #expect(decoded.state == .building)
        #expect(decoded.transitionHistory.count == 1)
        #expect(decoded.metadata["branch"] == "feat/x")
    }

    @Test("LifecycleEventType rawValues are stable strings for DB storage")
    func eventTypeRawValues() {
        // These raw values are stored in the DB — if they change, migrations are needed
        #expect(LifecycleEventType.lifecycleStarted.rawValue == "lifecycleStarted")
        #expect(LifecycleEventType.stateTransitioned.rawValue == "stateTransitioned")
        #expect(LifecycleEventType.gateEvaluated.rawValue == "gateEvaluated")
        #expect(LifecycleEventType.checkpointSaved.rawValue == "checkpointSaved")
    }
}
