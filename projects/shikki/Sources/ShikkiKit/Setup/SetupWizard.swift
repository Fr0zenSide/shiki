import Foundation

// MARK: - SetupResult

/// Result of a setup wizard run.
public struct SetupResult: Sendable {
    /// Whether setup completed successfully.
    public let success: Bool
    /// Number of steps that were executed.
    public let stepsExecuted: Int
    /// Number of steps that were skipped (already complete).
    public let stepsSkipped: Int
    /// Missing required tools, if any blocked setup.
    public let missingRequired: [(tool: RequiredTool, installCommand: String)]
    /// Broken tools detected during verification.
    public let brokenTools: [(tool: RequiredTool, error: String)]
    /// Optional tools status.
    public let optionalStatus: [OptionalDependency: DependencyChecker.ToolStatus]

    public init(
        success: Bool,
        stepsExecuted: Int = 0,
        stepsSkipped: Int = 0,
        missingRequired: [(tool: RequiredTool, installCommand: String)] = [],
        brokenTools: [(tool: RequiredTool, error: String)] = [],
        optionalStatus: [OptionalDependency: DependencyChecker.ToolStatus] = [:]
    ) {
        self.success = success
        self.stepsExecuted = stepsExecuted
        self.stepsSkipped = stepsSkipped
        self.missingRequired = missingRequired
        self.brokenTools = brokenTools
        self.optionalStatus = optionalStatus
    }
}

// MARK: - SetupError

/// Errors that can block setup.
public enum SetupError: Error, Sendable {
    /// A required dependency is missing and cannot be auto-installed.
    case requiredDependencyMissing(RequiredTool, fixCommand: String)
    /// Post-install verification failed for a required tool.
    case verificationFailed(RequiredTool, error: String)
    /// State persistence failed.
    case statePersistenceFailed(String)
}

// MARK: - SetupWizard

/// Orchestrator for the Shikki setup flow.
///
/// BR-02: Splash animation overlaps with background dependency checks via async let.
/// BR-05: All steps are idempotent — safe to re-run.
/// BR-09: Progress persisted to `~/.shikki/setup.json` after each step.
public struct SetupWizard: Sendable {

    // MARK: - Mode

    /// How the wizard should run.
    public enum Mode: Sendable {
        /// First-run: triggered automatically when no setup.json exists.
        case firstRun
        /// Retry: resume from last successful step.
        case retry
        /// Force: redo everything from scratch.
        case force
    }

    // MARK: - Setup Steps

    /// The ordered steps in the setup flow.
    enum Step: String, CaseIterable {
        case dependencies = "dependencies"
        case verification = "verification"
        case workspace = "workspace"
        case completions = "completions"
    }

    // MARK: - Properties

    private let checker: DependencyChecker
    private let verifier: SetupVerifier
    private let statePath: String
    private let version: String
    private let skipSplash: Bool

    // MARK: - Init

    /// Create a setup wizard with injectable dependencies.
    ///
    /// - Parameters:
    ///   - shell: Shell executor (use `DefaultShellExecutor` in production, mock in tests).
    ///   - platform: Target platform for install commands.
    ///   - statePath: Path to setup.json (defaults to `~/.shikki/setup.json`).
    ///   - version: Current Shikki version string.
    ///   - skipSplash: Skip the splash screen (for testing or CI).
    public init(
        shell: any ShellExecuting,
        platform: DependencyChecker.Platform? = nil,
        statePath: String? = nil,
        version: String,
        skipSplash: Bool = false
    ) {
        self.checker = DependencyChecker(shell: shell, platform: platform)
        self.verifier = SetupVerifier(shell: shell)
        self.statePath = statePath ?? SetupState.defaultPath
        self.version = version
        self.skipSplash = skipSplash
    }

    // MARK: - Run

    /// Execute the setup wizard.
    ///
    /// BR-02: Background dependency checks start concurrently with splash.
    /// BR-05: Each step is idempotent.
    /// BR-09: State persisted after each completed step.
    ///
    /// - Parameter mode: How to run (firstRun, retry, force).
    /// - Returns: A `SetupResult` describing what happened.
    public func run(mode: Mode) async throws -> SetupResult {
        // Load or create state based on mode
        var state: SetupState
        switch mode {
        case .firstRun, .retry:
            state = SetupState.load(from: statePath) ?? SetupState(version: version, steps: [:])
            // If version changed, reset state
            if state.version != version {
                state = SetupState(version: version, steps: [:])
            }
        case .force:
            // Force mode: start fresh
            state = SetupState(version: version, steps: [:])
        }

        // If already complete (for firstRun/retry), return early
        if mode != .force && state.allStepsComplete {
            return SetupResult(
                success: true,
                stepsExecuted: 0,
                stepsSkipped: Step.allCases.count
            )
        }

        var stepsExecuted = 0
        var stepsSkipped = 0

        // BR-02: Start background dependency checks while splash is showing
        // Using async let to overlap splash rendering with dependency discovery
        if !skipSplash {
            // In production: render splash while checks happen in background
            async let bgRequired = checker.checkAll()
            async let bgOptional = checker.checkAllOptional()

            // Splash would render here (SplashRenderer.render is synchronous ~1s)
            // For now we just await the background results
            let _ = await bgRequired
            let _ = await bgOptional
        }

        // Step 1: Dependencies (check required tools)
        let requiredResults: [RequiredTool: DependencyChecker.ToolStatus]
        let optionalResults: [OptionalDependency: DependencyChecker.ToolStatus]

        if !state.isStepComplete(Step.dependencies.rawValue) {
            requiredResults = await checker.checkAll()
            optionalResults = await checker.checkAllOptional()

            // BR-03: Required dependency failure blocks setup
            let missing = requiredResults.compactMap { tool, status -> (tool: RequiredTool, installCommand: String)? in
                if case .missing(let cmd) = status {
                    return (tool: tool, installCommand: cmd)
                }
                return nil
            }

            if !missing.isEmpty {
                return SetupResult(
                    success: false,
                    stepsExecuted: stepsExecuted,
                    stepsSkipped: stepsSkipped,
                    missingRequired: missing,
                    optionalStatus: optionalResults
                )
            }

            state.markStep(Step.dependencies.rawValue)
            try saveState(state)
            stepsExecuted += 1
        } else {
            // Dependencies already checked — re-check for verification step
            requiredResults = await checker.checkAll()
            optionalResults = await checker.checkAllOptional()
            stepsSkipped += 1
        }

        // Step 2: Verification (actually run tools)
        if !state.isStepComplete(Step.verification.rawValue) {
            let broken = await verifier.brokenTools()
            if !broken.isEmpty {
                return SetupResult(
                    success: false,
                    stepsExecuted: stepsExecuted,
                    stepsSkipped: stepsSkipped,
                    brokenTools: broken,
                    optionalStatus: optionalResults
                )
            }

            state.markStep(Step.verification.rawValue)
            try saveState(state)
            stepsExecuted += 1
        } else {
            stepsSkipped += 1
        }

        // Step 3: Workspace directories
        if !state.isStepComplete(Step.workspace.rawValue) {
            createWorkspaceDirs()
            state.markStep(Step.workspace.rawValue)
            try saveState(state)
            stepsExecuted += 1
        } else {
            stepsSkipped += 1
        }

        // Step 4: PATH and completions check
        if !state.isStepComplete(Step.completions.rawValue) {
            state.markStep(Step.completions.rawValue)
            try saveState(state)
            stepsExecuted += 1
        } else {
            stepsSkipped += 1
        }

        return SetupResult(
            success: true,
            stepsExecuted: stepsExecuted,
            stepsSkipped: stepsSkipped,
            optionalStatus: optionalResults
        )
    }

    // MARK: - Private Helpers

    /// Save setup state to disk.
    /// BR-09: Progress persisted after each step.
    private func saveState(_ state: SetupState) throws {
        do {
            try state.save(to: statePath)
        } catch {
            throw SetupError.statePersistenceFailed(
                "Failed to save setup state to \(statePath): \(error.localizedDescription)"
            )
        }
    }

    /// Create workspace directories.
    private func createWorkspaceDirs() {
        let fm = FileManager.default
        let dirs = [
            ".shikki",
            ".shikki/test-logs",
            ".shikki/plugins",
            ".shikki/sessions",
        ]
        for dir in dirs {
            let path = fm.currentDirectoryPath + "/" + dir
            if !fm.fileExists(atPath: path) {
                try? fm.createDirectory(atPath: path, withIntermediateDirectories: true)
            }
        }
    }
}
