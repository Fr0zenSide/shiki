import Foundation

// MARK: - Models

public struct PRReview: Sendable {
    public let title: String
    public let branch: String
    public let filesChanged: Int
    public let testsInfo: String
    public let sections: [ReviewSection]
    public let checklist: [String]

    public init(
        title: String,
        branch: String,
        filesChanged: Int,
        testsInfo: String,
        sections: [ReviewSection],
        checklist: [String]
    ) {
        self.title = title
        self.branch = branch
        self.filesChanged = filesChanged
        self.testsInfo = testsInfo
        self.sections = sections
        self.checklist = checklist
    }
}

public struct ReviewSection: Sendable {
    public let index: Int
    public let title: String
    public let body: String
    public let questions: [ReviewQuestion]

    public init(index: Int, title: String, body: String, questions: [ReviewQuestion]) {
        self.index = index
        self.title = title
        self.body = body
        self.questions = questions
    }
}

public struct ReviewQuestion: Sendable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

public enum PRReviewParserError: Error {
    case emptyInput
    case noTitle
}

// MARK: - Parser

public enum PRReviewParser {

    /// Parse a PR review markdown document into a structured PRReview.
    public static func parse(_ markdown: String) throws -> PRReview {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PRReviewParserError.emptyInput
        }

        let lines = trimmed.components(separatedBy: "\n")

        let title = parseTitle(lines)
        let branch = parseMetadata(lines, key: "Branch")
        let filesChanged = parseFilesChanged(lines)
        let testsInfo = parseMetadata(lines, key: "Tests")
        let sections = parseSections(lines)
        let checklist = parseChecklist(lines)

        return PRReview(
            title: title,
            branch: branch,
            filesChanged: filesChanged,
            testsInfo: testsInfo,
            sections: sections,
            checklist: checklist
        )
    }

    // MARK: - Private Parsers

    private static func parseTitle(_ lines: [String]) -> String {
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") && !trimmed.hasPrefix("## ") {
                return String(trimmed.dropFirst(2))
            }
        }
        return ""
    }

    private static func parseMetadata(_ lines: [String], key: String) -> String {
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Match: > **Key**: value  or > **Key**: `value`
            if trimmed.contains("**\(key)**") {
                let parts = trimmed.components(separatedBy: "**\(key)**:")
                if parts.count > 1 {
                    var value = parts[1].trimmingCharacters(in: .whitespaces)
                    // Strip backticks
                    value = value.replacingOccurrences(of: "`", with: "")
                    // For branch, take first part before arrow
                    if key == "Branch" {
                        if let arrowRange = value.range(of: " →") ?? value.range(of: " ->") {
                            value = String(value[..<arrowRange.lowerBound])
                        }
                    }
                    return value.trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return ""
    }

    private static func parseFilesChanged(_ lines: [String]) -> Int {
        for line in lines {
            if line.contains("**Files**") {
                // Extract number before "changed"
                let pattern = #"(\d+)\s+changed"#
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                   let range = Range(match.range(at: 1), in: line) {
                    return Int(line[range]) ?? 0
                }
            }
        }
        return 0
    }

    private static func parseSections(_ lines: [String]) -> [ReviewSection] {
        var sections: [ReviewSection] = []
        var currentTitle = ""
        var currentIndex = 0
        var currentBodyLines: [String] = []
        var inSection = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Match ### Section N: Title
            if trimmed.hasPrefix("### Section ") || trimmed.hasPrefix("### ") && !trimmed.hasPrefix("### Section") {
                // Save previous section
                if inSection {
                    sections.append(makeSection(
                        index: currentIndex,
                        title: currentTitle,
                        bodyLines: currentBodyLines
                    ))
                }

                // Parse new section
                let sectionHeader = parseSectionHeader(trimmed)
                currentIndex = sectionHeader.index
                currentTitle = sectionHeader.title
                currentBodyLines = []
                inSection = true
                continue
            }

            // Stop collecting at "## Reviewer Checklist" or next "## " heading
            if trimmed.hasPrefix("## ") && inSection {
                sections.append(makeSection(
                    index: currentIndex,
                    title: currentTitle,
                    bodyLines: currentBodyLines
                ))
                inSection = false
                continue
            }

            if inSection {
                currentBodyLines.append(line)
            }
        }

        // Save last section
        if inSection {
            sections.append(makeSection(
                index: currentIndex,
                title: currentTitle,
                bodyLines: currentBodyLines
            ))
        }

        return sections
    }

    private static func parseSectionHeader(_ line: String) -> (index: Int, title: String) {
        // "### Section 2: Critical Path — Ghost Process Cleanup"
        var stripped = line
        if stripped.hasPrefix("### Section ") {
            stripped = String(stripped.dropFirst("### Section ".count))
            // Try to get number
            let parts = stripped.split(separator: ":", maxSplits: 1)
            if parts.count == 2, let idx = Int(parts[0].trimmingCharacters(in: .whitespaces)) {
                return (idx, parts[1].trimmingCharacters(in: .whitespaces))
            }
        } else if stripped.hasPrefix("### ") {
            stripped = String(stripped.dropFirst("### ".count))
        }
        return (0, stripped)
    }

    private static func makeSection(index: Int, title: String, bodyLines: [String]) -> ReviewSection {
        let body = bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let questions = extractQuestions(from: bodyLines)
        return ReviewSection(index: index, title: title, body: body, questions: questions)
    }

    private static func extractQuestions(from lines: [String]) -> [ReviewQuestion] {
        var questions: [ReviewQuestion] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- [ ] ") {
                let text = String(trimmed.dropFirst("- [ ] ".count))
                questions.append(ReviewQuestion(text: text))
            }
        }
        return questions
    }

    private static func parseChecklist(_ lines: [String]) -> [String] {
        var checklist: [String] = []
        var inChecklist = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("## Reviewer Checklist") {
                inChecklist = true
                continue
            }
            if inChecklist && trimmed.hasPrefix("- [ ] ") {
                let text = String(trimmed.dropFirst("- [ ] ".count))
                // Strip markdown bold markers
                let clean = text.replacingOccurrences(of: "**", with: "")
                checklist.append(clean)
            }
        }
        return checklist
    }
}
