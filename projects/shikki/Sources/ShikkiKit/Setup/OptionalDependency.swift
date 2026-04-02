import Foundation

// MARK: - ShellExecuting Protocol

/// Protocol for shell command execution — mockable for tests.
/// All dependency checking flows through this protocol, never direct Process calls.
public protocol ShellExecuting: Sendable {
    /// Run a command with arguments. Returns stdout content and exit code.
    func run(_ command: String, arguments: [String]) async throws -> (stdout: String, exitCode: Int32)

    /// Look up a tool by name via `which`. Returns the resolved path or nil.
    func which(_ tool: String) async -> String?
}

// MARK: - DefaultShellExecutor

/// Production shell executor that runs real processes.
public struct DefaultShellExecutor: ShellExecuting {

    public init() {}

    public func run(_ command: String, arguments: [String]) async throws -> (stdout: String, exitCode: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (stdout: stdout, exitCode: process.terminationStatus)
    }

    public func which(_ tool: String) async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", tool]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return path?.isEmpty == false ? path : nil
        } catch {
            return nil
        }
    }
}

// MARK: - RequiredTool

/// Required tools that must be present for Shikki to function.
/// BR-03: Failure to find these blocks setup with platform-specific fix command.
public enum RequiredTool: String, CaseIterable, Sendable, Hashable {
    case git
    case tmux
    case claude

    /// The version flag used to verify the tool works.
    public var versionFlag: String {
        switch self {
        case .git: return "--version"
        case .tmux: return "-V"
        case .claude: return "--version"
        }
    }

    /// Human-readable description.
    public var description: String {
        switch self {
        case .git: return "Version control"
        case .tmux: return "Terminal multiplexer for session management"
        case .claude: return "Claude Code CLI for AI-assisted development"
        }
    }

    /// Platform-specific install command.
    /// BR-07: Uses compile-time platform detection, not shell uname.
    public func installCommand(for platform: DependencyChecker.Platform) -> String {
        switch (self, platform) {
        case (.git, .macOS): return "brew install git"
        case (.git, .linux): return "sudo apt install -y git"
        case (.tmux, .macOS): return "brew install tmux"
        case (.tmux, .linux): return "sudo apt install -y tmux"
        case (.claude, .macOS): return "npm install -g @anthropic-ai/claude-code"
        case (.claude, .linux): return "npm install -g @anthropic-ai/claude-code"
        }
    }
}

// MARK: - OptionalDependency

/// Optional tools that enhance the Shikki experience but are not required.
/// BR-04: Each dependency includes description and estimated download size.
public enum OptionalDependency: String, CaseIterable, Sendable, Hashable {
    case delta
    case bat
    case fzf
    case rg
    case gh

    /// The actual binary name on PATH.
    public var binaryName: String {
        rawValue
    }

    /// Human-readable description of what this tool provides.
    public var description: String {
        switch self {
        case .delta: return "Better diffs in terminal"
        case .bat: return "Syntax-highlighted file viewer"
        case .fzf: return "Fuzzy finder for interactive selection"
        case .rg: return "Fast recursive search (ripgrep)"
        case .gh: return "GitHub CLI for PR and issue management"
        }
    }

    /// Estimated download size in megabytes.
    public var estimatedSizeMB: Int {
        switch self {
        case .delta: return 5
        case .bat: return 3
        case .fzf: return 2
        case .rg: return 2
        case .gh: return 20
        }
    }

    /// The version flag used to verify the tool works.
    public var versionFlag: String {
        switch self {
        case .delta: return "--version"
        case .bat: return "--version"
        case .fzf: return "--version"
        case .rg: return "--version"
        case .gh: return "--version"
        }
    }

    /// Platform-specific install command.
    /// BR-07: Uses compile-time platform detection, not shell uname.
    public func installCommand(for platform: DependencyChecker.Platform) -> String {
        switch (self, platform) {
        case (.delta, .macOS): return "brew install git-delta"
        case (.delta, .linux): return "sudo apt install -y git-delta"
        case (.bat, .macOS): return "brew install bat"
        case (.bat, .linux): return "sudo apt install -y bat"
        case (.fzf, .macOS): return "brew install fzf"
        case (.fzf, .linux): return "sudo apt install -y fzf"
        case (.rg, .macOS): return "brew install ripgrep"
        case (.rg, .linux): return "sudo apt install -y ripgrep"
        case (.gh, .macOS): return "brew install gh"
        case (.gh, .linux): return "sudo apt install -y gh"
        }
    }
}
