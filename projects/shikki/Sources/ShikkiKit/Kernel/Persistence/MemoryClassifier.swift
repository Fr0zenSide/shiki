import Foundation

/// BR-27: Deterministic classifier for memory files.
/// Pure function — no AI, no network. Reproducible results based on filename pattern matching.
public struct MemoryClassifier: Sendable {

    // MARK: - Known Project IDs

    public static let projectShiki = "80c27043-5282-4814-b79d-5e6d3903cbc9"
    public static let projectMaya = "bb9e4385-f087-4f65-8251-470f14230c3c"
    public static let projectWabiSabi = "38172cfa-6081-4e64-8e3c-2798653d349b"
    public static let projectBrainy = "61056227-7790-4749-a2e1-70b4e372da47"
    public static let projectFlsh = "fadaa7d4-7d42-4d3c-a9d6-5388b5e61115"

    public init() {}

    /// Classify a single memory file by its filename (BR-27 deterministic rules).
    /// Returns nil for MEMORY.md (it is the manifest, not a memory).
    public func classify(_ filename: String) -> MemoryClassification? {
        guard filename != "MEMORY.md" else { return nil }

        let (scope, category) = scopeAndCategory(for: filename)
        let projectId = resolveProjectId(for: filename)

        return MemoryClassification(
            filename: filename,
            scope: scope,
            category: category,
            projectId: projectId
        )
    }

    /// Classify all .md files in a directory. Skips MEMORY.md.
    public func classifyDirectory(at path: String) throws -> [MemoryClassification] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else {
            throw MemoryClassifierError.directoryNotFound(path)
        }

        let contents = try fm.contentsOfDirectory(atPath: path)
        let mdFiles = contents.filter { $0.hasSuffix(".md") }.sorted()

        return mdFiles.compactMap { classify($0) }
    }

    // MARK: - BR-27 Classification Rules

    private func scopeAndCategory(for filename: String) -> (MemoryScope, MemoryCategory) {
        // User identity / PII
        if filename.hasPrefix("user_") {
            return (.personal, .identity)
        }
        if filename == "email-signature.md" {
            return (.personal, .identity)
        }

        // Feedback files — personal preferences
        if filename.hasPrefix("feedback_") {
            return (.personal, .preference)
        }

        // Radar references — personal
        if filename.hasPrefix("reference_") && filename.contains("-radar") {
            return (.personal, .radar)
        }

        // Other references — company
        if filename.hasPrefix("reference_") {
            return (.company, .reference)
        }

        // Maya backlog (special case — no project_ prefix)
        if filename == "maya-backlog.md" {
            return (.project, .backlog)
        }

        // Media strategy
        if filename == "media-strategy.md" {
            return (.company, .strategy)
        }

        // Object storage
        if filename == "object-storage.md" {
            return (.company, .infrastructure)
        }

        // Project files with specific patterns
        if filename.hasPrefix("project_") {
            return classifyProjectFile(filename)
        }

        // Fallback: anything else is project/plan
        return (.project, .plan)
    }

    private func classifyProjectFile(_ filename: String) -> (MemoryScope, MemoryCategory) {
        // IAL / fundraising / prelaunch — personal strategy
        if filename.hasPrefix("project_ial-") {
            return (.personal, .strategy)
        }
        if filename.contains("-fundraising") {
            return (.personal, .strategy)
        }
        if filename.contains("-prelaunch") {
            return (.personal, .strategy)
        }
        if filename == "project_haiku-conversion-strategy.md" {
            return (.personal, .strategy)
        }

        // Ownership structure — company infrastructure
        if filename == "project_ownership-structure.md" {
            return (.company, .infrastructure)
        }

        // Vision documents — company
        if filename.contains("-vision") {
            return (.company, .vision)
        }

        // Backlog documents — project
        if filename.contains("-backlog") {
            return (.project, .backlog)
        }

        // Decision documents — project
        if filename.contains("-decision") {
            return (.project, .decision)
        }

        // Plan / roadmap documents — project
        if filename.contains("-plan") || filename.contains("-roadmap") {
            return (.project, .plan)
        }

        // Branding / domain — company vision
        if filename == "project_branding-domain.md" {
            return (.company, .vision)
        }

        // Local LLM cluster — company vision
        if filename == "project_local-llm-cluster-vision.md" {
            return (.company, .vision)
        }

        // Agent skills audit — company reference
        if filename.hasPrefix("project_agent-skills-audit") {
            return (.company, .reference)
        }

        // Fallback for remaining project_ files
        return (.project, .plan)
    }

    // MARK: - Project Association (BR-08)

    private func resolveProjectId(for filename: String) -> String? {
        let lower = filename.lowercased()

        if lower.contains("maya") || lower.hasPrefix("project_ial-") {
            return Self.projectMaya
        }
        if lower.contains("wabisabi") || lower.contains("wabi-sabi") {
            return Self.projectWabiSabi
        }
        if lower.contains("brainy") || lower.contains("brainytube") {
            return Self.projectBrainy
        }
        if lower.contains("flsh") {
            return Self.projectFlsh
        }
        if lower.contains("shikki") || lower.contains("shiki") {
            return Self.projectShiki
        }

        return nil
    }
}

public enum MemoryClassifierError: Error, CustomStringConvertible {
    case directoryNotFound(String)

    public var description: String {
        switch self {
        case .directoryNotFound(let path):
            "Memory directory not found: \(path)"
        }
    }
}
