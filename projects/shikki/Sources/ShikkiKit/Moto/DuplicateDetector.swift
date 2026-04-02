import Foundation

/// Detects duplicate method signatures across different types.
///
/// Uses the ``MethodIndex`` to find identical signatures that appear
/// in multiple source files (excluding test files). Feeds
/// `shikki doctor --duplicates`.
public struct DuplicateDetector: Sendable {

    public init() {}

    /// Find duplicate method signatures in the given index.
    ///
    /// Groups entries by signature, then returns groups with 2+ entries.
    /// Test file entries (files matching `Tests/` or `*Tests.swift`) are
    /// excluded before grouping.
    ///
    /// - Parameter index: The method index to scan.
    /// - Returns: Array of ``DuplicateGroup``s, one per duplicated signature.
    public func findDuplicates(in index: MethodIndex) -> [DuplicateGroup] {
        // Filter out test files
        let sourceEntries = index.entries.filter { !isTestFile($0.file) }

        // Group by signature
        var groups: [String: [DuplicateLocation]] = [:]
        for entry in sourceEntries {
            let location = DuplicateLocation(
                typeName: entry.typeName,
                file: entry.file,
                module: entry.module
            )
            groups[entry.signature, default: []].append(location)
        }

        // Only keep groups with 2+ entries (actual duplicates)
        return groups
            .filter { $0.value.count >= 2 }
            .map { DuplicateGroup(signature: $0.key, locations: $0.value) }
            .sorted { $0.signature < $1.signature }
    }

    // MARK: - Private

    private func isTestFile(_ path: String) -> Bool {
        path.contains("Tests/") || path.hasSuffix("Tests.swift")
    }
}

/// A group of duplicate method signatures found across different types.
public struct DuplicateGroup: Sendable, Codable, Equatable {
    /// The duplicated method signature.
    public var signature: String
    /// Locations where this signature appears.
    public var locations: [DuplicateLocation]

    public init(signature: String, locations: [DuplicateLocation] = []) {
        self.signature = signature
        self.locations = locations
    }
}

/// A location where a duplicate signature was found.
public struct DuplicateLocation: Sendable, Codable, Equatable {
    /// The type name containing the method.
    public var typeName: String
    /// Source file path.
    public var file: String
    /// SPM module name.
    public var module: String

    public init(typeName: String, file: String = "", module: String = "") {
        self.typeName = typeName
        self.file = file
        self.module = module
    }
}
