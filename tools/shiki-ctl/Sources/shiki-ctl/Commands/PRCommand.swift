import ArgumentParser
import Foundation
import ShikiCtlKit

struct PRCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pr",
        abstract: "Smart PR review output — auto-builds cache, prioritized diff, pipe-friendly"
    )

    @Argument(help: "PR number")
    var number: Int

    @Flag(name: .long, help: "Force rebuild PR cache from git diff")
    var build: Bool = false

    @Flag(name: .long, help: "Output raw JSON (for piping to jq, shiki-qa)")
    var json: Bool = false

    @Flag(name: .long, help: "Output architecture-ordered diff (pipe to delta for syntax highlight)")
    var diff: Bool = false

    @Option(name: .long, help: "Base branch for diff (default: develop)")
    var base: String = "develop"

    func run() async throws {
        let cacheDir = "docs/pr\(number)-cache"
        let filesPath = "\(cacheDir)/files.json"

        // Force rebuild
        if build {
            try buildCache()
            return
        }

        // Auto-build cache if missing
        if !FileManager.default.fileExists(atPath: filesPath) {
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

        // JSON mode: raw output for piping
        if json {
            var result: [String: Any] = ["pr": number, "files": files]
            if let r = risk { result["risk"] = r }
            let jsonData = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            FileHandle.standardOutput.write(jsonData)
            FileHandle.standardOutput.write(Data("\n".utf8))
            return
        }

        // Diff mode: architecture-ordered diff output (pipe to delta)
        if diff {
            renderOrderedDiff(files: files)
            return
        }

        // Default: smart prioritized summary for human review
        renderSmartSummary(files: files, risk: risk)
    }

    // MARK: - Ordered Diff (pipe to delta)

    private func renderOrderedDiff(files: [[String: Any]]) {
        // Sort by architecture layer
        let sorted = files.sorted { a, b in
            let pa = layerPriority(path: a["path"] as? String ?? "")
            let pb = layerPriority(path: b["path"] as? String ?? "")
            if pa != pb { return pa < pb }
            let sizeA = (a["insertions"] as? Int ?? 0) + (a["deletions"] as? Int ?? 0)
            let sizeB = (b["insertions"] as? Int ?? 0) + (b["deletions"] as? Int ?? 0)
            return sizeA > sizeB
        }

        let paths = sorted.compactMap { $0["path"] as? String }

        // Run git diff with files in architecture order
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["diff", "\(base)...HEAD", "--"] + paths
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        FileHandle.standardOutput.write(data)
    }

    // MARK: - Smart Summary (default output)

    private func renderSmartSummary(files: [[String: Any]], risk: [[String: Any]]?) {
        let totalIns = files.reduce(0) { $0 + ($1["insertions"] as? Int ?? 0) }
        let totalDel = files.reduce(0) { $0 + ($1["deletions"] as? Int ?? 0) }

        // Header
        print("\(ANSI.bold)PR #\(number)\(ANSI.reset) — \(files.count) files, \(ANSI.green)+\(totalIns)\(ANSI.reset)/\(ANSI.red)-\(totalDel)\(ANSI.reset)")
        print(String(repeating: "─", count: 56))

        // Sort by architecture layer priority
        let sorted = files.sorted { a, b in
            let pa = layerPriority(path: a["path"] as? String ?? "")
            let pb = layerPriority(path: b["path"] as? String ?? "")
            if pa != pb { return pa < pb }
            // Within same layer: largest changes first
            let sizeA = (a["insertions"] as? Int ?? 0) + (a["deletions"] as? Int ?? 0)
            let sizeB = (b["insertions"] as? Int ?? 0) + (b["deletions"] as? Int ?? 0)
            return sizeA > sizeB
        }

        // Group by layer
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
            print("  \(ANSI.green)+\(String(format: "%3d", ins))\(ANSI.reset) \(ANSI.red)-\(String(format: "%3d", del))\(ANSI.reset) \(ANSI.dim)\(sizeBar)\(ANSI.reset) \(shortPath)")
        }

        print()
        print("\(ANSI.dim)Pipe: shiki pr \(number) --json | jq '.'")
        print("Diff: shiki pr \(number) --json | delta\(ANSI.reset)")
    }

    // MARK: - Architecture Layer Sorting

    /// Priority: lower = review first
    private func layerPriority(path: String) -> Int {
        // Protocols / Interfaces
        if path.contains("Protocol") || path.contains("Interface") { return 0 }
        // Errors & Enums
        if path.contains("Error") || path.contains("Enum") || path.contains("State") { return 1 }
        // Models / DTOs
        if path.contains("Model") || path.contains("DTO") || path.contains("Entity") { return 2 }
        // Core implementations
        if path.contains("Service") || path.contains("Manager") || path.contains("Provider") || path.contains("Engine") { return 3 }
        // Pipeline / Gates
        if path.contains("Gate") || path.contains("Pipeline") || path.contains("Runner") { return 4 }
        // CLI Commands
        if path.contains("Command") { return 5 }
        // Formatters / Renderers
        if path.contains("Formatter") || path.contains("Renderer") { return 6 }
        // Config / Scripts / Docs
        if path.contains(".md") || path.contains(".json") || path.contains(".yml") || path.contains("scripts/") { return 7 }
        // Tests (last)
        if path.contains("Tests/") || path.contains("Test") { return 8 }
        // Everything else
        return 5
    }

    private func layerName(_ priority: Int) -> String {
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
        let cacheDir = "docs/pr\(number)-cache"
        try FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)

        // Run git diff --stat to get file list
        let diffStat = Process()
        diffStat.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        diffStat.arguments = ["diff", "--numstat", "\(base)...HEAD"]
        let statPipe = Pipe()
        diffStat.standardOutput = statPipe
        try diffStat.run()
        // Read pipe BEFORE waitUntilExit to prevent pipe buffer deadlock (~64KB)
        let statData = statPipe.fileHandleForReading.readDataToEndOfFile()
        diffStat.waitUntilExit()
        let statOutput = String(data: statData, encoding: .utf8) ?? ""

        // Parse numstat into JSON
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

        // Save files.json
        let encoder = JSONSerialization.self
        let filesJSON = try encoder.data(withJSONObject: files, options: [.prettyPrinted, .sortedKeys])
        try filesJSON.write(to: URL(fileURLWithPath: "\(cacheDir)/files.json"))

        // Summary to stderr (stdout is for data)
        let total = files.count
        let ins = files.reduce(0) { $0 + ($1["insertions"] as? Int ?? 0) }
        let del = files.reduce(0) { $0 + ($1["deletions"] as? Int ?? 0) }
        FileHandle.standardError.write(Data("Cache built: \(total) files, +\(ins)/-\(del)\n".utf8))
        FileHandle.standardError.write(Data("Output: \(cacheDir)/\n".utf8))
    }
}
