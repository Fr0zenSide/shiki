import ArgumentParser
import Foundation
import ShikkiKit

/// `shikki spec` — Spec management hub.
///
/// Subcommands: generate, list, read, review, validate, progress.
/// Default subcommand: list (shows all specs with status).
struct SpecCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "spec",
        abstract: "Feature specification management — generate, list, review, validate",
        subcommands: [
            SpecGenerateCommand.self,
            SpecListCommand.self,
            SpecReadCommand.self,
            SpecReviewCommand.self,
            SpecValidateCommand.self,
            SpecProgressCommand.self,
        ],
        defaultSubcommand: SpecListCommand.self
    )
}

/// `shikki spec generate` — wraps the /md-feature skill into a ShikiCore CLI entry point.
///
/// BR-SP-01: The #1 priority component, first stone of Shikki.
/// BR-SP-02: Output to ShikiDB (source of truth) + features/*.md (human-readable backup).
/// BR-SP-03: Accepts backlog item ID, #N shorthand, or free text.
/// BR-SP-04: Completion triggers inbox item automatically.
/// BR-SP-05: Multi-project targeting via --company flag.
struct SpecGenerateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "generate",
        abstract: "Generate a feature specification — the first stone of Shikki Flow"
    )

    @Argument(help: "Feature description (free text), backlog item UUID, or #N shorthand")
    var input: String

    @Option(name: .long, help: "Target company slug (auto-detected from cwd if omitted)")
    var company: String?

    @Option(name: .long, help: "Backend URL")
    var url: String = "http://localhost:3900"

    @Flag(name: .long, help: "Show what would be specced without executing")
    var dryRun: Bool = false

    func run() async throws {
        // 1. Parse input into SpecInput (BR-SP-03)
        let specInput = resolveInputType(input)

        // 2. Resolve company (BR-SP-05)
        let companySlug = company ?? detectCompanyFromCwd()

        // 3. Dry-run mode — show plan and exit
        if dryRun {
            printDryRun(specInput: specInput, companySlug: companySlug)
            return
        }

        // 4. Build pipeline
        let agent = ClaudeAgentProvider()
        let persister = BackendSpecPersister(baseURL: url)
        let pipeline = SpecPipeline(
            agent: agent,
            persister: persister,
            featuresDirectory: findFeaturesDirectory()
        )

        // 5. Run pipeline
        FileHandle.standardError.write(Data("\u{1B}[2mSpec pipeline starting...\u{1B}[0m\n".utf8))

        let result: SpecResult
        do {
            result = try await pipeline.run(input: specInput, companySlug: companySlug)
        } catch let error as SpecPipelineError {
            FileHandle.standardError.write(Data("\u{1B}[31mSpec failed:\u{1B}[0m \(error.userMessage)\n".utf8))
            throw ExitCode.failure
        }

        // 6. Print summary
        printSummary(result)
    }

    // MARK: - Input Resolution (BR-SP-03)

    /// Parse the raw input string into a typed SpecInput.
    private func resolveInputType(_ raw: String) -> SpecInput {
        // Check #N shorthand
        if raw.hasPrefix("#"), let n = Int(raw.dropFirst()), n > 0 {
            return .shorthand(n)
        }

        // Check UUID
        if UUID(uuidString: raw) != nil {
            return .backlogItem(raw)
        }

        // Default: free text
        return .freeText(raw)
    }

    // MARK: - Company Detection (BR-SP-05)

    /// Auto-detect company from current working directory.
    /// Looks for known project directories in the path.
    private func detectCompanyFromCwd() -> String? {
        let cwd = FileManager.default.currentDirectoryPath

        // Check if we're inside a known project directory
        let knownProjects = ["maya", "wabisabi", "brainy", "flsh", "kintsugi-ds"]
        for project in knownProjects {
            if cwd.contains("/projects/\(project)") || cwd.contains("/\(project)/") {
                return project
            }
        }
        return nil
    }

    // MARK: - Features Directory

    /// Find the features/ directory relative to workspace root.
    private func findFeaturesDirectory() -> String {
        var dir = FileManager.default.currentDirectoryPath
        while dir != "/" {
            let featuresPath = "\(dir)/features"
            if FileManager.default.fileExists(atPath: featuresPath) {
                return featuresPath
            }
            dir = (dir as NSString).deletingLastPathComponent
        }
        // Fallback: create in cwd
        return "\(FileManager.default.currentDirectoryPath)/features"
    }

    // MARK: - Output

    private func printDryRun(specInput: SpecInput, companySlug: String?) {
        let inputDesc: String
        switch specInput {
        case .freeText(let text): inputDesc = "Free text: \"\(text)\""
        case .backlogItem(let uuid): inputDesc = "Backlog item: \(uuid)"
        case .shorthand(let n): inputDesc = "Backlog #\(n)"
        }

        FileHandle.standardOutput.write(Data("\u{1B}[1mSpec Dry Run\u{1B}[0m\n".utf8))
        FileHandle.standardOutput.write(Data("  Input: \(inputDesc)\n".utf8))
        FileHandle.standardOutput.write(Data("  Company: \(companySlug ?? "(auto-detect)")\n".utf8))
        FileHandle.standardOutput.write(Data("  Output: features/<slug>.md\n".utf8))
        FileHandle.standardOutput.write(Data("  Pipeline: resolve → prompt → agent → validate → write → DB → inbox\n".utf8))
    }

    private func printSummary(_ result: SpecResult) {
        let company = result.companySlug.map { " (\($0))" } ?? ""
        FileHandle.standardOutput.write(Data(
            "\u{1B}[32mSpec complete:\u{1B}[0m \(result.specPath) (\(result.lineCount) lines)\(company)\n".utf8
        ))
        FileHandle.standardOutput.write(Data(
            "\u{1B}[2mPlan saved to ShikiDB. Awaiting review in your inbox.\u{1B}[0m\n".utf8
        ))
    }
}

// MARK: - SpecPipelineError + User Messages

extension SpecPipelineError {
    var userMessage: String {
        switch self {
        case .invalidInput(let msg): return "Invalid input: \(msg)"
        case .agentFailed(let msg): return "Agent error: \(msg)"
        case .specGateFailed(let lines): return "Spec too short (\(lines) lines, minimum 50). Rerun or add detail."
        case .backendError(let msg): return "Backend error: \(msg)"
        case .fileWriteError(let msg): return "File error: \(msg)"
        }
    }
}
