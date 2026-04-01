import Foundation
import Testing
@testable import ShikkiKit

@Suite("SetupGuard gating logic")
struct SetupGuardTests {

    private func tempPath() -> String {
        NSTemporaryDirectory() + "shikki-test-guard-\(UUID().uuidString).json"
    }

    @Test("Exempt commands bypass guard")
    func exemptCommands() {
        let guard_ = SetupGuard(currentVersion: "0.3.0-pre")
        #expect(guard_.isExempt(command: "setup") == true)
        #expect(guard_.isExempt(command: "doctor") == true)
        #expect(guard_.isExempt(command: "--help") == true)
        #expect(guard_.isExempt(command: "-h") == true)
        #expect(guard_.isExempt(command: "--version") == true)
    }

    @Test("Non-exempt commands are not exempt")
    func nonExemptCommands() {
        let guard_ = SetupGuard(currentVersion: "0.3.0-pre")
        #expect(guard_.isExempt(command: "start") == false)
        #expect(guard_.isExempt(command: "status") == false)
        #expect(guard_.isExempt(command: "init") == false)
        #expect(guard_.isExempt(command: "stop") == false)
    }

    @Test("needsSetup returns true for missing state")
    func needsSetupMissing() {
        let path = "/tmp/nonexistent-\(UUID().uuidString).json"
        let guard_ = SetupGuard(currentVersion: "0.3.0-pre", statePath: path)
        #expect(guard_.needsSetup() == true)
    }

    @Test("needsSetup returns false for complete state")
    func needsSetupComplete() throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        try SetupState.markComplete(version: "0.3.0-pre", path: path)
        let guard_ = SetupGuard(currentVersion: "0.3.0-pre", statePath: path)
        #expect(guard_.needsSetup() == false)
    }

    @Test("needsSetup returns true for version mismatch")
    func needsSetupVersionMismatch() throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        try SetupState.markComplete(version: "0.2.0", path: path)
        let guard_ = SetupGuard(currentVersion: "0.3.0-pre", statePath: path)
        #expect(guard_.needsSetup() == true)
    }

    @Test("check returns true for exempt commands even without setup")
    func checkExemptNoSetup() async {
        let path = "/tmp/nonexistent-\(UUID().uuidString).json"
        let guard_ = SetupGuard(currentVersion: "0.3.0-pre", statePath: path)
        let result = await guard_.check(command: "doctor")
        #expect(result == true)
    }

    @Test("check returns true when setup is already complete")
    func checkAlreadyComplete() async throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        try SetupState.markComplete(version: "0.3.0-pre", path: path)
        let guard_ = SetupGuard(currentVersion: "0.3.0-pre", statePath: path)
        let result = await guard_.check(command: "start")
        #expect(result == true)
    }

    @Test("Exempt commands set is non-empty and contains expected values")
    func exemptCommandsSet() {
        let exempt = SetupGuard.exemptCommands
        #expect(exempt.count == 5)
        #expect(exempt.contains("setup"))
        #expect(exempt.contains("doctor"))
    }
}
