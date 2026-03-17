import Foundation

// MARK: - Tool Info

/// Metadata for an external tool that enhances the review experience.
public struct ToolInfo: Sendable {
    public let name: String
    public let shortcut: String
    public let description: String
    public let installHint: String

    public init(name: String, shortcut: String, description: String, installHint: String) {
        self.name = name
        self.shortcut = shortcut
        self.description = description
        self.installHint = installHint
    }
}

// MARK: - ExternalTools

/// Detects and provides access to external tools with graceful degradation.
/// Use now (shell-out), build later if limitations arise.
public struct ExternalTools: Sendable {

    public init() {}

    /// Known tools that enhance the review experience.
    public static let knownTools: [ToolInfo] = [
        ToolInfo(name: "delta", shortcut: "d", description: "Syntax-highlighted diff viewer", installHint: "brew install git-delta"),
        ToolInfo(name: "fzf", shortcut: "f", description: "Fuzzy file finder", installHint: "brew install fzf"),
        ToolInfo(name: "rg", shortcut: "g", description: "ripgrep — fast code search", installHint: "brew install ripgrep"),
        ToolInfo(name: "qmd", shortcut: "/", description: "BM25+vector+LLM semantic search", installHint: "See qmd docs"),
        ToolInfo(name: "bat", shortcut: "b", description: "cat with syntax highlighting", installHint: "brew install bat"),
    ]

    /// Check if a tool is available on PATH.
    public func isAvailable(_ tool: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", tool]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Get the best diff command name, with fallback.
    public func diffCommand(for filePath: String) -> String {
        if isAvailable("delta") {
            return "delta"
        } else if isAvailable("diff-so-fancy") {
            return "diff-so-fancy"
        } else {
            return "diff"
        }
    }

    /// Get the best pager/viewer args for a file (safe — no shell interpolation).
    public func viewCommand(for filePath: String) -> [String] {
        if isAvailable("bat") {
            return ["bat", "--style=numbers", "--color=always", filePath]
        } else {
            return ["cat", "-n", filePath]
        }
    }

    /// Get available tools as a status report.
    public func statusReport() -> [(tool: ToolInfo, available: Bool)] {
        Self.knownTools.map { tool in
            (tool: tool, available: isAvailable(tool.name))
        }
    }
}
