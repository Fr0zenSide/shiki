import Foundation

/// Splits Swift source files into semantic chunks for BM25 indexing.
///
/// Uses regex-based heuristics (no SwiftSyntax dependency) to detect
/// type boundaries, function boundaries, and top-level blocks.
/// Each chunk is self-contained and carries symbol metadata.
///
/// Design decision: independent from ``ProjectAnalyzer`` (Option B in spec).
/// Each evolves on its own timeline without coupling risk.
public struct SourceChunker: Sendable {

    /// Maximum lines per chunk before forced split.
    public let maxChunkLines: Int

    /// Minimum lines per chunk (avoids tiny fragments).
    public let minChunkLines: Int

    public init(maxChunkLines: Int = 80, minChunkLines: Int = 5) {
        self.maxChunkLines = maxChunkLines
        self.minChunkLines = minChunkLines
    }

    /// Chunk a single source file.
    ///
    /// - Parameters:
    ///   - content: The full file content.
    ///   - relativePath: Relative path from project root (e.g. "Sources/ShikkiKit/Foo.swift").
    /// - Returns: An array of ``SourceChunk`` values covering the entire file.
    public func chunk(content: String, relativePath: String) -> [SourceChunk] {
        let lines = content.components(separatedBy: "\n")
        guard !lines.isEmpty else { return [] }

        // Find declaration boundaries
        var boundaries: [Int] = [0]  // Always start at line 0

        for (index, line) in lines.enumerated() {
            if isDeclarationStart(line) && index > 0 {
                // Include doc comments: walk back from current line
                let adjustedIndex = walkBackForDocComments(lines: lines, from: index)
                if adjustedIndex != boundaries.last {
                    boundaries.append(adjustedIndex)
                }
            }
        }

        // Build chunks from boundaries
        var chunks: [SourceChunk] = []

        for i in 0..<boundaries.count {
            let start = boundaries[i]
            let end: Int
            if i + 1 < boundaries.count {
                end = boundaries[i + 1] - 1
            } else {
                end = lines.count - 1
            }

            // Skip empty trailing chunks
            let chunkLines = Array(lines[start...min(end, lines.count - 1)])
            let trimmedContent = chunkLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedContent.isEmpty { continue }

            // If chunk exceeds max, split it
            let subChunks = splitIfNeeded(
                lines: chunkLines,
                startLine: start,
                relativePath: relativePath
            )
            chunks.append(contentsOf: subChunks)
        }

        // Merge tiny trailing chunks
        return mergeTinyChunks(chunks)
    }

    /// Chunk all Swift files in a project directory.
    ///
    /// - Parameter projectPath: Absolute path to the project root.
    /// - Returns: All chunks across all Swift source files.
    public func chunkProject(projectPath: String) -> [SourceChunk] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: projectPath),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var allChunks: [SourceChunk] = []
        let basePath = projectPath.hasSuffix("/") ? projectPath : projectPath + "/"

        for case let url as URL in enumerator {
            let path = url.path
            // Skip build artifacts and packages
            if path.contains("/.build/") || path.contains("/Packages/") { continue }
            guard path.hasSuffix(".swift") || path.hasSuffix(".md") else { continue }

            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }

            let relativePath: String
            if path.hasPrefix(basePath) {
                relativePath = String(path.dropFirst(basePath.count))
            } else {
                relativePath = path
            }

            if path.hasSuffix(".md") {
                allChunks.append(contentsOf: chunkMarkdown(content: content, relativePath: relativePath))
            } else {
                allChunks.append(contentsOf: chunk(content: content, relativePath: relativePath))
            }
        }

        return allChunks
    }

    /// Chunk a markdown file into section-based chunks.
    public func chunkMarkdown(content: String, relativePath: String) -> [SourceChunk] {
        let lines = content.components(separatedBy: "\n")
        guard !lines.isEmpty else { return [] }

        var boundaries: [Int] = [0]
        for (index, line) in lines.enumerated() {
            if line.hasPrefix("#") && index > 0 {
                boundaries.append(index)
            }
        }

        var chunks: [SourceChunk] = []
        for i in 0..<boundaries.count {
            let start = boundaries[i]
            let end = (i + 1 < boundaries.count) ? boundaries[i + 1] - 1 : lines.count - 1
            let chunkLines = Array(lines[start...min(end, lines.count - 1)])
            let text = chunkLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { continue }

            // Extract heading as symbol
            var symbols: [String] = []
            if let first = chunkLines.first, first.hasPrefix("#") {
                let heading = first.drop(while: { $0 == "#" || $0 == " " })
                symbols.append(String(heading))
            }

            chunks.append(SourceChunk(
                file: relativePath,
                startLine: start + 1,
                endLine: end + 1,
                content: text,
                symbols: symbols
            ))
        }

        return chunks
    }

    // MARK: - Private

    /// Check if a line starts a new top-level declaration (type, function, extension, etc.).
    ///
    /// Only matches declarations at column 0 (no leading whitespace), so properties
    /// and local variables inside type bodies are not treated as chunk boundaries.
    func isDeclarationStart(_ line: String) -> Bool {
        // Must start at column 0 (no indentation) to be a top-level boundary
        guard let first = line.first, !first.isWhitespace else { return false }

        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Skip blank lines
        if trimmed.isEmpty { return false }

        // MARK comments are section separators
        if trimmed.hasPrefix("// MARK:") { return true }

        // Skip other comments
        if trimmed.hasPrefix("//") { return false }

        // Top-level declarations
        let pattern = #"^(public |private |internal |fileprivate |open )?(final )?(class |struct |enum |actor |protocol |extension |func )"#

        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    /// Walk backwards from a declaration line to include preceding doc comments.
    func walkBackForDocComments(lines: [String], from index: Int) -> Int {
        var i = index - 1
        while i >= 0 {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("///") || trimmed.hasPrefix("//") || trimmed.isEmpty {
                i -= 1
            } else {
                break
            }
        }
        return i + 1
    }

    /// Split a chunk if it exceeds `maxChunkLines`.
    func splitIfNeeded(lines: [String], startLine: Int, relativePath: String) -> [SourceChunk] {
        if lines.count <= maxChunkLines {
            let content = lines.joined(separator: "\n")
            let symbols = extractSymbols(from: content)
            return [SourceChunk(
                file: relativePath,
                startLine: startLine + 1,
                endLine: startLine + lines.count,
                content: content,
                symbols: symbols
            )]
        }

        // Split at maxChunkLines boundaries
        var chunks: [SourceChunk] = []
        var offset = 0
        while offset < lines.count {
            let end = min(offset + maxChunkLines, lines.count)
            let slice = Array(lines[offset..<end])
            let content = slice.joined(separator: "\n")
            let symbols = extractSymbols(from: content)
            chunks.append(SourceChunk(
                file: relativePath,
                startLine: startLine + offset + 1,
                endLine: startLine + end,
                content: content,
                symbols: symbols
            ))
            offset = end
        }

        return chunks
    }

    /// Merge chunks smaller than `minChunkLines` into their predecessor.
    func mergeTinyChunks(_ chunks: [SourceChunk]) -> [SourceChunk] {
        guard chunks.count > 1 else { return chunks }

        var result: [SourceChunk] = []
        for chunk in chunks {
            if chunk.lineCount < minChunkLines, let last = result.last {
                // Merge into previous chunk
                let merged = SourceChunk(
                    file: last.file,
                    startLine: last.startLine,
                    endLine: chunk.endLine,
                    content: last.content + "\n" + chunk.content,
                    symbols: last.symbols + chunk.symbols
                )
                result[result.count - 1] = merged
            } else {
                result.append(chunk)
            }
        }
        return result
    }

    /// Extract symbol names (types, functions) from a chunk of code.
    func extractSymbols(from content: String) -> [String] {
        var symbols: [String] = []

        // Type declarations
        let typePattern = #"(?:public\s+)?(?:final\s+)?(?:class|struct|enum|actor|protocol)\s+(\w+)"#
        if let regex = try? NSRegularExpression(pattern: typePattern) {
            let range = NSRange(content.startIndex..., in: content)
            regex.enumerateMatches(in: content, range: range) { match, _, _ in
                if let match, let r = Range(match.range(at: 1), in: content) {
                    symbols.append(String(content[r]))
                }
            }
        }

        // Function declarations
        let funcPattern = #"func\s+(\w+)\s*[<(]"#
        if let regex = try? NSRegularExpression(pattern: funcPattern) {
            let range = NSRange(content.startIndex..., in: content)
            regex.enumerateMatches(in: content, range: range) { match, _, _ in
                if let match, let r = Range(match.range(at: 1), in: content) {
                    symbols.append(String(content[r]))
                }
            }
        }

        return symbols
    }
}
