import Foundation
import Testing
@testable import ShikkiKit

@Suite("SetupService bootstrap logic")
struct SetupServiceTests {

    private func tempStatePath() -> String {
        NSTemporaryDirectory() + "shikki-test-service-\(UUID().uuidString).json"
    }

    @Test("binaryExists detects real binaries")
    func binaryExistsReal() {
        let service = SetupService(currentVersion: "0.3.0-pre")
        #expect(service.binaryExists("swift") == true)
        #expect(service.binaryExists("git") == true)
    }

    @Test("binaryExists returns false for missing binary")
    func binaryExistsMissing() {
        let service = SetupService(currentVersion: "0.3.0-pre")
        #expect(service.binaryExists("nonexistent-xyz-99999") == false)
    }

    @Test("createWorkspaceDirs creates directories")
    func createDirs() throws {
        let tempDir = NSTemporaryDirectory() + "shikki-test-ws-\(UUID().uuidString)"
        // Create the temp dir first so we can cd into it
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let originalDir = FileManager.default.currentDirectoryPath
        FileManager.default.changeCurrentDirectoryPath(tempDir)
        defer { FileManager.default.changeCurrentDirectoryPath(originalDir) }

        let service = SetupService(currentVersion: "0.3.0-pre")
        let created = service.createWorkspaceDirs()
        #expect(created == true)

        // Verify directories exist
        for dir in SetupService.workspaceDirs {
            let path = tempDir + "/" + dir
            var isDir: ObjCBool = false
            #expect(FileManager.default.fileExists(atPath: path, isDirectory: &isDir) == true)
            #expect(isDir.boolValue == true)
        }
    }

    @Test("Bootstrap skips all steps when state is complete")
    func bootstrapSkipsCompleted() async throws {
        let path = tempStatePath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        try SetupState.markComplete(version: "0.3.0-pre", path: path)

        let service = SetupService(currentVersion: "0.3.0-pre", statePath: path)
        let result = await service.bootstrap()
        #expect(result == true)
    }

    @Test("Required brew packages list has tmux")
    func requiredPackages() {
        let required = SetupService.requiredBrewPackages
        #expect(required.contains(where: { $0.binary == "tmux" }))
    }

    @Test("Optional brew packages has expected tools")
    func optionalPackages() {
        let optional = SetupService.optionalBrewPackages
        #expect(optional.contains(where: { $0.binary == "delta" && $0.formula == "git-delta" }))
        #expect(optional.contains(where: { $0.binary == "fzf" && $0.formula == "fzf" }))
        #expect(optional.contains(where: { $0.binary == "rg" && $0.formula == "ripgrep" }))
        #expect(optional.contains(where: { $0.binary == "bat" && $0.formula == "bat" }))
    }

    @Test("Workspace dirs list is correct")
    func workspaceDirsList() {
        let dirs = SetupService.workspaceDirs
        #expect(dirs.contains(".shikki"))
        #expect(dirs.contains(".shikki/test-logs"))
        #expect(dirs.contains(".shikki/plugins"))
        #expect(dirs.contains(".shikki/sessions"))
        #expect(dirs.count == 4)
    }
}
