import Foundation

/// Formats git repository status for tmux status bar display.
/// Inspired by Starship's git modules but designed for persistent tmux display.
public enum GitStatusFormatter {

    /// Git status data collected from the current working directory.
    public struct GitInfo: Sendable {
        public let branch: String
        public let remote: String?         // e.g., "github", "gitlab"
        public let staged: Int
        public let modified: Int
        public let untracked: Int
        public let deleted: Int
        public let conflicted: Int
        public let ahead: Int
        public let behind: Int
        public let isWorktree: Bool
        public let isDetached: Bool
        public let stashCount: Int

        public init(branch: String, remote: String? = nil, staged: Int = 0,
                    modified: Int = 0, untracked: Int = 0, deleted: Int = 0,
                    conflicted: Int = 0, ahead: Int = 0, behind: Int = 0,
                    isWorktree: Bool = false, isDetached: Bool = false,
                    stashCount: Int = 0) {
            self.branch = branch
            self.remote = remote
            self.staged = staged
            self.modified = modified
            self.untracked = untracked
            self.deleted = deleted
            self.conflicted = conflicted
            self.ahead = ahead
            self.behind = behind
            self.isWorktree = isWorktree
            self.isDetached = isDetached
            self.stashCount = stashCount
        }
    }

    // MARK: - Dracula ANSI Colors (matching tmux Dracula palette)

    private static let purple = "\u{1B}[38;2;189;147;249m"  // #bd93f9
    private static let green  = "\u{1B}[38;2;80;250;123m"   // #50fa7b
    private static let yellow = "\u{1B}[38;2;241;250;140m"  // #f1fa8c
    private static let red    = "\u{1B}[38;2;255;85;85m"    // #ff5555
    private static let cyan   = "\u{1B}[38;2;139;233;253m"  // #8be9fd
    private static let pink   = "\u{1B}[38;2;255;121;198m"  // #ff79c6
    private static let fg     = "\u{1B}[38;2;248;248;242m"  // #f8f8f2
    private static let dim    = "\u{1B}[38;2;98;114;164m"   // #6272a4
    private static let reset  = "\u{1B}[0m"

    // MARK: - Remote Icons

    private static func remoteIcon(for remote: String?) -> String {
        guard let r = remote?.lowercased() else { return "" }
        if r.contains("github") { return " " }
        if r.contains("gitlab") { return " " }
        if r.contains("bitbucket") { return " " }
        return " "
    }

    // MARK: - Format

    /// Compact git status for tmux: " main +2 !3 ?1 ⇡1"
    public static func format(_ info: GitInfo, arrowStyle: ArrowStyle = .none) -> String {
        var parts: [String] = []

        // Remote icon
        let remote = remoteIcon(for: info.remote)

        // Branch name (truncate at 20 chars)
        let branchDisplay = info.isDetached
            ? "\(red)@\(String(info.branch.prefix(8)))\(reset)"
            : "\(purple)\(info.branch.count > 20 ? String(info.branch.prefix(17)) + "..." : info.branch)\(reset)"

        parts.append("\(dim)\(remote)\(reset)\(branchDisplay)")

        // Worktree indicator
        if info.isWorktree {
            parts.append("\(green)⛓\(reset)")
        }

        // Status counts (only show non-zero)
        var statusParts: [String] = []
        if info.staged > 0    { statusParts.append("\(green)+\(info.staged)\(reset)") }
        if info.modified > 0  { statusParts.append("\(yellow)!\(info.modified)\(reset)") }
        if info.deleted > 0   { statusParts.append("\(red)-\(info.deleted)\(reset)") }
        if info.untracked > 0 { statusParts.append("\(cyan)?\(info.untracked)\(reset)") }
        if info.conflicted > 0 { statusParts.append("\(red)✖\(info.conflicted)\(reset)") }
        if info.stashCount > 0 { statusParts.append("\(dim)≡\(info.stashCount)\(reset)") }

        if !statusParts.isEmpty {
            parts.append(statusParts.joined(separator: " "))
        }

        // Ahead/behind
        if info.ahead > 0  { parts.append("\(cyan)⇡\(info.ahead)\(reset)") }
        if info.behind > 0 { parts.append("\(pink)⇣\(info.behind)\(reset)") }

        let content = parts.joined(separator: " ")
        return MiniStatusFormatter.wrapWithArrows(content, style: arrowStyle)
    }

    /// Format when not in a git repo.
    public static func formatNoRepo(arrowStyle: ArrowStyle = .none) -> String {
        MiniStatusFormatter.wrapWithArrows("\(dim)no repo\(reset)", style: arrowStyle)
    }

    // MARK: - Git Data Collection

    /// Collect git info from the given directory by running git commands.
    public static func collectGitInfo(at path: String) -> GitInfo? {
        // Check if inside a git repo
        guard shell("git -C \(path) rev-parse --is-inside-work-tree 2>/dev/null") == "true" else {
            return nil
        }

        // Branch name
        let branch = shell("git -C \(path) branch --show-current 2>/dev/null")
        let isDetached = branch.isEmpty
        let branchName = isDetached
            ? shell("git -C \(path) rev-parse --short HEAD 2>/dev/null")
            : branch

        // Remote URL (for icon)
        let remote = shell("git -C \(path) ls-remote --get-url 2>/dev/null")

        // Status counts
        let statusOutput = shell("git -C \(path) status --porcelain 2>/dev/null")
        var staged = 0, modified = 0, untracked = 0, deleted = 0, conflicted = 0
        for line in statusOutput.split(separator: "\n") {
            guard line.count >= 2 else { continue }
            let index = line[line.startIndex]
            let work = line[line.index(line.startIndex, offsetBy: 1)]

            if index == "U" || work == "U" || (index == "A" && work == "A") || (index == "D" && work == "D") {
                conflicted += 1
            } else {
                if index != " " && index != "?" { staged += 1 }
                if work == "M" { modified += 1 }
                if work == "D" { deleted += 1 }
                if index == "?" { untracked += 1 }
            }
        }

        // Ahead/behind
        var ahead = 0, behind = 0
        let abOutput = shell("git -C \(path) rev-list --left-right --count HEAD...@{upstream} 2>/dev/null")
        let abParts = abOutput.split(whereSeparator: { $0.isWhitespace })
        if abParts.count == 2 {
            ahead = Int(abParts[0]) ?? 0
            behind = Int(abParts[1]) ?? 0
        }

        // Worktree detection
        let commonDir = shell("git -C \(path) rev-parse --path-format=absolute --git-common-dir 2>/dev/null")
        let gitDir = shell("git -C \(path) rev-parse --path-format=absolute --git-dir 2>/dev/null")
        let isWorktree = !commonDir.isEmpty && !gitDir.isEmpty && commonDir != gitDir

        // Stash count
        let stashOutput = shell("git -C \(path) stash list 2>/dev/null")
        let stashCount = stashOutput.isEmpty ? 0 : stashOutput.split(separator: "\n").count

        return GitInfo(
            branch: branchName,
            remote: remote.isEmpty ? nil : remote,
            staged: staged,
            modified: modified,
            untracked: untracked,
            deleted: deleted,
            conflicted: conflicted,
            ahead: ahead,
            behind: behind,
            isWorktree: isWorktree,
            isDetached: isDetached,
            stashCount: stashCount
        )
    }

    // MARK: - Shell Helper

    private static func shell(_ command: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
