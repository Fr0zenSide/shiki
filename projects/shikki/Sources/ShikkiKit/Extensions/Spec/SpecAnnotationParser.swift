import Foundation

/// Status of an inline spec annotation.
public enum AnnotationStatus: String, Sendable, Codable, CaseIterable {
    case open
    case applied
    case resolved
}

/// An inline annotation extracted from spec markdown body.
///
/// Annotations are HTML comments following this pattern:
/// ```markdown
/// <!-- @note @Who 2026-03-31 -->
/// <!-- Content of the note -->
/// <!-- status: open -->
/// ```
public struct SpecAnnotation: Sendable, Equatable {
    /// Who left the note (e.g. "@Daimyo").
    public let who: String
    /// Date string from the annotation (may be nil if just "pending").
    public let date: String?
    /// The note content.
    public let content: String
    /// Current status: open, applied, or resolved.
    public let status: AnnotationStatus

    public init(
        who: String,
        date: String? = nil,
        content: String,
        status: AnnotationStatus = .open
    ) {
        self.who = who
        self.date = date
        self.content = content
        self.status = status
    }
}

/// Parses inline `<!-- @note -->` annotations from spec markdown bodies.
///
/// Annotations are groups of consecutive HTML comments starting with `<!-- @note @who ... -->`.
/// The parser extracts who, date, content lines, and status from these blocks.
public struct SpecAnnotationParser: Sendable {

    public init() {}

    /// Parse all annotations from a markdown string.
    public func parse(content: String) -> [SpecAnnotation] {
        let lines = content.components(separatedBy: "\n")
        var annotations: [SpecAnnotation] = []
        var index = 0

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)

            // Detect annotation start: <!-- @note @who [date] -->
            if let header = parseNoteHeader(trimmed) {
                var contentLines: [String] = []
                var status: AnnotationStatus = .open
                index += 1

                // Consume subsequent comment lines
                while index < lines.count {
                    let nextTrimmed = lines[index].trimmingCharacters(in: .whitespaces)

                    // Check for status line: <!-- status: open/applied/resolved -->
                    if let parsedStatus = parseStatusLine(nextTrimmed) {
                        status = parsedStatus
                        index += 1
                        continue
                    }

                    // Check for content comment line: <!-- ... --> or opening <!-- ...
                    if let commentContent = extractCommentContent(nextTrimmed) {
                        // Make sure it's not a new @note
                        if commentContent.hasPrefix("@note ") {
                            break
                        }
                        contentLines.append(commentContent)
                        index += 1

                        // If this was an opening <!-- without -->, accumulate until -->
                        if !nextTrimmed.hasSuffix("-->") {
                            while index < lines.count {
                                let contTrimmed = lines[index].trimmingCharacters(in: .whitespaces)
                                if let multiline = extractMultilineContent(contTrimmed) {
                                    // Closing --> found
                                    if !multiline.content.isEmpty {
                                        contentLines.append(multiline.content)
                                    }
                                    index += 1
                                    break
                                }
                                // Middle of multi-line comment (no markers)
                                if !contTrimmed.isEmpty {
                                    contentLines.append(contTrimmed)
                                }
                                index += 1
                            }
                        }
                        continue
                    }

                    // Multi-line comment continuation: line ending with -->
                    if let multiline = extractMultilineContent(nextTrimmed) {
                        if !multiline.content.isEmpty {
                            contentLines.append(multiline.content)
                        }
                        index += 1
                        continue
                    }

                    // Not a comment line — end of annotation block
                    break
                }

                let noteContent = contentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                annotations.append(SpecAnnotation(
                    who: header.who,
                    date: header.date,
                    content: noteContent,
                    status: status
                ))
            } else {
                index += 1
            }
        }

        return annotations
    }

    /// Return only open annotations.
    public func openNotes(in content: String) -> [SpecAnnotation] {
        parse(content: content).filter { $0.status == .open }
    }

    // MARK: - Header Parsing

    private struct NoteHeader {
        let who: String
        let date: String?
    }

    /// Parse `<!-- @note @Who 2026-03-31 -->` or `<!-- @note @Who pending -->`.
    private func parseNoteHeader(_ line: String) -> NoteHeader? {
        let content = extractCommentContent(line)
        guard let content, content.hasPrefix("@note ") else { return nil }

        let afterNote = content.dropFirst(6).trimmingCharacters(in: .whitespaces)
        let parts = afterNote.split(separator: " ", maxSplits: 1).map(String.init)

        guard let who = parts.first, who.hasPrefix("@") else { return nil }

        let datePart = parts.count > 1 ? parts[1] : nil
        let date: String?
        if let datePart, datePart != "pending", !datePart.isEmpty {
            date = datePart
        } else {
            date = nil
        }

        return NoteHeader(who: who, date: date)
    }

    // MARK: - Status Line

    /// Parse `<!-- status: open -->`.
    private func parseStatusLine(_ line: String) -> AnnotationStatus? {
        guard let content = extractCommentContent(line) else { return nil }
        let trimmed = content.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("status:") else { return nil }
        let value = trimmed.dropFirst(7).trimmingCharacters(in: .whitespaces)
        return AnnotationStatus(rawValue: String(value))
    }

    // MARK: - Comment Extraction

    /// Extract content from `<!-- ... -->`, returning nil if not a comment.
    /// Handles single-line comments: `<!-- content here -->`
    /// For multi-line support, check if line starts with `<!--` without closing `-->`.
    private func extractCommentContent(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("<!--") else { return nil }

        if trimmed.hasSuffix("-->") {
            // Single-line comment
            let inner = trimmed
                .dropFirst(4)
                .dropLast(3)
                .trimmingCharacters(in: .whitespaces)
            return inner
        }

        // Opening of multi-line comment — return content after <!--
        let inner = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
        return inner.isEmpty ? nil : inner
    }

    /// Check if a line is a multi-line comment continuation or closing.
    /// Returns (content, isClosing) or nil if not a comment part.
    private func extractMultilineContent(_ line: String) -> (content: String, isClosing: Bool)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix("-->") {
            let content = String(trimmed.dropLast(3)).trimmingCharacters(in: .whitespaces)
            return (content, true)
        }
        return nil
    }
}
