import Foundation
import Logging

// MARK: - SpecInput

/// Resolved input for a spec pipeline run.
/// BR-SP-03: Accepts backlog item ID, #N shorthand, or free text.
public enum SpecInput: Sendable, Equatable {
    /// Free text description of the feature to spec.
    case freeText(String)
    /// Backlog item UUID reference.
    case backlogItem(String)
    /// Shorthand backlog reference (#N from `shikki backlog` list).
    case shorthand(Int)
}

// MARK: - SpecResult

/// Output of a completed spec pipeline run.
/// BR-SP-02: DB record + features/*.md + inbox item.
public struct SpecResult: Sendable, Equatable {
    /// Path to the generated spec file (features/*.md).
    public let specPath: String
    /// Number of lines in the generated spec.
    public let lineCount: Int
    /// Title extracted from the spec.
    public let title: String
    /// Company slug this spec targets.
    public let companySlug: String?

    public init(specPath: String, lineCount: Int, title: String, companySlug: String?) {
        self.specPath = specPath
        self.lineCount = lineCount
        self.title = title
        self.companySlug = companySlug
    }
}

// MARK: - SpecPipelineError

public enum SpecPipelineError: Error, Equatable, Sendable {
    /// Input could not be resolved (invalid UUID, unknown #N, empty text).
    case invalidInput(String)
    /// Agent invocation failed.
    case agentFailed(String)
    /// Generated spec is too short (< 50 lines). SpecGate failure.
    case specGateFailed(Int)
    /// Backend communication failure.
    case backendError(String)
    /// Spec file could not be written.
    case fileWriteError(String)
}

// MARK: - AgentProviding

/// Protocol for agent invocation (AI-provider agnostic).
/// BR-SP-01: First stone — delegates to claude -p or any AgentProvider.
public protocol AgentProviding: Sendable {
    /// Run a prompt through the agent and return the raw output.
    func run(prompt: String, timeout: TimeInterval) async throws -> String
}

// MARK: - SpecPersisting

/// Protocol for spec persistence to backend (DB + inbox).
/// BR-SP-02 + BR-SP-04: DB record + inbox item creation.
public protocol SpecPersisting: Sendable {
    /// Post the completed spec record to ShikiDB.
    func saveSpecRecord(title: String, specPath: String, lineCount: Int, companySlug: String?) async throws
    /// Create an inbox item for spec review.
    /// BR-SP-04: Automatic, no manual step.
    func createInboxItem(title: String, specPath: String, companySlug: String?) async throws
}

// MARK: - SpecPromptBuilder

/// Builds the agent prompt with context injection.
/// Includes feature name, company context, and existing spec paths.
public enum SpecPromptBuilder {
    /// Build a spec prompt from the resolved input.
    public static func build(
        featureName: String,
        companySlug: String?,
        existingSpecPaths: [String] = []
    ) -> String {
        var lines: [String] = []

        lines.append("You are a senior software architect producing a detailed feature specification.")
        lines.append("")
        lines.append("## Feature")
        lines.append(featureName)
        lines.append("")

        if let company = companySlug {
            lines.append("## Target Company")
            lines.append(company)
            lines.append("")
        }

        if !existingSpecPaths.isEmpty {
            lines.append("## Existing Specs (for reference, avoid duplication)")
            for path in existingSpecPaths {
                lines.append("- \(path)")
            }
            lines.append("")
        }

        lines.append("## Output Format")
        lines.append("Produce a markdown specification with:")
        lines.append("- Title (# heading)")
        lines.append("- Summary (2-3 sentences)")
        lines.append("- Requirements (numbered list)")
        lines.append("- Wave breakdown (parallel execution groups)")
        lines.append("- Dependency tree")
        lines.append("- Test strategy per wave")
        lines.append("- Estimated effort per wave")
        lines.append("")
        lines.append("The spec MUST be at least 50 lines. Be thorough and actionable.")

        return lines.joined(separator: "\n")
    }
}

// MARK: - SpecPipeline

/// Orchestrates the spec generation pipeline.
/// BR-SP-01: The first stone of Shikki — wraps /md-feature skill into a ShikiCore component.
/// BR-SP-02: Output to DB (source of truth) + features/*.md (human-readable backup).
/// BR-SP-03: Accepts backlog item ID, #N shorthand, or free text.
/// BR-SP-04: Spec completion triggers inbox item automatically.
/// BR-SP-05: Multi-project targeting via --company flag.
public struct SpecPipeline: Sendable {
    private let agent: any AgentProviding
    private let persister: any SpecPersisting
    private let featuresDirectory: String
    private let logger: Logger

    public init(
        agent: any AgentProviding,
        persister: any SpecPersisting,
        featuresDirectory: String = "features",
        logger: Logger = Logger(label: "shikki.spec-pipeline")
    ) {
        self.agent = agent
        self.persister = persister
        self.featuresDirectory = featuresDirectory
        self.logger = logger
    }

    /// Resolve the input into a feature name for the prompt.
    public func resolveInput(_ input: SpecInput) throws -> String {
        switch input {
        case .freeText(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw SpecPipelineError.invalidInput("Empty text input")
            }
            return trimmed
        case .backlogItem(let uuid):
            // Validate UUID format
            guard UUID(uuidString: uuid) != nil else {
                throw SpecPipelineError.invalidInput("Invalid UUID: \(uuid)")
            }
            // In production, this would look up the backlog item from DB
            return "Backlog item \(uuid)"
        case .shorthand(let n):
            guard n > 0 else {
                throw SpecPipelineError.invalidInput("Invalid shorthand: #\(n) (must be > 0)")
            }
            // In production, this would resolve #N from the backlog list
            return "Backlog item #\(n)"
        }
    }

    /// Generate a slug from the feature title for the filename.
    public static func slugify(_ title: String) -> String {
        let lowered = title.lowercased()
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -"))
        let filtered = lowered.unicodeScalars.filter { allowed.contains($0) }
        let cleaned = String(String.UnicodeScalarView(filtered))
        let slug = cleaned
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        // Truncate to reasonable length
        let maxLength = 60
        if slug.count > maxLength {
            return String(slug.prefix(maxLength))
        }
        return slug.isEmpty ? "untitled-spec" : slug
    }

    /// Run the full spec pipeline.
    /// 1. Resolve input → feature name
    /// 2. Build prompt
    /// 3. Invoke agent
    /// 4. Validate output (SpecGate: >= 50 lines)
    /// 5. Write features/*.md
    /// 6. Post to DB
    /// 7. Create inbox item
    public func run(input: SpecInput, companySlug: String?) async throws -> SpecResult {
        // 1. Resolve input
        let featureName = try resolveInput(input)
        logger.info("Spec pipeline started", metadata: ["feature": "\(featureName)"])

        // 2. Build prompt
        let existingSpecs = listExistingSpecs()
        let prompt = SpecPromptBuilder.build(
            featureName: featureName,
            companySlug: companySlug,
            existingSpecPaths: existingSpecs
        )

        // 3. Invoke agent
        let agentOutput: String
        do {
            agentOutput = try await agent.run(prompt: prompt, timeout: 600)
        } catch {
            throw SpecPipelineError.agentFailed("Agent invocation failed: \(error)")
        }

        // 4. Validate output — SpecGate: >= 50 lines
        let lines = agentOutput.components(separatedBy: .newlines)
        let lineCount = lines.count
        guard lineCount >= 50 else {
            throw SpecPipelineError.specGateFailed(lineCount)
        }

        // Extract title from first # heading, or use feature name
        let title = extractTitle(from: agentOutput) ?? featureName

        // 5. Write features/*.md
        let slug = Self.slugify(title)
        let specPath = "\(featuresDirectory)/\(slug).md"

        do {
            // Ensure directory exists
            let fm = FileManager.default
            if !fm.fileExists(atPath: featuresDirectory) {
                try fm.createDirectory(atPath: featuresDirectory, withIntermediateDirectories: true)
            }
            try agentOutput.write(toFile: specPath, atomically: true, encoding: .utf8)
        } catch {
            throw SpecPipelineError.fileWriteError("Failed to write \(specPath): \(error)")
        }

        logger.info("Spec written", metadata: ["path": "\(specPath)", "lines": "\(lineCount)"])

        // 6. Post to DB (BR-SP-02: DB is source of truth)
        do {
            try await persister.saveSpecRecord(
                title: title,
                specPath: specPath,
                lineCount: lineCount,
                companySlug: companySlug
            )
        } catch {
            // Soft-fail: spec file exists, DB is best-effort
            logger.warning("DB save failed (spec file still exists)", metadata: ["error": "\(error)"])
        }

        // 7. Create inbox item (BR-SP-04: automatic, no manual step)
        do {
            try await persister.createInboxItem(
                title: title,
                specPath: specPath,
                companySlug: companySlug
            )
        } catch {
            logger.warning("Inbox item creation failed", metadata: ["error": "\(error)"])
        }

        return SpecResult(
            specPath: specPath,
            lineCount: lineCount,
            title: title,
            companySlug: companySlug
        )
    }

    // MARK: - Helpers

    /// Extract the first # heading from markdown content.
    private func extractTitle(from markdown: String) -> String? {
        let lines = markdown.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                let title = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !title.isEmpty { return title }
            }
        }
        return nil
    }

    /// List existing spec files in the features directory.
    private func listExistingSpecs() -> [String] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: featuresDirectory) else {
            return []
        }
        return files
            .filter { $0.hasSuffix(".md") }
            .sorted()
    }
}

// MARK: - ClaudeAgentProvider

/// Default agent provider using `claude -p` subprocess.
/// Follows the same Process pattern as BackendClient (curl subprocess).
public struct ClaudeAgentProvider: AgentProviding {
    private let model: String

    public init(model: String = "claude-sonnet-4-20250514") {
        self.model = model
    }

    public func run(prompt: String, timeout: TimeInterval) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["claude", "-p", "--model", model, prompt]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        // Read pipe BEFORE waitUntilExit to prevent pipe buffer deadlock
        let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let _ = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw SpecPipelineError.agentFailed("claude -p exited with status \(process.terminationStatus)")
        }

        guard let output = String(data: outputData, encoding: .utf8), !output.isEmpty else {
            throw SpecPipelineError.agentFailed("Empty output from claude -p")
        }

        return output
    }
}

// MARK: - BackendSpecPersister

/// Default persister using curl to ShikiDB backend.
/// Same subprocess pattern as BackendClient.
public struct BackendSpecPersister: SpecPersisting {
    private let baseURL: String
    private let logger: Logger

    public init(baseURL: String = "http://localhost:3900", logger: Logger = Logger(label: "shikki.spec-persister")) {
        self.baseURL = baseURL
        self.logger = logger
    }

    public func saveSpecRecord(title: String, specPath: String, lineCount: Int, companySlug: String?) async throws {
        var body: [String: Any] = [
            "title": title,
            "specPath": specPath,
            "lineCount": lineCount,
            "type": "spec",
        ]
        if let company = companySlug {
            body["companySlug"] = company
        }

        let jsonData = try JSONSerialization.data(withJSONObject: body)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "curl", "-sf",
            "--max-time", "5",
            "-X", "POST",
            "-H", "Content-Type: application/json",
            "-d", String(data: jsonData, encoding: .utf8) ?? "{}",
            "\(baseURL)/api/agent-events",
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()
    }

    public func createInboxItem(title: String, specPath: String, companySlug: String?) async throws {
        var body: [String: Any] = [
            "title": title,
            "specPath": specPath,
            "type": "spec_review",
        ]
        if let company = companySlug {
            body["companySlug"] = company
        }

        let jsonData = try JSONSerialization.data(withJSONObject: body)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "curl", "-sf",
            "--max-time", "5",
            "-X", "POST",
            "-H", "Content-Type: application/json",
            "-d", String(data: jsonData, encoding: .utf8) ?? "{}",
            "\(baseURL)/api/agent-events",
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()
    }
}
