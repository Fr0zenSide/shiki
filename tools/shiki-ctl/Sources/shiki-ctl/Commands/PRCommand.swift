import ArgumentParser
import Foundation
import ShikiCtlKit

struct PRCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pr",
        abstract: "Output PR cache data as JSON — pipe to delta, jq, or shiki-qa"
    )

    @Argument(help: "PR number (reads from docs/pr<N>-cache/)")
    var number: Int

    @Flag(name: .long, help: "Build/rebuild PR cache from git diff")
    var build: Bool = false

    @Option(name: .long, help: "Base branch for diff (default: develop)")
    var base: String = "develop"

    func run() async throws {
        if build {
            try buildCache()
            return
        }

        // Load cache and output as JSON to stdout
        let cacheDir = "docs/pr\(number)-cache"
        let filesPath = "\(cacheDir)/files.json"
        let riskPath = "\(cacheDir)/risk-map.json"

        guard FileManager.default.fileExists(atPath: filesPath) else {
            FileHandle.standardError.write(Data("No cache for PR #\(number). Run: shiki pr \(number) --build\n".utf8))
            throw ExitCode.failure
        }

        var result: [String: Any] = ["pr": number]

        let filesData = try Data(contentsOf: URL(fileURLWithPath: filesPath))
        if let files = try JSONSerialization.jsonObject(with: filesData) as? [[String: Any]] {
            result["files"] = files
        }

        if let riskData = FileManager.default.contents(atPath: riskPath),
           let risk = try JSONSerialization.jsonObject(with: riskData) as? [[String: Any]] {
            result["risk"] = risk
        }

        let json = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(json)
        FileHandle.standardOutput.write(Data("\n".utf8))
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
        diffStat.waitUntilExit()

        let statData = statPipe.fileHandleForReading.readDataToEndOfFile()
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
