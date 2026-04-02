import Foundation

// MARK: - SpecFrontmatterService

/// Parses and writes YAML frontmatter in spec markdown files.
///
/// Handles the enhanced frontmatter format from Spec Metadata v2:
/// - Lifecycle status, progress, reviewers, anchors
/// - In-place YAML updates preserving file content
/// - Section counting from markdown headings
public struct SpecFrontmatterService: Sendable {

    public init() {}

    // MARK: - Parsing

    /// Parse spec metadata from a markdown file's YAML frontmatter.
    /// Returns nil if no valid frontmatter block is found.
    public func parse(content: String, filename: String? = nil) -> SpecMetadata? {
        guard let yamlBlock = extractFrontmatter(from: content) else { return nil }
        return parseYAML(yamlBlock, filename: filename)
    }

    /// Parse spec metadata from a file path.
    public func parse(fileAt path: String) -> SpecMetadata? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let filename = (path as NSString).lastPathComponent
        return parse(content: content, filename: filename)
    }

    /// Count the number of `## ` headings (sections) in a markdown file.
    public func countSections(in content: String) -> Int {
        SpecCommandUtilities.countSections(in: content)
    }

    /// Find the line number of a heading anchor in a markdown file.
    /// Anchor format: `#8-tui-output` maps to `## 8. TUI Output`.
    /// Returns 1-indexed line number, or nil if not found.
    public func findAnchorLine(in content: String, anchor: String) -> Int? {
        let slug = anchor.hasPrefix("#") ? String(anchor.dropFirst()) : anchor
        let lines = content.components(separatedBy: "\n")

        for (index, line) in lines.enumerated() {
            guard line.hasPrefix("## ") || line.hasPrefix("# ") else { continue }
            let heading = line.drop(while: { $0 == "#" || $0 == " " })
            let headingSlug = slugifyHeading(String(heading))
            if headingSlug == slug {
                return index + 1
            }
        }
        return nil
    }

    // MARK: - Writing

    /// Update the frontmatter of a spec file in place.
    /// Returns the updated file content.
    public func updateFrontmatter(in content: String, with metadata: SpecMetadata) -> String {
        let yamlString = serializeToYAML(metadata)
        let newFrontmatter = "---\n\(yamlString)---"

        // Check if file already has frontmatter
        if let range = frontmatterRange(in: content) {
            var result = content
            result.replaceSubrange(range, with: newFrontmatter)
            return result
        } else {
            // Prepend frontmatter
            return newFrontmatter + "\n\n" + content
        }
    }

    /// Update a specific field in the frontmatter without rewriting the entire block.
    /// This preserves formatting and comments.
    public func updateField(in content: String, key: String, value: String) -> String {
        guard let fmRange = frontmatterRange(in: content) else {
            return content
        }

        let frontmatter = String(content[fmRange])
        let lines = frontmatter.components(separatedBy: "\n")
        var updatedLines: [String] = []
        var found = false

        for line in lines {
            if line.hasPrefix("\(key):") {
                updatedLines.append("\(key): \(value)")
                found = true
            } else {
                updatedLines.append(line)
            }
        }

        if !found {
            // Insert before closing ---
            if let lastDashIndex = updatedLines.lastIndex(of: "---") {
                updatedLines.insert("\(key): \(value)", at: lastDashIndex)
            }
        }

        var result = content
        result.replaceSubrange(fmRange, with: updatedLines.joined(separator: "\n"))
        return result
    }

    // MARK: - Scan

    /// Scan a features directory and return metadata for all spec files.
    public func scanDirectory(_ directoryPath: String) -> [SpecMetadata] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: directoryPath) else { return [] }

        return files
            .filter { $0.hasSuffix(".md") }
            .sorted()
            .compactMap { filename -> SpecMetadata? in
                let path = "\(directoryPath)/\(filename)"
                guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }

                var metadata = parse(content: content, filename: filename)

                // If no frontmatter, create a minimal metadata from the file
                if metadata == nil {
                    let title = extractFirstHeading(from: content) ?? filename
                    let sectionCount = countSections(in: content)
                    metadata = SpecMetadata(
                        title: title,
                        status: .draft,
                        progress: "0/\(sectionCount)",
                        filename: filename
                    )
                }

                return metadata
            }
    }

    // MARK: - Private: Frontmatter Extraction

    /// Extract the raw YAML frontmatter block (excluding delimiters).
    func extractFrontmatter(from content: String) -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("---") else { return nil }

        let afterOpening = trimmed.dropFirst(3).drop(while: { $0 == "\n" || $0 == "\r" })
        guard let closingRange = afterOpening.range(of: "\n---") else { return nil }

        return String(afterOpening[afterOpening.startIndex..<closingRange.lowerBound])
    }

    /// Get the range of the entire frontmatter block (including delimiters) in the content.
    func frontmatterRange(in content: String) -> Range<String.Index>? {
        let trimmedStart = content.startIndex
        guard content[trimmedStart...].hasPrefix("---") else { return nil }

        let afterOpening = content.index(trimmedStart, offsetBy: 3)
        let rest = content[afterOpening...]
        guard let closingMatch = rest.range(of: "\n---") else { return nil }

        let end = content.index(closingMatch.upperBound, offsetBy: 0)
        return trimmedStart..<end
    }

    // MARK: - Private: YAML Parsing (lightweight, no external dependency)

    /// Parse a simplified YAML frontmatter block into SpecMetadata.
    /// This handles the specific subset of YAML used in spec files.
    func parseYAML(_ yaml: String, filename: String? = nil) -> SpecMetadata? {
        let lines = yaml.components(separatedBy: "\n")
        var dict: [String: Any] = [:]
        var currentKey: String?
        var currentArray: [Any] = []
        var inArray = false
        var arrayItemDict: [String: String]?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            // Check for array item with key-value pairs (e.g., "  - who: @Daimyo")
            if trimmed.hasPrefix("- ") && currentKey != nil {
                // Save previous array item dict if any
                if let itemDict = arrayItemDict {
                    currentArray.append(itemDict)
                    arrayItemDict = nil
                }

                let itemContent = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)

                // Check if this is a key-value item
                if let colonIdx = itemContent.firstIndex(of: ":"),
                   colonIdx != itemContent.startIndex {
                    let key = String(itemContent[..<colonIdx]).trimmingCharacters(in: .whitespaces)
                    let value = cleanYAMLValue(String(itemContent[itemContent.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces))
                    arrayItemDict = [key: value]
                } else {
                    // Simple array item (e.g., "  - testing")
                    if !inArray {
                        inArray = true
                        currentArray = []
                    }
                    currentArray.append(cleanYAMLValue(itemContent))
                }
                continue
            }

            // Check for continuation of array item dict (e.g., "    date: 2026-03-31")
            if arrayItemDict != nil && (line.hasPrefix("    ") || line.hasPrefix("\t")) && !trimmed.hasPrefix("-") {
                if let colonIdx = trimmed.firstIndex(of: ":"),
                   colonIdx != trimmed.startIndex {
                    let key = String(trimmed[..<colonIdx]).trimmingCharacters(in: .whitespaces)
                    let rawValue = String(trimmed[trimmed.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                    arrayItemDict?[key] = cleanYAMLValue(rawValue)
                }
                continue
            }

            // Save pending state
            if let key = currentKey {
                if let itemDict = arrayItemDict {
                    currentArray.append(itemDict)
                    arrayItemDict = nil
                }
                if inArray || !currentArray.isEmpty {
                    dict[key] = currentArray
                    currentArray = []
                    inArray = false
                }
            }

            // Top-level key: value
            if let colonIdx = trimmed.firstIndex(of: ":"),
               colonIdx != trimmed.startIndex,
               !trimmed.hasPrefix("-") {
                let key = String(trimmed[..<colonIdx]).trimmingCharacters(in: .whitespaces)
                let rawValue = String(trimmed[trimmed.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)

                if rawValue.isEmpty {
                    // Might be start of array or block
                    currentKey = key
                    currentArray = []
                    inArray = false
                } else if rawValue.hasPrefix("[") && rawValue.hasSuffix("]") {
                    // Inline array: [testing, infrastructure]
                    let inner = rawValue.dropFirst().dropLast()
                    let items = inner.split(separator: ",").map {
                        cleanYAMLValue(String($0).trimmingCharacters(in: .whitespaces))
                    }
                    dict[key] = items
                    currentKey = nil
                } else {
                    dict[key] = cleanYAMLValue(rawValue)
                    currentKey = nil
                }
            }
        }

        // Flush remaining state
        if let key = currentKey {
            if let itemDict = arrayItemDict {
                currentArray.append(itemDict)
            }
            if !currentArray.isEmpty {
                dict[key] = currentArray
            }
        }

        // Build SpecMetadata from dict
        guard let title = dict["title"] as? String else { return nil }
        let statusStr = (dict["status"] as? String) ?? "draft"
        let status = SpecLifecycleStatus(rawValue: statusStr) ?? .draft

        var reviewers: [SpecReviewer] = []
        if let reviewerDicts = dict["reviewers"] as? [[String: String]] {
            for rd in reviewerDicts {
                guard let who = rd["who"] else { continue }
                let verdictStr = rd["verdict"] ?? "pending"
                let verdict = SpecReviewerVerdict(rawValue: verdictStr) ?? .pending
                let anchor = rd["anchor"]
                let date = rd["date"]
                let notes = rd["notes"]

                var sectionsValidated: [Int]?
                if let sv = rd["sections_validated"] {
                    sectionsValidated = parseInlineIntArray(sv)
                }

                var sectionsRework: [Int]?
                if let sr = rd["sections_rework"] {
                    sectionsRework = parseInlineIntArray(sr)
                }

                reviewers.append(SpecReviewer(
                    who: who,
                    date: date == "null" ? nil : date,
                    verdict: verdict,
                    anchor: anchor == "null" ? nil : anchor,
                    sectionsValidated: sectionsValidated,
                    sectionsRework: sectionsRework,
                    notes: notes
                ))
            }
        }

        var flsh: SpecFlshBlock?
        if let flshDict = dict["flsh"] as? [String: String] {
            if let summary = flshDict["summary"] {
                let duration = flshDict["duration"]
                let sections = flshDict["sections"].flatMap { Int($0) }
                flsh = SpecFlshBlock(summary: summary, duration: duration, sections: sections)
            }
        }

        let dependsOn = dict["depends-on"] as? [String]
        let relatesTo = dict["relates-to"] as? [String]
        let tags = dict["tags"] as? [String]

        // Tracking fields
        let epicBranch = dict["epic-branch"] as? String
        let validatedCommit = dict["validated-commit"] as? String
        let testRunId = dict["test-run-id"] as? String

        return SpecMetadata(
            title: title,
            status: status,
            progress: dict["progress"] as? String,
            priority: dict["priority"] as? String,
            project: dict["project"] as? String,
            created: dict["created"] as? String,
            updated: dict["updated"] as? String,
            authors: dict["authors"] as? String,
            reviewers: reviewers,
            dependsOn: dependsOn,
            relatesTo: relatesTo,
            tags: tags,
            flsh: flsh,
            epicBranch: epicBranch,
            validatedCommit: validatedCommit,
            testRunId: testRunId,
            filename: filename
        )
    }

    // MARK: - Private: YAML Serialization

    /// Serialize SpecMetadata to YAML frontmatter string (without --- delimiters).
    func serializeToYAML(_ metadata: SpecMetadata) -> String {
        var lines: [String] = []

        let escapedTitle = SpecCommandUtilities.escapeYAML(metadata.title)
        lines.append("title: \"\(escapedTitle)\"")
        lines.append("status: \(metadata.status.rawValue)")

        if let progress = metadata.progress {
            lines.append("progress: \(progress)")
        }
        if let priority = metadata.priority {
            lines.append("priority: \(priority)")
        }
        if let project = metadata.project {
            lines.append("project: \(project)")
        }
        if let created = metadata.created {
            lines.append("created: \(created)")
        }
        if let updated = metadata.updated {
            lines.append("updated: \(updated)")
        }
        if let authors = metadata.authors {
            lines.append("authors: \"\(SpecCommandUtilities.escapeYAML(authors))\"")
        }

        if let epicBranch = metadata.epicBranch {
            lines.append("epic-branch: \(epicBranch)")
        }
        if let validatedCommit = metadata.validatedCommit {
            lines.append("validated-commit: \(validatedCommit)")
        }
        if let testRunId = metadata.testRunId {
            lines.append("test-run-id: \(testRunId)")
        }

        if !metadata.reviewers.isEmpty {
            lines.append("reviewers:")
            for reviewer in metadata.reviewers {
                lines.append("  - who: \"\(SpecCommandUtilities.escapeYAML(reviewer.who))\"")
                lines.append("    date: \(reviewer.date ?? "null")")
                lines.append("    verdict: \(reviewer.verdict.rawValue)")
                lines.append("    anchor: \(reviewer.anchor ?? "null")")
                if let notes = reviewer.notes {
                    lines.append("    notes: \"\(SpecCommandUtilities.escapeYAML(notes))\"")
                }
                if let sv = reviewer.sectionsValidated {
                    lines.append("    sections_validated: [\(sv.map(String.init).joined(separator: ", "))]")
                }
                if let sr = reviewer.sectionsRework {
                    lines.append("    sections_rework: [\(sr.map(String.init).joined(separator: ", "))]")
                }
            }
        }

        if let deps = metadata.dependsOn, !deps.isEmpty {
            lines.append("depends-on:")
            for dep in deps {
                lines.append("  - \(dep)")
            }
        }
        if let rels = metadata.relatesTo, !rels.isEmpty {
            lines.append("relates-to:")
            for rel in rels {
                lines.append("  - \(rel)")
            }
        }
        if let tags = metadata.tags, !tags.isEmpty {
            lines.append("tags: [\(tags.joined(separator: ", "))]")
        }

        if let flsh = metadata.flsh {
            lines.append("flsh:")
            lines.append("  summary: \"\(SpecCommandUtilities.escapeYAML(flsh.summary))\"")
            if let duration = flsh.duration {
                lines.append("  duration: \(duration)")
            }
            if let sections = flsh.sections {
                lines.append("  sections: \(sections)")
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Private Helpers

    private func cleanYAMLValue(_ raw: String) -> String {
        var value = raw
        // Remove surrounding quotes
        if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
           (value.hasPrefix("'") && value.hasSuffix("'")) {
            value = String(value.dropFirst().dropLast())
        }
        return value
    }

    private func parseInlineIntArray(_ raw: String) -> [Int] {
        var cleaned = raw
        if cleaned.hasPrefix("[") { cleaned = String(cleaned.dropFirst()) }
        if cleaned.hasSuffix("]") { cleaned = String(cleaned.dropLast()) }
        return cleaned.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }

    private func extractFirstHeading(from content: String) -> String? {
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    func slugifyHeading(_ heading: String) -> String {
        heading
            .lowercased()
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: ":", with: "")
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
            .replacingOccurrences(of: "--", with: "-")
    }

    // MARK: - Formatting

    /// Format a single spec metadata entry for list display.
    /// Example: `  􁁛 [validated]     shikki-test-runner.md          14/14  @Daimyo 2026-03-31`
    public static func formatListEntry(_ metadata: SpecMetadata) -> String {
        let marker = metadata.status.marker
        let statusLabel = "[\(metadata.status.rawValue)]"
        let filename = metadata.filename ?? "unknown.md"
        let progress = metadata.progress ?? "0/0"

        let reviewerInfo: String
        if let reviewer = metadata.primaryReviewer, reviewer.verdict != .pending {
            let date = reviewer.date ?? ""
            reviewerInfo = "\(reviewer.who) \(date)"
        } else {
            reviewerInfo = "\u{2014}" // em dash
        }

        let statusPadded = statusLabel.padding(toLength: 16, withPad: " ", startingAt: 0)
        let filenamePadded = filename.padding(toLength: 35, withPad: " ", startingAt: 0)
        let progressPadded = progress.padding(toLength: 7, withPad: " ", startingAt: 0)

        return "  \(marker) \(statusPadded)\(filenamePadded)\(progressPadded)\(reviewerInfo)"
    }

    /// Format a progress summary for all specs.
    public static func formatProgressSummary(_ specs: [SpecMetadata]) -> String {
        let total = specs.count
        let validated = specs.filter { $0.status == .validated }.count
        let partial = specs.filter { $0.status == .partial }.count
        let draft = specs.filter { $0.status == .draft }.count
        let review = specs.filter { $0.status == .review }.count
        let implementing = specs.filter { $0.status == .implementing }.count
        let shipped = specs.filter { $0.status == .shipped }.count

        var lines: [String] = []
        lines.append("\u{1B}[1mSpec Progress Summary\u{1B}[0m")
        lines.append(String(repeating: "\u{2500}", count: 40))
        lines.append("  Total specs:     \(total)")
        lines.append("  Validated:       \(validated)")
        lines.append("  Partial:         \(partial)")
        lines.append("  In review:       \(review)")
        lines.append("  Draft:           \(draft)")
        lines.append("  Implementing:    \(implementing)")
        lines.append("  Shipped:         \(shipped)")

        // Progress bar
        if total > 0 {
            let pct = (validated * 100) / total
            let bar = String(repeating: "\u{2588}", count: pct / 5)
                + String(repeating: "\u{2591}", count: 20 - (pct / 5))
            lines.append("")
            lines.append("  [\(bar)] \(pct)% validated")
        }

        return lines.joined(separator: "\n")
    }
}
