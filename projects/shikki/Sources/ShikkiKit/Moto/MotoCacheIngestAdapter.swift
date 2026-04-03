import CommonCrypto
import Foundation

/// Lightweight pointer stored in ShikiDB instead of full source code.
///
/// When a project has a `.moto` dotfile, `/ingest` stores this pointer
/// referencing the Moto cache rather than duplicating all source code
/// into the knowledge layer.
public struct MotoIngestPointer: Codable, Sendable, Equatable {
    /// Human-readable project name (from the dotfile, not the manifest).
    public let projectName: String
    /// Cache version from the dotfile's `[cache]` section.
    public let motoVersion: String
    /// Remote cache endpoint, or `moto-local://<path>` for local-only caches.
    public let cacheEndpoint: String
    /// Composite checksum of all manifest file checksums.
    public let manifestChecksum: String
    /// Aggregate statistics summarizing the cached project.
    public let stats: MotoIngestStats
    /// Timestamp when the pointer was created.
    public let indexedAt: Date

    public init(
        projectName: String,
        motoVersion: String,
        cacheEndpoint: String,
        manifestChecksum: String,
        stats: MotoIngestStats,
        indexedAt: Date
    ) {
        self.projectName = projectName
        self.motoVersion = motoVersion
        self.cacheEndpoint = cacheEndpoint
        self.manifestChecksum = manifestChecksum
        self.stats = stats
        self.indexedAt = indexedAt
    }
}

/// Aggregate statistics for a Moto-cached project.
public struct MotoIngestStats: Codable, Sendable, Equatable {
    public let protocolCount: Int
    public let typeCount: Int
    public let methodCount: Int
    public let testCount: Int
    public let duplicateCount: Int

    public init(
        protocolCount: Int,
        typeCount: Int,
        methodCount: Int,
        testCount: Int,
        duplicateCount: Int
    ) {
        self.protocolCount = protocolCount
        self.typeCount = typeCount
        self.methodCount = methodCount
        self.testCount = testCount
        self.duplicateCount = duplicateCount
    }
}

/// Converts a Moto cache into lightweight ingest representations for ShikiDB.
///
/// The key insight: when a project has `.moto`, ShikiDB stores a **pointer**
/// to the cache (project name, endpoint, checksum, stats) instead of a full
/// copy of the source code. This keeps the knowledge layer small and fast
/// while still enabling architecture queries via the Moto cache endpoint.
public enum MotoCacheIngestAdapter {

    /// Convert a ``MotoCacheManifest`` and ``MotoDotfile`` into a lightweight
    /// pointer for ShikiDB storage.
    ///
    /// Uses the dotfile's project name (user-facing) rather than the manifest's
    /// internal project identifier. Falls back to `moto-local://<localPath>`
    /// when no remote endpoint is configured.
    ///
    /// - Parameters:
    ///   - manifest: The cache manifest with checksums and stats.
    ///   - dotfile: The `.moto` dotfile with project identity and endpoint.
    ///   - methodCount: Optional method count from a ``MethodIndex`` (default 0).
    ///   - duplicateCount: Optional duplicate count from a ``DuplicateDetector`` (default 0).
    /// - Returns: A ``MotoIngestPointer`` ready for ShikiDB storage.
    public static func createPointer(
        manifest: MotoCacheManifest,
        dotfile: MotoDotfile,
        methodCount: Int = 0,
        duplicateCount: Int = 0
    ) -> MotoIngestPointer {
        let endpoint: String
        if let remoteEndpoint = dotfile.cache.endpoint {
            endpoint = remoteEndpoint
        } else {
            endpoint = "moto-local://\(dotfile.cache.localPath)"
        }

        let checksum = compositeChecksum(from: manifest)

        let stats = MotoIngestStats(
            protocolCount: manifest.stats.protocols,
            typeCount: manifest.stats.types,
            methodCount: methodCount,
            testCount: manifest.stats.testCount,
            duplicateCount: duplicateCount
        )

        return MotoIngestPointer(
            projectName: dotfile.project.name,
            motoVersion: dotfile.cache.version ?? "0.0.0",
            cacheEndpoint: endpoint,
            manifestChecksum: checksum,
            stats: stats,
            indexedAt: Date()
        )
    }

    /// Convert a pointer into ingest chunks for ShikiDB storage.
    ///
    /// Produces exactly 2 chunks:
    /// 1. **Overview**: Human-readable project summary with stats.
    /// 2. **Cache reference**: Machine-parseable JSON of the full pointer.
    ///
    /// - Parameter pointer: The ingest pointer to convert.
    /// - Returns: Array of ``IngestChunk``s (always 2).
    public static func toIngestChunks(
        pointer: MotoIngestPointer
    ) -> [IngestChunk] {
        let overview = """
            Moto Cache: \(pointer.projectName)
            Version: \(pointer.motoVersion)
            Endpoint: \(pointer.cacheEndpoint)
            Checksum: \(pointer.manifestChecksum)
            Protocols: \(pointer.stats.protocolCount)
            Types: \(pointer.stats.typeCount)
            Methods: \(pointer.stats.methodCount)
            Tests: \(pointer.stats.testCount)
            Duplicates: \(pointer.stats.duplicateCount)
            """

        let overviewChunk = IngestChunk(
            content: overview,
            category: "moto_cache",
            sourceType: "moto_cache",
            sourceUri: pointer.cacheEndpoint
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = (try? encoder.encode(pointer)) ?? Data()
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

        let referenceChunk = IngestChunk(
            content: jsonString,
            category: "moto_cache",
            sourceType: "moto_cache",
            sourceUri: pointer.cacheEndpoint
        )

        return [overviewChunk, referenceChunk]
    }

    // MARK: - Private

    /// Compute a composite SHA-256 checksum from all manifest file checksums.
    ///
    /// Concatenates all non-nil file entry checksums in a stable order,
    /// then hashes the result. This gives a single fingerprint for the
    /// entire cache state.
    private static func compositeChecksum(from manifest: MotoCacheManifest) -> String {
        let checksums = [
            manifest.files.package?.sha256,
            manifest.files.protocols?.sha256,
            manifest.files.types?.sha256,
            manifest.files.dependencies?.sha256,
            manifest.files.patterns?.sha256,
            manifest.files.tests?.sha256,
            manifest.files.apiSurface?.sha256,
        ]
        let combined = checksums.compactMap { $0 }.joined(separator: ":")
        return sha256Hex(combined)
    }

    private static func sha256Hex(_ string: String) -> String {
        let data = Data(string.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
