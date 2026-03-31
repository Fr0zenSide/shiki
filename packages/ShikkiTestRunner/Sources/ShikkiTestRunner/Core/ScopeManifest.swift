// MARK: - ScopeManifest
// Model for scope definitions — loadable from Moto cache or manual JSON config.

import Foundation

/// A single scope definition that maps architecture modules to test files.
public struct ScopeDefinition: Sendable, Codable, Equatable, Hashable {
    /// Unique name for this scope (e.g. "nats", "flywheel", "kernel").
    public let name: String

    /// Module names that belong to this scope (matched against `import` statements).
    /// Example: ["NATSClient", "NATSProtocol"]
    public let modulePatterns: [String]

    /// Type names that belong to this scope (matched against type references in test files).
    /// Example: ["NATSClientProtocol", "EventBus", "NATSConnection"]
    public let typePatterns: [String]

    /// Glob patterns for test files that explicitly belong to this scope.
    /// Example: ["**/NATS*Tests.swift", "**/EventBus*Tests.swift"]
    public let testFilePatterns: [String]

    public init(
        name: String,
        modulePatterns: [String] = [],
        typePatterns: [String] = [],
        testFilePatterns: [String] = []
    ) {
        self.name = name
        self.modulePatterns = modulePatterns
        self.typePatterns = typePatterns
        self.testFilePatterns = testFilePatterns
    }
}

/// The full manifest describing all scopes for a project.
public struct ScopeManifest: Sendable, Codable, Equatable {
    /// Ordered list of scope definitions. Order matters: first match wins.
    public let scopes: [ScopeDefinition]

    /// Source of this manifest (for diagnostics).
    public let source: ManifestSource

    public init(scopes: [ScopeDefinition], source: ManifestSource) {
        self.scopes = scopes
        self.source = source
    }

    /// Where the manifest was loaded from.
    public enum ManifestSource: Sendable, Codable, Equatable {
        case motoCache
        case jsonConfig(path: String)
        case defaultFallback
    }
}

// MARK: - Validation

extension ScopeManifest {

    /// Validation errors found in the manifest.
    public enum ValidationError: Error, Equatable, Sendable {
        case duplicateScopeName(String)
        case emptyScopeDefinition(String)
        case reservedScopeName(String)
    }

    /// Validate the manifest for correctness.
    /// - Returns: Array of validation errors (empty if valid).
    public func validate() -> [ValidationError] {
        var errors: [ValidationError] = []
        var seenNames: Set<String> = []

        for scope in scopes {
            if seenNames.contains(scope.name) {
                errors.append(.duplicateScopeName(scope.name))
            }
            seenNames.insert(scope.name)

            if scope.modulePatterns.isEmpty
                && scope.typePatterns.isEmpty
                && scope.testFilePatterns.isEmpty
            {
                errors.append(.emptyScopeDefinition(scope.name))
            }

            if scope.name == "unscoped" {
                errors.append(.reservedScopeName(scope.name))
            }
        }

        return errors
    }

    /// Whether this manifest passes all validation checks.
    public var isValid: Bool {
        validate().isEmpty
    }
}

// MARK: - JSON Loading

extension ScopeManifest {

    /// Load a manifest from a JSON file at the given path.
    public static func load(from path: String) throws -> ScopeManifest {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(ScopeManifest.self, from: data)
        return ScopeManifest(
            scopes: decoded.scopes,
            source: .jsonConfig(path: path)
        )
    }

    /// Encode this manifest to JSON data.
    public func toJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

// MARK: - Default Scopes (Hardcoded Fallback)

extension ScopeManifest {

    /// Default scope manifest for the Shikki project.
    /// Used as fallback when no Moto cache or JSON config is available.
    public static let shikkiDefaults = ScopeManifest(
        scopes: [
            ScopeDefinition(
                name: "nats",
                modulePatterns: ["NATSClient", "NATSProtocol"],
                typePatterns: [
                    "NATSClientProtocol", "NATSConnection", "NATSSubscription",
                    "EventBus", "EventRouter",
                ],
                testFilePatterns: ["**/NATS*Tests.swift", "**/EventBus*Tests.swift"]
            ),
            ScopeDefinition(
                name: "flywheel",
                modulePatterns: ["Flywheel"],
                typePatterns: [
                    "CalibrationStore", "RiskScoringEngine", "FlywheelEngine",
                    "CommunityFlywheel",
                ],
                testFilePatterns: ["**/Flywheel*Tests.swift", "**/Calibration*Tests.swift"]
            ),
            ScopeDefinition(
                name: "tui",
                modulePatterns: ["TUI", "TerminalKit"],
                typePatterns: [
                    "TerminalOutput", "ANSIRenderer", "PaletteEngine",
                    "TUIComponent", "ProgressBar",
                ],
                testFilePatterns: ["**/TUI*Tests.swift", "**/Terminal*Tests.swift"]
            ),
            ScopeDefinition(
                name: "safety",
                modulePatterns: ["Safety"],
                typePatterns: [
                    "BudgetACL", "AuditLogger", "AnomalyDetector",
                    "SafetyGuard",
                ],
                testFilePatterns: ["**/Safety*Tests.swift", "**/Budget*Tests.swift"]
            ),
            ScopeDefinition(
                name: "codegen",
                modulePatterns: ["CodeGen", "ArchitectureKit"],
                typePatterns: [
                    "ArchitectureCache", "SpecParser", "CodeGenerator",
                    "TemplateEngine",
                ],
                testFilePatterns: ["**/CodeGen*Tests.swift", "**/Spec*Tests.swift"]
            ),
            ScopeDefinition(
                name: "observatory",
                modulePatterns: ["Observatory"],
                typePatterns: [
                    "DecisionJournal", "AgentReportCard", "OversightDashboard",
                ],
                testFilePatterns: ["**/Observatory*Tests.swift", "**/Decision*Tests.swift"]
            ),
            ScopeDefinition(
                name: "ship",
                modulePatterns: ["Ship"],
                typePatterns: [
                    "ShipGate", "VersionBumper", "ReleaseManager",
                    "ChangelogGenerator",
                ],
                testFilePatterns: ["**/Ship*Tests.swift", "**/Release*Tests.swift"]
            ),
            ScopeDefinition(
                name: "kernel",
                modulePatterns: ["ShikkiKit"],
                typePatterns: [
                    "ShikkiKernel", "ManagedService", "ServiceLifecycle",
                    "KernelState",
                ],
                testFilePatterns: ["**/Kernel*Tests.swift", "**/ShikkiKernel*Tests.swift"]
            ),
            ScopeDefinition(
                name: "answer-engine",
                modulePatterns: ["AnswerEngine"],
                typePatterns: [
                    "BM25Index", "SourceChunker", "AnswerPipeline",
                    "RetrievalRouter",
                ],
                testFilePatterns: ["**/AnswerEngine*Tests.swift", "**/BM25*Tests.swift"]
            ),
            ScopeDefinition(
                name: "s3-parser",
                modulePatterns: ["S3Parser"],
                typePatterns: [
                    "S3Parser", "S3Validator", "S3Lexer", "S3Token",
                ],
                testFilePatterns: ["**/S3*Tests.swift"]
            ),
            ScopeDefinition(
                name: "blue-flame",
                modulePatterns: ["BlueFlame"],
                typePatterns: [
                    "FlameEmotion", "FlameRenderer", "PersonalityEngine",
                ],
                testFilePatterns: ["**/Flame*Tests.swift", "**/BlueFlame*Tests.swift"]
            ),
            ScopeDefinition(
                name: "moto",
                modulePatterns: ["Moto", "MotoKit"],
                typePatterns: [
                    "MotoDotfile", "MotoCacheBuilder", "MotoResolver",
                ],
                testFilePatterns: ["**/Moto*Tests.swift"]
            ),
            ScopeDefinition(
                name: "memory",
                modulePatterns: ["MemoryKit"],
                typePatterns: [
                    "MemoryClassifier", "MemoryFileScanner", "MemoryStore",
                ],
                testFilePatterns: ["**/Memory*Tests.swift"]
            ),
        ],
        source: .defaultFallback
    )
}
