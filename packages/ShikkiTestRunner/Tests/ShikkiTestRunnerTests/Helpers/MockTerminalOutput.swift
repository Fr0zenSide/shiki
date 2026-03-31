// MockTerminalOutput.swift — Test double for TerminalOutput
// Part of ShikkiTestRunnerTests

import Foundation
@testable import ShikkiTestRunner

/// Captures terminal output for test assertions.
actor MockTerminalOutput: TerminalOutput {
    private var buffer: [String] = []

    init() {}

    nonisolated func write(_ text: String) async {
        await appendToBuffer(text)
    }

    private func appendToBuffer(_ text: String) {
        buffer.append(text)
    }

    /// Get all written text concatenated.
    func allOutput() -> String {
        buffer.joined()
    }

    /// Get individual write calls.
    func writes() -> [String] {
        buffer
    }

    /// Number of write calls.
    func writeCount() -> Int {
        buffer.count
    }

    func clear() {
        buffer.removeAll()
    }
}
