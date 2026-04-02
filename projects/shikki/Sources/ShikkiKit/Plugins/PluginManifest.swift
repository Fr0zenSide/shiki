import Foundation

// MARK: - PluginID

/// Type-safe plugin identifier, e.g. "shikki/creative-studio".
public struct PluginID: Hashable, Sendable, Codable, CustomStringConvertible, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }
}

// MARK: - SemanticVersion

/// Semantic version with major.minor.patch components.
public struct SemanticVersion: Sendable, Codable, Hashable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Parse from string like "1.2.3".
    public init?(string: String) {
        let parts = string.split(separator: ".")
        guard parts.count == 3,
              let major = Int(parts[0]),
              let minor = Int(parts[1]),
              let patch = Int(parts[2]) else {
            return nil
        }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        let parts = string.split(separator: ".")
        guard parts.count == 3,
              let major = Int(parts[0]),
              let minor = Int(parts[1]),
              let patch = Int(parts[2]) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid semantic version: \(string). Expected format: major.minor.patch"
            )
        }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

extension SemanticVersion: Comparable {
    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

// MARK: - PluginSource

/// Where the plugin comes from.
public enum PluginSource: Sendable, Hashable {
    case builtin
    case local(path: String)
    case marketplace(url: URL, verified: Bool)
}

extension PluginSource: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, path, url, verified
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "builtin":
            self = .builtin
        case "local":
            let path = try container.decode(String.self, forKey: .path)
            self = .local(path: path)
        case "marketplace":
            let url = try container.decode(URL.self, forKey: .url)
            let verified = try container.decodeIfPresent(Bool.self, forKey: .verified) ?? false
            self = .marketplace(url: url, verified: verified)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container,
                debugDescription: "Unknown plugin source type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .builtin:
            try container.encode("builtin", forKey: .type)
        case .local(let path):
            try container.encode("local", forKey: .type)
            try container.encode(path, forKey: .path)
        case .marketplace(let url, let verified):
            try container.encode("marketplace", forKey: .type)
            try container.encode(url, forKey: .url)
            try container.encode(verified, forKey: .verified)
        }
    }
}

// MARK: - PluginCommand

/// A command provided by a plugin.
public struct PluginCommand: Codable, Sendable, Hashable {
    public let name: String
    public let description: String?

    public init(name: String, description: String? = nil) {
        self.name = name
        self.description = description
    }
}

// MARK: - PluginDependencies

/// External dependencies required by a plugin.
public struct PluginDependencies: Codable, Sendable, Hashable {
    public let systemTools: [String]
    public let pythonPackages: [String]
    public let minimumDiskGB: Double
    public let minimumRAMGB: Double
    public let venvPath: String?

    public init(
        systemTools: [String] = [],
        pythonPackages: [String] = [],
        minimumDiskGB: Double = 0,
        minimumRAMGB: Double = 0,
        venvPath: String? = nil
    ) {
        self.systemTools = systemTools
        self.pythonPackages = pythonPackages
        self.minimumDiskGB = minimumDiskGB
        self.minimumRAMGB = minimumRAMGB
        self.venvPath = venvPath
    }
}

// MARK: - CertificationLevel

/// Trust level for a plugin. Ordered from lowest to highest trust.
public enum CertificationLevel: String, Codable, Sendable, CaseIterable {
    case uncertified
    case communityReviewed
    case shikkiCertified
    case enterpriseSafe
}

extension CertificationLevel: Comparable {
    public static func < (lhs: CertificationLevel, rhs: CertificationLevel) -> Bool {
        lhs.trustOrder < rhs.trustOrder
    }

    private var trustOrder: Int {
        switch self {
        case .uncertified: return 0
        case .communityReviewed: return 1
        case .shikkiCertified: return 2
        case .enterpriseSafe: return 3
        }
    }
}

// MARK: - PluginCertification

/// Certification metadata for enterprise trust.
public struct PluginCertification: Codable, Sendable, Hashable {
    public let level: CertificationLevel
    public let certifiedAt: Date?
    public let certifiedBy: String?
    public let expiresAt: Date?
    public let signature: String?

    public init(
        level: CertificationLevel,
        certifiedAt: Date? = nil,
        certifiedBy: String? = nil,
        expiresAt: Date? = nil,
        signature: String? = nil
    ) {
        self.level = level
        self.certifiedAt = certifiedAt
        self.certifiedBy = certifiedBy
        self.expiresAt = expiresAt
        self.signature = signature
    }

    /// Whether the certification has expired.
    public var isExpired: Bool {
        guard let expiresAt else { return false }
        return Date() > expiresAt
    }
}

// MARK: - PluginManifest

/// The manifest describing a Shikki plugin — its identity, capabilities, and requirements.
public struct PluginManifest: Sendable, Identifiable, Hashable {
    public let id: PluginID
    public let displayName: String
    public let version: SemanticVersion
    public let source: PluginSource

    // What this plugin provides
    public let commands: [PluginCommand]
    public let capabilities: [String]

    // What this plugin requires
    public let dependencies: PluginDependencies
    public let minimumShikkiVersion: SemanticVersion

    // Runtime
    public let entryPoint: String
    public let configSchema: [String: String]?

    // Metadata
    public let author: String
    public let license: String
    public let description: String
    public let checksum: String

    // Additional metadata
    public let websiteURL: URL?
    public let updatedAt: Date
    public let repositoryURL: URL?

    // Certification
    public let certification: PluginCertification?

    public init(
        id: PluginID,
        displayName: String,
        version: SemanticVersion,
        source: PluginSource,
        commands: [PluginCommand],
        capabilities: [String],
        dependencies: PluginDependencies,
        minimumShikkiVersion: SemanticVersion,
        entryPoint: String,
        configSchema: [String: String]? = nil,
        author: String,
        license: String,
        description: String,
        checksum: String,
        websiteURL: URL? = nil,
        updatedAt: Date = Date(),
        repositoryURL: URL? = nil,
        certification: PluginCertification? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.version = version
        self.source = source
        self.commands = commands
        self.capabilities = capabilities
        self.dependencies = dependencies
        self.minimumShikkiVersion = minimumShikkiVersion
        self.entryPoint = entryPoint
        self.configSchema = configSchema
        self.author = author
        self.license = license
        self.description = description
        self.checksum = checksum
        self.websiteURL = websiteURL
        self.updatedAt = updatedAt
        self.repositoryURL = repositoryURL
        self.certification = certification
    }
}

// MARK: - Codable

extension PluginManifest: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, displayName, version, source
        case commands, capabilities
        case dependencies, minimumShikkiVersion
        case entryPoint, configSchema
        case author, license, description, checksum
        case websiteURL, updatedAt, repositoryURL
        case certification
    }
}

// MARK: - Validation

extension PluginManifest {

    /// Validation errors for a plugin manifest.
    public enum ValidationError: Error, CustomStringConvertible, Sendable {
        case emptyID
        case emptyDisplayName
        case emptyAuthor
        case emptyEntryPoint
        case emptyChecksum
        case noCommands
        case invalidIDFormat(String)
        case minimumVersionNotMet(required: SemanticVersion, current: SemanticVersion)

        public var description: String {
            switch self {
            case .emptyID: return "Plugin ID must not be empty"
            case .invalidIDFormat(let id):
                return "Plugin ID must match 'org/name' format (alphanumeric, hyphens, dots), got: \(id)"
            case .emptyDisplayName: return "Display name must not be empty"
            case .emptyAuthor: return "Author must not be empty"
            case .emptyEntryPoint: return "Entry point must not be empty"
            case .emptyChecksum: return "Checksum must not be empty"
            case .noCommands: return "Plugin must provide at least one command"
            case .minimumVersionNotMet(let required, let current):
                return "Requires Shikki \(required), current is \(current)"
            }
        }
    }

    /// Validate the manifest for structural correctness.
    public func validate() throws {
        if id.rawValue.isEmpty { throw ValidationError.emptyID }

        // Validate ID format: must be "org/name", no path traversal
        let idValue = id.rawValue
        guard !idValue.contains(".."),
              !idValue.hasPrefix("/"),
              !idValue.hasPrefix("."),
              idValue.contains("/"),
              idValue.split(separator: "/").count == 2 else {
            throw ValidationError.invalidIDFormat(idValue)
        }
        // Each segment must be alphanumeric with hyphens/dots only
        let segments = idValue.split(separator: "/").map(String.init)
        let validPattern = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._"))
        for segment in segments {
            guard !segment.isEmpty,
                  segment.unicodeScalars.allSatisfy({ validPattern.contains($0) }) else {
                throw ValidationError.invalidIDFormat(idValue)
            }
        }

        if displayName.isEmpty { throw ValidationError.emptyDisplayName }
        if author.isEmpty { throw ValidationError.emptyAuthor }
        if entryPoint.isEmpty { throw ValidationError.emptyEntryPoint }
        if checksum.isEmpty { throw ValidationError.emptyChecksum }
        if commands.isEmpty { throw ValidationError.noCommands }
    }

    /// Check if this plugin is compatible with the given Shikki version.
    public func isCompatible(with shikkiVersion: SemanticVersion) -> Bool {
        shikkiVersion >= minimumShikkiVersion
    }

    /// Verify the checksum matches the expected value.
    public func verifyChecksum(_ expected: String) -> Bool {
        checksum == expected
    }
}
