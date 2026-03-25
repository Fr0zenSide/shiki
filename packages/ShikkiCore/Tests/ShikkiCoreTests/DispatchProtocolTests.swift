import Testing
import Foundation
@testable import ShikkiCore

@Suite("Dispatch Protocol — S1a")
struct DispatchProtocolTests {

    // MARK: - DispatchRequest

    @Test("DispatchRequest Codable round-trip preserves all fields")
    func requestRoundTrip() throws {
        let scope = TestScope(packagePath: "projects/Maya", filterPattern: "AnimationTests", expectedNewTests: 23)
        let request = DispatchRequest(
            agentId: "agent-maya-1",
            project: "projects/Maya/",
            branch: "epic/maya-animations",
            baseBranch: "develop",
            specPath: "features/maya-animations-v1.md",
            testScope: scope,
            successCriteria: ["swift build — zero errors", "23/23 green"]
        )

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(DispatchRequest.self, from: data)

        #expect(decoded.agentId == "agent-maya-1")
        #expect(decoded.project == "projects/Maya/")
        #expect(decoded.branch == "epic/maya-animations")
        #expect(decoded.baseBranch == "develop")
        #expect(decoded.specPath == "features/maya-animations-v1.md")
        #expect(decoded.testScope?.packagePath == "projects/Maya")
        #expect(decoded.testScope?.expectedNewTests == 23)
        #expect(decoded.successCriteria.count == 2)
    }

    @Test("DispatchRequest ID is deterministic from agentId + branch")
    func requestId() {
        let request = DispatchRequest(
            agentId: "agent-1",
            project: "p/",
            branch: "feat/x",
            baseBranch: "develop",
            specPath: "spec.md"
        )
        #expect(request.id == "agent-1-feat/x")
    }

    // MARK: - DispatchEvent

    @Test("DispatchEvent Codable round-trip preserves all fields")
    func eventRoundTrip() throws {
        let event = DispatchEvent(
            agentId: "agent-maya-1",
            type: .testPassed,
            timestamp: Date(timeIntervalSince1970: 1_000_000),
            data: ["testCount": "23", "passCount": "23"]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        let data = try encoder.encode(event)
        let decoded = try decoder.decode(DispatchEvent.self, from: data)

        #expect(decoded.agentId == "agent-maya-1")
        #expect(decoded.type == .testPassed)
        #expect(decoded.timestamp == Date(timeIntervalSince1970: 1_000_000))
        #expect(decoded.data["testCount"] == "23")
    }

    @Test("DispatchEventType covers all required orchestrator events")
    func eventTypesComplete() {
        let allTypes = DispatchEventType.allCases
        #expect(allTypes.contains(.taskStarted))
        #expect(allTypes.contains(.waveStarted))
        #expect(allTypes.contains(.testPassed))
        #expect(allTypes.contains(.testFailed))
        #expect(allTypes.contains(.blockerHit))
        #expect(allTypes.contains(.prCreated))
        #expect(allTypes.contains(.taskCompleted))
        #expect(allTypes.count == 7)
    }

    @Test("DispatchEvent default timestamp is near now")
    func eventDefaultTimestamp() {
        let before = Date()
        let event = DispatchEvent(agentId: "a", type: .taskStarted)
        let after = Date()
        #expect(event.timestamp >= before)
        #expect(event.timestamp <= after)
    }
}
