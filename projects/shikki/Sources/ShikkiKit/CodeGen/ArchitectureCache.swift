import Foundation

/// Cached architecture snapshot for a project.
///
/// Built by ``ProjectAnalyzer`` and persisted by ``CacheStore``.
/// Agents query this instead of reading 20+ source files.
public struct ArchitectureCache: Sendable, Codable {
    /// Project identifier (directory name, e.g. "brainy", "wabisabi").
    public let projectId: String
    /// Absolute path to the project root.
    public let projectPath: String
    /// Git commit hash when the cache was built.
    public let gitHash: String
    /// Timestamp of cache construction.
    public let builtAt: Date

    /// SPM package structure.
    public var packageInfo: PackageInfo
    /// All protocols discovered in the project.
    public var protocols: [ProtocolDescriptor]
    /// All types (structs, enums, classes, actors) discovered.
    public var types: [TypeDescriptor]
    /// Dependency graph: module name -> imported modules.
    public var dependencyGraph: [String: [String]]
    /// Detected code patterns (error handling, mocks, endpoints, etc.).
    public var patterns: [CodePattern]
    /// Test conventions and statistics.
    public var testInfo: TestInfo
    /// Shared utility functions used across multiple files.
    public var sharedUtilities: [SharedUtility]

    public init(
        projectId: String,
        projectPath: String,
        gitHash: String,
        builtAt: Date,
        packageInfo: PackageInfo,
        protocols: [ProtocolDescriptor],
        types: [TypeDescriptor],
        dependencyGraph: [String: [String]],
        patterns: [CodePattern],
        testInfo: TestInfo,
        sharedUtilities: [SharedUtility] = []
    ) {
        self.projectId = projectId
        self.projectPath = projectPath
        self.gitHash = gitHash
        self.builtAt = builtAt
        self.packageInfo = packageInfo
        self.protocols = protocols
        self.types = types
        self.dependencyGraph = dependencyGraph
        self.patterns = patterns
        self.testInfo = testInfo
        self.sharedUtilities = sharedUtilities
    }
}

// MARK: - Package Info

public struct PackageInfo: Sendable, Codable {
    public var name: String
    public var platforms: [String]
    public var targets: [TargetInfo]
    public var dependencies: [DependencyInfo]

    public init(
        name: String = "",
        platforms: [String] = [],
        targets: [TargetInfo] = [],
        dependencies: [DependencyInfo] = []
    ) {
        self.name = name
        self.platforms = platforms
        self.targets = targets
        self.dependencies = dependencies
    }
}

public struct TargetInfo: Sendable, Codable {
    public var name: String
    public var type: TargetType
    public var path: String
    public var dependencies: [String]
    public var sourceFiles: Int

    public init(
        name: String,
        type: TargetType,
        path: String = "",
        dependencies: [String] = [],
        sourceFiles: Int = 0
    ) {
        self.name = name
        self.type = type
        self.path = path
        self.dependencies = dependencies
        self.sourceFiles = sourceFiles
    }
}

public enum TargetType: String, Sendable, Codable {
    case library
    case executable
    case test
}

public struct DependencyInfo: Sendable, Codable {
    public var name: String
    public var isLocal: Bool
    public var path: String?
    public var url: String?

    public init(name: String, isLocal: Bool, path: String? = nil, url: String? = nil) {
        self.name = name
        self.isLocal = isLocal
        self.path = path
        self.url = url
    }
}

// MARK: - Protocol Descriptor

public struct ProtocolDescriptor: Sendable, Codable {
    public var name: String
    /// Relative path from project root.
    public var file: String
    /// Method signatures declared in the protocol.
    public var methods: [String]
    /// Type names that conform to this protocol.
    public var conformers: [String]
    /// SPM target this protocol belongs to.
    public var module: String

    public init(
        name: String,
        file: String = "",
        methods: [String] = [],
        conformers: [String] = [],
        module: String = ""
    ) {
        self.name = name
        self.file = file
        self.methods = methods
        self.conformers = conformers
        self.module = module
    }
}

// MARK: - Type Descriptor

public struct TypeDescriptor: Sendable, Codable {
    public var name: String
    public var kind: TypeKind
    /// Relative path from project root.
    public var file: String
    /// SPM target this type belongs to.
    public var module: String
    /// Property names.
    public var fields: [String]
    /// Protocol conformance names.
    public var conformances: [String]
    public var isPublic: Bool
    /// Method signatures (e.g. "func configure(apiKey: String)").
    public var methods: [String]
    /// Computed property signatures (e.g. "var isConfigured: Bool { get }").
    public var computedProperties: [String]

    public init(
        name: String,
        kind: TypeKind,
        file: String = "",
        module: String = "",
        fields: [String] = [],
        conformances: [String] = [],
        isPublic: Bool = false,
        methods: [String] = [],
        computedProperties: [String] = []
    ) {
        self.name = name
        self.kind = kind
        self.file = file
        self.module = module
        self.fields = fields
        self.conformances = conformances
        self.isPublic = isPublic
        self.methods = methods
        self.computedProperties = computedProperties
    }
}

public enum TypeKind: String, Sendable, Codable {
    case `struct`
    case `class`
    case `enum`
    case `actor`
    case `protocol`
}

// MARK: - Code Pattern

public struct CodePattern: Sendable, Codable {
    /// Pattern identifier (e.g. "error_pattern", "mock_pattern", "endpoint_pattern").
    public var name: String
    /// Human-readable description.
    public var description: String
    /// Actual code example from the project.
    public var example: String
    /// Files where this pattern appears.
    public var files: [String]

    public init(name: String, description: String = "", example: String = "", files: [String] = []) {
        self.name = name
        self.description = description
        self.example = example
        self.files = files
    }
}

// MARK: - Test Info

public struct TestInfo: Sendable, Codable {
    /// Test framework used ("swift-testing", "xctest", "mixed").
    public var framework: String
    /// Number of test source files.
    public var testFiles: Int
    /// Total number of test methods/functions.
    public var testCount: Int
    /// Mock naming pattern (e.g. "Mock* with call tracking + shouldThrow").
    public var mockPattern: String?
    /// How test fixtures are loaded/created.
    public var fixturePattern: String?

    public init(
        framework: String = "unknown",
        testFiles: Int = 0,
        testCount: Int = 0,
        mockPattern: String? = nil,
        fixturePattern: String? = nil
    ) {
        self.framework = framework
        self.testFiles = testFiles
        self.testCount = testCount
        self.mockPattern = mockPattern
        self.fixturePattern = fixturePattern
    }
}

// MARK: - Shared Utility

/// A shared utility function referenced across multiple files.
public struct SharedUtility: Sendable, Codable {
    /// Utility function name (e.g. "formatDate").
    public var name: String
    /// Full function signature.
    public var signature: String
    /// File where the utility is defined.
    public var file: String
    /// Files where the utility is used.
    public var usageFiles: [String]

    public init(
        name: String,
        signature: String = "",
        file: String = "",
        usageFiles: [String] = []
    ) {
        self.name = name
        self.signature = signature
        self.file = file
        self.usageFiles = usageFiles
    }
}
