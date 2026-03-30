import Foundation

/// Errors from reading Moto cache files.
public enum MotoCacheReaderError: Error, LocalizedError, Sendable {
    case cacheNotFound(String)
    case manifestNotFound(String)
    case fileNotFound(String)
    case decodingFailed(file: String, detail: String)
    case checksumMismatch(file: String, expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .cacheNotFound(let path):
            return "Moto cache directory not found: \(path)"
        case .manifestNotFound(let path):
            return "manifest.json not found in cache: \(path)"
        case .fileNotFound(let path):
            return "Cache file not found: \(path)"
        case .decodingFailed(let file, let detail):
            return "Failed to decode \(file): \(detail)"
        case .checksumMismatch(let file, let expected, let actual):
            return "Checksum mismatch for \(file): expected \(expected), got \(actual)"
        }
    }
}

/// Reads a Moto cache from a local directory.
///
/// Supports loading individual cache files (protocols, types, etc.)
/// or converting the entire cache back to an ``ArchitectureCache``.
public struct MotoCacheReader: Sendable {

    private let cachePath: String

    /// Create a reader for the given cache directory.
    ///
    /// - Parameter cachePath: Absolute path to the `.moto-cache/` directory.
    public init(cachePath: String) {
        self.cachePath = cachePath
    }

    // MARK: - Manifest

    /// Load the cache manifest.
    public func loadManifest() throws -> MotoCacheManifest {
        let manifestPath = (cachePath as NSString).appendingPathComponent("manifest.json")
        return try loadJSON(at: manifestPath)
    }

    // MARK: - Individual Files

    /// Load the package info from `package.json`.
    public func loadPackageInfo() throws -> PackageInfo {
        let path = (cachePath as NSString).appendingPathComponent("package.json")
        return try loadJSON(at: path)
    }

    /// Load all protocols from `protocols.json`.
    public func loadProtocols() throws -> [ProtocolDescriptor] {
        let path = (cachePath as NSString).appendingPathComponent("protocols.json")
        return try loadJSON(at: path)
    }

    /// Load all types from `types.json`.
    public func loadTypes() throws -> [TypeDescriptor] {
        let path = (cachePath as NSString).appendingPathComponent("types.json")
        return try loadJSON(at: path)
    }

    /// Load the dependency graph from `dependencies.json`.
    public func loadDependencies() throws -> [String: [String]] {
        let path = (cachePath as NSString).appendingPathComponent("dependencies.json")
        return try loadJSON(at: path)
    }

    /// Load code patterns from `patterns.json`.
    public func loadPatterns() throws -> [CodePattern] {
        let path = (cachePath as NSString).appendingPathComponent("patterns.json")
        return try loadJSON(at: path)
    }

    /// Load test info from `tests.json`.
    public func loadTestInfo() throws -> TestInfo {
        let path = (cachePath as NSString).appendingPathComponent("tests.json")
        return try loadJSON(at: path)
    }

    /// Load API surface from `api-surface.json`.
    public func loadAPISurface() throws -> APISurface {
        let path = (cachePath as NSString).appendingPathComponent("api-surface.json")
        return try loadJSON(at: path)
    }

    // MARK: - Full Cache Conversion

    /// Load all cache files and convert back to an ``ArchitectureCache``.
    ///
    /// This enables Moto caches to be used wherever ``ArchitectureCache`` is expected
    /// in ShikkiKit's CodeGen pipeline.
    public func loadAsArchitectureCache() throws -> ArchitectureCache {
        let manifest = try loadManifest()
        let packageInfo = try loadPackageInfo()
        let protocols = try loadProtocols()
        let types = try loadTypes()
        let dependencies = try loadDependencies()
        let patterns = try loadPatterns()
        let testInfo = try loadTestInfo()

        // Parse the builtAt timestamp
        let formatter = ISO8601DateFormatter()
        let builtAt = formatter.date(from: manifest.builtAt) ?? Date()

        return ArchitectureCache(
            projectId: manifest.project,
            projectPath: cachePath,
            gitHash: manifest.gitCommit,
            builtAt: builtAt,
            packageInfo: packageInfo,
            protocols: protocols,
            types: types,
            dependencyGraph: dependencies,
            patterns: patterns,
            testInfo: testInfo
        )
    }

    // MARK: - Validation

    /// Validate cache integrity by checking all checksums against the manifest.
    ///
    /// - Returns: Array of files that failed checksum validation. Empty means all valid.
    public func validate() throws -> [String] {
        let manifest = try loadManifest()
        var failures: [String] = []

        let builder = MotoCacheBuilder()

        let entries: [(String, MotoCacheManifest.FileEntry?)] = [
            ("package.json", manifest.files.package),
            ("protocols.json", manifest.files.protocols),
            ("types.json", manifest.files.types),
            ("dependencies.json", manifest.files.dependencies),
            ("patterns.json", manifest.files.patterns),
            ("tests.json", manifest.files.tests),
            ("api-surface.json", manifest.files.apiSurface),
        ]

        for (filename, entry) in entries {
            guard let entry else { continue }
            let filePath = (cachePath as NSString).appendingPathComponent(filename)
            guard FileManager.default.fileExists(atPath: filePath) else {
                failures.append(filename)
                continue
            }
            let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
            let actual = builder.sha256Hex(data)
            if actual != entry.sha256 {
                failures.append(filename)
            }
        }

        return failures
    }

    // MARK: - Query

    /// Find a specific type by name.
    public func findType(named name: String) throws -> TypeDescriptor? {
        let types = try loadTypes()
        return types.first { $0.name == name }
    }

    /// Find a specific protocol by name.
    public func findProtocol(named name: String) throws -> ProtocolDescriptor? {
        let protocols = try loadProtocols()
        return protocols.first { $0.name == name }
    }

    /// Find all types conforming to a given protocol.
    public func findConformers(of protocolName: String) throws -> [TypeDescriptor] {
        let types = try loadTypes()
        return types.filter { $0.conformances.contains(protocolName) }
    }

    // MARK: - Private

    private func loadJSON<T: Decodable>(at path: String) throws -> T {
        guard FileManager.default.fileExists(atPath: path) else {
            throw MotoCacheReaderError.fileNotFound(path)
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw MotoCacheReaderError.decodingFailed(
                file: (path as NSString).lastPathComponent,
                detail: error.localizedDescription
            )
        }
    }
}
