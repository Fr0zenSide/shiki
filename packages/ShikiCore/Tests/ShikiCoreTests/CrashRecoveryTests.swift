import Testing
import Foundation
@testable import ShikiCore

@Suite("CrashRecovery")
struct CrashRecoveryTests {

    @Test("findRecoverable returns non-done checkpoints")
    func findRecoverableReturnsStale() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shiki-test-checkpoints-\(UUID().uuidString)")
            .path
        try FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        // Create a checkpoint in "building" state (recoverable)
        let building = LifecycleCheckpoint(
            featureId: "feat-building",
            state: .building,
            timestamp: Date(),
            metadata: [:],
            transitionHistory: []
        )
        try building.save(to: "\(tmpDir)/feat-building.json")

        // Create a checkpoint in "done" state (not recoverable)
        let done = LifecycleCheckpoint(
            featureId: "feat-done",
            state: .done,
            timestamp: Date(),
            metadata: [:],
            transitionHistory: []
        )
        try done.save(to: "\(tmpDir)/feat-done.json")

        // Create a checkpoint in "failed" state (not recoverable)
        let failed = LifecycleCheckpoint(
            featureId: "feat-failed",
            state: .failed,
            timestamp: Date(),
            metadata: [:],
            transitionHistory: []
        )
        try failed.save(to: "\(tmpDir)/feat-failed.json")

        let recovery = CrashRecovery(checkpointDir: tmpDir)
        let recoverable = try recovery.findRecoverable()

        #expect(recoverable.count == 1)
        #expect(recoverable[0].featureId == "feat-building")
    }

    @Test("findRecoverable returns empty for nonexistent dir")
    func findRecoverableEmptyForMissingDir() throws {
        let recovery = CrashRecovery(checkpointDir: "/tmp/shiki-nonexistent-\(UUID().uuidString)")
        let recoverable = try recovery.findRecoverable()
        #expect(recoverable.isEmpty)
    }
}
