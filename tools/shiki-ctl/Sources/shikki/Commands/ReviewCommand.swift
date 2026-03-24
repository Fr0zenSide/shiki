import ArgumentParser
import Foundation
import ShikiCtlKit

/// `shikki review` — unified PR review command with inbox integration and range notation.
///
/// BR-I-01: `shikki review inbox` pipes all PRs from inbox to review pipeline.
/// BR-I-02: `shikki review 14..18` processes PRs 14 through 18 sequentially.
/// BR-I-03: `shikki review <N>` pipes diff to stdout for `| bat`, `| delta`.
/// BR-I-04: Review progress saves per-file state to ShikkiDB via BackendClient.
struct ReviewCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "review",
        abstract: "PR review with inbox integration, range notation, and progress tracking",
        discussion: """
        Review PRs with external diff tools:
          shikki review 14            — pipe diff to stdout
          shikki review 14 | bat      — syntax-highlighted diff
          shikki review 14 | delta    — side-by-side diff
          shikki review 14..18        — review PRs 14 through 18 sequentially
          shikki review inbox         — review all PRs from inbox
          shikki review --from inbox  — same as above

        Context popup (v1.1): press ? during review for tmux context popup.
        """,
        subcommands: [ReadSubcommand.self, CommentSubcommand.self, SyncSubcommand.self]
    )

    @Argument(help: "PR number, range (14..18), or 'inbox'")
    var target: String

    @Flag(name: .long, help: "Force rebuild PR cache from git diff")
    var build: Bool = false

    @Flag(name: .long, help: "Output raw JSON (for piping to jq)")
    var json: Bool = false

    @Flag(name: .long, help: "Show only unreviewed/changed files")
    var delta: Bool = false

    @Flag(name: .long, help: "Show only files with comments")
    var comments: Bool = false

    @Option(name: .long, help: "Source: branch, prN, SHA, or 'inbox'. Example: --from inbox")
    var from: String?

    // MARK: - Execution

    func run() async throws {
        // BR-I-01: `shikki review inbox` or `shikki review --from inbox`
        if target == "inbox" || from == "inbox" {
            try await reviewInbox()
            return
        }

        // BR-I-02: Range notation — `shikki review 14..18`
        if target.contains("..") {
            let prNumbers = try parseRange(target)
            for prNumber in prNumbers {
                try await reviewSinglePR(prNumber)
            }
            return
        }

        // BR-I-03: Single PR — `shikki review 14`
        guard let prNumber = Int(target) else {
            throw ValidationError("Invalid target '\(target)'. Expected PR number, range (14..18), or 'inbox'.")
        }
        try await reviewSinglePR(prNumber)
    }

    @Option(name: .long, help: "Backend URL (for inbox integration)")
    var url: String = "http://localhost:3900"

    // MARK: - Inbox Pipeline (BR-I-01)

    /// Fetch all open PRs from inbox via InboxManager and review them sequentially.
    /// Uses InboxManager for unified urgency-sorted PR list (not raw gh output).
    private func reviewInbox() async throws {
        let client = BackendClient(baseURL: url)
        let manager = InboxManager(client: client)

        let prNumbers: [Int]
        do {
            prNumbers = try await manager.prNumbers()
        } catch {
            // Fallback to direct gh call if InboxManager fails
            prNumbers = try fetchInboxPRNumbersFallback()
        }

        try? await client.shutdown()

        if prNumbers.isEmpty {
            FileHandle.standardError.write(Data("\(ANSI.dim)No PRs in inbox.\(ANSI.reset)\n".utf8))
            return
        }

        FileHandle.standardError.write(Data("\(ANSI.dim)Inbox: \(prNumbers.count) PRs to review\(ANSI.reset)\n".utf8))

        for prNumber in prNumbers {
            try await reviewSinglePR(prNumber)
        }
    }

    /// Fallback: fetch open PR numbers directly from `gh pr list`.
    private func fetchInboxPRNumbersFallback() throws -> [Int] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.currentDirectoryURL = gitRoot
        process.arguments = ["gh", "pr", "list", "--json", "number", "--jq", ".[].number"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else {
            return []
        }

        return output.split(separator: "\n").compactMap { Int($0) }.sorted()
    }

    // MARK: - Range Parsing (BR-I-02)

    /// Parse "14..18" into [14, 15, 16, 17, 18].
    static func parseRange(_ input: String) throws -> [Int] {
        let parts = input.split(separator: ".", omittingEmptySubsequences: true)
        guard parts.count == 2,
              let start = Int(parts[0]),
              let end = Int(parts[1]) else {
            throw ValidationError("Invalid range '\(input)'. Expected format: 14..18")
        }
        guard start <= end else {
            throw ValidationError("Invalid range '\(input)': start (\(start)) must be <= end (\(end)).")
        }
        guard end - start < 100 else {
            throw ValidationError("Range too large (\(end - start + 1) PRs). Maximum 100.")
        }
        return Array(start...end)
    }

    private func parseRange(_ input: String) throws -> [Int] {
        try Self.parseRange(input)
    }

    // MARK: - Single PR Review (BR-I-03)

    /// Review a single PR: pipe architecture-ordered diff to stdout.
    /// Progress is saved to ShikkiDB (BR-I-04).
    private func reviewSinglePR(_ prNumber: Int) async throws {
        let root = gitRoot

        // Resolve diff spec
        let base = from.map { resolveRef($0) } ?? "develop"
        let head = resolveRef("pr\(prNumber)")
        let actualHead = head.hasPrefix("pr") || head.hasPrefix("#") ? "HEAD" : head
        let diffSpec = "\(base)...\(actualHead)"

        // Build cache if needed
        let cacheDir = "\(root.path)/docs/pr\(prNumber)-cache"
        let filesPath = "\(cacheDir)/files.json"

        if build || !FileManager.default.fileExists(atPath: filesPath) {
            FileHandle.standardError.write(Data("Building cache for PR #\(prNumber)...\n".utf8))
            try buildCache(prNumber: prNumber, diffSpec: diffSpec, root: root)
        }

        // Load file list from cache
        guard FileManager.default.fileExists(atPath: filesPath) else {
            FileHandle.standardError.write(Data("No changes found for PR #\(prNumber).\n".utf8))
            return
        }

        let filesData = try Data(contentsOf: URL(fileURLWithPath: filesPath))
        let parsed = try JSONSerialization.jsonObject(with: filesData)
        let files: [[String: Any]]
        if let wrapper = parsed as? [String: Any], let f = wrapper["files"] as? [[String: Any]] {
            files = f
        } else if let flat = parsed as? [[String: Any]] {
            files = flat
        } else {
            FileHandle.standardError.write(Data("Invalid cache format for PR #\(prNumber).\n".utf8))
            return
        }

        // Load review state for progress tracking (BR-I-04)
        let stateManager = PRReviewStateManager(prNumber: prNumber)
        let filePaths = files.compactMap { $0["path"] as? String }
        let reviewState = try stateManager.loadOrCreate(prNumber: prNumber, filePaths: filePaths)

        // JSON mode
        if json {
            var result: [String: Any] = ["pr": prNumber, "files": files]
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let stateData = try? encoder.encode(reviewState),
               let stateDict = try? JSONSerialization.jsonObject(with: stateData) {
                result["reviewState"] = stateDict
            }
            let jsonData = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            FileHandle.standardOutput.write(jsonData)
            FileHandle.standardOutput.write(Data("\n".utf8))
            return
        }

        // Comments filter
        if comments {
            renderCommentsView(reviewState: reviewState, prNumber: prNumber)
            return
        }

        // Default: architecture-ordered diff to stdout (BR-I-03)
        let sorted = sortByArchitectureLayer(files, deltaOnly: delta, reviewState: reviewState)
        let paths = sorted.compactMap { $0["path"] as? String }

        guard !paths.isEmpty else {
            FileHandle.standardError.write(Data("No files to review for PR #\(prNumber).\n".utf8))
            return
        }

        // Emit header as comment (visible in diff tools)
        let pendingCount = reviewState.reviewedFiles.filter { $0.status == .pending }.count
        let progress = "\(reviewState.reviewedCount)/\(reviewState.totalCount) reviewed"
        let header = "// shikki review #\(prNumber): \(paths.count) files, \(progress), \(pendingCount) pending\n"
        FileHandle.standardOutput.write(Data(header.utf8))

        // Pipe git diff to stdout
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.currentDirectoryURL = root
        process.arguments = ["diff", diffSpec, "--"] + paths
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let diffData = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        FileHandle.standardOutput.write(diffData)

        // BR-I-04: Save progress to ShikkiDB (soft-fail)
        try await saveProgressToDB(prNumber: prNumber, reviewState: reviewState)

        // v1.1 hook point: context popup via tmux `?` key
        // When tmux popup is implemented, this is where the `bind-key ?`
        // trigger would open a floating pane showing:
        // - Current file context (what function/type is this diff in)
        // - Review state summary
        // - Quick actions (mark reviewed, add comment, skip)
        // Implementation: tmux display-popup -E "shikki review-context <prNumber> <currentFile>"
    }

    // MARK: - Progress Persistence (BR-I-04)

    /// Save review progress to ShikkiDB via data-sync endpoint.
    /// Soft-fail: logs warning on error, never throws.
    private func saveProgressToDB(prNumber: Int, reviewState: PRReviewProgress) async throws {
        let dbSync = DBSyncClient()
        let payload: [String: Any] = [
            "type": "review_progress",
            "pr_number": prNumber,
            "reviewed_count": reviewState.reviewedCount,
            "total_count": reviewState.totalCount,
            "progress_percent": reviewState.progressPercent,
            "is_complete": reviewState.isComplete,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "curl", "-sf",
            "--max-time", "\(dbSync.timeoutSeconds)",
            "-X", "POST",
            "-H", "Content-Type: application/json",
            "-d", "@-",
            "http://localhost:3900/api/data-sync/agent_events",
        ]
        let stdin = Pipe()
        process.standardInput = stdin
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            stdin.fileHandleForWriting.write(jsonData)
            try stdin.fileHandleForWriting.close()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                FileHandle.standardError.write(Data("\(ANSI.dim)DB sync skipped (backend unavailable)\(ANSI.reset)\n".utf8))
            }
        } catch {
            FileHandle.standardError.write(Data("\(ANSI.dim)DB sync skipped: \(error.localizedDescription)\(ANSI.reset)\n".utf8))
        }
    }

    // MARK: - Comments View

    private func renderCommentsView(reviewState: PRReviewProgress, prNumber: Int) {
        let commented = reviewState.commentedFiles(includeResolved: false)

        if commented.isEmpty {
            FileHandle.standardError.write(Data("\(ANSI.dim)No open comments for PR #\(prNumber)\(ANSI.reset)\n".utf8))
            return
        }

        FileHandle.standardError.write(Data("\n\(ANSI.bold)Comments on PR #\(prNumber)\(ANSI.reset)\n".utf8))
        FileHandle.standardError.write(Data("\(String(repeating: "\u{2500}", count: 56))\n\n".utf8))

        for file in commented {
            let shortPath = (file.path as NSString).lastPathComponent
            let comment = file.comment ?? ""
            FileHandle.standardError.write(Data("  \(file.status.indicator) \(shortPath)\n".utf8))
            FileHandle.standardError.write(Data("    \(ANSI.dim)\"\(comment)\"\(ANSI.reset)\n\n".utf8))
        }
    }

    // MARK: - Architecture Layer Sorting

    private func sortByArchitectureLayer(_ files: [[String: Any]], deltaOnly: Bool, reviewState: PRReviewProgress) -> [[String: Any]] {
        var filtered = files
        if deltaOnly {
            let deltaFiles = Set(reviewState.deltaFiles.map(\.path))
            filtered = files.filter { deltaFiles.contains($0["path"] as? String ?? "") }
        }

        return filtered.sorted { a, b in
            let pa = layerPriority(path: a["path"] as? String ?? "")
            let pb = layerPriority(path: b["path"] as? String ?? "")
            if pa != pb { return pa < pb }
            let sizeA = (a["insertions"] as? Int ?? 0) + (a["deletions"] as? Int ?? 0)
            let sizeB = (b["insertions"] as? Int ?? 0) + (b["deletions"] as? Int ?? 0)
            return sizeA > sizeB
        }
    }

    private func layerPriority(path: String) -> Int {
        if path.contains("Protocol") || path.contains("Interface") { return 0 }
        if path.contains("Error") || path.contains("Enum") || path.contains("State") { return 1 }
        if path.contains("Model") || path.contains("DTO") || path.contains("Entity") { return 2 }
        if path.contains("Service") || path.contains("Manager") || path.contains("Provider") || path.contains("Engine") { return 3 }
        if path.contains("Gate") || path.contains("Pipeline") || path.contains("Runner") { return 4 }
        if path.contains("Command") { return 5 }
        if path.contains("Formatter") || path.contains("Renderer") { return 6 }
        if path.contains(".md") || path.contains(".json") || path.contains(".yml") || path.contains("scripts/") { return 7 }
        if path.contains("Tests/") || path.contains("Test") { return 8 }
        return 5
    }

    // MARK: - Git Helpers

    /// Resolve git root from cwd or binary path.
    private var gitRoot: URL {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["rev-parse", "--show-toplevel"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        try? p.run()
        let d = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        if p.terminationStatus == 0,
           let out = String(data: d, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !out.isEmpty {
            return URL(fileURLWithPath: out)
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    /// Resolve a ref string (branch, SHA, prN, #N) to a git-usable ref.
    private func resolveRef(_ ref: String) -> String {
        let t = ref.trimmingCharacters(in: .whitespaces)
        let num: String?
        if t.hasPrefix("pr#") { num = String(t.dropFirst(3)) }
        else if t.hasPrefix("pr") { num = String(t.dropFirst(2)) }
        else if t.hasPrefix("#") { num = String(t.dropFirst(1)) }
        else { num = nil }
        guard let n = num, Int(n) != nil else { return t }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.currentDirectoryURL = gitRoot
        p.arguments = ["gh", "pr", "view", n, "--json", "headRefOid", "-q", ".headRefOid"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        try? p.run()
        let d = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        if p.terminationStatus == 0,
           let sha = String(data: d, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !sha.isEmpty {
            return sha
        }
        return t
    }

    // MARK: - Build Cache

    private func buildCache(prNumber: Int, diffSpec: String, root: URL) throws {
        let cacheDir = "\(root.path)/docs/pr\(prNumber)-cache"
        try FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.currentDirectoryURL = root
        process.arguments = ["diff", "--numstat", diffSpec]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""

        var files: [[String: Any]] = []
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 2)
            guard parts.count == 3 else { continue }
            files.append([
                "path": String(parts[2]),
                "insertions": Int(parts[0]) ?? 0,
                "deletions": Int(parts[1]) ?? 0,
            ])
        }

        let cacheData: [String: Any] = [
            "_command": "shikki review \(prNumber)",
            "_diffSpec": diffSpec,
            "_builtAt": ISO8601DateFormatter().string(from: Date()),
            "files": files,
        ]
        let cacheJSON = try JSONSerialization.data(withJSONObject: cacheData, options: [.prettyPrinted, .sortedKeys])
        try cacheJSON.write(to: URL(fileURLWithPath: "\(cacheDir)/files.json"))

        let total = files.count
        let ins = files.reduce(0) { $0 + ($1["insertions"] as? Int ?? 0) }
        let del = files.reduce(0) { $0 + ($1["deletions"] as? Int ?? 0) }
        FileHandle.standardError.write(Data("Cache built: \(total) files, +\(ins)/-\(del)\n".utf8))
    }
}
