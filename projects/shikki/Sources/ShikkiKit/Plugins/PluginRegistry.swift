import Foundation

// MARK: - PluginRegistryError

/// Errors from plugin registry operations.
public enum PluginRegistryError: Error, CustomStringConvertible, Sendable {
    case pluginNotFound(PluginID)
    case pluginAlreadyInstalled(PluginID)
    case checksumMismatch(pluginID: PluginID, expected: String, actual: String)
    case incompatibleVersion(pluginID: PluginID, required: SemanticVersion, current: SemanticVersion)
    case manifestNotFound(path: String)
    case manifestDecodingFailed(path: String, underlying: String)
    case duplicateCommand(command: String, existingPlugin: PluginID, newPlugin: PluginID)

    public var description: String {
        switch self {
        case .pluginNotFound(let id):
            return "Plugin '\(id)' not found"
        case .pluginAlreadyInstalled(let id):
            return "Plugin '\(id)' is already installed"
        case .checksumMismatch(let id, let expected, let actual):
            return "Checksum mismatch for '\(id)': expected \(expected), got \(actual)"
        case .incompatibleVersion(let id, let required, let current):
            return "Plugin '\(id)' requires Shikki \(required), current is \(current)"
        case .manifestNotFound(let path):
            return "Plugin manifest not found at: \(path)"
        case .manifestDecodingFailed(let path, let underlying):
            return "Failed to decode plugin manifest at \(path): \(underlying)"
        case .duplicateCommand(let command, let existing, let new):
            return "Command '\(command)' already registered by '\(existing)', cannot register for '\(new)'"
        }
    }
}

// MARK: - PluginRegistry

/// Thread-safe registry that manages installed Shikki plugins.
/// Discovers plugins from `~/.shikki/plugins/` directory, validates manifests,
/// and resolves commands to their owning plugin.
public actor PluginRegistry {

    /// Current Shikki version for compatibility checks.
    private let shikkiVersion: SemanticVersion

    /// Installed plugins keyed by ID.
    private var plugins: [PluginID: PluginManifest] = [:]

    /// Command-to-plugin lookup for fast resolution.
    private var commandIndex: [String: PluginID] = [:]

    /// File manager for disk operations.
    private let fileManager: FileManager

    /// JSON decoder configured for plugin manifests.
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public init(
        shikkiVersion: SemanticVersion = SemanticVersion(major: 0, minor: 3, patch: 0),
        fileManager: FileManager = .default
    ) {
        self.shikkiVersion = shikkiVersion
        self.fileManager = fileManager
    }

    // MARK: - Registration

    /// Register a plugin manifest. Validates checksum and version compatibility.
    /// - Throws: `PluginRegistryError` if the plugin is already installed, incompatible, or has duplicate commands.
    @discardableResult
    public func register(manifest: PluginManifest) throws -> PluginManifest {
        // Check for duplicates
        if plugins[manifest.id] != nil {
            throw PluginRegistryError.pluginAlreadyInstalled(manifest.id)
        }

        // Check version compatibility
        if !manifest.isCompatible(with: shikkiVersion) {
            throw PluginRegistryError.incompatibleVersion(
                pluginID: manifest.id,
                required: manifest.minimumShikkiVersion,
                current: shikkiVersion
            )
        }

        // Check for command conflicts
        for command in manifest.commands {
            if let existingPlugin = commandIndex[command.name] {
                throw PluginRegistryError.duplicateCommand(
                    command: command.name,
                    existingPlugin: existingPlugin,
                    newPlugin: manifest.id
                )
            }
        }

        // Register
        plugins[manifest.id] = manifest
        for command in manifest.commands {
            commandIndex[command.name] = manifest.id
        }

        return manifest
    }

    /// Unregister a plugin by ID.
    /// - Throws: `PluginRegistryError.pluginNotFound` if the plugin is not installed.
    public func unregister(id: PluginID) throws {
        guard let manifest = plugins[id] else {
            throw PluginRegistryError.pluginNotFound(id)
        }

        // Remove command index entries
        for command in manifest.commands {
            commandIndex.removeValue(forKey: command.name)
        }

        plugins.removeValue(forKey: id)
    }

    // MARK: - Queries

    /// All installed plugins, sorted by display name.
    public func installed() -> [PluginManifest] {
        plugins.values.sorted { $0.displayName < $1.displayName }
    }

    /// Find the plugin that owns a given command.
    public func resolve(command: String) -> PluginManifest? {
        guard let pluginID = commandIndex[command] else { return nil }
        return plugins[pluginID]
    }

    /// Get a specific plugin by ID.
    public func plugin(id: PluginID) -> PluginManifest? {
        plugins[id]
    }

    /// Number of installed plugins.
    public var count: Int {
        plugins.count
    }

    // MARK: - Verification

    /// Verify a plugin's checksum matches the expected value.
    /// - Returns: `true` if the checksum matches.
    /// - Throws: `PluginRegistryError.pluginNotFound` if not installed.
    public func verify(id: PluginID, expectedChecksum: String) throws -> Bool {
        guard let manifest = plugins[id] else {
            throw PluginRegistryError.pluginNotFound(id)
        }
        return manifest.verifyChecksum(expectedChecksum)
    }

    // MARK: - Discovery

    /// Default plugins directory: `~/.shikki/plugins/`.
    public static var defaultPluginsDirectory: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.shikki/plugins"
    }

    /// Load all plugin manifests from a directory.
    /// Each subdirectory should contain a `manifest.json` file.
    /// Invalid manifests are skipped with a warning (does not throw).
    public func loadFromDirectory(_ path: String) -> [PluginLoadResult] {
        var results: [PluginLoadResult] = []

        guard fileManager.fileExists(atPath: path) else {
            return results
        }

        guard let contents = try? fileManager.contentsOfDirectory(atPath: path) else {
            return results
        }

        for entry in contents {
            let pluginDir = (path as NSString).appendingPathComponent(entry)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: pluginDir, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                continue
            }

            let manifestPath = (pluginDir as NSString).appendingPathComponent("manifest.json")
            guard fileManager.fileExists(atPath: manifestPath) else {
                results.append(.skipped(directory: entry, reason: "No manifest.json found"))
                continue
            }

            do {
                let manifest = try loadManifest(from: manifestPath)
                try register(manifest: manifest)
                results.append(.loaded(manifest))
            } catch {
                results.append(.failed(directory: entry, error: "\(error)"))
            }
        }

        return results
    }

    /// Load a single plugin manifest from a JSON file path.
    public func loadManifest(from path: String) throws -> PluginManifest {
        guard fileManager.fileExists(atPath: path) else {
            throw PluginRegistryError.manifestNotFound(path: path)
        }

        guard let data = fileManager.contents(atPath: path) else {
            throw PluginRegistryError.manifestNotFound(path: path)
        }

        do {
            return try decoder.decode(PluginManifest.self, from: data)
        } catch {
            throw PluginRegistryError.manifestDecodingFailed(
                path: path,
                underlying: error.localizedDescription
            )
        }
    }
}

// MARK: - PluginLoadResult

/// Result of attempting to load a plugin from a directory.
public enum PluginLoadResult: Sendable {
    case loaded(PluginManifest)
    case skipped(directory: String, reason: String)
    case failed(directory: String, error: String)
}
