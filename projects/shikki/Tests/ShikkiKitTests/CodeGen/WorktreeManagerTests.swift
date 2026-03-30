import Testing
import Foundation
@testable import ShikkiKit

@Suite("WorktreeManager")
struct WorktreeManagerTests {

    // MARK: - Path Generation

    @Test("worktree directory uses project root and unit ID")
    func worktreeDir() {
        let manager = WorktreeManager(projectRoot: "/tmp/project")
        let unit = WorkUnit(id: "unit-1", worktreeBranch: "codegen/feature/unit-1")
        let path = manager.worktreeDir(for: unit)
        #expect(path == "/tmp/project/.worktrees/codegen/unit-1")
    }

    @Test("worktree directory is unique per unit ID")
    func uniquePaths() {
        let manager = WorktreeManager(projectRoot: "/tmp/project")
        let unit1 = WorkUnit(id: "unit-protocols")
        let unit2 = WorkUnit(id: "unit-impl-1")
        #expect(manager.worktreeDir(for: unit1) != manager.worktreeDir(for: unit2))
    }

    // MARK: - Git Runner

    @Test("git runner returns exit code and output")
    func gitRunner() async throws {
        let manager = WorktreeManager(projectRoot: NSTemporaryDirectory())
        let result = try await manager.runGit(["--version"])
        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("git version"))
    }

    @Test("git runner returns non-zero for invalid commands")
    func gitRunnerFail() async throws {
        let manager = WorktreeManager(projectRoot: NSTemporaryDirectory())
        let result = try await manager.runGit(["status", "--nonexistent-flag"])
        #expect(result.exitCode != 0)
    }
}
