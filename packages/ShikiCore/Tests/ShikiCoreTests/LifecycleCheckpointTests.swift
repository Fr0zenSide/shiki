import Testing
import Foundation
@testable import ShikiCore

@Suite("LifecycleCheckpoint")
struct LifecycleCheckpointTests {

    @Test("Save and load round-trip preserves all fields")
    func saveLoadRoundTrip() throws {
        let transition = LifecycleTransition(
            from: .idle,
            to: .specDrafting,
            timestamp: Date(timeIntervalSince1970: 1_710_000_000),
            actor: .agent(id: "claude-1"),
            reason: "Feature started"
        )

        let checkpoint = LifecycleCheckpoint(
            featureId: "test-feature-001",
            state: .specDrafting,
            timestamp: Date(timeIntervalSince1970: 1_710_000_000),
            metadata: ["branch": "feature/test", "wave": "1"],
            transitionHistory: [transition]
        )

        let tempPath = NSTemporaryDirectory() + "shikicore-test-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        try checkpoint.save(to: tempPath)
        let loaded = try LifecycleCheckpoint.load(from: tempPath)

        #expect(loaded != nil)
        #expect(loaded?.featureId == "test-feature-001")
        #expect(loaded?.state == .specDrafting)
        #expect(loaded?.metadata["branch"] == "feature/test")
        #expect(loaded?.metadata["wave"] == "1")
        #expect(loaded?.transitionHistory.count == 1)
        #expect(loaded?.transitionHistory.first?.from == .idle)
        #expect(loaded?.transitionHistory.first?.to == .specDrafting)
        #expect(loaded?.transitionHistory.first?.reason == "Feature started")
    }

    @Test("Load from nonexistent path returns nil")
    func loadNonexistentReturnsNil() throws {
        let result = try LifecycleCheckpoint.load(from: "/tmp/nonexistent-\(UUID().uuidString).json")
        #expect(result == nil)
    }

    @Test("Checkpoint captures full transition history")
    func capturesFullHistory() throws {
        let transitions: [LifecycleTransition] = [
            LifecycleTransition(from: .idle, to: .specDrafting, timestamp: Date(), actor: .system, reason: "Start"),
            LifecycleTransition(from: .specDrafting, to: .specPendingApproval, timestamp: Date(), actor: .agent(id: "claude"), reason: "Spec done"),
            LifecycleTransition(from: .specPendingApproval, to: .building, timestamp: Date(), actor: .user(id: "daimyo"), reason: "Approved"),
        ]

        let checkpoint = LifecycleCheckpoint(
            featureId: "multi-transition",
            state: .building,
            timestamp: Date(),
            metadata: [:],
            transitionHistory: transitions
        )

        #expect(checkpoint.transitionHistory.count == 3)
        #expect(checkpoint.transitionHistory[0].from == .idle)
        #expect(checkpoint.transitionHistory[2].to == .building)

        // Verify Codable round-trip
        let data = try JSONEncoder().encode(checkpoint)
        let decoded = try JSONDecoder().decode(LifecycleCheckpoint.self, from: data)
        #expect(decoded.transitionHistory.count == 3)
    }
}
