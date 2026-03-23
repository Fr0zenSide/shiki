import ArgumentParser
import Foundation
import ShikiCtlKit

// MARK: - PRCommand (thin pipe — outputs JSON/diff to stdout)

/// Generates PR diff cache and outputs structured data for piping.
/// Rendering and review tracking belong to shiki-qa (external tool).
///
/// Usage:
///   shikki pr 6                    → JSON summary to stdout
///   shikki pr 6 --diff | delta     → architecture-ordered diff
///   shikki pr 6 | jq '.files[]'   → pipe to jq
///   shikki pr 6 --build            → force-rebuild cache
struct PRCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pr",
        abstract: "Output PR diff data as JSON (pipe to delta, jq, shiki-qa)"
    )

    @Argument(help: "PR number")
    var number: Int

    @Flag(name: .long, help: "Force rebuild PR cache from git diff")
    var build: Bool = false

    @Flag(name: .long, help: "Output architecture-ordered diff (pipe to delta for syntax highlight)")
    var diff: Bool = false

    @Option(name: .long, help: "Base ref: branch, prN, #N, SHA (default: develop). Example: --from pr24")
    var from: String?

    // MARK: - Git Root Resolution

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

    // MARK: - Ref Resolution

    /// Resolve a ref string to a git-usable ref.
    /// Accepts: branch name, commit SHA, #N, prN, pr#N.
    private func resolveRef(_ ref: String) -> String {
        let t = ref.trimmingCharacters(in: .whitespaces)
        let num: String?
        if t.hasPrefix("pr#") { num = String(t.dropFirst(3)) }
        else if t.hasPrefix("pr") { num = String(t.dropFirst(2)) }
        else if t.hasPrefix("#") { num = String(t.dropFirst(1)) }
        else { num = nil }
        guard let n = num, Int(n) != nil else { return t }

        // Try gh first
        let p = makeProcess(arguments: ["gh", "pr", "view", n, "--json", "headRefOid", "-q", ".headRefOid"])
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

        // Fallback: find PR merge commit via git log
        let git = makeProcess(executable: "/usr/bin/git", arguments: [
            "log", "--all", "--grep=PR #\(n)", "--grep=#\(n)", "--format=%H", "-1",
        ])
        let gitPipe = Pipe()
        git.standardOutput = gitPipe
        git.standardError = FileHandle.nullDevice
        try? git.run()
        let gitData = gitPipe.fileHandleForReading.readDataToEndOfFile()
        git.waitUntilExit()
        if git.terminationStatus == 0,
           let sha = String(data: gitData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !sha.isEmpty {
            FileHandle.standardError.write(Data("  \u{1B}[2m(resolved PR #\(n) via git log)\u{1B}[0m\n".utf8))
            return sha
        }

        FileHandle.standardError.write(Data("\u{1B}[33mCannot resolve PR #\(n)\u{1B}[0m\n".utf8))
        return t
    }

    /// Resolve base and head refs. Returns (base, head, diffSpec).
    private func resolveDiffSpec() -> (base: String, head: String, spec: String) {
        let base: String
        if let fromSpec = from {
            if fromSpec.contains("..") {
                let parts = fromSpec.split(separator: ".", maxSplits: 2, omittingEmptySubsequences: true)
                base = resolveRef(String(parts.first ?? "develop"))
            } else {
                base = resolveRef(fromSpec)
            }
        } else {
            base = resolveRef("develop")
        }

        let head: String
        if let fromSpec = from, fromSpec.contains("..") {
            let parts = fromSpec.split(separator: ".", maxSplits: 2, omittingEmptySubsequences: true)
            if parts.count >= 2 {
                head = resolveRef(String(parts.last!))
            } else {
                head = "HEAD"
            }
        } else {
            let resolved = resolveRef("pr\(number)")
            head = (resolved.hasPrefix("pr") || resolved.hasPrefix("#")) ? "HEAD" : resolved
        }

        return (base, head, "\(base)...\(head)")
    }

    // MARK: - Run

    func run() async throws {
        let root = gitRoot
        let (_, _, diffSpec) = resolveDiffSpec()
        let cacheDir = "\(root.path)/docs/pr\(number)-cache"
        let filesPath = "\(cacheDir)/files.json"

        // Force rebuild
        if build {
            try buildCache(diffSpec: diffSpec, cacheDir: cacheDir)
            return
        }

        // Auto-build cache if missing or diff spec changed
        if !FileManager.default.fileExists(atPath: filesPath) {
            FileHandle.standardError.write(Data("Building cache for PR #\(number)...\n".utf8))
            try buildCache(diffSpec: diffSpec, cacheDir: cacheDir)
        } else if let cacheData = FileManager.default.contents(atPath: filesPath),
                  let cache = try? JSONSerialization.jsonObject(with: cacheData) as? [String: Any],
                  let cachedSpec = cache["_diffSpec"] as? String,
                  cachedSpec != diffSpec {
            FileHandle.standardError.write(Data("Base changed (\(cachedSpec) -> \(diffSpec)), rebuilding...\n".utf8))
            try buildCache(diffSpec: diffSpec, cacheDir: cacheDir)
        }

        // Load cache
        guard FileManager.default.fileExists(atPath: filesPath) else {
            FileHandle.standardError.write(Data("No changes found for PR #\(number).\n".utf8))
            throw ExitCode.failure
        }

        let filesData = try Data(contentsOf: URL(fileURLWithPath: filesPath))
        let parsed = try JSONSerialization.jsonObject(with: filesData)
        let files: [[String: Any]]
        if let wrapper = parsed as? [String: Any], let f = wrapper["files"] as? [[String: Any]] {
            files = f
        } else if let flat = parsed as? [[String: Any]] {
            files = flat
        } else {
            throw ExitCode.failure
        }

        // Diff mode: output ordered diff for piping to delta
        if diff {
            outputOrderedDiff(files: files, diffSpec: diffSpec)
            return
        }

        // Default: JSON output to stdout
        var result: [String: Any] = [
            "pr": number,
            "diffSpec": diffSpec,
            "files": files,
        ]

        let riskPath = "\(cacheDir)/risk-map.json"
        if let riskData = FileManager.default.contents(atPath: riskPath),
           let risk = try? JSONSerialization.jsonObject(with: riskData) as? [[String: Any]] {
            result["risk"] = risk
        }

        let jsonData = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(jsonData)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    // MARK: - Ordered Diff (pipe to delta)

    private func outputOrderedDiff(files: [[String: Any]], diffSpec: String) {
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

        let header = "// PR #\(number) diff: \(diffSpec) (\(paths.count) files, architecture-ordered)\n"
        FileHandle.standardOutput.write(Data(header.utf8))

        let process = makeProcess(executable: "/usr/bin/git", arguments: ["diff", diffSpec, "--"] + paths)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        FileHandle.standardOutput.write(data)
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

    // MARK: - Build Cache

    private func buildCache(diffSpec: String, cacheDir: String) throws {
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

        let cacheData: [String: Any] = [
            "_command": "shikki pr \(number) --from \(from ?? "develop")",
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
        FileHandle.standardError.write(Data("Output: \(cacheDir)/\n".utf8))
    }
}
