import ArgumentParser
import Foundation
import ShikiCtlKit

struct PRCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pr",
        abstract: "Smart PR review with persistent progress tracking",
        subcommands: [ReadSubcommand.self, CommentSubcommand.self, SyncSubcommand.self]
    )

    @Argument(help: "PR number")
    var number: Int

    @Flag(name: .long, help: "Force rebuild PR cache from git diff")
    var build: Bool = false

    @Flag(name: .long, help: "Output raw JSON (for piping to jq, shiki-qa)")
    var json: Bool = false

    @Flag(name: .long, help: "Output architecture-ordered diff (pipe to delta for syntax highlight)")
    var diff: Bool = false

    @Flag(name: .long, help: "Show only unreviewed/changed files")
    var delta: Bool = false

    @Flag(name: .long, help: "Show only files with comments")
    var comments: Bool = false

    @Option(name: .long, help: "Base ref: branch, #N, prN, pr#N, SHA (default: develop)")
    var base: String = "develop"

    @Option(name: .long, help: "Range: --from pr24 (single base) or --from pr20..pr24 (base..head)")
    var from: String?

    /// Resolve git root so commands work from any cwd.
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

    /// Create a Process pre-configured with the git root as working directory.
    private func makeProcess(executable: String = "/usr/bin/env", arguments: [String]) -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.currentDirectoryURL = gitRoot
        p.arguments = arguments
        return p
    }

    /// Resolve a ref string to a git-usable ref.
    /// Accepts: branch name, commit SHA, #N, prN, pr#N.
    /// For PRs: resolves to headRefOid (SHA) — works even after branch deletion.
    private func resolveRef(_ ref: String) -> String {
        let t = ref.trimmingCharacters(in: .whitespaces)
        let num: String?
        if t.hasPrefix("pr#") { num = String(t.dropFirst(3)) }
        else if t.hasPrefix("pr") { num = String(t.dropFirst(2)) }
        else if t.hasPrefix("#") { num = String(t.dropFirst(1)) }
        else { num = nil }
        guard let n = num, Int(n) != nil else { return t }
        // Resolve PR to head commit SHA — survives branch deletion
        let p = makeProcess(arguments: ["gh", "pr", "view", n, "--json", "headRefOid", "-q", ".headRefOid"])
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        try? p.run()
        let d = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        if p.terminationStatus == 0, let sha = String(data: d, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !sha.isEmpty { return sha }
        return t
    }

    /// The resolved base ref for diff (left side).
    private var resolvedBase: String {
        // --from takes priority over --base
        if let fromSpec = from {
            if fromSpec.contains("..") {
                let parts = fromSpec.split(separator: ".", maxSplits: 2, omittingEmptySubsequences: true)
                if let first = parts.first {
                    return resolveRef(String(first))
                }
            }
            return resolveRef(fromSpec)
        }
        return resolveRef(base)
    }

    /// The resolved head ref for diff (right side).
    /// Normally HEAD, but --from pr20..pr24 uses the second ref.
    private var resolvedHead: String {
        if let fromSpec = from, fromSpec.contains("..") {
            let parts = fromSpec.split(separator: ".", maxSplits: 2, omittingEmptySubsequences: true)
            if parts.count >= 2 {
                return resolveRef(String(parts.last!))
            }
        }
        // Default: resolve from the PR number argument
        return resolveRef("pr\(number)")
    }

    /// The diff spec string: base...head
    private var diffSpec: String {
        "\(resolvedBase)...\(resolvedHead)"
    }

    func run() async throws {
        let root = gitRoot
        let cacheDir = "\(root.path)/docs/pr\(number)-cache"
        let filesPath = "\(cacheDir)/files.json"

        // Force rebuild (does NOT destroy review-state.json per BR-11)
        if build {
            try buildCache()
            return
        }

        // Auto-build cache if missing or if --base/--from changed the diff spec
        let needsRebuild: Bool
        let metaPath = "\(cacheDir)/cache-meta.json"
        if !FileManager.default.fileExists(atPath: filesPath) {
            needsRebuild = true
        } else if let metaData = FileManager.default.contents(atPath: metaPath),
                  let meta = try? JSONSerialization.jsonObject(with: metaData) as? [String: String],
                  meta["diffSpec"] != diffSpec {
            needsRebuild = true
            FileHandle.standardError.write(Data("Base changed (\(meta["diffSpec"] ?? "?") → \(diffSpec)), rebuilding...\n".utf8))
        } else {
            needsRebuild = false
        }
        if needsRebuild {
            FileHandle.standardError.write(Data("Building cache for PR #\(number)...\n".utf8))
            try buildCache()
        }

        // Load cache
        guard FileManager.default.fileExists(atPath: filesPath) else {
            FileHandle.standardError.write(Data("No changes found for PR #\(number).\n".utf8))
            throw ExitCode.failure
        }

        let filesData = try Data(contentsOf: URL(fileURLWithPath: filesPath))
        guard let files = try JSONSerialization.jsonObject(with: filesData) as? [[String: Any]] else {
            throw ExitCode.failure
        }

        let riskPath = "\(cacheDir)/risk-map.json"
        var risk: [[String: Any]]?
        if let riskData = FileManager.default.contents(atPath: riskPath) {
            risk = try JSONSerialization.jsonObject(with: riskData) as? [[String: Any]]
        }

        // Load or create review state
        let stateManager = PRReviewStateManager(prNumber: number)
        let filePaths = files.compactMap { $0["path"] as? String }
        var reviewState = try stateManager.loadOrCreate(prNumber: number, filePaths: filePaths)

        // Delta detection: compare current PR HEAD with lastReviewedCommit
        let currentHead = fetchPRHead()
        if !reviewState.lastReviewedCommit.isEmpty,
           let head = currentHead,
           head != reviewState.lastReviewedCommit {
            let changedFiles = gitDiffFiles(from: reviewState.lastReviewedCommit, to: head)
            if !changedFiles.isEmpty {
                reviewState.applyDelta(changedPaths: changedFiles)
                try stateManager.save(reviewState)

                let changedCount = reviewState.reviewedFiles.filter { $0.status == .changed }.count
                if changedCount > 0 {
                    let changedNames = reviewState.reviewedFiles
                        .filter { $0.status == .changed }
                        .map { ($0.path as NSString).lastPathComponent }
                    FileHandle.standardError.write(Data("\n  \(ANSI.yellow)⚠ \(changedCount) files changed since your last review\(ANSI.reset)\n".utf8))
                    FileHandle.standardError.write(Data("  \(ANSI.dim)Changed: \(changedNames.joined(separator: ", "))\(ANSI.reset)\n".utf8))
                }
            }
        }

        // --comments filter
        if comments {
            renderCommentsView(reviewState: reviewState)
            return
        }

        // JSON mode: raw output for piping
        if json {
            var result: [String: Any] = ["pr": number, "files": files]
            if let r = risk { result["risk"] = r }
            // Add review state to JSON output
            if stateManager.hasState {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                if let stateData = try? encoder.encode(reviewState),
                   let stateDict = try? JSONSerialization.jsonObject(with: stateData) {
                    result["reviewState"] = stateDict
                }
            }
            let jsonData = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            FileHandle.standardOutput.write(jsonData)
            FileHandle.standardOutput.write(Data("\n".utf8))
            return
        }

        // Diff mode
        if diff {
            if delta {
                // --delta --diff: only diff delta files
                let deltaFiles = reviewState.deltaFiles.map(\.path)
                let deltaFileEntries = files.filter { deltaFiles.contains($0["path"] as? String ?? "") }
                renderOrderedDiff(files: deltaFileEntries)
            } else {
                renderOrderedDiff(files: files)
            }
            return
        }

        // Default: smart prioritized summary with progress
        if delta {
            let deltaFiles = reviewState.deltaFiles.map(\.path)
            let deltaFileEntries = files.filter { deltaFiles.contains($0["path"] as? String ?? "") }
            renderSmartSummary(files: deltaFileEntries, risk: risk, reviewState: reviewState, isDelta: true)
        } else {
            renderSmartSummary(files: files, risk: risk, reviewState: reviewState, isDelta: false)
        }
    }

    // MARK: - Comments View

    private func renderCommentsView(reviewState: PRReviewProgress) {
        let commented = reviewState.commentedFiles(includeResolved: false)

        if commented.isEmpty {
            print("\(ANSI.dim)No open comments for PR #\(number)\(ANSI.reset)")
            return
        }

        print()
        print("\(ANSI.bold)Comments on PR #\(number)\(ANSI.reset)")
        print(String(repeating: "─", count: 56))
        print()

        for file in commented {
            let shortPath = (file.path as NSString).lastPathComponent
            let comment = file.comment ?? ""
            print("  \(file.status.indicator) \(shortPath)")
            print("    \(ANSI.dim)\"\(comment)\"\(ANSI.reset)")
            print()
        }
    }

    // MARK: - Ordered Diff (pipe to delta)

    private func renderOrderedDiff(files: [[String: Any]]) {
        let sorted = files.sorted { a, b in
            let pa = layerPriority(path: a["path"] as? String ?? "")
            let pb = layerPriority(path: b["path"] as? String ?? "")
            if pa != pb { return pa < pb }
            let sizeA = (a["insertions"] as? Int ?? 0) + (a["deletions"] as? Int ?? 0)
            let sizeB = (b["insertions"] as? Int ?? 0) + (b["deletions"] as? Int ?? 0)
            return sizeA > sizeB
        }

        let paths = sorted.compactMap { $0["path"] as? String }
        guard !paths.isEmpty else { return }

        // Header comment with base info
        let header = "// PR #\(number) diff: \(diffSpec) (\(paths.count) files, architecture-ordered)\n"
        FileHandle.standardOutput.write(Data(header.utf8))

        // Run git diff with files in architecture order
        let process = makeProcess(executable: "/usr/bin/git", arguments: ["diff", diffSpec, "--"] + paths)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        FileHandle.standardOutput.write(data)
    }

    // MARK: - Smart Summary (default output)

    private func renderSmartSummary(files: [[String: Any]], risk: [[String: Any]]?, reviewState: PRReviewProgress, isDelta: Bool) {
        let totalIns = files.reduce(0) { $0 + ($1["insertions"] as? Int ?? 0) }
        let totalDel = files.reduce(0) { $0 + ($1["deletions"] as? Int ?? 0) }

        let prInfo = fetchPRInfo()

        // Header
        print()
        if let title = prInfo["title"] {
            print("\(ANSI.bold)PR #\(number): \(title)\(ANSI.reset)")
        } else {
            print("\(ANSI.bold)PR #\(number)\(ANSI.reset)")
        }

        if let branch = prInfo["branch"] {
            let displayBase = base != "develop" ? resolvedBase : (prInfo["base"] ?? "develop")
            print("\(ANSI.dim)\(branch) → \(displayBase)\(ANSI.reset) │ \(files.count) files │ \(ANSI.green)+\(totalIns)\(ANSI.reset)/\(ANSI.red)-\(totalDel)\(ANSI.reset)")
        } else {
            print("\(files.count) files │ \(ANSI.green)+\(totalIns)\(ANSI.reset)/\(ANSI.red)-\(totalDel)\(ANSI.reset)")
        }

        if let author = prInfo["author"], let age = prInfo["age"] {
            print("\(ANSI.dim)Author: @\(author) │ \(age)\(ANSI.reset)")
        }

        print(String(repeating: "─", count: 56))

        // Progress display (Wave 6)
        if reviewState.totalCount > 0 {
            print()
            if reviewState.isComplete {
                print("  Progress: \(reviewState.progressFraction) \(ANSI.green)✓ — all files reviewed\(ANSI.reset)")
            } else {
                print("  Progress: \(reviewState.progressFraction)")
            }
            print("  \(reviewState.progressBar) \(reviewState.reviewedCount)/\(reviewState.totalCount)")

            let pendingCount = reviewState.reviewedFiles.filter { $0.status == .pending }.count
            let changedCount = reviewState.reviewedFiles.filter { $0.status == .changed }.count
            let commentedCount = reviewState.reviewedFiles.filter { $0.status == .commented }.count
            var remaining: [String] = []
            if pendingCount > 0 { remaining.append("\(pendingCount) pending") }
            if changedCount > 0 { remaining.append("\(changedCount) changed since last review") }
            if commentedCount > 0 { remaining.append("\(commentedCount) commented") }
            if !remaining.isEmpty {
                print("  \(ANSI.dim)\(remaining.joined(separator: " │ "))\(ANSI.reset)")
            }
            print()
        }

        if isDelta {
            print("  \(ANSI.dim)Showing delta only (--delta)\(ANSI.reset)")
        }

        // PR description summary
        if let body = prInfo["body"], !body.isEmpty {
            let summaryLines = body.components(separatedBy: "\n")
                .filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("🤖") }
                .prefix(3)
            if !summaryLines.isEmpty {
                print()
                for line in summaryLines {
                    let trimmed = line.count > 80 ? String(line.prefix(77)) + "..." : line
                    print("  \(ANSI.dim)\(trimmed)\(ANSI.reset)")
                }
            }
        }

        // Layer summary
        print()
        let layerCounts = Dictionary(grouping: files) { layerPriority(path: $0["path"] as? String ?? "") }
            .sorted { $0.key < $1.key }
        let layerSummary = layerCounts.map { "\(layerName($0.key, short: true)):\($0.value.count)" }
        print("  \(ANSI.dim)\(layerSummary.joined(separator: " │ "))\(ANSI.reset)")
        print()

        // Sort by architecture layer
        let sorted = files.sorted { a, b in
            let pa = layerPriority(path: a["path"] as? String ?? "")
            let pb = layerPriority(path: b["path"] as? String ?? "")
            if pa != pb { return pa < pb }
            let sizeA = (a["insertions"] as? Int ?? 0) + (a["deletions"] as? Int ?? 0)
            let sizeB = (b["insertions"] as? Int ?? 0) + (b["deletions"] as? Int ?? 0)
            return sizeA > sizeB
        }

        // Group by layer with status indicators
        var currentLayer = -1
        for file in sorted {
            let path = file["path"] as? String ?? ""
            let ins = file["insertions"] as? Int ?? 0
            let del = file["deletions"] as? Int ?? 0
            let layer = layerPriority(path: path)

            if layer != currentLayer {
                currentLayer = layer
                print()
                print("\(ANSI.dim)\(layerName(layer))\(ANSI.reset)")
            }

            let sizeBar = String(repeating: "█", count: min((ins + del) / 10 + 1, 20))
            let shortPath = path.count > 50 ? "…" + String(path.suffix(47)) : path

            // Status indicator from review state
            let reviewedFile = reviewState.reviewedFiles.first { $0.path == path }
            let statusIcon = reviewedFile?.status.indicator ?? "[ ]"

            var line = "  \(statusIcon) \(ANSI.green)+\(String(format: "%3d", ins))\(ANSI.reset) \(ANSI.red)-\(String(format: "%3d", del))\(ANSI.reset) \(ANSI.dim)\(sizeBar)\(ANSI.reset) \(shortPath)"

            // Show truncated comment inline
            if let comment = reviewedFile?.comment, reviewedFile?.status == .commented {
                let truncated = comment.count > 40 ? String(comment.prefix(37)) + "..." : comment
                line += "  \(ANSI.dim)\"\(truncated)\"\(ANSI.reset)"
            }

            print(line)
        }

        print()
        print("\(ANSI.dim)──────────────────────────────────────────────────────────\(ANSI.reset)")
        print("\(ANSI.dim)  shiki pr \(number) --diff | delta   syntax-highlighted diff")
        print("  shiki pr \(number) --json | jq     raw JSON for piping")
        print("  shiki pr \(number) --delta         show only unreviewed/changed")
        print("  shiki pr \(number) read <file>     mark file as reviewed")
        print("  /review \(number)                  interactive review\(ANSI.reset)")
        print()
    }

    // MARK: - Fetch PR Metadata

    private func fetchPRInfo() -> [String: String] {
        let process = makeProcess(arguments: [
            "gh", "pr", "view", "\(number)",
            "--json", "title,headRefName,baseRefName,author,createdAt,body",
            "--jq", "[.title, .headRefName, .baseRefName, .author.login, .createdAt, .body] | @tsv",
        ])
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else {
            return [:]
        }

        let parts = output.components(separatedBy: "\t")
        guard parts.count >= 5 else { return [:] }

        let formatter = ISO8601DateFormatter()
        var age = ""
        if let date = formatter.date(from: parts[4]) {
            let interval = Date().timeIntervalSince(date)
            if interval < 3600 { age = "\(Int(interval / 60))m ago" }
            else if interval < 86400 { age = "\(Int(interval / 3600))h ago" }
            else { age = "\(Int(interval / 86400))d ago" }
        }

        return [
            "title": parts[0],
            "branch": parts[1],
            "base": parts[2],
            "author": parts[3],
            "age": age,
            "body": parts.count > 5 ? parts[5] : "",
        ]
    }

    /// Fetch current PR HEAD commit SHA.
    private func fetchPRHead() -> String? {
        let process = makeProcess(arguments: ["gh", "pr", "view", "\(number)", "--json", "headRefOid", "-q", ".headRefOid"])
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else {
            return nil
        }
        return output
    }

    /// Get files changed between two commits.
    private func gitDiffFiles(from: String, to: String) -> [String] {
        let process = makeProcess(executable: "/usr/bin/git", arguments: ["diff", "--name-only", "\(from)..\(to)"])
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8) else {
            return []
        }
        return output.split(separator: "\n").map(String.init)
    }

    // MARK: - Architecture Layer Sorting

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

    private func layerName(_ priority: Int, short: Bool = false) -> String {
        if short {
            switch priority {
            case 0: return "proto"
            case 1: return "types"
            case 2: return "model"
            case 3: return "impl"
            case 4: return "gates"
            case 5: return "cmd"
            case 6: return "fmt"
            case 7: return "docs"
            case 8: return "test"
            default: return "other"
            }
        }
        switch priority {
        case 0: return "── Protocols & Interfaces ──"
        case 1: return "── Errors & State Enums ──"
        case 2: return "── Models & DTOs ──"
        case 3: return "── Services & Implementations ──"
        case 4: return "── Pipeline & Gates ──"
        case 5: return "── Commands & Other ──"
        case 6: return "── Formatters & Renderers ──"
        case 7: return "── Config & Docs ──"
        case 8: return "── Tests ──"
        default: return "── Other ──"
        }
    }

    // MARK: - Build Cache

    private func buildCache() throws {
        let root = gitRoot
        let cacheDir = "\(root.path)/docs/pr\(number)-cache"
        try FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)

        let diffStat = makeProcess(executable: "/usr/bin/git", arguments: ["diff", "--numstat", diffSpec])
        let statPipe = Pipe()
        diffStat.standardOutput = statPipe
        try diffStat.run()
        let statData = statPipe.fileHandleForReading.readDataToEndOfFile()
        diffStat.waitUntilExit()
        let statOutput = String(data: statData, encoding: .utf8) ?? ""

        var files: [[String: Any]] = []
        for line in statOutput.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 2)
            guard parts.count == 3 else { continue }
            let insertions = Int(parts[0]) ?? 0
            let deletions = Int(parts[1]) ?? 0
            let path = String(parts[2])
            files.append([
                "path": path,
                "insertions": insertions,
                "deletions": deletions,
            ])
        }

        let encoder = JSONSerialization.self
        let filesJSON = try encoder.data(withJSONObject: files, options: [.prettyPrinted, .sortedKeys])
        try filesJSON.write(to: URL(fileURLWithPath: "\(cacheDir)/files.json"))

        // Save cache metadata so we know when to auto-rebuild
        let meta: [String: String] = ["diffSpec": diffSpec, "builtAt": ISO8601DateFormatter().string(from: Date())]
        let metaJSON = try JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys])
        try metaJSON.write(to: URL(fileURLWithPath: "\(cacheDir)/cache-meta.json"))

        let total = files.count
        let ins = files.reduce(0) { $0 + ($1["insertions"] as? Int ?? 0) }
        let del = files.reduce(0) { $0 + ($1["deletions"] as? Int ?? 0) }
        FileHandle.standardError.write(Data("Cache built: \(total) files, +\(ins)/-\(del)\n".utf8))
        FileHandle.standardError.write(Data("Output: \(cacheDir)/\n".utf8))
    }
}

// MARK: - Read Subcommand (Wave 3)

struct ReadSubcommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "read",
        abstract: "Mark files as reviewed"
    )

    @Argument(help: "PR number")
    var number: Int

    @Argument(help: "File path (partial match)")
    var file: String?

    @Flag(name: .long, help: "Mark all files as reviewed")
    var all: Bool = false

    @Flag(name: .long, help: "Reset all files to pending")
    var reset: Bool = false

    func run() async throws {
        let stateManager = PRReviewStateManager(prNumber: number)

        // Load cache to get file list
        let cacheDir = "docs/pr\(number)-cache"
        let filesPath = "\(cacheDir)/files.json"
        guard FileManager.default.fileExists(atPath: filesPath) else {
            FileHandle.standardError.write(Data("No cache for PR #\(number). Run `shiki pr \(number)` first.\n".utf8))
            throw ExitCode.failure
        }

        let filesData = try Data(contentsOf: URL(fileURLWithPath: filesPath))
        guard let files = try JSONSerialization.jsonObject(with: filesData) as? [[String: Any]] else {
            throw ExitCode.failure
        }
        let filePaths = files.compactMap { $0["path"] as? String }

        var state = try stateManager.loadOrCreate(prNumber: number, filePaths: filePaths)

        // Fetch current PR HEAD for commit tracking
        let currentHead = fetchCurrentHead(number: number)

        if reset {
            state.resetAll()
            try stateManager.save(state)
            print("\(ANSI.yellow)Reset all files to pending for PR #\(number)\(ANSI.reset)")
            return
        }

        if all {
            let now = Date()
            state.markAllReviewed(at: now, commit: currentHead)
            try stateManager.save(state)
            print("\(ANSI.green)Marked all \(state.totalCount) files as reviewed for PR #\(number)\(ANSI.reset)")
            return
        }

        guard let query = file else {
            FileHandle.standardError.write(Data("Specify a file, --all, or --reset\n".utf8))
            throw ExitCode.failure
        }

        let resolvedPath = try state.resolveFile(query)
        let now = Date()
        state.markFileReviewed(resolvedPath, at: now, commit: currentHead)
        try stateManager.save(state)

        let basename = (resolvedPath as NSString).lastPathComponent
        print("\(ANSI.green)[✓]\(ANSI.reset) \(basename) marked as reviewed (\(state.reviewedCount)/\(state.totalCount))")
    }

    private func fetchCurrentHead(number: Int) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["gh", "pr", "view", "\(number)", "--json", "headRefOid", "-q", ".headRefOid"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        if process.terminationStatus == 0,
           let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !output.isEmpty {
            return output
        }
        // Fallback to local HEAD
        let gitProcess = Process()
        gitProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        gitProcess.arguments = ["rev-parse", "HEAD"]
        let gitPipe = Pipe()
        gitProcess.standardOutput = gitPipe
        try? gitProcess.run()
        let gitData = gitPipe.fileHandleForReading.readDataToEndOfFile()
        gitProcess.waitUntilExit()
        return String(data: gitData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
    }
}

// MARK: - Comment Subcommand (Wave 4)

struct CommentSubcommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "comment",
        abstract: "Attach a comment to a file (optionally targeting a line or range)"
    )

    @Argument(help: "PR number")
    var number: Int

    @Argument(help: "File path (partial match)")
    var file: String

    @Argument(help: "Comment text")
    var message: String

    @Option(name: .shortAndLong, help: "Target lines: -l 42, -l 18-25, -l 10-15/22/30-35")
    var line: String?

    func run() async throws {
        let stateManager = PRReviewStateManager(prNumber: number)

        let cacheDir = "docs/pr\(number)-cache"
        let filesPath = "\(cacheDir)/files.json"
        guard FileManager.default.fileExists(atPath: filesPath) else {
            FileHandle.standardError.write(Data("No cache for PR #\(number). Run `shiki pr \(number)` first.\n".utf8))
            throw ExitCode.failure
        }

        let filesData = try Data(contentsOf: URL(fileURLWithPath: filesPath))
        guard let files = try JSONSerialization.jsonObject(with: filesData) as? [[String: Any]] else {
            throw ExitCode.failure
        }
        let filePaths = files.compactMap { $0["path"] as? String }

        var state = try stateManager.loadOrCreate(prNumber: number, filePaths: filePaths)

        let resolvedPath = try state.resolveFile(file)

        // Parse line spec: "42", "18-25", "10-15/22/30-35"
        let lineSpec = line.flatMap { parseLineSpec($0) }

        // Fetch current HEAD
        let currentHead = fetchCurrentHead(number: number)
        let now = Date()

        // Use first range for the model (full spec stored in comment text)
        let firstLine = lineSpec?.first?.start
        let firstEndLine = lineSpec?.first.flatMap { $0.end != $0.start ? $0.end : nil }

        state.addComment(to: resolvedPath, message: message, line: firstLine, endLine: firstEndLine, at: now, commit: currentHead)
        try stateManager.save(state)

        let basename = (resolvedPath as NSString).lastPathComponent
        let lineInfo = line.map { " L\($0)" } ?? ""
        print("\(ANSI.cyan)[✎]\(ANSI.reset) \(basename)\(lineInfo): \"\(message)\"")

        // Best-effort GitHub sync (first line for inline comment)
        let ghBody = line != nil ? "L\(line!): \(message)" : message
        ghPostComment(prNumber: number, path: resolvedPath, body: ghBody, line: firstLine)
    }

    /// Parse line spec: "42" → [(42,42)], "18-25" → [(18,25)], "10-15/22/30-35" → [(10,15),(22,22),(30,35)]
    private func parseLineSpec(_ spec: String) -> [(start: Int, end: Int)] {
        spec.split(separator: "/").compactMap { segment in
            let parts = segment.split(separator: "-", maxSplits: 1)
            guard let start = Int(parts[0]) else { return nil }
            let end = parts.count > 1 ? Int(parts[1]) ?? start : start
            return (start, end)
        }
    }

    private func fetchCurrentHead(number: Int) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["gh", "pr", "view", "\(number)", "--json", "headRefOid", "-q", ".headRefOid"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        if process.terminationStatus == 0,
           let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !output.isEmpty {
            return output
        }
        return "unknown"
    }

    /// Best-effort post comment to GitHub. Failure is silent — local is source of truth.
    private func ghPostComment(prNumber: Int, path: String, body: String, line: Int? = nil) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")

        if let line {
            // Inline review comment on specific line
            let commitOid = fetchCurrentHead(number: prNumber)
            let owner = getRepoOwner()
            process.arguments = [
                "gh", "api", "repos/\(owner)/pulls/\(prNumber)/comments",
                "-f", "body=\(body)",
                "-f", "path=\(path)",
                "-F", "line=\(line)",
                "-f", "side=RIGHT",
                "-f", "commit_id=\(commitOid)",
            ]
        } else {
            // General PR comment
            process.arguments = [
                "gh", "pr", "comment", "\(prNumber)",
                "--body", "**\(path)**\n\n\(body)",
            ]
        }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        // Don't wait — fire and forget (local is source of truth)
    }

    private func getRepoOwner() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["gh", "repo", "view", "--json", "owner,name", "-q", ".owner.login + \"/\" + .name"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown/unknown"
    }
}

// MARK: - Sync Subcommand (Wave 4 — retry queue)

struct SyncSubcommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "Sync local comments to GitHub"
    )

    @Argument(help: "PR number")
    var number: Int

    func run() async throws {
        let stateManager = PRReviewStateManager(prNumber: number)
        guard let state = try stateManager.load() else {
            print("\(ANSI.dim)No review state for PR #\(number)\(ANSI.reset)")
            return
        }

        let commented = state.reviewedFiles.filter { $0.status == .commented && $0.comment != nil }
        if commented.isEmpty {
            print("\(ANSI.dim)No comments to sync for PR #\(number)\(ANSI.reset)")
            return
        }

        print("Syncing \(commented.count) comments to GitHub...")
        var synced = 0

        for file in commented {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [
                "gh", "pr", "comment", "\(number)",
                "--body", "**\(file.path)**\n\n\(file.comment ?? "")",
            ]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                synced += 1
                let basename = (file.path as NSString).lastPathComponent
                print("  \(ANSI.green)✓\(ANSI.reset) \(basename)")
            } else {
                let basename = (file.path as NSString).lastPathComponent
                print("  \(ANSI.red)✗\(ANSI.reset) \(basename) — failed to sync")
            }
        }

        print("\(ANSI.dim)Synced \(synced)/\(commented.count) comments\(ANSI.reset)")
    }
}
