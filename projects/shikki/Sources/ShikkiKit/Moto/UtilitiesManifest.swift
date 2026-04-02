import Foundation

/// Manifest of shared utility functions with usage counts.
///
/// Built from an ``ArchitectureCache`` to help dispatch agents
/// understand which helpers are available and how widely used they are.
/// Corresponds to `utilities.json` in the Moto cache.
public struct UtilitiesManifest: Sendable, Codable, Equatable {
    /// All shared utility entries, sorted by usage count descending.
    public var utilities: [UtilityEntry]

    public init(utilities: [UtilityEntry] = []) {
        self.utilities = utilities
    }
}

/// A single utility entry in the ``UtilitiesManifest``.
public struct UtilityEntry: Sendable, Codable, Equatable {
    /// Utility function name.
    public var name: String
    /// Full function signature.
    public var signature: String
    /// File where the utility is defined.
    public var definitionFile: String
    /// Number of files that use this utility.
    public var usageCount: Int
    /// Files where this utility is referenced.
    public var usageFiles: [String]

    public init(
        name: String,
        signature: String = "",
        definitionFile: String = "",
        usageCount: Int = 0,
        usageFiles: [String] = []
    ) {
        self.name = name
        self.signature = signature
        self.definitionFile = definitionFile
        self.usageCount = usageCount
        self.usageFiles = usageFiles
    }
}
