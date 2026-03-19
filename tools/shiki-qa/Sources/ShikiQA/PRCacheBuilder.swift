import Foundation

// MARK: - Models

public enum FileCategory: String, Codable, Sendable {
    case source
    case test
    case docs
    case config
    case asset
    case generated
}

public struct PRFileEntry: Codable, Sendable {
    public let path: String
    public let insertions: Int
    public let deletions: Int
    public let isNew: Bool
    public let category: FileCategory

    public init(path: String, insertions: Int, deletions: Int, isNew: Bool, category: FileCategory) {
        self.path = path
        self.insertions = insertions
        self.deletions = deletions
        self.isNew = isNew
        self.category = category
    }

    public var totalChanges: Int { insertions + deletions }
}

public struct PRCacheMeta: Codable, Sendable {
    public let prNumber: Int
    public let branch: String
    public let baseBranch: String
    public let builtAt: Date
    public let fileCount: Int
    public let totalInsertions: Int
    public let totalDeletions: Int
}

// MARK: - Builder

public enum PRCacheBuilder {

    /// Parse file entries from raw `git diff` output.
    public static func parseFilesFromDiff(_ diff: String) -> [PRFileEntry] {
        guard !diff.isEmpty else { return [] }

        var files: [PRFileEntry] = []
        let lines = diff.components(separatedBy: "\n")

        var currentPath: String?
        var currentInsertions = 0
        var currentDeletions = 0
        var currentIsNew = false

        for line in lines {
            // New file header: "diff --git a/path b/path"
            if line.hasPrefix("diff --git ") {
                // Save previous file
                if let path = currentPath {
                    files.append(PRFileEntry(
                        path: path,
                        insertions: currentInsertions,
                        deletions: currentDeletions,
                        isNew: currentIsNew,
                        category: categorize(path)
                    ))
                }

                // Parse new path from "diff --git a/X b/X"
                let parts = line.components(separatedBy: " b/")
                if parts.count >= 2 {
                    currentPath = parts.last!
                } else {
                    currentPath = nil
                }
                currentInsertions = 0
                currentDeletions = 0
                currentIsNew = false
                continue
            }

            // Detect new file
            if line.hasPrefix("new file mode") {
                currentIsNew = true
                continue
            }

            // Count insertions/deletions (lines starting with +/- but not headers)
            if line.hasPrefix("+") && !line.hasPrefix("+++") {
                currentInsertions += 1
            } else if line.hasPrefix("-") && !line.hasPrefix("---") {
                currentDeletions += 1
            }
        }

        // Save last file
        if let path = currentPath {
            files.append(PRFileEntry(
                path: path,
                insertions: currentInsertions,
                deletions: currentDeletions,
                isNew: currentIsNew,
                category: categorize(path)
            ))
        }

        return files
    }

    /// Build full PR cache from git diff between two refs.
    public static func build(
        prNumber: Int,
        base: String,
        head: String,
        outputDir: String
    ) throws -> PRCacheMeta {
        // Get full diff
        let diff = try shellExec("git diff \(base)...\(head)")

        let files = parseFilesFromDiff(diff)

        // Write files.json
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let filesData = try encoder.encode(files)
        try filesData.write(to: URL(fileURLWithPath: "\(outputDir)/files.json"))

        // Write diff.md
        let diffMd = generateDiffMarkdown(diff: diff, files: files)
        try diffMd.write(toFile: "\(outputDir)/diff.md", atomically: true, encoding: .utf8)

        let meta = PRCacheMeta(
            prNumber: prNumber,
            branch: head,
            baseBranch: base,
            builtAt: Date(),
            fileCount: files.count,
            totalInsertions: files.reduce(0) { $0 + $1.insertions },
            totalDeletions: files.reduce(0) { $0 + $1.deletions }
        )

        // Write meta.json
        let metaEncoder = JSONEncoder()
        metaEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        metaEncoder.dateEncodingStrategy = .iso8601
        let metaData = try metaEncoder.encode(meta)
        try metaData.write(to: URL(fileURLWithPath: "\(outputDir)/meta.json"))

        return meta
    }

    // MARK: - Categorization

    public static func categorize(_ path: String) -> FileCategory {
        let lowered = path.lowercased()
        let filename = (path as NSString).lastPathComponent.lowercased()

        // Tests
        if lowered.contains("test") || lowered.contains("spec") {
            return .test
        }

        // Docs
        if filename.hasSuffix(".md") || filename.hasSuffix(".txt") ||
           filename.hasSuffix(".rst") || lowered.contains("docs/") ||
           lowered.contains("doc/") {
            return .docs
        }

        // Config
        if filename == "package.swift" || filename == "package.json" ||
           filename.hasSuffix(".yml") || filename.hasSuffix(".yaml") ||
           filename.hasSuffix(".toml") || filename == ".gitignore" ||
           filename.hasSuffix(".lock") || filename.hasSuffix(".resolved") {
            return .config
        }

        // Assets
        if filename.hasSuffix(".png") || filename.hasSuffix(".jpg") ||
           filename.hasSuffix(".svg") || filename.hasSuffix(".xcassets") ||
           lowered.contains("assets/") || lowered.contains("resources/") {
            return .asset
        }

        // Generated
        if lowered.contains("generated") || lowered.contains(".build/") ||
           filename.hasSuffix(".pbxproj") {
            return .generated
        }

        return .source
    }

    // MARK: - Diff Markdown

    private static func generateDiffMarkdown(diff: String, files: [PRFileEntry]) -> String {
        var md = "# PR Diff\n\n"
        md += "| File | +/- | Category |\n"
        md += "|------|-----|----------|\n"
        for f in files {
            md += "| `\(f.path)` | +\(f.insertions)/-\(f.deletions) | \(f.category.rawValue) |\n"
        }
        md += "\n---\n\n"
        md += "```diff\n\(diff)\n```\n"
        return md
    }

    // MARK: - Shell

    private static func shellExec(_ command: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        // Read data before waitUntilExit to avoid pipe buffer deadlock
        try process.run()
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return String(data: outData, encoding: .utf8) ?? ""
    }
}
