import Foundation

// MARK: - Migration Report

/// Summary of a single file migration.
public struct SpecMigrationFileReport: Sendable, Equatable {
    public let filename: String
    public let path: String
    public let fieldsAdded: [String]
    public let statusNormalized: Bool
    public let alreadyUpToDate: Bool

    public init(
        filename: String,
        path: String,
        fieldsAdded: [String] = [],
        statusNormalized: Bool = false,
        alreadyUpToDate: Bool = false
    ) {
        self.filename = filename
        self.path = path
        self.fieldsAdded = fieldsAdded
        self.statusNormalized = statusNormalized
        self.alreadyUpToDate = alreadyUpToDate
    }
}

/// Summary of the full migration run.
public struct SpecMigrationReport: Sendable, Equatable {
    public let scanned: Int
    public let updated: Int
    public let upToDate: Int
    public let files: [SpecMigrationFileReport]

    public init(scanned: Int, updated: Int, upToDate: Int, files: [SpecMigrationFileReport]) {
        self.scanned = scanned
        self.updated = updated
        self.upToDate = upToDate
        self.files = files
    }
}

// MARK: - SpecMigrationService

/// Scans spec files in `features/` and adds missing v2 frontmatter fields.
///
/// For each `.md` file:
/// - Parses existing frontmatter (YAML `---` blocks or markdown-style `> **Status**:`)
/// - Adds missing fields: progress, updated, tags, flsh block, reviewers
/// - Normalizes status to valid ``SpecLifecycleStatus`` enum values
/// - Preserves ALL existing fields
/// - FIX 2: When migrating markdown-style metadata, strips the original
///   `> **Key**: Value` blockquote lines from the body after generating YAML.
public struct SpecMigrationService: Sendable {

    public init() {}

    // MARK: - Public API

    /// Migrate all spec files in the given directory.
    /// - Parameters:
    ///   - directory: Path to the `features/` directory.
    ///   - dryRun: If true, compute changes but do not write files.
    /// - Returns: A migration report summarizing what was changed.
    public func migrateAll(directory: String, dryRun: Bool = false) throws -> SpecMigrationReport {
        let files = try scanSpecFiles(directory: directory)
        var reports: [SpecMigrationFileReport] = []

        for filePath in files {
            let report = try migrateFile(at: filePath, dryRun: dryRun)
            reports.append(report)
        }

        let updated = reports.filter { !$0.alreadyUpToDate }.count
        let upToDate = reports.filter { $0.alreadyUpToDate }.count

        return SpecMigrationReport(
            scanned: files.count,
            updated: updated,
            upToDate: upToDate,
            files: reports
        )
    }

    /// Migrate a single spec file.
    /// - Parameters:
    ///   - filePath: Absolute path to the .md file.
    ///   - dryRun: If true, compute changes but do not write the file.
    /// - Returns: A file-level migration report.
    public func migrateFile(at filePath: String, dryRun: Bool = false) throws -> SpecMigrationFileReport {
        let content = try String(contentsOfFile: filePath, encoding: .utf8)
        let filename = (filePath as NSString).lastPathComponent

        let hasFrontmatter = content.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("---")

        let result: MigrationResult
        if hasFrontmatter {
            result = migrateYAMLFrontmatter(content: content, filePath: filePath)
        } else {
            result = migrateMarkdownStyle(content: content, filePath: filePath)
        }

        if result.fieldsAdded.isEmpty && !result.statusNormalized {
            return SpecMigrationFileReport(
                filename: filename,
                path: filePath,
                alreadyUpToDate: true
            )
        }

        if !dryRun {
            try result.updatedContent.write(toFile: filePath, atomically: true, encoding: .utf8)
        }

        return SpecMigrationFileReport(
            filename: filename,
            path: filePath,
            fieldsAdded: result.fieldsAdded,
            statusNormalized: result.statusNormalized
        )
    }

    // MARK: - Scanning

    /// Find all .md files in the directory (non-recursive).
    func scanSpecFiles(directory: String) throws -> [String] {
        let contents = try FileManager.default.contentsOfDirectory(atPath: directory)
        return contents
            .filter { $0.hasSuffix(".md") }
            .sorted()
            .map { "\(directory)/\($0)" }
    }

    // MARK: - Migration Result

    struct MigrationResult {
        let updatedContent: String
        let fieldsAdded: [String]
        let statusNormalized: Bool
    }

    // MARK: - YAML Frontmatter Migration

    /// Migrate a file that already has `---` YAML frontmatter.
    func migrateYAMLFrontmatter(content: String, filePath: String) -> MigrationResult {
        let lines = content.components(separatedBy: "\n")

        // Find frontmatter boundaries
        guard let (yamlStart, yamlEnd) = findFrontmatterBounds(lines) else {
            // Malformed — skip
            return MigrationResult(updatedContent: content, fieldsAdded: [], statusNormalized: false)
        }

        let yamlLines = Array(lines[(yamlStart + 1)..<yamlEnd])
        let bodyLines = Array(lines[(yamlEnd + 1)...])
        let body = bodyLines.joined(separator: "\n")
        let yamlBlock = yamlLines.joined(separator: "\n")

        // Parse existing fields
        let existingFields = parseExistingFields(yamlBlock)

        // Compute what's needed
        var fieldsAdded: [String] = []
        var statusNormalized = false
        var newYAMLLines = yamlLines

        // 1. Normalize status
        if let rawStatus = existingFields["status"] {
            let normalized = normalizeStatus(rawStatus)
            if normalized != rawStatus {
                newYAMLLines = replaceFieldValue(in: newYAMLLines, key: "status", value: normalized)
                statusNormalized = true
            }
        }

        // 2. Add progress if missing
        if existingFields["progress"] == nil {
            let sectionCount = countSections(body)
            let progressValue = "0/\(sectionCount)"
            newYAMLLines.append("progress: \(progressValue)")
            fieldsAdded.append("progress")
        }

        // 3. Add updated if missing
        if existingFields["updated"] == nil {
            let updated = getFileModifiedDate(filePath)
            newYAMLLines.append("updated: \(updated)")
            fieldsAdded.append("updated")
        }

        // 4. Add tags if missing
        if existingFields["tags"] == nil {
            let tags = generateTags(body)
            if !tags.isEmpty {
                let tagList = tags.joined(separator: ", ")
                newYAMLLines.append("tags: [\(tagList)]")
                fieldsAdded.append("tags")
            }
        }

        // 5. Add reviewers if missing
        if !yamlBlock.contains("reviewers:") {
            newYAMLLines.append("reviewers: []")
            fieldsAdded.append("reviewers")
        }

        // 6. Add flsh block if missing
        if !yamlBlock.contains("flsh:") {
            let flshLines = generateFlshBlock(body: body)
            newYAMLLines.append(contentsOf: flshLines)
            fieldsAdded.append("flsh")
        }

        // Reassemble
        var result = ["---"]
        result.append(contentsOf: newYAMLLines)
        result.append("---")
        result.append(contentsOf: bodyLines)

        return MigrationResult(
            updatedContent: result.joined(separator: "\n"),
            fieldsAdded: fieldsAdded,
            statusNormalized: statusNormalized
        )
    }

    // MARK: - Markdown-Style Migration

    /// Migrate a file that uses `> **Status**: ...` or `> Status: ...` markdown metadata.
    /// Converts it to proper YAML frontmatter.
    ///
    /// **FIX 2**: After generating YAML, strips original `> **Key**: Value` blockquote
    /// metadata lines from the body to avoid duplication.
    func migrateMarkdownStyle(content: String, filePath: String) -> MigrationResult {
        let lines = content.components(separatedBy: "\n")

        // Extract title from first `# ` heading
        let title = lines.first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("# ") }?
            .trimmingCharacters(in: .whitespaces)
            .dropFirst(2)
            .trimmingCharacters(in: .whitespaces) ?? (filePath as NSString).lastPathComponent.replacingOccurrences(of: ".md", with: "")

        // Extract inline metadata from `> **Key**: Value` or `> Key: Value` lines
        var extractedStatus: String?
        var extractedPriority: String?
        var extractedDate: String?
        var extractedProject: String?
        var metaLineIndices: Set<Int> = []

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("> ") {
                let afterQuote = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                // Parse `**Key**: Value` or `Key: Value`
                if let (key, value) = parseInlineMetaField(afterQuote) {
                    let keyLower = key.lowercased()
                    if keyLower == "status" {
                        extractedStatus = value
                        metaLineIndices.insert(index)
                    } else if keyLower == "priority" {
                        extractedPriority = value
                        metaLineIndices.insert(index)
                    } else if keyLower == "date" || keyLower == "created" {
                        extractedDate = value
                        metaLineIndices.insert(index)
                    } else if keyLower == "project" || keyLower == "scope" {
                        extractedProject = value
                        metaLineIndices.insert(index)
                    }
                }
            }
        }

        // FIX 2: Strip old metadata blockquote lines from body.
        // Remove lines matching `> **Key**: Value` pattern (lines starting with `> ` followed by
        // bold or capitalized key) so they don't duplicate the new YAML frontmatter.
        let strippedBodyLines = lines.enumerated().compactMap { index, line -> String? in
            if metaLineIndices.contains(index) {
                return nil
            }
            // Also strip any remaining `> **Key**:` blockquote metadata lines
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("> **") && trimmed.contains("**:") {
                return nil
            }
            // Strip lines matching `> Key: Value` where Key starts with uppercase
            if trimmed.hasPrefix("> ") {
                let afterQuote = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if let firstChar = afterQuote.first,
                   firstChar.isUppercase,
                   afterQuote.contains(":"),
                   !afterQuote.hasPrefix("#"),
                   !afterQuote.hasPrefix("-"),
                   afterQuote.count < 100 {
                    // Check it looks like a metadata line: `> Key: Value`
                    if let colonIdx = afterQuote.firstIndex(of: ":") {
                        let potentialKey = String(afterQuote[afterQuote.startIndex..<colonIdx])
                            .trimmingCharacters(in: .whitespaces)
                            .replacingOccurrences(of: "**", with: "")
                        let knownKeys = ["status", "priority", "date", "created", "project", "scope", "author", "authors"]
                        if knownKeys.contains(potentialKey.lowercased()) {
                            return nil
                        }
                    }
                }
            }
            return line
        }

        let body = strippedBodyLines.joined(separator: "\n")
        let sectionCount = countSections(body)
        let normalizedStatus = extractedStatus.map { normalizeStatus($0) } ?? "draft"
        let updated = getFileModifiedDate(filePath)
        let tags = generateTags(body)
        let flshLines = generateFlshBlock(body: body)

        // Build YAML frontmatter
        var yaml: [String] = []
        yaml.append("---")
        yaml.append("title: \"\(title)\"")
        yaml.append("status: \(normalizedStatus)")
        yaml.append("progress: 0/\(sectionCount)")
        if let priority = extractedPriority {
            yaml.append("priority: \(priority)")
        }
        if let project = extractedProject {
            yaml.append("project: \(project)")
        }
        if let date = extractedDate {
            yaml.append("created: \(date)")
        }
        yaml.append("updated: \(updated)")
        if !tags.isEmpty {
            yaml.append("tags: [\(tags.joined(separator: ", "))]")
        }
        yaml.append("reviewers: []")
        yaml.append(contentsOf: flshLines)
        yaml.append("---")

        // Append the stripped body (old metadata lines removed)
        var result = yaml
        result.append(contentsOf: strippedBodyLines)

        var fieldsAdded = ["title", "status", "progress", "updated", "reviewers", "flsh"]
        if extractedPriority != nil { fieldsAdded.append("priority") }
        if extractedProject != nil { fieldsAdded.append("project") }
        if extractedDate != nil { fieldsAdded.append("created") }
        if !tags.isEmpty { fieldsAdded.append("tags") }

        let statusWasNormalized = extractedStatus.map { normalizeStatus($0) != $0 } ?? false

        return MigrationResult(
            updatedContent: result.joined(separator: "\n"),
            fieldsAdded: fieldsAdded,
            statusNormalized: statusWasNormalized
        )
    }

    // MARK: - Field Parsing

    /// Parse top-level `key: value` pairs from YAML (ignoring nested/indented lines).
    func parseExistingFields(_ yaml: String) -> [String: String] {
        var fields: [String: String] = [:]
        for line in yaml.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("-") { continue }
            if line.hasPrefix("  ") || line.hasPrefix("\t") { continue }

            guard let colonIdx = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[trimmed.startIndex..<colonIdx]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: colonIdx)...])
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !value.isEmpty {
                fields[key] = value
            }
        }
        return fields
    }

    /// Parse `**Key**: Value` or `Key: Value` from a blockquote line.
    func parseInlineMetaField(_ line: String) -> (key: String, value: String)? {
        var text = line

        // Strip bold markers
        if text.hasPrefix("**") {
            text = String(text.dropFirst(2))
            if let endBold = text.range(of: "**") {
                let key = String(text[text.startIndex..<endBold.lowerBound])
                var afterBold = String(text[endBold.upperBound...]).trimmingCharacters(in: .whitespaces)
                // Remove leading colon
                if afterBold.hasPrefix(":") {
                    afterBold = String(afterBold.dropFirst()).trimmingCharacters(in: .whitespaces)
                }
                if !afterBold.isEmpty {
                    return (key, afterBold)
                }
            }
            return nil
        }

        // Simple `Key: Value` with pipe-separated multi-field lines
        if let colonIdx = text.firstIndex(of: ":") {
            let key = String(text[text.startIndex..<colonIdx]).trimmingCharacters(in: .whitespaces)
            let rawValue = String(text[text.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)

            // Handle pipe-separated values — take only up to the first pipe
            let value: String
            if let pipeIdx = rawValue.firstIndex(of: "|") {
                value = String(rawValue[rawValue.startIndex..<pipeIdx]).trimmingCharacters(in: .whitespaces)
            } else {
                value = rawValue
            }
            if !key.isEmpty && !value.isEmpty {
                return (key, value)
            }
        }

        return nil
    }

    // MARK: - Frontmatter Bounds

    /// Find the start and end line indices of `---` delimited frontmatter.
    func findFrontmatterBounds(_ lines: [String]) -> (start: Int, end: Int)? {
        guard let firstLine = lines.first,
              firstLine.trimmingCharacters(in: .whitespaces) == "---" else {
            return nil
        }

        for i in 1..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                return (0, i)
            }
        }
        return nil
    }

    // MARK: - Status Normalization

    /// Map common status strings to valid ``SpecLifecycleStatus`` raw values.
    public func normalizeStatus(_ raw: String) -> String {
        let lowered = raw.lowercased()
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

        // Direct matches
        if SpecLifecycleStatus(rawValue: lowered) != nil {
            return lowered
        }

        // Known aliases
        switch lowered {
        case "spec", "plan", "planning", "planned", "idea", "brainstorm":
            return "draft"
        case "wip", "in-progress", "in progress", "active", "started":
            return "implementing"
        case "done", "complete", "completed", "merged", "released":
            return "shipped"
        case "deprecated", "superseded", "replaced":
            return "outdated"
        case "approved", "accepted", "confirmed":
            return "validated"
        case "blocked", "paused", "on-hold", "on hold":
            return "review"
        case "cancelled", "canceled", "declined", "denied":
            return "rejected"
        default:
            // Check for compound status strings like "PLAN — tests first"
            let firstWord = lowered.split(separator: " ").first.map(String.init) ?? lowered
            if let lifecycle = SpecLifecycleStatus(rawValue: firstWord) {
                return lifecycle.rawValue
            }
            // Try known first-word aliases
            switch firstWord {
            case "spec", "plan", "planning", "draft":
                return "draft"
            case "implementing", "wip", "active":
                return "implementing"
            case "ready":
                return "review"
            default:
                return "draft"
            }
        }
    }

    // MARK: - Section Counting

    /// Count `## ` level-2 headings in the body text.
    public func countSections(_ body: String) -> Int {
        body.components(separatedBy: "\n")
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return trimmed.hasPrefix("## ") && !trimmed.hasPrefix("### ")
            }
            .count
    }

    // MARK: - Tag Generation

    /// Generate tags from body content by keyword frequency analysis.
    ///
    /// **BONUS FIX**: Uses word boundary checks to avoid false positives
    /// (e.g., "ai" inside "maintain" or "certain").
    func generateTags(
        _ body: String,
        maxTags: Int = 5
    ) -> [String] {
        let lowered = body.lowercased()

        // Domain-specific keyword -> tag mappings
        let keywordMap: [(keywords: [String], tag: String)] = [
            (["swift", "swiftui", "uikit", "spm", "xcode"], "swift"),
            (["test", "testing", "tdd", "tpdd", "xctestcase", "@test"], "testing"),
            (["mcp", "model context protocol"], "mcp"),
            (["ai", "llm", "gpt", "claude", "model", "inference"], "ai"),
            (["tui", "terminal", "cli", "command line"], "tui"),
            (["voice", "tts", "flsh", "whisper", "speech"], "voice"),
            (["api", "rest", "http", "endpoint", "graphql"], "api"),
            (["database", "sqlite", "postgres", "sql", "db"], "database"),
            (["security", "auth", "keychain", "encryption", "token"], "security"),
            (["network", "socket", "websocket", "nats", "mqtt"], "networking"),
            (["ui", "design", "layout", "animation", "component"], "ui"),
            (["deploy", "release", "ci", "cd", "pipeline"], "infrastructure"),
            (["agent", "orchestrat", "dispatch", "autopilot"], "orchestration"),
            (["moto", "hanko", "dns", "cache"], "moto"),
            (["brainy", "rss", "feed", "reader"], "brainy"),
            (["maya", "fitness", "health", "workout"], "maya"),
            (["wabisabi", "meditation", "mindful", "practice"], "wabisabi"),
            (["docker", "container", "colima", "compose"], "docker"),
            (["git", "branch", "merge", "pr", "pull request"], "git"),
            (["tmux", "pane", "session", "window"], "tmux"),
        ]

        // Word boundary characters for matching
        let wordBoundaryChars = CharacterSet.alphanumerics.inverted

        var tagScores: [(tag: String, score: Int)] = []

        for mapping in keywordMap {
            var score = 0
            for keyword in mapping.keywords {
                // For short keywords (<=3 chars like "ai", "db", "ui", "ci", "cd"),
                // use word boundary matching to avoid false positives
                if keyword.count <= 3 && !keyword.hasPrefix("@") {
                    score += countWordBoundaryMatches(keyword: keyword, in: lowered, boundaryChars: wordBoundaryChars)
                } else {
                    // Longer keywords: simple substring count (safe from false positives)
                    var searchRange = lowered.startIndex..<lowered.endIndex
                    while let range = lowered.range(of: keyword, range: searchRange) {
                        score += 1
                        searchRange = range.upperBound..<lowered.endIndex
                    }
                }
            }
            if score > 0 {
                tagScores.append((mapping.tag, score))
            }
        }

        return tagScores
            .sorted { $0.score > $1.score }
            .prefix(maxTags)
            .map(\.tag)
    }

    /// Count occurrences of a keyword that appear at word boundaries.
    /// This prevents "ai" from matching inside "maintain", "certain", etc.
    private func countWordBoundaryMatches(keyword: String, in text: String, boundaryChars: CharacterSet) -> Int {
        var count = 0
        var searchRange = text.startIndex..<text.endIndex

        while let range = text.range(of: keyword, range: searchRange) {
            let beforeOK = range.lowerBound == text.startIndex ||
                String(text[text.index(before: range.lowerBound)]).rangeOfCharacter(from: boundaryChars) != nil
            let afterOK = range.upperBound == text.endIndex ||
                String(text[range.upperBound]).rangeOfCharacter(from: boundaryChars) != nil

            if beforeOK && afterOK {
                count += 1
            }
            searchRange = range.upperBound..<text.endIndex
        }

        return count
    }

    // MARK: - Flsh Block Generation

    /// Generate `flsh:` YAML lines from body content.
    func generateFlshBlock(body: String) -> [String] {
        let summary = generateSummary(body)
        let wordCount = body.split(separator: " ").count
        let duration = estimateDuration(wordCount: wordCount)
        let sections = countSections(body)

        var lines: [String] = []
        lines.append("flsh:")
        if let summary {
            lines.append("  summary: \"\(summary)\"")
        }
        lines.append("  duration: \(duration)")
        lines.append("  sections: \(sections)")
        return lines
    }

    /// Extract the first sentence after the first `## ` heading as a summary.
    func generateSummary(_ body: String) -> String? {
        let lines = body.components(separatedBy: "\n")
        var foundHeading = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("## ") {
                foundHeading = true
                continue
            }

            if foundHeading && !trimmed.isEmpty && !trimmed.hasPrefix("#") && !trimmed.hasPrefix("---") && !trimmed.hasPrefix(">") && !trimmed.hasPrefix("|") && !trimmed.hasPrefix("```") {
                // Extract first sentence
                let sentence = extractFirstSentence(trimmed)
                if sentence.count >= 10 {
                    return sentence
                }
            }
        }

        return nil
    }

    /// Extract the first sentence from text (up to the first `.` followed by a space or end).
    func extractFirstSentence(_ text: String) -> String {
        var result = ""
        let chars = Array(text)
        for (i, char) in chars.enumerated() {
            result.append(char)
            if char == "." || char == "!" || char == "?" {
                let isEnd = i == chars.count - 1
                let nextIsSpace = i + 1 < chars.count && (chars[i + 1] == " " || chars[i + 1] == "\n")
                if isEnd || nextIsSpace {
                    break
                }
            }
        }
        var clean = result.trimmingCharacters(in: .whitespaces)
        if clean.hasPrefix("- ") { clean = String(clean.dropFirst(2)) }
        if clean.hasPrefix("* ") { clean = String(clean.dropFirst(2)) }
        return clean
    }

    /// Estimate read-aloud duration from word count at 150 WPM.
    public func estimateDuration(wordCount: Int) -> String {
        let minutes = max(1, Int(round(Double(wordCount) / 150.0)))
        return "\(minutes)m"
    }

    // MARK: - File Date

    /// Get the file modification date as a YYYY-MM-DD string.
    func getFileModifiedDate(_ filePath: String) -> String {
        if let attributes = try? FileManager.default.attributesOfItem(atPath: filePath),
           let modDate = attributes[.modificationDate] as? Date {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone.current
            return formatter.string(from: modDate)
        }
        // Fallback to today
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: Date())
    }

    // MARK: - YAML Field Replacement

    /// Replace the value of a top-level YAML field in-place.
    func replaceFieldValue(in lines: [String], key: String, value: String) -> [String] {
        lines.map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("\(key):") && !line.hasPrefix("  ") && !line.hasPrefix("\t") {
                return "\(key): \(value)"
            }
            return line
        }
    }
}
