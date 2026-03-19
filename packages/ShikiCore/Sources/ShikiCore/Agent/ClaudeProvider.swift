import Foundation
import Logging

/// Claude CLI wrapper — dispatches prompts via `claude -p` binary.
/// Uses Process (not HTTP, not curl) to invoke the actual claude CLI.
public actor ClaudeProvider: AgentProvider {
    public nonisolated let name = "claude"
    private let logger = Logger(label: "shiki.core.claude-provider")
    private var currentProcess: Process?

    public init() {}

    /// Build CLI arguments for the claude binary.
    /// Exposed for testing — callers should use `dispatch()`.
    public nonisolated func buildArguments(prompt: String, options: AgentOptions) -> [String] {
        var args: [String] = []

        args.append("-p")
        args.append(prompt)

        args.append("--output-format")
        args.append(options.outputFormat.rawValue)

        if let model = options.model {
            args.append("--model")
            args.append(model)
        }

        if let maxTokens = options.maxTokens {
            args.append("--max-tokens")
            args.append(String(maxTokens))
        }

        if !options.allowedTools.isEmpty {
            args.append("--allowedTools")
            args.append(options.allowedTools.joined(separator: ","))
        }

        return args
    }

    public func dispatch(
        prompt: String,
        workingDirectory: URL,
        options: AgentOptions
    ) async throws -> AgentResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["claude"] + buildArguments(prompt: prompt, options: options)
        process.currentDirectoryURL = workingDirectory

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        currentProcess = process

        let clock = ContinuousClock()
        let start = clock.now

        try process.run()

        // Read pipes BEFORE waitUntilExit to prevent pipe buffer deadlock (~64KB)
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let _ = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let elapsed = clock.now - start
        let duration = Duration.nanoseconds(Int64(elapsed.components.seconds) * 1_000_000_000
            + Int64(elapsed.components.attoseconds / 1_000_000_000))

        let output = String(data: outputData, encoding: .utf8) ?? ""

        currentProcess = nil

        return AgentResult(
            output: output,
            exitCode: process.terminationStatus,
            tokensUsed: nil, // TODO: parse from claude JSON output
            duration: duration
        )
    }

    public func cancel() async {
        currentProcess?.terminate()
        currentProcess = nil
    }
}
