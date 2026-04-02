import Foundation

/// Index of method-level symbols extracted from an ``ArchitectureCache``.
///
/// Includes function signatures, computed properties, and their locations.
/// Enables dispatched agents to get scoped code context instead of
/// re-reading the entire codebase.
public struct MethodIndex: Sendable, Codable, Equatable {
    /// All indexed method/property entries.
    public var entries: [MethodIndexEntry]

    public init(entries: [MethodIndexEntry] = []) {
        self.entries = entries
    }

    /// Query entries belonging to a specific type.
    public func methods(for typeName: String) -> [MethodIndexEntry] {
        entries.filter { $0.typeName == typeName }
    }

    /// Query entries by signature substring match.
    public func search(signature query: String) -> [MethodIndexEntry] {
        entries.filter { $0.signature.contains(query) }
    }
}

/// A single entry in the ``MethodIndex``.
public struct MethodIndexEntry: Sendable, Codable, Equatable {
    /// The type this method/property belongs to.
    public var typeName: String
    /// The method or computed property signature.
    public var signature: String
    /// The kind of entry.
    public var kind: MethodEntryKind
    /// Source file path (relative to project root).
    public var file: String
    /// SPM module name.
    public var module: String

    public init(
        typeName: String,
        signature: String,
        kind: MethodEntryKind,
        file: String = "",
        module: String = ""
    ) {
        self.typeName = typeName
        self.signature = signature
        self.kind = kind
        self.file = file
        self.module = module
    }
}

/// The kind of a method index entry.
public enum MethodEntryKind: String, Sendable, Codable, Equatable {
    /// A function/method.
    case function
    /// A computed property.
    case computedProperty
    /// A protocol requirement.
    case protocolRequirement
}
