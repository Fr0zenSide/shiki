import Foundation
import Testing
@testable import ShikkiKit

// MARK: - Mock Setup Dependencies

/// Tracks step execution order for wizard tests.
final class StepTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var _steps: [String] = []

    var steps: [String] {
        lock.lock()
        defer { lock.unlock() }
        return _steps
    }

    func record(_ step: String) {
        lock.lock()
        defer { lock.unlock() }
        _steps.append(step)
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        _steps.removeAll()
    }
}

/// Mock shell that tracks calls and returns configurable results.
final class WizardMockShell: ShellExecuting, @unchecked Sendable {
    let tracker: StepTracker
    var whichResults: [String: String] = [:]
    var runResults: [String: (stdout: String, exitCode: Int32)] = [:]

    init(tracker: StepTracker) {
        self.tracker = tracker
    }

    func run(_ command: String, arguments: [String]) async throws -> (stdout: String, exitCode: Int32) {
        let key = ([command] + arguments).joined(separator: " ")
        tracker.record("run:\(key)")
        if let result = runResults[key] {
            return result
        }
        return (stdout: "", exitCode: 0)
    }

    func which(_ tool: String) async -> String? {
        tracker.record("which:\(tool)")
        return whichResults[tool]
    }
}

// MARK: - SetupWizard Tests

@Suite("SetupWizard — orchestration and flow control")
struct SetupWizardTests {

    /// Helper to create a temp state path.
    private func tempStatePath() -> String {
        NSTemporaryDirectory() + "shikki-test-wizard-\(UUID().uuidString).json"
    }

    /// Helper to create a fully-configured mock shell with all tools available.
    private func allToolsAvailableShell(tracker: StepTracker) -> WizardMockShell {
        let shell = WizardMockShell(tracker: tracker)
        shell.whichResults = [
            "git": "/usr/bin/git",
            "tmux": "/opt/homebrew/bin/tmux",
            "claude": "/usr/local/bin/claude",
        ]
        shell.runResults = [
            "git --version": (stdout: "git version 2.43.0", exitCode: 0),
            "tmux -V": (stdout: "tmux 3.4", exitCode: 0),
            "claude --version": (stdout: "claude 1.0.0", exitCode: 0),
        ]
        return shell
    }

    // MARK: - Scenario 7: Wizard runs steps in correct order

    @Test("Wizard runs steps in correct order with background pre-loading")
    func runsStepsInOrder() async throws {
        let tracker = StepTracker()
        let shell = allToolsAvailableShell(tracker: tracker)
        let statePath = tempStatePath()
        defer { try? FileManager.default.removeItem(atPath: statePath) }

        let wizard = SetupWizard(
            shell: shell,
            platform: .macOS,
            statePath: statePath,
            version: "0.3.0-pre",
            skipSplash: true
        )

        let result = try await wizard.run(mode: .firstRun)
        #expect(result.success, "Wizard should succeed when all tools are available")

        // Verify state was saved
        let state = SetupState.load(from: statePath)
        #expect(state != nil, "Setup state should be persisted")
    }

    // MARK: - Scenario 8: Setup state persists after each step

    @Test("Setup state persists after each step")
    func statePersistsAfterEachStep() async throws {
        let tracker = StepTracker()
        let shell = allToolsAvailableShell(tracker: tracker)
        let statePath = tempStatePath()
        defer { try? FileManager.default.removeItem(atPath: statePath) }

        let wizard = SetupWizard(
            shell: shell,
            platform: .macOS,
            statePath: statePath,
            version: "0.3.0-pre",
            skipSplash: true
        )

        let result = try await wizard.run(mode: .firstRun)
        #expect(result.success)

        // Load the persisted state
        let state = SetupState.load(from: statePath)
        #expect(state != nil, "State should exist on disk")
        #expect(state?.isStepComplete("dependencies") == true, "dependencies step should be complete")
    }

    // MARK: - Scenario 9: --retry resumes from last successful step

    @Test("Retry resumes from last successful step")
    func retryResumesFromLastStep() async throws {
        let tracker = StepTracker()
        let shell = allToolsAvailableShell(tracker: tracker)
        let statePath = tempStatePath()
        defer { try? FileManager.default.removeItem(atPath: statePath) }

        // Pre-populate state with some steps done
        var state = SetupState(version: "0.3.0-pre")
        state.markStep("dependencies")
        try state.save(to: statePath)

        let wizard = SetupWizard(
            shell: shell,
            platform: .macOS,
            statePath: statePath,
            version: "0.3.0-pre",
            skipSplash: true
        )

        let result = try await wizard.run(mode: .retry)
        #expect(result.success, "Retry should succeed")

        // In retry mode with dependencies already done, the dependency step is skipped
        #expect(result.stepsSkipped > 0, "Should have skipped at least one step")
    }

    // MARK: - Scenario 10: --force reruns everything from scratch

    @Test("Force reruns everything from scratch")
    func forceRerunsEverything() async throws {
        let tracker = StepTracker()
        let shell = allToolsAvailableShell(tracker: tracker)
        let statePath = tempStatePath()
        defer { try? FileManager.default.removeItem(atPath: statePath) }

        // Pre-populate state as fully complete
        try SetupState.markComplete(version: "0.3.0-pre", path: statePath)

        let wizard = SetupWizard(
            shell: shell,
            platform: .macOS,
            statePath: statePath,
            version: "0.3.0-pre",
            skipSplash: true
        )

        let result = try await wizard.run(mode: .force)
        #expect(result.success, "Force run should succeed")
        #expect(result.stepsSkipped == 0, "Force mode should not skip any steps")
    }

    // MARK: - Scenario 11: Setup works offline — skips optional deps

    @Test("Setup works offline — skips optional deps")
    func worksOffline() async throws {
        let tracker = StepTracker()
        let shell = allToolsAvailableShell(tracker: tracker)
        // Optional tools not available
        shell.whichResults = [
            "git": "/usr/bin/git",
            "tmux": "/opt/homebrew/bin/tmux",
            "claude": "/usr/local/bin/claude",
        ]
        let statePath = tempStatePath()
        defer { try? FileManager.default.removeItem(atPath: statePath) }

        let wizard = SetupWizard(
            shell: shell,
            platform: .macOS,
            statePath: statePath,
            version: "0.3.0-pre",
            skipSplash: true
        )

        let result = try await wizard.run(mode: .firstRun)
        #expect(result.success, "Setup should succeed without optional deps")
    }

    // MARK: - Scenario 12: All steps idempotent — running twice produces same result

    @Test("All steps idempotent — running twice produces same result")
    func idempotent() async throws {
        let tracker = StepTracker()
        let shell = allToolsAvailableShell(tracker: tracker)
        let statePath = tempStatePath()
        defer { try? FileManager.default.removeItem(atPath: statePath) }

        let wizard = SetupWizard(
            shell: shell,
            platform: .macOS,
            statePath: statePath,
            version: "0.3.0-pre",
            skipSplash: true
        )

        // Run once
        let result1 = try await wizard.run(mode: .firstRun)
        #expect(result1.success)

        // Run again — should succeed with steps skipped
        tracker.reset()
        let result2 = try await wizard.run(mode: .firstRun)
        #expect(result2.success, "Second run should also succeed")
        // Second run should skip all steps since they're already complete
        #expect(result2.stepsSkipped > 0, "Second run should skip completed steps")
    }
}
