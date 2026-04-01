import Foundation
import Testing
@testable import ShikkiKit

@Suite("SetupState persistence and queries")
struct SetupStateTests {

    /// Create a temp path for each test to avoid collisions.
    private func tempPath() -> String {
        NSTemporaryDirectory() + "shikki-test-setup-\(UUID().uuidString).json"
    }

    @Test("Save and load round-trips correctly")
    func saveAndLoad() throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        var state = SetupState(version: "0.3.0-pre")
        state.markStep("dependencies")
        state.markStep("build")
        try state.save(to: path)

        let loaded = SetupState.load(from: path)
        #expect(loaded != nil)
        #expect(loaded?.version == "0.3.0-pre")
        #expect(loaded?.isStepComplete("dependencies") == true)
        #expect(loaded?.isStepComplete("build") == true)
        #expect(loaded?.isStepComplete("symlink") == false)
    }

    @Test("Load returns nil for missing file")
    func loadMissingFile() {
        let path = "/tmp/nonexistent-\(UUID().uuidString).json"
        let state = SetupState.load(from: path)
        #expect(state == nil)
    }

    @Test("Version mismatch means setup needed")
    func versionMismatch() throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        try SetupState.markComplete(version: "0.2.0", path: path)
        #expect(SetupState.isComplete(currentVersion: "0.2.0", path: path) == true)
        #expect(SetupState.isComplete(currentVersion: "0.3.0-pre", path: path) == false)
        #expect(SetupState.needsSetup(currentVersion: "0.3.0-pre", path: path) == true)
    }

    @Test("markComplete fills all steps")
    func markComplete() throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        try SetupState.markComplete(version: "1.0.0", path: path)
        let loaded = SetupState.load(from: path)!
        #expect(loaded.version == "1.0.0")
        #expect(loaded.allStepsComplete == true)
        for step in SetupState.allSteps {
            #expect(loaded.isStepComplete(step) == true)
        }
    }

    @Test("Individual step tracking")
    func stepTracking() {
        var state = SetupState(version: "0.3.0-pre")
        #expect(state.isStepComplete("dependencies") == false)
        #expect(state.allStepsComplete == false)

        state.markStep("dependencies")
        #expect(state.isStepComplete("dependencies") == true)
        #expect(state.allStepsComplete == false)
    }

    @Test("allStepsComplete requires every known step")
    func allStepsComplete() {
        var state = SetupState(version: "0.3.0-pre")
        for step in SetupState.allSteps {
            #expect(state.allStepsComplete == false)
            state.markStep(step)
        }
        #expect(state.allStepsComplete == true)
    }

    @Test("needsSetup returns true for missing state file")
    func needsSetupMissing() {
        let path = "/tmp/nonexistent-\(UUID().uuidString).json"
        #expect(SetupState.needsSetup(currentVersion: "0.3.0", path: path) == true)
    }

    @Test("isComplete returns true for matching version")
    func isCompleteMatching() throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        try SetupState.markComplete(version: "0.3.0-pre", path: path)
        #expect(SetupState.isComplete(currentVersion: "0.3.0-pre", path: path) == true)
    }

    @Test("allSteps contains expected entries")
    func allStepsContents() {
        let steps = SetupState.allSteps
        #expect(steps.contains("dependencies"))
        #expect(steps.contains("build"))
        #expect(steps.contains("symlink"))
        #expect(steps.contains("workspace"))
        #expect(steps.contains("backend"))
        #expect(steps.contains("completions"))
        #expect(steps.count == 6)
    }

    @Test("Codable encoding preserves date with ISO8601")
    func codableDate() throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let now = Date()
        let state = SetupState(version: "1.0.0", completedAt: now)
        try state.save(to: path)

        // Read raw JSON and verify ISO8601 format
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let json = String(data: data, encoding: .utf8)!
        #expect(json.contains("completedAt"))
        // ISO8601 dates contain "T" separator
        #expect(json.contains("T"))
    }
}
