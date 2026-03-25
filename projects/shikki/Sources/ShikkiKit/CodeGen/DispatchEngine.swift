import Foundation

/// Errors that can occur during dispatch.
public enum DispatchError: Error, LocalizedError, Sendable {
    case noUnitsToDispatch
    case agentFailed(String, String)
    case allAgentsFailed([String])
    case timeout(String)

    public var errorDescription: String? {
        switch self {
        case .noUnitsToDispatch:
            return "No work units to dispatch"
        case .agentFailed(let unitId, let reason):
            return "Agent for unit '\(unitId)' failed: \(reason)"
        case .allAgentsFailed(let unitIds):
            return "All agents failed: \(unitIds.joined(separator: ", "))"
        case .timeout(let unitId):
            return "Agent for unit '\(unitId)' timed out"
        }
    }
}

/// Status of a dispatched agent.
public enum AgentStatus: String, Sendable, Codable {
    case pending
    case running
    case completed
    case failed
    case timedOut
}

/// Result from a single agent's work.
public struct AgentResult: Sendable {
    /// The work unit that was dispatched.
    public let unitId: String
    /// Final status.
    public let status: AgentStatus
    /// Files created or modified.
    public let filesCreated: [String]
    /// Git commit hash (if the agent committed).
    public let commitHash: String?
    /// Error message if failed.
    public let error: String?
    /// Duration in seconds.
    public let durationSeconds: Int

    public init(
        unitId: String,
        status: AgentStatus,
        filesCreated: [String] = [],
        commitHash: String? = nil,
        error: String? = nil,
        durationSeconds: Int = 0
    ) {
        self.unitId = unitId
        self.status = status
        self.filesCreated = filesCreated
        self.commitHash = commitHash
        self.error = error
        self.durationSeconds = durationSeconds
    }
}

/// Overall dispatch result.
public struct DispatchResult: Sendable {
    /// Results from all agents.
    public let agentResults: [AgentResult]
    /// Total dispatch duration in seconds.
    public let totalDurationSeconds: Int
    /// Strategy that was used.
    public let strategy: DispatchStrategy

    public var successCount: Int {
        agentResults.filter { $0.status == .completed }.count
    }

    public var failureCount: Int {
        agentResults.filter { $0.status == .failed || $0.status == .timedOut }.count
    }

    public var allSucceeded: Bool {
        failureCount == 0
    }

    public init(agentResults: [AgentResult], totalDurationSeconds: Int, strategy: DispatchStrategy) {
        self.agentResults = agentResults
        self.totalDurationSeconds = totalDurationSeconds
        self.strategy = strategy
    }
}

/// Protocol for agent execution — abstracted for testability.
///
/// Implementations:
/// - ``CLIAgentRunner``: runs `claude -p` with generated prompt
/// - Mock implementations for testing
public protocol AgentRunner: Sendable {
    /// Execute an agent with the given prompt in the given directory.
    ///
    /// - Parameters:
    ///   - prompt: The implementation prompt.
    ///   - workingDirectory: Absolute path to the worktree.
    ///   - unitId: Work unit ID for tracking.
    /// - Returns: The agent result.
    func run(prompt: String, workingDirectory: String, unitId: String) async throws -> AgentResult
}

/// Orchestrates parallel dispatch of work units to agents.
///
/// Flow:
/// 1. Create worktrees (via ``WorktreeManager``)
/// 2. Generate prompts (via ``AgentPromptGenerator``)
/// 3. Dispatch agents in parallel (via ``AgentRunner``)
/// 4. Collect results
/// 5. Report progress
public struct DispatchEngine: Sendable {

    private let worktreeManager: WorktreeManager
    private let promptGenerator: AgentPromptGenerator
    private let agentRunner: AgentRunner
    private let projectRoot: String

    public init(
        projectRoot: String,
        agentRunner: AgentRunner
    ) {
        self.projectRoot = projectRoot
        self.worktreeManager = WorktreeManager(projectRoot: projectRoot)
        self.promptGenerator = AgentPromptGenerator()
        self.agentRunner = agentRunner
    }

    /// Dispatch a work plan.
    ///
    /// - Parameters:
    ///   - plan: The work plan from ``WorkUnitPlanner``.
    ///   - layer: The protocol layer (contracts).
    ///   - cache: Optional architecture cache for context.
    ///   - baseBranch: Branch to create worktrees from.
    ///   - onProgress: Callback for progress updates.
    /// - Returns: The dispatch result.
    public func dispatch(
        plan: WorkPlan,
        layer: ProtocolLayer,
        cache: ArchitectureCache? = nil,
        baseBranch: String = "HEAD",
        onProgress: (@Sendable (ProgressEvent) -> Void)? = nil
    ) async throws -> DispatchResult {
        guard !plan.units.isEmpty else {
            throw DispatchError.noUnitsToDispatch
        }

        let start = Date()

        switch plan.strategy {
        case .sequential:
            return try await dispatchSequential(
                plan: plan, layer: layer, cache: cache,
                baseBranch: baseBranch, start: start, onProgress: onProgress
            )

        case .parallel, .massiveParallel:
            return try await dispatchParallel(
                plan: plan, layer: layer, cache: cache,
                baseBranch: baseBranch, start: start, onProgress: onProgress
            )
        }
    }

    // MARK: - Sequential Dispatch

    func dispatchSequential(
        plan: WorkPlan,
        layer: ProtocolLayer,
        cache: ArchitectureCache?,
        baseBranch: String,
        start: Date,
        onProgress: (@Sendable (ProgressEvent) -> Void)?
    ) async throws -> DispatchResult {
        let unit = plan.units[0]
        let prompt = promptGenerator.generateCompact(for: unit, layer: layer, cache: cache)

        onProgress?(.unitStarted(unitId: unit.id, description: unit.description))

        let result = try await agentRunner.run(
            prompt: prompt,
            workingDirectory: projectRoot,
            unitId: unit.id
        )

        onProgress?(.unitCompleted(unitId: unit.id, status: result.status))

        let duration = Int(Date().timeIntervalSince(start))
        return DispatchResult(
            agentResults: [result],
            totalDurationSeconds: duration,
            strategy: .sequential
        )
    }

    // MARK: - Parallel Dispatch

    func dispatchParallel(
        plan: WorkPlan,
        layer: ProtocolLayer,
        cache: ArchitectureCache?,
        baseBranch: String,
        start: Date,
        onProgress: (@Sendable (ProgressEvent) -> Void)?
    ) async throws -> DispatchResult {
        // 1. Create worktrees
        onProgress?(.phase("Creating worktrees"))
        let worktrees = try await worktreeManager.createAll(for: plan, baseBranch: baseBranch)

        // Map unitId → worktree
        let worktreeMap = Dictionary(uniqueKeysWithValues: worktrees.map { ($0.unitId, $0) })

        // 2. Generate prompts
        onProgress?(.phase("Generating agent prompts"))
        let prompts = plan.units.map { unit in
            (unit, promptGenerator.generate(for: unit, layer: layer, cache: cache))
        }

        // 3. Dispatch protocol unit first (priority 0), then rest in parallel
        let protoUnits = prompts.filter { $0.0.priority == 0 }
        let implUnits = prompts.filter { $0.0.priority > 0 }

        var allResults: [AgentResult] = []

        // Protocol units must complete first
        for (unit, prompt) in protoUnits {
            let worktreePath = worktreeMap[unit.id]?.path ?? projectRoot
            onProgress?(.unitStarted(unitId: unit.id, description: unit.description))

            let result = try await agentRunner.run(
                prompt: prompt,
                workingDirectory: worktreePath,
                unitId: unit.id
            )
            allResults.append(result)
            onProgress?(.unitCompleted(unitId: unit.id, status: result.status))

            // If protocol unit failed, abort
            if result.status == .failed {
                await worktreeManager.removeAll(worktrees)
                throw DispatchError.agentFailed(unit.id, result.error ?? "Protocol unit failed")
            }
        }

        // Implementation units in parallel
        if !implUnits.isEmpty {
            onProgress?(.phase("Dispatching \(implUnits.count) agents in parallel"))

            let results = await withTaskGroup(of: AgentResult.self) { group in
                for (unit, prompt) in implUnits {
                    let worktreePath = worktreeMap[unit.id]?.path ?? projectRoot
                    let runner = agentRunner
                    group.addTask {
                        do {
                            return try await runner.run(
                                prompt: prompt,
                                workingDirectory: worktreePath,
                                unitId: unit.id
                            )
                        } catch {
                            return AgentResult(
                                unitId: unit.id,
                                status: .failed,
                                error: error.localizedDescription
                            )
                        }
                    }
                }

                var collected: [AgentResult] = []
                for await result in group {
                    collected.append(result)
                    onProgress?(.unitCompleted(unitId: result.unitId, status: result.status))
                }
                return collected
            }

            allResults.append(contentsOf: results)
        }

        let duration = Int(Date().timeIntervalSince(start))

        return DispatchResult(
            agentResults: allResults,
            totalDurationSeconds: duration,
            strategy: plan.strategy
        )
    }
}

// MARK: - Progress Events

/// Progress events emitted during dispatch.
public enum ProgressEvent: Sendable {
    case phase(String)
    case unitStarted(unitId: String, description: String)
    case unitCompleted(unitId: String, status: AgentStatus)
}

// MARK: - CLI Agent Runner

/// Default agent runner that shells out to `claude -p`.
public struct CLIAgentRunner: AgentRunner, Sendable {

    /// The claude binary path (default: "claude" from PATH).
    private let claudeBinary: String

    public init(claudeBinary: String = "claude") {
        self.claudeBinary = claudeBinary
    }

    public func run(prompt: String, workingDirectory: String, unitId: String) async throws -> AgentResult {
        let start = Date()

        // Write prompt to temp file to avoid arg length limits
        let promptFile = NSTemporaryDirectory() + "shikki-prompt-\(unitId).md"
        try prompt.write(toFile: promptFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: promptFile) }

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [claudeBinary, "-p", prompt, "--output-format", "text"]
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let duration = Int(Date().timeIntervalSince(start))
        let stdout = String(
            data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        if process.terminationStatus == 0 {
            // Parse created files from output (best effort)
            let files = parseCreatedFiles(stdout, workingDirectory: workingDirectory)
            let commitHash = parseCommitHash(stdout)

            return AgentResult(
                unitId: unitId,
                status: .completed,
                filesCreated: files,
                commitHash: commitHash,
                durationSeconds: duration
            )
        } else {
            let stderr = String(
                data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            return AgentResult(
                unitId: unitId,
                status: .failed,
                error: stderr.isEmpty ? "Exit code \(process.terminationStatus)" : stderr,
                durationSeconds: duration
            )
        }
    }

    func parseCreatedFiles(_ output: String, workingDirectory: String) -> [String] {
        // Look for file paths in the output
        var files: [String] = []
        let pattern = #"(?:Created?|Writ(?:ing|ten)|Edit(?:ing|ed))\s+[`"]?(\S+\.swift)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return files
        }
        let range = NSRange(output.startIndex..., in: output)
        regex.enumerateMatches(in: output, range: range) { match, _, _ in
            guard let match, let r = Range(match.range(at: 1), in: output) else { return }
            files.append(String(output[r]))
        }
        return files
    }

    func parseCommitHash(_ output: String) -> String? {
        let pattern = #"[a-f0-9]{7,40}"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let range = Range(match.range, in: output) else {
            return nil
        }
        return String(output[range])
    }
}
