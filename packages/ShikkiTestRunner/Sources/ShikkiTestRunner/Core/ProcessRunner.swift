// ProcessRunner.swift — Protocol for running external processes (testable)
// Part of ShikkiTestRunner

import Foundation

/// Output from a process execution.
public struct ProcessOutput: Sendable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32

    public init(stdout: String, stderr: String, exitCode: Int32) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }
}

/// Protocol for running external processes. Abstracted for testing.
public protocol ProcessRunner: Sendable {
    func run(
        executable: String,
        arguments: [String],
        workingDirectory: String?
    ) async throws -> ProcessOutput
}

/// Real process runner using Foundation.Process.
public struct SystemProcessRunner: ProcessRunner {
    public init() {}

    public func run(
        executable: String,
        arguments: [String],
        workingDirectory: String?
    ) async throws -> ProcessOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        process.waitUntilExit()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        return ProcessOutput(
            stdout: stdout,
            stderr: stderr,
            exitCode: process.terminationStatus
        )
    }
}
