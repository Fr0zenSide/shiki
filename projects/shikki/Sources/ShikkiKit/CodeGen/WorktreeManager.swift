import Foundation

/// Errors that can occur during worktree operations.
public enum WorktreeError: Error, LocalizedError, Sendable {
    case creationFailed(String, String)
    case cleanupFailed(String, String)
    case gitNotAvailable
    case baseBranchNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .creationFailed(let branch, let detail):
            return "Failed to create worktree '\(branch)': \(detail)"
        case .cleanupFailed(let branch, let detail):
            return "Failed to remove worktree '\(branch)': \(detail)"
        case .gitNotAvailable:
            return "Git is not available"
        case .baseBranchNotFound(let branch):
            return "Base branch '\(branch)' not found"
        }
    }
}

/// A created worktree with its path and branch info.
public struct Worktree: Sendable {
    /// Absolute path to the worktree directory.
    public let path: String
    /// Branch name.
    public let branch: String
    /// The WorkUnit ID this worktree belongs to.
    public let unitId: String

    public init(path: String, branch: String, unitId: String) {
        self.path = path
        self.branch = branch
        self.unitId = unitId
    }
}

/// Manages git worktrees for parallel agent dispatch.
///
/// Creates one worktree per ``WorkUnit``, runs SPM setup, and cleans up after merge.
/// Worktrees are created under `<projectRoot>/.worktrees/codegen/`.
public struct WorktreeManager: Sendable {

    private let projectRoot: String

    public init(projectRoot: String) {
        self.projectRoot = projectRoot
    }

    /// Create a worktree for a work unit.
    ///
    /// - Parameters:
    ///   - unit: The work unit needing a worktree.
    ///   - baseBranch: Branch to create from (default: HEAD).
    /// - Returns: The created worktree.
    public func create(for unit: WorkUnit, baseBranch: String = "HEAD") async throws -> Worktree {
        let worktreePath = worktreeDir(for: unit)
        let branch = unit.worktreeBranch

        // Create the worktree directory parent
        let parentDir = (worktreePath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: parentDir,
            withIntermediateDirectories: true
        )

        // git worktree add -b <branch> <path> <base>
        let result = try await runGit([
            "worktree", "add", "-b", branch, worktreePath, baseBranch
        ])

        guard result.exitCode == 0 else {
            throw WorktreeError.creationFailed(branch, result.stderr)
        }

        return Worktree(path: worktreePath, branch: branch, unitId: unit.id)
    }

    /// Create worktrees for all units in a work plan.
    ///
    /// Protocol units (priority 0) are created first since others may depend on them.
    public func createAll(for plan: WorkPlan, baseBranch: String = "HEAD") async throws -> [Worktree] {
        let sorted = plan.units.sorted { $0.priority < $1.priority }
        var worktrees: [Worktree] = []

        for unit in sorted {
            let wt = try await create(for: unit, baseBranch: baseBranch)
            worktrees.append(wt)
        }

        return worktrees
    }

    /// Remove a worktree and its branch.
    public func remove(_ worktree: Worktree) async throws {
        // git worktree remove <path> --force
        let result = try await runGit(["worktree", "remove", worktree.path, "--force"])

        if result.exitCode != 0 {
            // Fallback: try manual cleanup
            try? FileManager.default.removeItem(atPath: worktree.path)
            _ = try await runGit(["worktree", "prune"])
        }

        // Delete the branch
        _ = try await runGit(["branch", "-D", worktree.branch])
    }

    /// Remove all codegen worktrees.
    public func removeAll(_ worktrees: [Worktree]) async {
        for wt in worktrees {
            try? await remove(wt)
        }

        // Prune any stale worktree refs
        _ = try? await runGit(["worktree", "prune"])
    }

    /// List existing codegen worktrees.
    public func listCodegenWorktrees() async throws -> [String] {
        let result = try await runGit(["worktree", "list", "--porcelain"])
        guard result.exitCode == 0 else { return [] }

        let codegenDir = "\(projectRoot)/.worktrees/codegen/"
        return result.stdout
            .components(separatedBy: "\n")
            .filter { $0.hasPrefix("worktree ") }
            .map { String($0.dropFirst("worktree ".count)) }
            .filter { $0.hasPrefix(codegenDir) }
    }

    // MARK: - Paths

    func worktreeDir(for unit: WorkUnit) -> String {
        "\(projectRoot)/.worktrees/codegen/\(unit.id)"
    }

    // MARK: - Git Runner

    struct GitResult: Sendable {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    func runGit(_ arguments: [String]) async throws -> GitResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: projectRoot)
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return GitResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            stderr: String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
    }
}
