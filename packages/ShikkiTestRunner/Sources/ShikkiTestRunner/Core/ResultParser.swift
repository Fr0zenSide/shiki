// ResultParser.swift — Parse swift test output into structured results
// Part of ShikkiTestRunner

import Foundation

/// Parses `swift test` output (both plain text and event stream JSON) into TestCaseResult arrays.
public struct ResultParser: Sendable {

    public init() {}

    /// Parse combined stdout+stderr output from `swift test` into test case results.
    public func parse(output: String, scope: TestScope) -> [TestCaseResult] {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
        var results: [TestCaseResult] = []

        for line in lines {
            let trimmed = String(line).trimmingCharacters(in: .whitespaces)

            // Try JSON event stream first
            if trimmed.hasPrefix("{"), let jsonResult = parseJSONEvent(trimmed, scope: scope) {
                results.append(jsonResult)
                continue
            }

            // Fall back to plain text parsing
            // Pattern: "Test Case 'SuiteName.testName' passed (0.001 seconds)."
            // Pattern: "Test Case 'SuiteName.testName' failed (0.002 seconds)."
            if let textResult = parseTextLine(trimmed, scope: scope) {
                results.append(textResult)
            }
        }

        return results
    }

    private func parseJSONEvent(_ line: String, scope: TestScope) -> TestCaseResult? {
        guard let data = line.data(using: .utf8) else { return nil }

        struct EventStreamEvent: Decodable {
            let kind: String?
            let name: String?
            let testID: String?
            let status: String?
            let duration: Double?
            let message: String?
            let sourceLocation: String?
        }

        guard let event = try? JSONDecoder().decode(EventStreamEvent.self, from: data) else {
            return nil
        }

        // Only care about test completion events
        guard let kind = event.kind,
              (kind == "testPassed" || kind == "testFailed" || kind == "testSkipped") else {
            return nil
        }

        let status: TestStatus
        switch kind {
        case "testPassed": status = .passed
        case "testFailed": status = .failed
        case "testSkipped": status = .skipped
        default: return nil
        }

        let testName = event.name ?? event.testID ?? "unknown"
        let durationMs = Int((event.duration ?? 0) * 1000)

        return TestCaseResult(
            testName: testName,
            suiteName: scope.name,
            status: status,
            durationMs: durationMs,
            errorMessage: status == .failed ? event.message : nil,
            errorFile: event.sourceLocation
        )
    }

    private func parseTextLine(_ line: String, scope: TestScope) -> TestCaseResult? {
        // Match: "Test Case 'SuiteName.testName' passed (0.001 seconds)."
        // Match: "Test Case 'SuiteName.testName' failed (0.002 seconds)."
        guard line.hasPrefix("Test Case '") else { return nil }

        let statusPatterns: [(String, TestStatus)] = [
            ("' passed (", .passed),
            ("' failed (", .failed),
            ("' skipped", .skipped)
        ]

        for (pattern, status) in statusPatterns {
            guard let range = line.range(of: pattern) else { continue }

            let nameStart = line.index(line.startIndex, offsetBy: "Test Case '".count)
            let nameEnd = range.lowerBound
            let fullName = String(line[nameStart..<nameEnd])

            // Split "SuiteName.testName"
            let parts = fullName.split(separator: ".", maxSplits: 1)
            let suiteName = parts.count > 1 ? String(parts[0]) : scope.name
            let testName = parts.count > 1 ? String(parts[1]) : fullName

            // Extract duration
            var durationMs = 0
            if status != .skipped {
                let afterPattern = line[range.upperBound...]
                if let secondsEnd = afterPattern.range(of: " seconds)") {
                    let durationStr = String(afterPattern[afterPattern.startIndex..<secondsEnd.lowerBound])
                    durationMs = Int((Double(durationStr) ?? 0) * 1000)
                }
            }

            return TestCaseResult(
                testName: testName,
                suiteName: suiteName,
                status: status,
                durationMs: durationMs
            )
        }

        return nil
    }
}
