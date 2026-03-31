// MockProcessRunner.swift — Test double for ProcessRunner
// Part of ShikkiTestRunnerTests

import Foundation
@testable import ShikkiTestRunner

/// Mock process runner that returns preconfigured output per scope filter.
actor MockProcessRunner: ProcessRunner {
    private var responses: [String: ProcessOutput] = [:]
    private var invocations: [(executable: String, arguments: [String])] = []
    private var delay: Duration?

    init() {}

    /// Register a response for a given filter argument.
    func register(filter: String, output: ProcessOutput) {
        responses[filter] = output
    }

    /// Register a default response for any filter.
    func registerDefault(output: ProcessOutput) {
        responses["__default__"] = output
    }

    /// Set an artificial delay for each invocation (simulates work).
    func setDelay(_ delay: Duration) {
        self.delay = delay
    }

    /// Get all invocations recorded.
    func allInvocations() -> [(executable: String, arguments: [String])] {
        invocations
    }

    /// Number of times run() was called.
    func invocationCount() -> Int {
        invocations.count
    }

    nonisolated func run(
        executable: String,
        arguments: [String],
        workingDirectory: String?
    ) async throws -> ProcessOutput {
        // Extract filter value from arguments
        let filter = await extractFilter(arguments: arguments)
        await recordInvocation(executable: executable, arguments: arguments)

        if let delay = await self.delay {
            try await Task.sleep(for: delay)
        }

        if let response = await lookupResponse(filter: filter) {
            return response
        }

        // Return empty success by default
        return ProcessOutput(stdout: "", stderr: "", exitCode: 0)
    }

    private func extractFilter(arguments: [String]) -> String? {
        guard let filterIndex = arguments.firstIndex(of: "--filter"),
              filterIndex + 1 < arguments.count else {
            return nil
        }
        return arguments[filterIndex + 1]
    }

    private func recordInvocation(executable: String, arguments: [String]) {
        invocations.append((executable: executable, arguments: arguments))
    }

    private func lookupResponse(filter: String?) -> ProcessOutput? {
        if let filter, let response = responses[filter] {
            return response
        }
        return responses["__default__"]
    }
}
