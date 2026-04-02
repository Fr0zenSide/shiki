import Foundation
import Logging

// MARK: - QuickPipelineStep

/// Steps in the quick flow pipeline.
/// Maps to quick-flow.md Step 1-4.
public enum QuickPipelineStep: Int, Sendable, CaseIterable, CustomStringConvertible {
    case spec = 0
    case implementation = 1
    case selfReview = 2
    case ship = 3

    public var description: String {
        switch self {
        case .spec: return "step_1_spec"
        case .implementation: return "step_2_implementation"
        case .selfReview: return "step_3_self_review"
        case .ship: return "step_4_ship"
        }
    }

    public var displayName: String {
        switch self {
        case .spec: return "Quick Spec"
        case .implementation: return "TDD Implementation"
        case .selfReview: return "Self-Review"
        case .ship: return "Ship"
        }
    }
}

// MARK: - QuickPipelineResult

/// Output of a completed quick pipeline run.
public struct QuickPipelineResult: Sendable {
    /// One-line summary of what was done.
    public let summary: String
    /// Number of files changed.
    public let filesChanged: Int
    /// Number of tests passing after the change.
    public let testsPassing: Int
    /// Number of new tests added.
    public let newTests: Int
    /// Commit hash if committed, nil if unstaged.
    public let commitHash: String?
    /// Notes from self-review step, if available.
    public let reviewNotes: String?
    /// Total pipeline duration in seconds.
    public let duration: TimeInterval
    /// Steps completed (0-4).
    public let stepsCompleted: Int

    public init(
        summary: String,
        filesChanged: Int,
        testsPassing: Int,
        newTests: Int,
        commitHash: String?,
        reviewNotes: String? = nil,
        duration: TimeInterval,
        stepsCompleted: Int
    ) {
        self.summary = summary
        self.filesChanged = filesChanged
        self.testsPassing = testsPassing
        self.newTests = newTests
        self.commitHash = commitHash
        self.reviewNotes = reviewNotes
        self.duration = duration
        self.stepsCompleted = stepsCompleted
    }
}

// MARK: - QuickPipelineError

public enum QuickPipelineError: Error, Sendable, Equatable {
    /// Empty or whitespace-only prompt.
    case emptyPrompt
    /// Scope detection triggered -- change is too large for quick flow.
    case scopeTooLarge(score: Int, signals: [String])
    /// Agent invocation failed.
    case agentFailed(String)
    /// Tests failed after implementation.
    case testsFailed(String)
    /// Too many fix attempts (escalation trigger).
    case escalationRequired(attempts: Int)
}

// MARK: - ScopeSignal

/// Signals that indicate a change may be too large for quick flow.
/// Score >= 2 triggers a warning/escalation.
public enum ScopeSignal: String, Sendable, CaseIterable {
    case multipleComponents = "Multiple components mentioned"
    case architectureLanguage = "Architecture/redesign language detected"
    case userUncertainty = "User uncertainty detected"
    case crossFeature = "Cross-feature interaction"
    case newNavigation = "New navigation route needed"
    case newDI = "New DI registration needed"
    case manyFiles = "Estimated > 5 files changed"
}

// MARK: - ScopeDetector

/// Evaluates a prompt for scope signals.
/// Quick flow is for small, well-understood changes.
/// Score >= 2 means the change should escalate to /md-feature.
public struct ScopeDetector: Sendable {

    public init() {}

    /// Evaluate the prompt and return detected signals with total score.
    public func evaluate(_ prompt: String) -> (score: Int, signals: [ScopeSignal]) {
        let lower = prompt.lowercased()
        var signals: [ScopeSignal] = []

        // Multiple components
        let componentKeywords = ["and", "also", "plus", "both", "all"]
        let componentCount = componentKeywords.filter { containsWord($0, in: lower) }.count
        if componentCount >= 2 {
            signals.append(.multipleComponents)
        }

        // Architecture language
        let archKeywords = ["system", "architecture", "redesign", "refactor all", "overhaul", "rewrite"]
        if archKeywords.contains(where: { lower.contains($0) }) {
            signals.append(.architectureLanguage)
        }

        // User uncertainty
        let uncertainKeywords = ["maybe", "not sure", "might", "possibly", "perhaps", "i think"]
        if uncertainKeywords.contains(where: { lower.contains($0) }) {
            signals.append(.userUncertainty)
        }

        // Cross-feature
        let crossKeywords = ["affects", "impacts", "changes to", "breaks", "depends on"]
        if crossKeywords.contains(where: { lower.contains($0) }) {
            signals.append(.crossFeature)
        }

        // Navigation
        let navKeywords = ["new screen", "new route", "navigation", "coordinator", "flow"]
        if navKeywords.contains(where: { lower.contains($0) }) {
            signals.append(.newNavigation)
        }

        // DI
        let diKeywords = ["register", "inject", "container", "dependency injection", "di container"]
        if diKeywords.contains(where: { lower.contains($0) }) {
            signals.append(.newDI)
        }

        // Many files
        let manyFilesKeywords = [
            "every file", "all files", "across the project", "everywhere",
            "global change", "rename everywhere",
        ]
        if manyFilesKeywords.contains(where: { lower.contains($0) }) {
            signals.append(.manyFiles)
        }

        return (score: signals.count, signals: signals)
    }

    /// Check if a word exists at word boundaries in the text.
    /// Prevents "and" from matching "understand", "band", etc.
    private func containsWord(_ word: String, in text: String) -> Bool {
        let boundaries = CharacterSet.alphanumerics.inverted
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: word, range: searchRange) {
            let beforeOK = range.lowerBound == text.startIndex ||
                String(text[text.index(before: range.lowerBound)]).rangeOfCharacter(from: boundaries) != nil
            let afterOK = range.upperBound == text.endIndex ||
                String(text[range.upperBound]).rangeOfCharacter(from: boundaries) != nil
            if beforeOK && afterOK { return true }
            searchRange = range.upperBound..<text.endIndex
        }
        return false
    }
}

// MARK: - QuickPipeline

/// Orchestrates the quick flow: spec -> implement -> review -> ship.
/// Follows quick-flow.md pipeline definition.
///
/// Design: The pipeline is the Swift contract (gate enforcement, step ordering, escalation).
/// The agent provider handles the LLM reasoning (prompt interpretation, code generation).
public struct QuickPipeline: Sendable {
    private let agent: any AgentProviding
    private let scopeDetector: ScopeDetector
    private let logger: Logger

    /// Maximum fix attempts before escalation (quick-flow.md rule).
    public static let maxFixAttempts = 3

    public init(
        agent: any AgentProviding,
        scopeDetector: ScopeDetector = ScopeDetector(),
        logger: Logger = Logger(label: "shikki.quick-pipeline")
    ) {
        self.agent = agent
        self.scopeDetector = scopeDetector
        self.logger = logger
    }

    /// Run the quick pipeline for a given prompt.
    ///
    /// Steps:
    /// 1. Validate prompt + scope detection
    /// 2. Generate quick spec via agent
    /// 3. Agent implements with TDD
    /// 4. Self-review
    ///
    /// The caller (QuickCommand) handles Step 4 (ship) since it involves
    /// user interaction choices (commit+PR, commit only, keep unstaged).
    ///
    /// - Parameters:
    ///   - prompt: The change description
    ///   - yolo: Skip confirmation, auto-commit
    ///   - projectPath: Working directory for the change
    /// - Returns: Pipeline result with stats
    public func run(
        prompt: String,
        yolo: Bool = false,
        projectPath: String? = nil
    ) async throws -> QuickPipelineResult {
        let startTime = Date()

        // Step 0: Validate prompt
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw QuickPipelineError.emptyPrompt
        }

        // Step 0b: Scope detection
        let scope = scopeDetector.evaluate(trimmed)
        if scope.score >= 2 {
            throw QuickPipelineError.scopeTooLarge(
                score: scope.score,
                signals: scope.signals.map(\.rawValue)
            )
        }

        logger.info("Quick pipeline started", metadata: ["prompt": "\(trimmed)"])

        // Step 1: Quick Spec — agent produces a mini-spec
        let specPrompt = QuickPromptBuilder.buildSpecPrompt(
            change: trimmed,
            projectPath: projectPath
        )
        let specOutput: String
        do {
            specOutput = try await agent.run(prompt: specPrompt, timeout: 120)
        } catch {
            throw QuickPipelineError.agentFailed("Spec generation failed: \(error)")
        }

        // Step 2: TDD Implementation — agent implements the change
        let implPrompt = QuickPromptBuilder.buildImplementationPrompt(
            change: trimmed,
            spec: specOutput,
            projectPath: projectPath
        )
        let implOutput: String
        do {
            implOutput = try await agent.run(prompt: implPrompt, timeout: 300)
        } catch {
            throw QuickPipelineError.agentFailed("Implementation failed: \(error)")
        }

        // Step 3: Self-Review — agent reviews its own work
        let reviewPrompt = QuickPromptBuilder.buildReviewPrompt(
            change: trimmed,
            spec: specOutput,
            implementation: implOutput,
            projectPath: projectPath
        )
        var reviewNotes: String?
        do {
            reviewNotes = try await agent.run(prompt: reviewPrompt, timeout: 120)
        } catch {
            // Self-review failure is non-fatal — log and continue
            logger.warning("Self-review failed", metadata: ["error": "\(error)"])
        }

        let duration = Date().timeIntervalSince(startTime)

        // Parse stats from agent output
        let stats = QuickOutputParser.parseStats(from: implOutput)

        return QuickPipelineResult(
            summary: QuickOutputParser.extractSummary(from: specOutput) ?? trimmed,
            filesChanged: stats.filesChanged,
            testsPassing: stats.testsPassing,
            newTests: stats.newTests,
            commitHash: nil, // Caller handles commit
            reviewNotes: reviewNotes,
            duration: duration,
            stepsCompleted: 3
        )
    }
}

// MARK: - QuickPromptBuilder

/// Builds prompts for each step of the quick pipeline.
/// The prompt body is the "skill" content — Swift owns the contract,
/// the prompt owns the reasoning.
public enum QuickPromptBuilder {

    public static func buildSpecPrompt(
        change: String,
        projectPath: String?
    ) -> String {
        var lines: [String] = []
        lines.append("You are implementing a small, well-understood change using Quick Flow.")
        lines.append("Write a quick spec (NOT a full feature spec) covering:")
        lines.append("- Problem: 1-2 sentences")
        lines.append("- Solution: 1-2 sentences")
        lines.append("- Files: list of files to create/modify")
        lines.append("- Test plan: which tests to write/modify")
        lines.append("- Risk: Low or Medium")
        lines.append("")
        lines.append("## Change Request")
        lines.append(change)
        if let path = projectPath {
            lines.append("")
            lines.append("## Project Path")
            lines.append(path)
        }
        return lines.joined(separator: "\n")
    }

    public static func buildImplementationPrompt(
        change: String,
        spec: String,
        projectPath: String?
    ) -> String {
        var lines: [String] = []
        lines.append("Implement this change using strict TDD:")
        lines.append("1. Write failing test(s) first")
        lines.append("2. Run tests — verify RED")
        lines.append("3. Implement the fix")
        lines.append("4. Run tests — verify GREEN")
        lines.append("5. Refactor if needed (keep GREEN)")
        lines.append("")
        lines.append("Rules:")
        lines.append("- NO production code without a failing test first")
        lines.append("- Run the full test suite after every change")
        lines.append("- If 3 fix attempts fail on the same test, STOP and report")
        lines.append("")
        lines.append("## Change Request")
        lines.append(change)
        lines.append("")
        lines.append("## Quick Spec")
        lines.append(spec)
        if let path = projectPath {
            lines.append("")
            lines.append("## Project Path")
            lines.append(path)
        }
        return lines.joined(separator: "\n")
    }

    public static func buildReviewPrompt(
        change: String,
        spec: String,
        implementation: String,
        projectPath: String?
    ) -> String {
        var lines: [String] = []
        lines.append("Self-review the implementation against the spec:")
        lines.append("1. Check git diff — every changed line intentional?")
        lines.append("2. Does the implementation match the spec? Nothing more?")
        lines.append("3. No stray formatting, debug prints, or commented code?")
        lines.append("4. All tests pass?")
        lines.append("")
        lines.append("## Change Request")
        lines.append(change)
        lines.append("")
        lines.append("## Spec")
        lines.append(spec)
        lines.append("")
        lines.append("## Implementation Output")
        lines.append(implementation)
        return lines.joined(separator: "\n")
    }
}

// MARK: - QuickOutputParser

/// Parses stats from agent output for the pipeline result.
public enum QuickOutputParser {

    public struct Stats: Sendable {
        public let filesChanged: Int
        public let testsPassing: Int
        public let newTests: Int

        public init(filesChanged: Int, testsPassing: Int, newTests: Int) {
            self.filesChanged = filesChanged
            self.testsPassing = testsPassing
            self.newTests = newTests
        }
    }

    /// Extract a one-line summary from the spec output.
    public static func extractSummary(from specOutput: String) -> String? {
        let lines = specOutput.components(separatedBy: .newlines)
        // Look for "Problem:" or "Solution:" line
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- Problem:") || trimmed.hasPrefix("Problem:") {
                let value = trimmed
                    .replacingOccurrences(of: "- Problem:", with: "")
                    .replacingOccurrences(of: "Problem:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { return value }
            }
        }
        // Fallback: first non-empty, non-heading line
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                return String(trimmed.prefix(120))
            }
        }
        return nil
    }

    /// Parse file/test stats from implementation output.
    /// Looks for patterns like "X files changed", "Y tests passing", "Z new tests".
    public static func parseStats(from output: String) -> Stats {
        let lower = output.lowercased()
        let filesPattern = /(\d+)\s+files?\s+changed/
        let testsPattern = /(\d+)\s+tests?\s+pass/
        let newTestsPattern = /(\d+)\s+new\s+tests?/

        let files = lower.firstMatch(of: filesPattern).flatMap { Int($0.1) } ?? 0
        let tests = lower.firstMatch(of: testsPattern).flatMap { Int($0.1) } ?? 0
        let newTests = lower.firstMatch(of: newTestsPattern).flatMap { Int($0.1) } ?? 0

        return Stats(filesChanged: files, testsPassing: tests, newTests: newTests)
    }
}
