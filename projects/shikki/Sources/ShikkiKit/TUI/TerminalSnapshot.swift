import Foundation

/// TUI snapshot testing utility.
/// Captures rendered terminal output and compares against golden files.
/// Like SwiftUI snapshot testing, but for ANSI terminal output.
public enum TerminalSnapshot {

    /// Capture stdout from a synchronous closure.
    public static func capture(_ block: () -> Void) -> String {
        let pipe = Pipe()
        let original = dup(STDOUT_FILENO)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)

        block()
        fflush(stdout)

        dup2(original, STDOUT_FILENO)
        close(original)
        pipe.fileHandleForWriting.closeFile()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Strip ANSI escape codes for text-only comparison.
    public static func stripANSI(_ string: String) -> String {
        string.replacingOccurrences(
            of: "\u{1B}\\[[0-9;]*[a-zA-Z]", with: "",
            options: .regularExpression
        )
    }

    /// Assert that captured output matches a golden snapshot file.
    /// On first run (or record mode): creates the golden file.
    /// On subsequent runs: compares and returns a diff if mismatched.
    ///
    /// - Parameters:
    ///   - output: The captured terminal output
    ///   - named: Snapshot name (used as filename)
    ///   - snapshotDir: Directory for golden files
    ///   - record: If true, always overwrite the golden file
    /// - Returns: nil if match, or a diff description if mismatch
    @discardableResult
    public static func assertSnapshot(
        _ output: String,
        named: String,
        snapshotDir: String,
        record: Bool = ProcessInfo.processInfo.environment["SHIKI_RECORD_SNAPSHOTS"] == "1"
    ) throws -> SnapshotResult {
        let fm = FileManager.default
        let stripped = stripANSI(output)
        let filePath = "\(snapshotDir)/\(named).snapshot"

        if !fm.fileExists(atPath: snapshotDir) {
            try fm.createDirectory(atPath: snapshotDir, withIntermediateDirectories: true)
        }

        if record || !fm.fileExists(atPath: filePath) {
            try stripped.write(toFile: filePath, atomically: true, encoding: .utf8)
            return .recorded(path: filePath)
        }

        let golden = try String(contentsOfFile: filePath, encoding: .utf8)
        if stripped == golden {
            return .matched
        }

        // Build diff
        let goldenLines = golden.split(separator: "\n", omittingEmptySubsequences: false)
        let actualLines = stripped.split(separator: "\n", omittingEmptySubsequences: false)
        var diffs: [(line: Int, expected: String, actual: String)] = []

        let maxLines = max(goldenLines.count, actualLines.count)
        for i in 0..<maxLines {
            let expected = i < goldenLines.count ? String(goldenLines[i]) : "<missing>"
            let actual = i < actualLines.count ? String(actualLines[i]) : "<missing>"
            if expected != actual {
                diffs.append((line: i + 1, expected: expected, actual: actual))
            }
        }

        return .mismatched(diffs: diffs, goldenPath: filePath)
    }
}

/// Result of a snapshot comparison.
public enum SnapshotResult: Sendable {
    case matched
    case recorded(path: String)
    case mismatched(diffs: [(line: Int, expected: String, actual: String)], goldenPath: String)

    public var isMatch: Bool {
        switch self {
        case .matched, .recorded: true
        case .mismatched: false
        }
    }
}

// Sendable conformance for the tuple
extension SnapshotResult: Equatable {
    public static func == (lhs: SnapshotResult, rhs: SnapshotResult) -> Bool {
        switch (lhs, rhs) {
        case (.matched, .matched): true
        case (.recorded(let a), .recorded(let b)): a == b
        case (.mismatched, .mismatched): true // simplified — compare by isMatch
        default: false
        }
    }
}
