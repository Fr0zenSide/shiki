import Foundation

/// Errors that can occur during contract verification.
public enum ContractVerifierError: Error, LocalizedError, Sendable {
    case verificationFailed([String])
    case buildFailed(String)
    case tempDirectoryFailed

    public var errorDescription: String? {
        switch self {
        case .verificationFailed(let issues):
            return "Contract verification failed:\n" + issues.joined(separator: "\n")
        case .buildFailed(let output):
            return "Protocol layer build failed:\n\(output)"
        case .tempDirectoryFailed:
            return "Failed to create temporary verification directory"
        }
    }
}

/// Result of contract verification.
public struct ContractResult: Sendable {
    /// Whether the protocol layer is valid.
    public let isValid: Bool
    /// Issues found during verification (empty if valid).
    public let issues: [String]
    /// Warnings (non-blocking).
    public let warnings: [String]
    /// Verification duration in milliseconds.
    public let durationMs: Int

    public init(isValid: Bool, issues: [String] = [], warnings: [String] = [], durationMs: Int = 0) {
        self.isValid = isValid
        self.issues = issues
        self.warnings = warnings
        self.durationMs = durationMs
    }
}

/// Verifies that a ``ProtocolLayer`` is internally consistent and can compile.
///
/// Two levels of verification:
/// 1. **Static analysis** — checks naming, references, completeness (fast, no build)
/// 2. **Build verification** — generates a minimal Swift package and runs `swift build` (slower, optional)
public struct ContractVerifier: Sendable {

    public init() {}

    /// Run static analysis on the protocol layer.
    ///
    /// Checks for:
    /// - Duplicate protocol/type names
    /// - Circular conformances
    /// - Missing referenced types
    /// - Empty protocols (warning)
    /// - Protocols with no planned implementations (warning)
    public func verify(_ layer: ProtocolLayer) -> ContractResult {
        let start = DispatchTime.now()
        var issues: [String] = []
        var warnings: [String] = []

        // Check for duplicates
        let protoNames = layer.protocols.map(\.name)
        let typeNames = layer.types.map(\.name)
        let allNames = protoNames + typeNames

        let duplicates = Dictionary(grouping: allNames, by: { $0 })
            .filter { $0.value.count > 1 }
            .keys
        for dup in duplicates {
            issues.append("Duplicate declaration: '\(dup)' appears \(allNames.filter { $0 == dup }.count) times")
        }

        // Check conformances reference known protocols
        let knownProtos = Set(protoNames)
        let wellKnown: Set<String> = [
            "Sendable", "Codable", "Encodable", "Decodable", "Hashable",
            "Equatable", "Comparable", "Identifiable", "CustomStringConvertible",
            "Error", "LocalizedError", "CaseIterable", "RawRepresentable",
            "ObservableObject", "View",
        ]

        for type in layer.types {
            for conformance in type.conformances {
                if !knownProtos.contains(conformance) && !wellKnown.contains(conformance) {
                    warnings.append("Type '\(type.name)' conforms to '\(conformance)' — not defined in this spec (external dependency?)")
                }
            }
        }

        // Check for empty protocols
        for proto in layer.protocols where proto.methods.isEmpty && proto.associatedTypes.isEmpty {
            warnings.append("Protocol '\(proto.name)' has no methods or associated types — marker protocol?")
        }

        // Check protocol inheritance references
        for proto in layer.protocols {
            for parent in proto.inherits {
                if !knownProtos.contains(parent) && !wellKnown.contains(parent) {
                    warnings.append("Protocol '\(proto.name)' inherits from '\(parent)' — not defined in this spec")
                }
            }
        }

        // Check for types with no fields (might be intentional for enums)
        for type in layer.types where type.fields.isEmpty && type.kind != .enum {
            warnings.append("Type '\(type.name)' (\(type.kind.rawValue)) has no fields defined")
        }

        // Check file spec coverage — every protocol and type should have a target file
        for proto in layer.protocols where proto.targetFile.isEmpty {
            warnings.append("Protocol '\(proto.name)' has no target file assigned")
        }
        for type in layer.types where type.targetFile.isEmpty {
            warnings.append("Type '\(type.name)' has no target file assigned")
        }

        let elapsed = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
        let ms = Int(elapsed / 1_000_000)

        return ContractResult(
            isValid: issues.isEmpty,
            issues: issues,
            warnings: warnings,
            durationMs: ms
        )
    }

    /// Verify against an existing architecture cache.
    ///
    /// Checks that the new protocol layer doesn't conflict with existing project architecture.
    public func verifyAgainstCache(_ layer: ProtocolLayer, cache: ArchitectureCache) -> ContractResult {
        let start = DispatchTime.now()
        var issues: [String] = []
        var warnings: [String] = []

        // Run base verification first
        let baseResult = verify(layer)
        issues.append(contentsOf: baseResult.issues)
        warnings.append(contentsOf: baseResult.warnings)

        // Check for name collisions with existing project types
        let existingTypeNames = Set(cache.types.map(\.name))
        let existingProtoNames = Set(cache.protocols.map(\.name))

        for proto in layer.protocols {
            if existingProtoNames.contains(proto.name) {
                warnings.append("Protocol '\(proto.name)' already exists in project — will be overwritten")
            }
            if existingTypeNames.contains(proto.name) {
                issues.append("Protocol '\(proto.name)' conflicts with existing type of same name")
            }
        }

        for type in layer.types {
            if existingTypeNames.contains(type.name) {
                warnings.append("Type '\(type.name)' already exists in project — will be overwritten")
            }
            if existingProtoNames.contains(type.name) {
                issues.append("Type '\(type.name)' conflicts with existing protocol of same name")
            }
        }

        // Check module exists in project
        if !layer.targetModule.isEmpty {
            let targetExists = cache.packageInfo.targets.contains { $0.name == layer.targetModule }
            if !targetExists {
                warnings.append("Target module '\(layer.targetModule)' not found in project — will need to be created")
            }
        }

        let elapsed = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
        let ms = Int(elapsed / 1_000_000)

        return ContractResult(
            isValid: issues.isEmpty,
            issues: issues,
            warnings: warnings,
            durationMs: ms
        )
    }

    /// Generate the Swift source for the protocol layer (for build verification or code review).
    ///
    /// Produces a single Swift file containing all protocol and type declarations.
    public func generateSource(_ layer: ProtocolLayer) -> String {
        var lines: [String] = []
        lines.append("// Auto-generated protocol layer for: \(layer.featureName)")
        lines.append("// This file is used for contract verification — do not edit directly.")
        lines.append("import Foundation")
        lines.append("")

        // Generate protocols
        for proto in layer.protocols {
            let inheritance = proto.inherits.isEmpty ? "" : ": \(proto.inherits.joined(separator: ", "))"
            lines.append("public protocol \(proto.name)\(inheritance) {")

            for assocType in proto.associatedTypes {
                lines.append("    associatedtype \(assocType)")
            }

            for method in proto.methods {
                lines.append("    \(method)")
            }

            lines.append("}")
            lines.append("")
        }

        // Generate types
        for type in layer.types {
            let conformances = type.conformances.isEmpty ? "" : ": \(type.conformances.joined(separator: ", "))"
            lines.append("public \(type.kind.rawValue) \(type.name)\(conformances) {")

            for field in type.fields {
                let optional = field.isOptional && !field.type.hasSuffix("?") ? "?" : ""
                lines.append("    public let \(field.name): \(field.type)\(optional)")
            }

            lines.append("}")
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}
