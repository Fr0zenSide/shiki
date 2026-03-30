import Foundation

/// Generates implementation prompts for agents working on ``WorkUnit``s.
///
/// Each prompt includes:
/// 1. The protocol contracts to implement against
/// 2. Architecture context from the project cache
/// 3. File-specific instructions (what to create, what patterns to follow)
/// 4. Test expectations
///
/// Language-agnostic design: the prompt structure works for any language.
/// Swift-specific details come from the ArchitectureCache, not the generator.
public struct AgentPromptGenerator: Sendable {

    public init() {}

    /// Generate a complete implementation prompt for a work unit.
    ///
    /// - Parameters:
    ///   - unit: The work unit to generate a prompt for.
    ///   - layer: The protocol layer (contracts).
    ///   - cache: Optional architecture cache for project context.
    /// - Returns: A markdown-formatted prompt string.
    public func generate(
        for unit: WorkUnit,
        layer: ProtocolLayer,
        cache: ArchitectureCache? = nil
    ) -> String {
        var sections: [String] = []

        // Header
        sections.append(generateHeader(unit, layer: layer))

        // Architecture context (if cache available)
        if let cache {
            sections.append(generateArchitectureContext(cache))
        }

        // Protocol contracts
        sections.append(generateContracts(unit, layer: layer))

        // File instructions
        sections.append(generateFileInstructions(unit))

        // Test expectations
        sections.append(generateTestExpectations(unit, layer: layer, cache: cache))

        // Constraints
        sections.append(generateConstraints(cache: cache))

        return sections.joined(separator: "\n\n")
    }

    /// Generate a compact prompt for sequential (inline) execution.
    public func generateCompact(
        for unit: WorkUnit,
        layer: ProtocolLayer,
        cache: ArchitectureCache? = nil
    ) -> String {
        var lines: [String] = []

        lines.append("# Implement: \(unit.description)")
        lines.append("")

        // Compact contracts
        let relevantProtos = layer.protocols.filter { unit.protocolNames.contains($0.name) }
        if !relevantProtos.isEmpty {
            lines.append("## Contracts")
            let verifier = ContractVerifier()
            let compactLayer = ProtocolLayer(
                featureName: layer.featureName,
                protocols: relevantProtos,
                types: layer.types.filter { unit.typeNames.contains($0.name) },
                targetModule: layer.targetModule
            )
            lines.append("```swift")
            lines.append(verifier.generateSource(compactLayer))
            lines.append("```")
        }

        // File list
        lines.append("## Files to create")
        for file in unit.files {
            lines.append("- `\(file.path)` (\(file.role.rawValue))\(file.description.isEmpty ? "" : " — \(file.description)")")
        }

        // Architecture hint
        if let cache {
            lines.append("")
            lines.append("## Project context")
            lines.append(ContextBuilder.agentSummary(cache))
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Sections

    func generateHeader(_ unit: WorkUnit, layer: ProtocolLayer) -> String {
        """
        # Agent Task: \(unit.description)

        You are implementing part of the **\(layer.featureName)** feature.
        Your work unit: `\(unit.id)` (priority \(unit.priority))
        Branch: `\(unit.worktreeBranch)`

        **Important**: Implement ONLY the files listed below. Do not modify files outside your scope.
        The protocol contracts are your API — implement against them exactly.
        """
    }

    func generateArchitectureContext(_ cache: ArchitectureCache) -> String {
        var lines: [String] = []
        lines.append("## Project Architecture")
        lines.append("")
        lines.append(ContextBuilder.agentSummary(cache))

        // Add relevant patterns
        if !cache.patterns.isEmpty {
            lines.append("")
            lines.append("### Code Patterns to Follow")
            for pattern in cache.patterns {
                lines.append("- **\(pattern.name)**: \(pattern.description)")
                if !pattern.example.isEmpty {
                    lines.append("  ```swift")
                    lines.append("  \(pattern.example.prefix(200))")
                    lines.append("  ```")
                }
            }
        }

        // Test conventions
        lines.append("")
        lines.append("### Test Conventions")
        lines.append("- Framework: \(cache.testInfo.framework)")
        if let mock = cache.testInfo.mockPattern {
            lines.append("- Mock pattern: \(mock)")
        }
        if let fixture = cache.testInfo.fixturePattern {
            lines.append("- Fixture pattern: \(fixture)")
        }

        return lines.joined(separator: "\n")
    }

    func generateContracts(_ unit: WorkUnit, layer: ProtocolLayer) -> String {
        var lines: [String] = []
        lines.append("## Protocol Contracts")
        lines.append("")
        lines.append("These are the contracts you must implement against. Do NOT modify the protocols.")
        lines.append("")

        let verifier = ContractVerifier()

        // Filter to relevant protocols
        let relevantProtos = layer.protocols.filter { proto in
            unit.protocolNames.contains(proto.name)
        }

        // Include all types since they might be referenced
        let relevantLayer = ProtocolLayer(
            featureName: layer.featureName,
            protocols: relevantProtos.isEmpty ? layer.protocols : relevantProtos,
            types: layer.types,
            targetModule: layer.targetModule
        )

        lines.append("```swift")
        lines.append(verifier.generateSource(relevantLayer))
        lines.append("```")

        // Protocol details with method signatures
        for proto in (relevantProtos.isEmpty ? layer.protocols : relevantProtos) {
            if !proto.methods.isEmpty {
                lines.append("")
                lines.append("### \(proto.name)")
                for method in proto.methods {
                    lines.append("- `\(method)`")
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    func generateFileInstructions(_ unit: WorkUnit) -> String {
        var lines: [String] = []
        lines.append("## Files to Create")
        lines.append("")

        for file in unit.files {
            let roleEmoji: String
            switch file.role {
            case .protocol: roleEmoji = "protocol"
            case .model: roleEmoji = "model"
            case .implementation: roleEmoji = "impl"
            case .test: roleEmoji = "test"
            case .mock: roleEmoji = "mock"
            }
            lines.append("### `\(file.path)` [\(roleEmoji)]")
            if !file.description.isEmpty {
                lines.append(file.description)
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    func generateTestExpectations(_ unit: WorkUnit, layer: ProtocolLayer, cache: ArchitectureCache?) -> String {
        var lines: [String] = []
        lines.append("## Test Expectations")
        lines.append("")

        if !unit.testScope.isEmpty {
            lines.append("Tests that must pass after your implementation:")
            for test in unit.testScope {
                lines.append("- `\(test)`")
            }
        } else {
            lines.append("Create tests for every public method/type you implement.")
        }

        // Framework guidance
        let framework = cache?.testInfo.framework ?? "swift-testing"
        lines.append("")
        if framework == "swift-testing" || framework == "mixed" {
            lines.append("Use Swift Testing framework (`import Testing`, `@Test`, `@Suite`, `#expect`).")
        } else {
            lines.append("Use XCTest framework (`import XCTest`, `XCTestCase`, `XCTAssert*`).")
        }

        return lines.joined(separator: "\n")
    }

    func generateConstraints(cache: ArchitectureCache?) -> String {
        var lines: [String] = []
        lines.append("## Constraints")
        lines.append("")
        lines.append("- Implement ONLY your assigned files — do not touch other files")
        lines.append("- Follow the protocol contracts exactly — do not add extra methods")
        lines.append("- All types must be `Sendable` unless explicitly marked otherwise")
        lines.append("- All public APIs must have doc comments")
        lines.append("- No `print()` in production code or tests")
        lines.append("- Run `swift build` to verify compilation before finishing")

        if let cache, !cache.packageInfo.dependencies.isEmpty {
            lines.append("- Available dependencies: \(cache.packageInfo.dependencies.map(\.name).joined(separator: ", "))")
        }

        return lines.joined(separator: "\n")
    }
}
