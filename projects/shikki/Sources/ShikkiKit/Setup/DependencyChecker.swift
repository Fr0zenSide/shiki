import Foundation

// MARK: - DependencyChecker

/// Platform-aware dependency checker that discovers tools via `which` and generates
/// platform-specific install commands.
///
/// BR-07: Platform detection via compile-time `#if os()`, not runtime shell calls.
/// BR-08: All tool paths resolved via `which`, never hardcoded.
/// BR-03: Missing required tools produce actionable fix commands.
public struct DependencyChecker: Sendable {

    // MARK: - Platform

    /// Target platform, determined at compile time.
    /// BR-07: Uses Swift conditional compilation, not shell uname.
    public enum Platform: Sendable, Equatable {
        case macOS
        case linux

        /// The current platform, detected at compile time.
        public static var current: Platform {
            #if os(macOS)
            return .macOS
            #elseif os(Linux)
            return .linux
            #else
            return .macOS // Fallback
            #endif
        }
    }

    // MARK: - ToolStatus

    /// Status of a dependency check.
    public enum ToolStatus: Sendable {
        /// Tool found at the given path, with an optional version string.
        case available(path: String, version: String?)
        /// Tool not found; includes platform-specific install command.
        case missing(installCommand: String)
    }

    // MARK: - Properties

    /// Shell executor for running commands. Protocol-based for testability.
    let shell: any ShellExecuting

    /// Target platform for install command generation.
    let platform: Platform

    // MARK: - Init

    public init(shell: any ShellExecuting, platform: Platform? = nil) {
        self.shell = shell
        self.platform = platform ?? .current
    }

    // MARK: - Single Tool Check

    /// Check a single required tool.
    /// BR-08: Resolves path via `which`, not hardcoded.
    /// Returns `.available` with path and version, or `.missing` with install command.
    public func check(_ tool: RequiredTool) async -> ToolStatus {
        guard let path = await shell.which(tool.rawValue) else {
            return .missing(installCommand: tool.installCommand(for: platform))
        }

        // Try to get version info
        let version = await getVersion(tool.rawValue, flag: tool.versionFlag)
        return .available(path: path, version: version)
    }

    /// Check a single optional dependency.
    public func checkOptional(_ dep: OptionalDependency) async -> ToolStatus {
        guard let path = await shell.which(dep.binaryName) else {
            return .missing(installCommand: dep.installCommand(for: platform))
        }

        let version = await getVersion(dep.binaryName, flag: dep.versionFlag)
        return .available(path: path, version: version)
    }

    // MARK: - Batch Checks

    /// Check all required tools.
    /// BR-03: Missing required tools will block setup.
    public func checkAll() async -> [RequiredTool: ToolStatus] {
        var results: [RequiredTool: ToolStatus] = [:]
        for tool in RequiredTool.allCases {
            results[tool] = await check(tool)
        }
        return results
    }

    /// Check all optional dependencies.
    public func checkAllOptional() async -> [OptionalDependency: ToolStatus] {
        var results: [OptionalDependency: ToolStatus] = [:]
        for dep in OptionalDependency.allCases {
            results[dep] = await checkOptional(dep)
        }
        return results
    }

    /// Returns true if all required tools are available.
    public func allRequiredAvailable() async -> Bool {
        let results = await checkAll()
        return results.values.allSatisfy { status in
            if case .available = status { return true }
            return false
        }
    }

    /// Returns only the missing required tools with their install commands.
    public func missingRequired() async -> [(tool: RequiredTool, installCommand: String)] {
        let results = await checkAll()
        return results.compactMap { tool, status in
            if case .missing(let cmd) = status {
                return (tool: tool, installCommand: cmd)
            }
            return nil
        }
    }

    // MARK: - Private Helpers

    /// Run a tool's version command and extract the output.
    private func getVersion(_ tool: String, flag: String) async -> String? {
        do {
            let result = try await shell.run(tool, arguments: [flag])
            if result.exitCode == 0 && !result.stdout.isEmpty {
                return result.stdout
            }
        } catch {
            // Version check failed — tool exists but may be broken
        }
        return nil
    }
}
