import Foundation

// MARK: - CommandSource

/// Searches registered shiki commands.
public struct CommandSource: PaletteSource {
    public let category = "command"
    public let prefix: String? = ">"

    private static let commands: [(name: String, description: String)] = [
        ("status", "Show orchestrator status"),
        ("dispatch", "Dispatch a task to an agent"),
        ("board", "Show the session board"),
        ("doctor", "Run diagnostics"),
        ("notify", "Manage notifications"),
        ("research", "Open research sandbox"),
        ("pr", "Review pull requests"),
        ("report", "Generate weekly report"),
        ("restart", "Restart orchestrator"),
        ("stop", "Stop orchestrator"),
        ("start", "Start orchestrator"),
        ("config", "Edit configuration"),
    ]

    public init() {}

    public func search(query: String) async -> [PaletteResult] {
        if query.isEmpty {
            return Self.commands.map { cmd in
                PaletteResult(
                    id: "cmd:\(cmd.name)", title: cmd.name,
                    subtitle: cmd.description, category: category,
                    icon: ">", score: 0
                )
            }
        }
        return Self.commands.compactMap { cmd in
            guard let match = FuzzyMatcher.match(query: query, in: cmd.name) else {
                return nil
            }
            return PaletteResult(
                id: "cmd:\(match.target)", title: match.target,
                subtitle: cmd.description, category: category,
                icon: ">", score: match.score
            )
        }
    }
}

// MARK: - SessionSource

/// Searches the SessionRegistry for active sessions.
public struct SessionSource: PaletteSource {
    public let category = "session"
    public let prefix: String? = "s:"

    private let registry: SessionRegistry

    public init(registry: SessionRegistry) {
        self.registry = registry
    }

    public func search(query: String) async -> [PaletteResult] {
        let sessions = await registry.allSessions
        if query.isEmpty {
            return sessions.map { session in
                PaletteResult(
                    id: "session:\(session.windowName)", title: session.windowName,
                    subtitle: session.state.rawValue, category: category,
                    icon: stateIcon(session.state), score: 0
                )
            }
        }
        return sessions.compactMap { session in
            guard let match = FuzzyMatcher.match(query: query, in: session.windowName) else {
                return nil
            }
            return PaletteResult(
                id: "session:\(session.windowName)", title: session.windowName,
                subtitle: session.state.rawValue, category: category,
                icon: stateIcon(session.state), score: match.score
            )
        }
    }

    private func stateIcon(_ state: SessionState) -> String {
        switch state {
        case .working: return "*"
        case .awaitingApproval: return "!"
        case .prOpen, .reviewPending: return "^"
        case .done, .merged: return "="
        case .ciFailed, .changesRequested: return "x"
        default: return "-"
        }
    }
}

// MARK: - FeatureSource

/// Searches features/*.md files by name.
public struct FeatureSource: PaletteSource {
    public let category = "feature"
    public let prefix: String? = "f:"

    private let workspaceRoot: String

    public init(workspaceRoot: String) {
        self.workspaceRoot = workspaceRoot
    }

    public func search(query: String) async -> [PaletteResult] {
        let featuresDir = (workspaceRoot as NSString).appendingPathComponent("features")
        let fileManager = FileManager.default

        guard let entries = try? fileManager.contentsOfDirectory(atPath: featuresDir) else {
            return []
        }

        let mdFiles = entries.filter { $0.hasSuffix(".md") }
            .map { String($0.dropLast(3)) } // strip .md

        if query.isEmpty {
            return mdFiles.map { name in
                PaletteResult(
                    id: "feature:\(name)", title: name,
                    subtitle: "features/\(name).md", category: category,
                    icon: "#", score: 0
                )
            }
        }

        return mdFiles.compactMap { name in
            guard let match = FuzzyMatcher.match(query: query, in: name) else {
                return nil
            }
            return PaletteResult(
                id: "feature:\(name)", title: name,
                subtitle: "features/\(name).md", category: category,
                icon: "#", score: match.score
            )
        }
    }
}

// MARK: - BranchSource

/// Searches git branches.
public struct BranchSource: PaletteSource {
    public let category = "branch"
    public let prefix: String? = "b:"

    private let workspaceRoot: String

    public init(workspaceRoot: String) {
        self.workspaceRoot = workspaceRoot
    }

    public func search(query: String) async -> [PaletteResult] {
        guard let output = runCapture("git", arguments: ["-C", workspaceRoot, "branch", "--format=%(refname:short)"]) else {
            return []
        }

        let branches = output.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        if query.isEmpty {
            return branches.map { name in
                PaletteResult(
                    id: "branch:\(name)", title: name,
                    subtitle: nil, category: category,
                    icon: "~", score: 0
                )
            }
        }

        return branches.compactMap { name in
            guard let match = FuzzyMatcher.match(query: query, in: name) else {
                return nil
            }
            return PaletteResult(
                id: "branch:\(name)", title: name,
                subtitle: nil, category: category,
                icon: "~", score: match.score
            )
        }
    }

    private func runCapture(_ executable: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}
