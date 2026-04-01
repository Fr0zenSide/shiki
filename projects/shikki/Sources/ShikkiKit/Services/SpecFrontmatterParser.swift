import Foundation

/// Errors from frontmatter parsing.
public enum SpecFrontmatterError: Error, LocalizedError, Sendable {
    case noFrontmatter
    case invalidStatus(String)
    case invalidProgressFormat(String)
    case invalidAnchor(String)
    case malformedYAML(String)

    public var errorDescription: String? {
        switch self {
        case .noFrontmatter:
            return "No YAML frontmatter found (expected --- delimiters)"
        case .invalidStatus(let value):
            return "Invalid lifecycle status: '\(value)'"
        case .invalidProgressFormat(let value):
            return "Invalid progress format: '\(value)' (expected N/M)"
        case .invalidAnchor(let value):
            return "Invalid anchor: '\(value)' (must start with #)"
        case .malformedYAML(let detail):
            return "Malformed YAML: \(detail)"
        }
    }
}

/// Parses enhanced YAML frontmatter from spec markdown files.
///
/// Extracts all ``SpecMetadata`` fields from the YAML block between `---` delimiters,
/// counts `##` headings in the body for `totalSections`, and validates formats.
///
/// Uses the canonical W2 types: ``SpecLifecycleStatus``, ``SpecReviewer``,
/// ``SpecReviewerVerdict``, ``SpecFlshBlock``.
public struct SpecFrontmatterParser: Sendable {

    public init() {}

    /// Parse a spec file at the given path.
    public func parse(filePath: String) throws -> SpecMetadata {
        guard FileManager.default.fileExists(atPath: filePath) else {
            throw SpecFrontmatterError.noFrontmatter
        }
        let content = try String(contentsOfFile: filePath, encoding: .utf8)
        return try parse(content: content)
    }

    /// Parse spec content directly.
    public func parse(content: String) throws -> SpecMetadata {
        let (yaml, body) = try extractFrontmatter(content)
        let fields = parseYAMLFields(yaml)
        let totalSections = countSections(body)

        // Required: title
        guard let title = fields["title"]?.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) else {
            throw SpecFrontmatterError.malformedYAML("missing required field: title")
        }

        // Status (required, validated)
        let statusRaw = fields["status"]?.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) ?? "draft"
        guard let status = SpecLifecycleStatus(rawValue: statusRaw) else {
            throw SpecFrontmatterError.invalidStatus(statusRaw)
        }

        // Progress (optional, format N/M)
        let progress = fields["progress"]?.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        if let progress {
            try validateProgress(progress)
        }

        // Simple string fields
        let priority = fields["priority"]?.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        let project = fields["project"]?.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        let created = fields["created"]?.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        let updated = fields["updated"]?.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        let authors = fields["authors"]?.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

        // Array fields
        let dependsOn = parseArrayField(yaml, key: "depends-on")
        let relatesTo = parseArrayField(yaml, key: "relates-to")
        let tags = parseInlineTags(fields["tags"])

        // Reviewers (complex nested array)
        let reviewers = try parseReviewers(yaml)

        // Flsh block
        let flsh = parseFlshBlock(yaml)

        return SpecMetadata(
            title: title,
            status: status,
            progress: progress,
            priority: priority,
            project: project,
            created: created,
            updated: updated,
            authors: authors,
            reviewers: reviewers,
            dependsOn: dependsOn.isEmpty ? nil : dependsOn,
            relatesTo: relatesTo.isEmpty ? nil : relatesTo,
            tags: tags.isEmpty ? nil : tags,
            flsh: flsh,
            totalSections: totalSections
        )
    }

    // MARK: - Frontmatter Extraction

    /// Extract YAML between `---` delimiters and the remaining body.
    func extractFrontmatter(_ content: String) throws -> (yaml: String, body: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("---") else {
            throw SpecFrontmatterError.noFrontmatter
        }

        // Find the closing ---
        let afterFirst = trimmed.index(trimmed.startIndex, offsetBy: 3)
        let rest = String(trimmed[afterFirst...])

        // Find second --- (must be on its own line)
        let lines = rest.components(separatedBy: "\n")
        var yamlLines: [String] = []
        var foundEnd = false
        var bodyStartIndex = 0

        for (index, line) in lines.enumerated() {
            let stripped = line.trimmingCharacters(in: .whitespaces)
            if stripped == "---" && index > 0 {
                foundEnd = true
                bodyStartIndex = index + 1
                break
            }
            yamlLines.append(line)
        }

        guard foundEnd else {
            throw SpecFrontmatterError.noFrontmatter
        }

        let yaml = yamlLines.joined(separator: "\n")
        let body = lines[bodyStartIndex...].joined(separator: "\n")
        return (yaml, body)
    }

    // MARK: - Simple YAML Parsing

    /// Parse top-level key: value pairs from YAML (no nested support here).
    func parseYAMLFields(_ yaml: String) -> [String: String] {
        var fields: [String: String] = [:]
        let lines = yaml.components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Skip empty, comments, array items, nested keys
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("-") { continue }
            // Must be a top-level key (no leading whitespace beyond trivial)
            if line.hasPrefix("  ") || line.hasPrefix("\t") { continue }

            guard let colonIndex = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[trimmed.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
            if !value.isEmpty {
                fields[key] = value
            }
        }

        return fields
    }

    // MARK: - Array Fields

    /// Parse a YAML array field with `- item` entries under a key.
    func parseArrayField(_ yaml: String, key: String) -> [String] {
        var results: [String] = []
        let lines = yaml.components(separatedBy: "\n")
        var capturing = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("\(key):") {
                // Check for inline value
                let afterColon = trimmed.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)
                if !afterColon.isEmpty && !afterColon.hasPrefix("[") {
                    // Single value on same line
                    results.append(afterColon.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")))
                }
                capturing = true
                continue
            }

            if capturing {
                if trimmed.hasPrefix("- ") {
                    let value = String(trimmed.dropFirst(2))
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    results.append(value)
                } else if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                    // Hit a non-array line — stop capturing
                    capturing = false
                }
            }
        }

        return results
    }

    // MARK: - Inline Tags

    /// Parse `[tag1, tag2, tag3]` inline array format.
    func parseInlineTags(_ raw: String?) -> [String] {
        guard let raw, !raw.isEmpty else { return [] }
        let stripped = raw
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .trimmingCharacters(in: .whitespaces)
        guard !stripped.isEmpty else { return [] }
        return stripped.components(separatedBy: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
              .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
    }

    // MARK: - Reviewers

    /// Parse the `reviewers:` nested array block.
    /// Returns ``[SpecReviewer]`` using the canonical W2 type.
    func parseReviewers(_ yaml: String) throws -> [SpecReviewer] {
        var entries: [SpecReviewer] = []
        let lines = yaml.components(separatedBy: "\n")
        var inReviewers = false
        var currentEntry: [String: String] = [:]
        var currentSectionsValidated: [Int] = []
        var currentSectionsRework: [Int] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Detect start of reviewers block
            if trimmed == "reviewers:" || trimmed.hasPrefix("reviewers:") {
                inReviewers = true
                continue
            }

            guard inReviewers else { continue }

            // Detect we've left the reviewers block (non-indented, non-empty line that's a top-level key)
            if !line.hasPrefix(" ") && !line.hasPrefix("\t") && !trimmed.isEmpty && trimmed.contains(":") {
                // Save current entry if any
                if let entry = try buildReviewerEntry(currentEntry, sectionsValidated: currentSectionsValidated, sectionsRework: currentSectionsRework) {
                    entries.append(entry)
                }
                inReviewers = false
                continue
            }

            // New reviewer entry starts with `- who:`
            if trimmed.hasPrefix("- who:") {
                // Save previous entry
                if let entry = try buildReviewerEntry(currentEntry, sectionsValidated: currentSectionsValidated, sectionsRework: currentSectionsRework) {
                    entries.append(entry)
                }
                currentEntry = [:]
                currentSectionsValidated = []
                currentSectionsRework = []
                let value = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                currentEntry["who"] = value
                continue
            }

            // Parse nested fields within a reviewer entry
            if inReviewers && !trimmed.isEmpty && !trimmed.hasPrefix("-") && !trimmed.hasPrefix("#") {
                if let colonIdx = trimmed.firstIndex(of: ":") {
                    let key = String(trimmed[trimmed.startIndex..<colonIdx]).trimmingCharacters(in: .whitespaces)
                    let value = String(trimmed[trimmed.index(after: colonIdx)...])
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

                    if key == "sections_validated" {
                        currentSectionsValidated = parseIntArray(value)
                    } else if key == "sections_rework" {
                        currentSectionsRework = parseIntArray(value)
                    } else {
                        currentEntry[key] = value
                    }
                }
            }
        }

        // Capture final entry
        if inReviewers, let entry = try buildReviewerEntry(currentEntry, sectionsValidated: currentSectionsValidated, sectionsRework: currentSectionsRework) {
            entries.append(entry)
        }

        return entries
    }

    /// Build a ``SpecReviewer`` from parsed key-value pairs.
    private func buildReviewerEntry(
        _ fields: [String: String],
        sectionsValidated: [Int],
        sectionsRework: [Int]
    ) throws -> SpecReviewer? {
        guard let who = fields["who"], !who.isEmpty else { return nil }

        let dateValue = fields["date"]
        let date: String? = (dateValue == "null" || dateValue == nil || dateValue?.isEmpty == true) ? nil : dateValue

        let verdictRaw = fields["verdict"] ?? "pending"
        guard let verdict = SpecReviewerVerdict(rawValue: verdictRaw) else {
            return SpecReviewer(who: who, verdict: .pending)
        }

        let anchorValue = fields["anchor"]
        let anchor: String? = (anchorValue == "null" || anchorValue == nil || anchorValue?.isEmpty == true) ? nil : anchorValue

        // Validate anchor format
        if let anchor, !anchor.isEmpty {
            guard anchor.hasPrefix("#") else {
                throw SpecFrontmatterError.invalidAnchor(anchor)
            }
        }

        let notesValue = fields["notes"]
        let notes: String? = (notesValue == nil || notesValue?.isEmpty == true) ? nil : notesValue

        return SpecReviewer(
            who: who,
            date: date,
            verdict: verdict,
            anchor: anchor,
            sectionsValidated: sectionsValidated.isEmpty ? nil : sectionsValidated,
            sectionsRework: sectionsRework.isEmpty ? nil : sectionsRework,
            notes: notes
        )
    }

    /// Parse `[1, 2, 3]` inline integer array.
    private func parseIntArray(_ raw: String) -> [Int] {
        let stripped = raw.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        guard !stripped.isEmpty else { return [] }
        return stripped.components(separatedBy: ",").compactMap {
            Int($0.trimmingCharacters(in: .whitespaces))
        }
    }

    // MARK: - Flsh Block

    /// Parse the `flsh:` nested block. Returns ``SpecFlshBlock`` (canonical W2 type).
    /// Note: ``SpecFlshBlock.summary`` is non-optional — defaults to empty string if missing.
    func parseFlshBlock(_ yaml: String) -> SpecFlshBlock? {
        let lines = yaml.components(separatedBy: "\n")
        var inFlsh = false
        var summary: String?
        var duration: String?
        var sections: Int?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed == "flsh:" || trimmed.hasPrefix("flsh:") {
                inFlsh = true
                continue
            }

            guard inFlsh else { continue }

            // Left the flsh block
            if !line.hasPrefix(" ") && !line.hasPrefix("\t") && !trimmed.isEmpty && trimmed.contains(":") {
                break
            }

            if let colonIdx = trimmed.firstIndex(of: ":") {
                let key = String(trimmed[trimmed.startIndex..<colonIdx]).trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[trimmed.index(after: colonIdx)...])
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

                switch key {
                case "summary": summary = value
                case "duration": duration = value
                case "sections": sections = Int(value)
                default: break
                }
            }
        }

        guard inFlsh else { return nil }
        // SpecFlshBlock.summary is non-optional; require it or return nil
        guard let summary else {
            if duration == nil && sections == nil { return nil }
            // If we have duration/sections but no summary, provide default
            return SpecFlshBlock(summary: "", duration: duration, sections: sections)
        }
        return SpecFlshBlock(summary: summary, duration: duration, sections: sections)
    }

    // MARK: - Section Counting

    /// Count `## ` level-2 headings in the markdown body.
    func countSections(_ body: String) -> Int {
        let lines = body.components(separatedBy: "\n")
        return lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("## ") && !trimmed.hasPrefix("### ")
        }.count
    }

    // MARK: - Validation

    /// Validate progress format is "N/M" where N and M are non-negative integers and N <= M.
    func validateProgress(_ progress: String) throws {
        let parts = progress.split(separator: "/")
        guard parts.count == 2,
              let n = Int(parts[0]),
              let m = Int(parts[1]),
              n >= 0, m >= 0, n <= m
        else {
            throw SpecFrontmatterError.invalidProgressFormat(progress)
        }
    }
}
