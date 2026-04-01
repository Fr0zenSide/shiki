import ArgumentParser
import Foundation
import ShikkiKit

/// `shikki spec-check` — Parse, validate, and optionally compile S3 spec files.
///
/// Reads an S3 (Shiki Spec Syntax) file, validates its structure, reports
/// diagnostics, and can generate Swift Testing @Test stubs.
struct SpecCheckCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "spec-check",
        abstract: "Validate and compile S3 spec files into Swift @Test functions"
    )

    @Argument(help: "Path to .s3.md or .md file containing S3 spec syntax")
    var file: String

    @Flag(name: .long, help: "Generate Swift @Test output to stdout")
    var generate: Bool = false

    @Option(name: .shortAndLong, help: "Write generated tests to this file path")
    var output: String?

    @Flag(name: .long, help: "Show spec statistics summary")
    var stats: Bool = false

    @Flag(name: .long, help: "Output diagnostics as JSON")
    var json: Bool = false

    func run() async throws {
        // 1. Read file
        let path = resolvePath(file)
        guard FileManager.default.fileExists(atPath: path) else {
            writeStderr("Error: file not found: \(path)\n")
            throw ExitCode.failure
        }

        let content: String
        do {
            content = try String(contentsOfFile: path, encoding: .utf8)
        } catch {
            writeStderr("Error: cannot read file: \(error.localizedDescription)\n")
            throw ExitCode.failure
        }

        // 2. Validate
        let validation = S3Validator.validate(content)

        if json {
            try outputJSON(validation: validation, path: path, content: content)
            return
        }

        // 3. Print diagnostics
        printDiagnostics(validation, path: path)

        // 4. Parse
        let spec: S3Spec
        do {
            spec = try S3Parser.parse(content)
        } catch {
            writeStderr("Parse error: \(error)\n")
            throw ExitCode.failure
        }

        // 5. Statistics
        if stats || (!generate && output == nil) {
            let statistics = S3Statistics.from(spec)
            printStatistics(statistics, title: spec.title)
        }

        // 6. Generate
        if generate || output != nil {
            let generated = S3TestGenerator.generate(spec)

            if let outputPath = output {
                let resolved = resolvePath(outputPath)
                do {
                    try generated.write(toFile: resolved, atomically: true, encoding: .utf8)
                    writeStderr("Generated: \(resolved)\n")
                } catch {
                    writeStderr("Error: cannot write to \(resolved): \(error.localizedDescription)\n")
                    throw ExitCode.failure
                }
            }

            if generate {
                writeStdout(generated)
            }
        }

        // 7. Exit code based on validation
        if !validation.isValid {
            throw ExitCode.failure
        }
    }

    // MARK: - Path Resolution

    private func resolvePath(_ input: String) -> String {
        if input.hasPrefix("/") {
            return input
        }
        let cwd = FileManager.default.currentDirectoryPath
        return "\(cwd)/\(input)"
    }

    // MARK: - Output Helpers

    private func writeStdout(_ text: String) {
        FileHandle.standardOutput.write(Data(text.utf8))
    }

    private func writeStderr(_ text: String) {
        FileHandle.standardError.write(Data(text.utf8))
    }

    private func printDiagnostics(_ result: S3ValidationResult, path: String) {
        let filename = (path as NSString).lastPathComponent

        for diag in result.diagnostics {
            let icon: String
            switch diag.severity {
            case .error: icon = "\u{1B}[31merror\u{1B}[0m"
            case .warning: icon = "\u{1B}[33mwarn\u{1B}[0m"
            case .hint: icon = "\u{1B}[2mhint\u{1B}[0m"
            }
            writeStderr("\(filename):\(diag.line): \(icon): \(diag.message)\n")
        }

        if result.diagnostics.isEmpty {
            writeStderr("\u{1B}[32mNo issues found.\u{1B}[0m\n")
        } else {
            let errorCount = result.errors.count
            let warnCount = result.warnings.count
            writeStderr("\(errorCount) error\(errorCount == 1 ? "" : "s"), \(warnCount) warning\(warnCount == 1 ? "" : "s")\n")
        }
    }

    private func printStatistics(_ stats: S3Statistics, title: String) {
        writeStdout("\n\u{1B}[1m\(title)\u{1B}[0m\n")
        writeStdout("  Sections:    \(stats.sectionCount)\n")
        writeStdout("  Scenarios:   \(stats.scenarioCount)\n")
        writeStdout("  Assertions:  \(stats.assertionCount)\n")
        writeStdout("  Conditions:  \(stats.conditionCount)\n")
        writeStdout("  Concerns:    \(stats.concernCount)\n")
        writeStdout("  Sequences:   \(stats.sequenceCount)\n")
        writeStdout("  Est. tests:  \(stats.estimatedTestCount)\n")
        writeStdout("\n")
    }

    private func outputJSON(validation: S3ValidationResult, path: String, content: String) throws {
        // Also parse for statistics
        let spec = try S3Parser.parse(content)
        let statistics = S3Statistics.from(spec)

        let report = S3CheckReport(
            file: path,
            title: spec.title,
            isValid: validation.isValid,
            diagnostics: validation.diagnostics,
            statistics: statistics
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        if let jsonString = String(data: data, encoding: .utf8) {
            writeStdout(jsonString)
            writeStdout("\n")
        }
    }
}

// MARK: - JSON Report

struct S3CheckReport: Codable, Sendable {
    let file: String
    let title: String
    let isValid: Bool
    let diagnostics: [S3Diagnostic]
    let statistics: S3Statistics
}
