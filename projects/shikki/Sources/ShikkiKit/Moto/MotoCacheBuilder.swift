import Foundation
import CommonCrypto

/// Errors from Moto cache building.
public enum MotoCacheBuilderError: Error, LocalizedError, Sendable {
    case outputDirectoryCreationFailed(String)
    case serializationFailed(String)
    case projectAnalysisFailed(String)

    public var errorDescription: String? {
        switch self {
        case .outputDirectoryCreationFailed(let path):
            return "Failed to create cache output directory: \(path)"
        case .serializationFailed(let detail):
            return "Failed to serialize cache file: \(detail)"
        case .projectAnalysisFailed(let detail):
            return "Project analysis failed: \(detail)"
        }
    }
}

/// Builds a Moto-format architecture cache from an ``ArchitectureCache``.
///
/// Converts ShikkiKit's internal cache format into the Moto open standard:
/// separate JSON files for each concern (protocols, types, dependencies, etc.)
/// plus a `manifest.json` index with checksums and stats.
public struct MotoCacheBuilder: Sendable {

    /// Builder identifier stamped in the manifest.
    public let builderId: String

    public init(builderId: String = "shikki@0.3.0") {
        self.builderId = builderId
    }

    /// Build the complete Moto cache directory from an ``ArchitectureCache``.
    ///
    /// - Parameters:
    ///   - cache: The analyzed project architecture.
    ///   - outputPath: Absolute path to the output directory (e.g. `.moto-cache/`).
    ///   - branch: Git branch name.
    ///   - tag: Git tag (optional).
    /// - Returns: The generated ``MotoCacheManifest``.
    @discardableResult
    public func build(
        from cache: ArchitectureCache,
        outputPath: String,
        branch: String = "main",
        tag: String? = nil
    ) throws -> MotoCacheManifest {
        let fm = FileManager.default
        let outputURL = URL(fileURLWithPath: outputPath)

        // Create output directory
        if !fm.fileExists(atPath: outputPath) {
            do {
                try fm.createDirectory(at: outputURL, withIntermediateDirectories: true)
            } catch {
                throw MotoCacheBuilderError.outputDirectoryCreationFailed(outputPath)
            }
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        // Write package.json
        let packageData = try encoder.encode(cache.packageInfo)
        let packagePath = outputURL.appendingPathComponent("package.json")
        try packageData.write(to: packagePath, options: .atomic)

        // Write protocols.json
        let protocolsData = try encoder.encode(cache.protocols)
        let protocolsPath = outputURL.appendingPathComponent("protocols.json")
        try protocolsData.write(to: protocolsPath, options: .atomic)

        // Write types.json
        let typesData = try encoder.encode(cache.types)
        let typesPath = outputURL.appendingPathComponent("types.json")
        try typesData.write(to: typesPath, options: .atomic)

        // Write dependencies.json
        let depsData = try encoder.encode(cache.dependencyGraph)
        let depsPath = outputURL.appendingPathComponent("dependencies.json")
        try depsData.write(to: depsPath, options: .atomic)

        // Write patterns.json
        let patternsData = try encoder.encode(cache.patterns)
        let patternsPath = outputURL.appendingPathComponent("patterns.json")
        try patternsData.write(to: patternsPath, options: .atomic)

        // Write tests.json
        let testsData = try encoder.encode(cache.testInfo)
        let testsPath = outputURL.appendingPathComponent("tests.json")
        try testsData.write(to: testsPath, options: .atomic)

        // Write api-surface.json (extracted from types)
        let apiSurface = extractAPISurface(from: cache)
        let apiData = try encoder.encode(apiSurface)
        let apiPath = outputURL.appendingPathComponent("api-surface.json")
        try apiData.write(to: apiPath, options: .atomic)

        // Compute source file count
        let sourceFileCount = cache.packageInfo.targets
            .filter { $0.type != .test }
            .reduce(0) { $0 + $1.sourceFiles }

        // Estimate token count (~4 tokens per JSON byte / 4)
        let totalBytes = packageData.count + protocolsData.count + typesData.count
            + depsData.count + patternsData.count + testsData.count + apiData.count
        let estimatedTokens = totalBytes / 4

        // Build manifest
        let formatter = ISO8601DateFormatter()
        let manifest = MotoCacheManifest(
            schemaVersion: 1,
            project: cache.projectId,
            language: "swift",
            gitCommit: cache.gitHash,
            gitBranch: branch,
            gitTag: tag,
            builtAt: formatter.string(from: cache.builtAt),
            builder: builderId,
            files: MotoCacheManifest.FileReferences(
                package: MotoCacheManifest.FileEntry(
                    path: "package.json",
                    sha256: sha256Hex(packageData)
                ),
                protocols: MotoCacheManifest.FileEntry(
                    path: "protocols.json",
                    sha256: sha256Hex(protocolsData)
                ),
                types: MotoCacheManifest.FileEntry(
                    path: "types.json",
                    sha256: sha256Hex(typesData)
                ),
                dependencies: MotoCacheManifest.FileEntry(
                    path: "dependencies.json",
                    sha256: sha256Hex(depsData)
                ),
                patterns: MotoCacheManifest.FileEntry(
                    path: "patterns.json",
                    sha256: sha256Hex(patternsData)
                ),
                tests: MotoCacheManifest.FileEntry(
                    path: "tests.json",
                    sha256: sha256Hex(testsData)
                ),
                apiSurface: MotoCacheManifest.FileEntry(
                    path: "api-surface.json",
                    sha256: sha256Hex(apiData)
                )
            ),
            stats: MotoCacheManifest.CacheStats(
                sourceFiles: sourceFileCount,
                protocols: cache.protocols.count,
                types: cache.types.count,
                testCount: cache.testInfo.testCount,
                totalCacheTokens: estimatedTokens
            )
        )

        // Write manifest.json
        let manifestEncoder = JSONEncoder()
        manifestEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifestData = try manifestEncoder.encode(manifest)
        let manifestPath = outputURL.appendingPathComponent("manifest.json")
        try manifestData.write(to: manifestPath, options: .atomic)

        return manifest
    }

    // MARK: - API Surface Extraction

    /// Extract the public API surface from an ``ArchitectureCache``.
    func extractAPISurface(from cache: ArchitectureCache) -> APISurface {
        // Group by module
        var moduleMap: [String: (types: [String], functions: [String], protocols: [String])] = [:]

        for type in cache.types where type.isPublic {
            var entry = moduleMap[type.module] ?? (types: [], functions: [], protocols: [])
            if type.kind == .protocol {
                entry.protocols.append(type.name)
            } else {
                entry.types.append(type.name)
            }
            moduleMap[type.module] = entry
        }

        for proto in cache.protocols {
            var entry = moduleMap[proto.module] ?? (types: [], functions: [], protocols: [])
            if !entry.protocols.contains(proto.name) {
                entry.protocols.append(proto.name)
            }
            moduleMap[proto.module] = entry
        }

        let modules = moduleMap.map { key, value in
            ModuleSurface(
                name: key,
                publicTypes: value.types.sorted(),
                publicFunctions: value.functions.sorted(),
                publicProtocols: value.protocols.sorted()
            )
        }.sorted { $0.name < $1.name }

        return APISurface(modules: modules)
    }

    // MARK: - Method Index

    /// Build a method-level index from an ``ArchitectureCache``.
    ///
    /// Extracts function signatures and computed properties from all types,
    /// plus protocol method requirements.
    public func buildMethodIndex(from cache: ArchitectureCache) -> MethodIndex {
        var entries: [MethodIndexEntry] = []

        // Index type methods and computed properties
        for type in cache.types {
            for method in type.methods {
                entries.append(MethodIndexEntry(
                    typeName: type.name,
                    signature: method,
                    kind: .function,
                    file: type.file,
                    module: type.module
                ))
            }
            for prop in type.computedProperties {
                entries.append(MethodIndexEntry(
                    typeName: type.name,
                    signature: prop,
                    kind: .computedProperty,
                    file: type.file,
                    module: type.module
                ))
            }
        }

        // Index protocol requirements
        for proto in cache.protocols {
            for method in proto.methods {
                let kind: MethodEntryKind = method.hasPrefix("var ") ? .computedProperty : .protocolRequirement
                entries.append(MethodIndexEntry(
                    typeName: proto.name,
                    signature: method,
                    kind: kind,
                    file: proto.file,
                    module: proto.module
                ))
            }
        }

        return MethodIndex(entries: entries)
    }

    // MARK: - Utilities Manifest

    /// Build a shared utilities manifest from an ``ArchitectureCache``.
    ///
    /// Lists shared helper functions with their usage counts,
    /// sorted by usage count descending.
    public func buildUtilitiesManifest(from cache: ArchitectureCache) -> UtilitiesManifest {
        let utilityEntries = cache.sharedUtilities.map { utility in
            UtilityEntry(
                name: utility.name,
                signature: utility.signature,
                definitionFile: utility.file,
                usageCount: utility.usageFiles.count,
                usageFiles: utility.usageFiles
            )
        }.sorted { $0.usageCount > $1.usageCount }

        return UtilitiesManifest(utilities: utilityEntries)
    }

    // MARK: - SHA-256

    func sha256Hex(_ data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
