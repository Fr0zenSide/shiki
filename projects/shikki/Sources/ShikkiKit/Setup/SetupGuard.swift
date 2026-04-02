import Foundation

// MARK: - SetupGuard

/// Gate that checks whether Shikki setup is complete before allowing commands to run.
/// Exempt commands (setup, doctor, --help, --version) bypass the guard.
public struct SetupGuard: Sendable {

    /// Commands that are allowed to run without setup being complete.
    public static let exemptCommands: Set<String> = [
        "setup",
        "doctor",
        "--help",
        "-h",
        "--version",
    ]

    /// The current binary version.
    public let currentVersion: String

    /// Path to setup state file (overridable for testing).
    public let statePath: String?

    public init(currentVersion: String, statePath: String? = nil) {
        self.currentVersion = currentVersion
        self.statePath = statePath
    }

    /// Check if a command name is exempt from the setup guard.
    public func isExempt(command: String) -> Bool {
        Self.exemptCommands.contains(command)
    }

    /// Returns true if setup is needed (state missing or version mismatch).
    public func needsSetup() -> Bool {
        SetupState.needsSetup(currentVersion: currentVersion, path: statePath)
    }

    /// Run the setup guard. If setup is incomplete, runs bootstrap automatically.
    /// Returns true if the command should proceed, false if setup failed.
    @discardableResult
    public func check(command: String) async -> Bool {
        // Exempt commands always proceed
        if isExempt(command: command) {
            return true
        }

        // If setup is complete, proceed
        if !needsSetup() {
            return true
        }

        // Setup needed — run bootstrap
        print("\u{1B}[33mShikki setup incomplete. Running bootstrap...\u{1B}[0m")
        print()

        let service = SetupService(currentVersion: currentVersion, statePath: statePath)
        let success = await service.bootstrap()

        if success {
            // Mark complete
            do {
                try SetupState.markComplete(version: currentVersion, path: statePath)
            } catch {
                // Non-fatal — setup worked, state save failed
            }
        }

        return success
    }
}
