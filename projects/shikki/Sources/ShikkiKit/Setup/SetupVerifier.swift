import Foundation

// MARK: - SetupVerifier

/// Post-install verification that actually runs tools to confirm they work.
///
/// BR-10: Verification runs actual tool invocations (`git --version`, `tmux -V`),
/// not just file existence checks via `which`. A tool can exist on PATH but be
/// broken (wrong architecture, missing dynamic library, corrupted binary).
public struct SetupVerifier: Sendable {

    // MARK: - VerificationResult

    /// Result of verifying a single tool.
    public enum VerificationResult: Sendable {
        /// Tool runs and produces a version string.
        case working(version: String)
        /// Tool exists but fails to execute properly.
        case broken(error: String)
    }

    // MARK: - Properties

    /// Shell executor for running verification commands.
    let shell: any ShellExecuting

    // MARK: - Init

    public init(shell: any ShellExecuting) {
        self.shell = shell
    }

    // MARK: - Verify Required Tools

    /// Verify a single required tool by actually running it.
    /// BR-10: Runs `<tool> <versionFlag>` and checks exit code + output.
    public func verify(_ tool: RequiredTool) async -> VerificationResult {
        // First check if tool is on PATH
        guard let path = await shell.which(tool.rawValue) else {
            return .broken(error: "\(tool.rawValue) not found on PATH")
        }

        // Actually run the tool
        do {
            let result = try await shell.run(tool.rawValue, arguments: [tool.versionFlag])
            if result.exitCode == 0 && !result.stdout.isEmpty {
                return .working(version: result.stdout)
            } else if result.exitCode != 0 {
                return .broken(
                    error: "\(tool.rawValue) found at \(path) but \(tool.versionFlag) failed (exit \(result.exitCode))"
                )
            } else {
                return .broken(
                    error: "\(tool.rawValue) found at \(path) but produced no version output"
                )
            }
        } catch {
            return .broken(
                error: "\(tool.rawValue) found at \(path) but execution failed: \(error.localizedDescription)"
            )
        }
    }

    /// Verify an optional dependency by actually running it.
    public func verifyOptional(_ dep: OptionalDependency) async -> VerificationResult {
        guard let path = await shell.which(dep.binaryName) else {
            return .broken(error: "\(dep.binaryName) not found on PATH")
        }

        do {
            let result = try await shell.run(dep.binaryName, arguments: [dep.versionFlag])
            if result.exitCode == 0 && !result.stdout.isEmpty {
                return .working(version: result.stdout)
            } else if result.exitCode != 0 {
                return .broken(
                    error: "\(dep.binaryName) found at \(path) but \(dep.versionFlag) failed (exit \(result.exitCode))"
                )
            } else {
                return .broken(
                    error: "\(dep.binaryName) found at \(path) but produced no version output"
                )
            }
        } catch {
            return .broken(
                error: "\(dep.binaryName) found at \(path) but execution failed: \(error.localizedDescription)"
            )
        }
    }

    /// Verify all required tools.
    /// Returns a dictionary of tool -> verification result.
    public func verifyAll() async -> [RequiredTool: VerificationResult] {
        var results: [RequiredTool: VerificationResult] = [:]
        for tool in RequiredTool.allCases {
            results[tool] = await verify(tool)
        }
        return results
    }

    /// Returns true if all required tools pass verification.
    public func allWorking() async -> Bool {
        let results = await verifyAll()
        return results.values.allSatisfy { result in
            if case .working = result { return true }
            return false
        }
    }

    /// Returns only the broken tools with their error messages.
    public func brokenTools() async -> [(tool: RequiredTool, error: String)] {
        let results = await verifyAll()
        return results.compactMap { tool, result in
            if case .broken(let error) = result {
                return (tool: tool, error: error)
            }
            return nil
        }
    }
}
