// TestOutputCapture.swift — Capture stdout/stderr from swift test processes
// Part of ShikkiTestRunner

import Foundation

/// Thread-safe buffer that captures process output.
/// Stores raw output that would normally be written to the terminal,
/// redirecting it to memory for later persistence to SQLite.
public actor OutputBuffer {
    private var lines: [OutputLine] = []

    public enum Source: Sendable {
        case stdout
        case stderr
        case logger
    }

    public struct OutputLine: Sendable {
        public let timestamp: Date
        public let source: Source
        public let content: String

        public init(timestamp: Date = Date(), source: Source, content: String) {
            self.timestamp = timestamp
            self.source = source
            self.content = content
        }
    }

    public init() {}

    /// Append a line to the buffer.
    public func append(_ content: String, source: Source) {
        lines.append(OutputLine(timestamp: Date(), source: source, content: content))
    }

    /// Append multiple lines at once.
    public func appendBatch(_ batch: [(String, Source)]) {
        for (content, source) in batch {
            lines.append(OutputLine(timestamp: Date(), source: source, content: content))
        }
    }

    /// Get all captured lines.
    public func allLines() -> [OutputLine] {
        lines
    }

    /// Get combined raw output as a single string.
    public func rawOutput() -> String {
        lines.map(\.content).joined(separator: "\n")
    }

    /// Get only stdout content.
    public func stdoutContent() -> String {
        lines.filter { $0.source == .stdout }.map(\.content).joined(separator: "\n")
    }

    /// Get only stderr content.
    public func stderrContent() -> String {
        lines.filter { $0.source == .stderr }.map(\.content).joined(separator: "\n")
    }

    /// Get only logger content.
    public func loggerContent() -> String {
        lines.filter { $0.source == .logger }.map(\.content).joined(separator: "\n")
    }

    /// Number of captured lines.
    public func lineCount() -> Int {
        lines.count
    }

    /// Clear all captured content.
    public func clear() {
        lines.removeAll()
    }
}

/// Captures and separates process output streams into an OutputBuffer.
/// Used by ParallelExecutor to capture per-scope output without polluting the terminal.
public struct TestOutputCapture: Sendable {

    public init() {}

    /// Capture process output into the provided buffer.
    /// Splits stdout and stderr into separate source-tagged lines.
    public func capture(output: ProcessOutput, into buffer: OutputBuffer) async {
        var batch: [(String, OutputBuffer.Source)] = []

        let stdoutLines = output.stdout.split(separator: "\n", omittingEmptySubsequences: false)
        for line in stdoutLines where !line.isEmpty {
            batch.append((String(line), .stdout))
        }

        let stderrLines = output.stderr.split(separator: "\n", omittingEmptySubsequences: false)
        for line in stderrLines where !line.isEmpty {
            batch.append((String(line), .stderr))
        }

        await buffer.appendBatch(batch)
    }

    /// Capture a logger message (from swift-log redirection) into the buffer.
    public func captureLogMessage(_ message: String, into buffer: OutputBuffer) async {
        await buffer.append(message, source: .logger)
    }
}
