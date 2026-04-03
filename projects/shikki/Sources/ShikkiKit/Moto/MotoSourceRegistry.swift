import Foundation

/// Registry mapping project paths to their `.moto` cache locations.
///
/// Provides lookup, loading, and registration of known Moto sources.
/// Used by `/ingest` to detect whether a project has a pre-computed
/// architecture cache and should store a pointer instead of full source.
public actor MotoSourceRegistry {

    /// Registered sources: project path -> parsed dotfile.
    private var sources: [String: MotoDotfile] = [:]

    public init() {}

    /// Check if a project path has a `.moto` file.
    ///
    /// Looks for a file named `.moto` directly in the given directory.
    /// Does NOT walk up parent directories (use ``MotoDotfileParser/discover(from:)``
    /// for that behavior).
    ///
    /// - Parameter path: Absolute path to the project directory.
    /// - Returns: `true` if a `.moto` file exists at the path.
    public func hasMotoCache(at path: String) -> Bool {
        let motoPath = (path as NSString).appendingPathComponent(".moto")
        return FileManager.default.fileExists(atPath: motoPath)
    }

    /// Load and parse the `.moto` dotfile from a project path.
    ///
    /// - Parameter path: Absolute path to the project directory.
    /// - Returns: The parsed ``MotoDotfile``.
    /// - Throws: ``MotoDotfileError`` if the file is missing or malformed.
    public func loadDotfile(at path: String) throws -> MotoDotfile {
        let motoPath = (path as NSString).appendingPathComponent(".moto")
        let parser = MotoDotfileParser()
        return try parser.parse(at: motoPath)
    }

    /// Register a known `.moto` source for future lookups.
    ///
    /// - Parameters:
    ///   - projectPath: Absolute path to the project directory.
    ///   - dotfile: The parsed dotfile to associate with the path.
    public func register(projectPath: String, dotfile: MotoDotfile) {
        sources[projectPath] = dotfile
    }

    /// List all registered `.moto` sources.
    ///
    /// - Returns: Array of `(path, dotfile)` tuples, sorted by path.
    public func listSources() -> [(path: String, dotfile: MotoDotfile)] {
        sources
            .map { (path: $0.key, dotfile: $0.value) }
            .sorted { $0.path < $1.path }
    }
}
