import Foundation

/// Root index for the Moto architecture cache.
///
/// Corresponds to `manifest.json` in the `.moto-cache/` directory.
/// Contains metadata, file references with checksums, and aggregate stats.
public struct MotoCacheManifest: Sendable, Codable, Equatable {
    /// Cache schema version (currently 1).
    public var schemaVersion: Int
    /// Project identifier.
    public var project: String
    /// Primary language.
    public var language: String
    /// Git commit hash the cache was built from.
    public var gitCommit: String
    /// Git branch the cache was built from.
    public var gitBranch: String
    /// Git tag (if any).
    public var gitTag: String?
    /// Timestamp of cache construction.
    public var builtAt: String
    /// Builder identifier (e.g. "shikki@0.3.0", "originate-action@v1").
    public var builder: String
    /// File references with checksums.
    public var files: FileReferences
    /// Aggregate statistics.
    public var stats: CacheStats

    public init(
        schemaVersion: Int = 1,
        project: String,
        language: String = "swift",
        gitCommit: String,
        gitBranch: String = "main",
        gitTag: String? = nil,
        builtAt: String,
        builder: String = "shikki",
        files: FileReferences = FileReferences(),
        stats: CacheStats = CacheStats()
    ) {
        self.schemaVersion = schemaVersion
        self.project = project
        self.language = language
        self.gitCommit = gitCommit
        self.gitBranch = gitBranch
        self.gitTag = gitTag
        self.builtAt = builtAt
        self.builder = builder
        self.files = files
        self.stats = stats
    }

    // MARK: - File References

    public struct FileReferences: Sendable, Codable, Equatable {
        public var package: FileEntry?
        public var protocols: FileEntry?
        public var types: FileEntry?
        public var dependencies: FileEntry?
        public var patterns: FileEntry?
        public var tests: FileEntry?
        public var apiSurface: FileEntry?

        public init(
            package: FileEntry? = nil,
            protocols: FileEntry? = nil,
            types: FileEntry? = nil,
            dependencies: FileEntry? = nil,
            patterns: FileEntry? = nil,
            tests: FileEntry? = nil,
            apiSurface: FileEntry? = nil
        ) {
            self.package = package
            self.protocols = protocols
            self.types = types
            self.dependencies = dependencies
            self.patterns = patterns
            self.tests = tests
            self.apiSurface = apiSurface
        }

        enum CodingKeys: String, CodingKey {
            case package
            case protocols
            case types
            case dependencies
            case patterns
            case tests
            case apiSurface = "api_surface"
        }
    }

    public struct FileEntry: Sendable, Codable, Equatable {
        public var path: String
        public var sha256: String

        public init(path: String, sha256: String = "") {
            self.path = path
            self.sha256 = sha256
        }
    }

    // MARK: - Cache Stats

    public struct CacheStats: Sendable, Codable, Equatable {
        public var sourceFiles: Int
        public var protocols: Int
        public var types: Int
        public var testCount: Int
        public var totalCacheTokens: Int

        public init(
            sourceFiles: Int = 0,
            protocols: Int = 0,
            types: Int = 0,
            testCount: Int = 0,
            totalCacheTokens: Int = 0
        ) {
            self.sourceFiles = sourceFiles
            self.protocols = protocols
            self.types = types
            self.testCount = testCount
            self.totalCacheTokens = totalCacheTokens
        }

        enum CodingKeys: String, CodingKey {
            case sourceFiles = "source_files"
            case protocols
            case types
            case testCount = "test_count"
            case totalCacheTokens = "total_cache_tokens"
        }
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case project
        case language
        case gitCommit = "git_commit"
        case gitBranch = "git_branch"
        case gitTag = "git_tag"
        case builtAt = "built_at"
        case builder
        case files
        case stats
    }
}

// MARK: - API Surface (new cache file, not in ArchitectureCache)

/// Public API surface description for the project.
///
/// Corresponds to `api-surface.json` in the cache. Lists all public symbols
/// that external consumers can use.
public struct APISurface: Sendable, Codable, Equatable {
    /// All exported symbols grouped by module.
    public var modules: [ModuleSurface]

    public init(modules: [ModuleSurface] = []) {
        self.modules = modules
    }
}

/// Public API surface for a single module.
public struct ModuleSurface: Sendable, Codable, Equatable {
    public var name: String
    public var publicTypes: [String]
    public var publicFunctions: [String]
    public var publicProtocols: [String]

    public init(
        name: String,
        publicTypes: [String] = [],
        publicFunctions: [String] = [],
        publicProtocols: [String] = []
    ) {
        self.name = name
        self.publicTypes = publicTypes
        self.publicFunctions = publicFunctions
        self.publicProtocols = publicProtocols
    }

    enum CodingKeys: String, CodingKey {
        case name
        case publicTypes = "public_types"
        case publicFunctions = "public_functions"
        case publicProtocols = "public_protocols"
    }
}
