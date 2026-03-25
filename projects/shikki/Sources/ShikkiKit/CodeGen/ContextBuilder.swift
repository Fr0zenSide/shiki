import Foundation

/// Builds compact, agent-friendly context strings from ``ArchitectureCache``.
///
/// Produces structured text summaries that give agents instant project knowledge
/// without reading source files directly.
public enum ContextBuilder {

    /// Full project overview (~2K tokens instead of reading 20 files).
    public static func projectOverview(_ cache: ArchitectureCache) -> String {
        var lines: [String] = []

        lines.append("# Project: \(cache.packageInfo.name.isEmpty ? cache.projectId : cache.packageInfo.name)")
        lines.append("Path: \(cache.projectPath)")
        lines.append("Git: \(cache.gitHash)")
        lines.append("Cached: \(formatDate(cache.builtAt))")
        lines.append("")

        // Package info
        if !cache.packageInfo.platforms.isEmpty {
            lines.append("## Platforms")
            lines.append(cache.packageInfo.platforms.joined(separator: ", "))
            lines.append("")
        }

        // Targets
        if !cache.packageInfo.targets.isEmpty {
            lines.append("## Targets")
            for target in cache.packageInfo.targets {
                let typeLabel = target.type.rawValue.uppercased()
                let deps = target.dependencies.isEmpty ? "" : " (deps: \(target.dependencies.joined(separator: ", ")))"
                lines.append("- [\(typeLabel)] \(target.name) — \(target.sourceFiles) files\(deps)")
            }
            lines.append("")
        }

        // Dependencies
        if !cache.packageInfo.dependencies.isEmpty {
            lines.append("## Dependencies")
            for dep in cache.packageInfo.dependencies {
                if dep.isLocal {
                    lines.append("- \(dep.name) (local: \(dep.path ?? "?"))")
                } else {
                    lines.append("- \(dep.name) (\(dep.url ?? "?"))")
                }
            }
            lines.append("")
        }

        // Protocols
        if !cache.protocols.isEmpty {
            lines.append("## Protocols (\(cache.protocols.count))")
            for proto in cache.protocols {
                let conformers = proto.conformers.isEmpty ? "" : " — impl: \(proto.conformers.joined(separator: ", "))"
                lines.append("- \(proto.name) [\(proto.module)] \(proto.methods.count) methods\(conformers)")
            }
            lines.append("")
        }

        // Types summary (grouped by kind)
        if !cache.types.isEmpty {
            lines.append("## Types (\(cache.types.count))")
            let grouped = Dictionary(grouping: cache.types, by: \.kind)
            for kind in [TypeKind.struct, .class, .enum, .actor] {
                if let types = grouped[kind], !types.isEmpty {
                    let names = types.prefix(15).map(\.name).joined(separator: ", ")
                    let suffix = types.count > 15 ? " (+\(types.count - 15) more)" : ""
                    lines.append("- \(kind.rawValue)s: \(names)\(suffix)")
                }
            }
            lines.append("")
        }

        // Patterns
        if !cache.patterns.isEmpty {
            lines.append("## Patterns")
            for pattern in cache.patterns {
                lines.append("- **\(pattern.name)**: \(pattern.description)")
            }
            lines.append("")
        }

        // Test info
        lines.append("## Tests")
        lines.append("- Framework: \(cache.testInfo.framework)")
        lines.append("- Files: \(cache.testInfo.testFiles), Tests: \(cache.testInfo.testCount)")
        if let mock = cache.testInfo.mockPattern {
            lines.append("- Mock pattern: \(mock)")
        }
        if let fixture = cache.testInfo.fixturePattern {
            lines.append("- Fixtures: \(fixture)")
        }

        return lines.joined(separator: "\n")
    }

    /// Protocol details with all implementations.
    public static func protocolContext(_ name: String, cache: ArchitectureCache) -> String {
        guard let proto = cache.protocols.first(where: { $0.name == name }) else {
            return "Protocol '\(name)' not found in cache."
        }

        var lines: [String] = []
        lines.append("# Protocol: \(proto.name)")
        lines.append("Module: \(proto.module)")
        lines.append("File: \(proto.file)")
        lines.append("")

        if !proto.methods.isEmpty {
            lines.append("## Methods")
            for method in proto.methods {
                lines.append("  \(method)")
            }
            lines.append("")
        }

        if !proto.conformers.isEmpty {
            lines.append("## Implementations")
            for conformer in proto.conformers {
                if let type = cache.types.first(where: { $0.name == conformer }) {
                    lines.append("- \(conformer) (\(type.kind.rawValue), \(type.file))")
                } else {
                    lines.append("- \(conformer)")
                }
            }
        } else {
            lines.append("No known implementations.")
        }

        return lines.joined(separator: "\n")
    }

    /// Type with relationships.
    public static func typeContext(_ name: String, cache: ArchitectureCache) -> String {
        guard let type = cache.types.first(where: { $0.name == name }) else {
            return "Type '\(name)' not found in cache."
        }

        var lines: [String] = []
        lines.append("# \(type.kind.rawValue.capitalized): \(type.name)")
        lines.append("Module: \(type.module)")
        lines.append("File: \(type.file)")
        lines.append("Public: \(type.isPublic ? "yes" : "no")")
        lines.append("")

        if !type.conformances.isEmpty {
            lines.append("## Conformances")
            lines.append(type.conformances.joined(separator: ", "))
            lines.append("")
        }

        if !type.fields.isEmpty {
            lines.append("## Fields")
            for field in type.fields {
                lines.append("  - \(field)")
            }
            lines.append("")
        }

        // Find protocols this type implements
        let implementedProtocols = cache.protocols.filter { $0.conformers.contains(name) }
        if !implementedProtocols.isEmpty {
            lines.append("## Implements Protocols")
            for proto in implementedProtocols {
                lines.append("- \(proto.name) (\(proto.methods.count) methods)")
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Relevant patterns for a given task description.
    public static func patternContext(for task: String, cache: ArchitectureCache) -> String {
        guard !cache.patterns.isEmpty else {
            return "No patterns detected in project."
        }

        let taskLower = task.lowercased()

        // Score patterns by relevance to the task
        let scored = cache.patterns.map { pattern -> (CodePattern, Int) in
            var score = 0
            if taskLower.contains(pattern.name.replacingOccurrences(of: "_", with: " ")) { score += 10 }
            if taskLower.contains("error") && pattern.name.contains("error") { score += 5 }
            if taskLower.contains("mock") && pattern.name.contains("mock") { score += 5 }
            if taskLower.contains("test") && pattern.name.contains("mock") { score += 3 }
            if taskLower.contains("api") && pattern.name.contains("endpoint") { score += 5 }
            if taskLower.contains("endpoint") && pattern.name.contains("endpoint") { score += 5 }
            // Every pattern gets base score of 1 to show up
            return (pattern, max(score, 1))
        }.sorted { $0.1 > $1.1 }

        var lines: [String] = []
        lines.append("# Patterns for: \(task)")
        lines.append("")

        for (pattern, _) in scored {
            lines.append("## \(pattern.name)")
            lines.append(pattern.description)
            lines.append("Files: \(pattern.files.joined(separator: ", "))")
            if !pattern.example.isEmpty {
                lines.append("```swift")
                lines.append(pattern.example)
                lines.append("```")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    /// Compact summary for agent prompt injection (~500 tokens).
    public static func agentSummary(_ cache: ArchitectureCache) -> String {
        var lines: [String] = []
        let name = cache.packageInfo.name.isEmpty ? cache.projectId : cache.packageInfo.name

        lines.append("Project: \(name) | \(cache.packageInfo.platforms.joined(separator: ", "))")

        // Targets one-liner
        let targetSummary = cache.packageInfo.targets.map { t in
            "\(t.name)(\(t.type.rawValue.prefix(3)),\(t.sourceFiles)f)"
        }.joined(separator: " ")
        if !targetSummary.isEmpty {
            lines.append("Targets: \(targetSummary)")
        }

        // Key protocols
        if !cache.protocols.isEmpty {
            let protoNames = cache.protocols.prefix(10).map(\.name).joined(separator: ", ")
            lines.append("Protocols: \(protoNames)")
        }

        // Key types (only public)
        let publicTypes = cache.types.filter(\.isPublic)
        if !publicTypes.isEmpty {
            let typeNames = publicTypes.prefix(15).map(\.name).joined(separator: ", ")
            lines.append("Public types: \(typeNames)")
        }

        // Deps
        if !cache.packageInfo.dependencies.isEmpty {
            let depNames = cache.packageInfo.dependencies.map(\.name).joined(separator: ", ")
            lines.append("Deps: \(depNames)")
        }

        // Patterns one-liner
        if !cache.patterns.isEmpty {
            let patternNames = cache.patterns.map(\.name).joined(separator: ", ")
            lines.append("Patterns: \(patternNames)")
        }

        // Tests one-liner
        lines.append("Tests: \(cache.testInfo.framework), \(cache.testInfo.testCount) tests in \(cache.testInfo.testFiles) files")

        return lines.joined(separator: "\n")
    }

    // MARK: - Private

    private static func formatDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        return formatter.string(from: date)
    }
}
