import Foundation

// MARK: - AppConfig

/// App configuration from ~/.config/shikki/apps.toml.
/// Defines scheme, team, bundle ID, and signing details for each registered app.
public struct AppConfig: Sendable, Codable, Equatable {
    public let slug: String
    public let scheme: String
    public let teamID: String
    public let bundleID: String
    public let projectPath: String
    public let testflightGroup: String
    public let exportMethod: String
    public let asc: ASCKeyConfig?

    public init(
        slug: String,
        scheme: String,
        teamID: String,
        bundleID: String,
        projectPath: String,
        testflightGroup: String = "External Testers",
        exportMethod: String = "app-store",
        asc: ASCKeyConfig? = nil
    ) {
        self.slug = slug
        self.scheme = scheme
        self.teamID = teamID
        self.bundleID = bundleID
        self.projectPath = projectPath
        self.testflightGroup = testflightGroup
        self.exportMethod = exportMethod
        self.asc = asc
    }
}

// MARK: - ASCKeyConfig

/// App Store Connect API key configuration.
public struct ASCKeyConfig: Sendable, Codable, Equatable {
    public let keyID: String
    public let issuerID: String

    public init(keyID: String, issuerID: String) {
        self.keyID = keyID
        self.issuerID = issuerID
    }
}

// MARK: - AppConfigRegistry

/// Manages loading and querying app configurations from the apps.toml file.
public struct AppConfigRegistry: Sendable {

    /// Default path: ~/.config/shikki/apps.toml
    public static var defaultPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.config/shikki/apps.toml"
    }

    private let configs: [String: AppConfig]

    public init(configs: [String: AppConfig]) {
        self.configs = configs
    }

    /// Load configs from a TOML file.
    /// Uses a minimal TOML parser since we control the format.
    public static func load(from path: String) throws -> AppConfigRegistry {
        guard FileManager.default.fileExists(atPath: path) else {
            throw AppConfigError.fileNotFound(path)
        }

        let content = try String(contentsOfFile: path, encoding: .utf8)
        let configs = try parseTOML(content)
        return AppConfigRegistry(configs: configs)
    }

    /// Get app config by slug. Returns nil if not found.
    public func app(_ slug: String) -> AppConfig? {
        configs[slug]
    }

    /// All registered app slugs.
    public var slugs: [String] {
        Array(configs.keys).sorted()
    }

    /// Number of registered apps.
    public var count: Int {
        configs.count
    }

    /// Select an app: if slug is provided, look it up. If nil and only one app, auto-select.
    public func select(slug: String?) throws -> AppConfig {
        if let slug {
            guard let config = configs[slug] else {
                throw AppConfigError.unknownApp(slug, available: slugs)
            }
            return config
        }

        if configs.count == 1, let config = configs.values.first {
            return config
        }

        throw AppConfigError.ambiguousApp(available: slugs)
    }

    // MARK: - TOML Parser (minimal, handles our flat table format)

    private static func parseTOML(_ content: String) throws -> [String: AppConfig] {
        // Two-pass: collect all values per slug, then build configs.
        // slugValues[slug] = (main values, asc values)
        var slugValues: [(slug: String, values: [String: String], ascValues: [String: String])] = []
        var currentSlug: String?
        var currentValues: [String: String] = [:]
        var ascValues: [String: String] = [:]
        var inASCSection = false

        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines and comments
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            // Table header: [slug] or [slug.asc]
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                let header = String(trimmed.dropFirst().dropLast())

                if header.hasSuffix(".asc") {
                    // Sub-table for ASC keys -- stays with current slug
                    inASCSection = true
                } else {
                    // New top-level slug -- save previous if any
                    if let slug = currentSlug, !currentValues.isEmpty {
                        slugValues.append((slug: slug, values: currentValues, ascValues: ascValues))
                    }
                    currentSlug = header
                    currentValues = [:]
                    ascValues = [:]
                    inASCSection = false
                }
                continue
            }

            // Key-value pair: key = "value"
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }

            let key = parts[0].trimmingCharacters(in: .whitespaces)
            var value = parts[1].trimmingCharacters(in: .whitespaces)

            // Strip quotes
            if value.hasPrefix("\"") && value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
            }

            if inASCSection {
                ascValues[key] = value
            } else {
                currentValues[key] = value
            }
        }

        // Save last section
        if let slug = currentSlug, !currentValues.isEmpty {
            slugValues.append((slug: slug, values: currentValues, ascValues: ascValues))
        }

        var configs: [String: AppConfig] = [:]
        for entry in slugValues {
            configs[entry.slug] = try buildConfig(
                slug: entry.slug, values: entry.values, ascValues: entry.ascValues
            )
        }

        return configs
    }

    private static func buildConfig(
        slug: String,
        values: [String: String],
        ascValues: [String: String]
    ) throws -> AppConfig {
        guard let scheme = values["scheme"] else {
            throw AppConfigError.missingField(slug: slug, field: "scheme")
        }
        guard let teamID = values["team_id"] else {
            throw AppConfigError.missingField(slug: slug, field: "team_id")
        }
        guard let bundleID = values["bundle_id"] else {
            throw AppConfigError.missingField(slug: slug, field: "bundle_id")
        }
        guard let projectPath = values["project_path"] else {
            throw AppConfigError.missingField(slug: slug, field: "project_path")
        }

        var ascConfig: ASCKeyConfig?
        if let keyID = ascValues["key_id"], let issuerID = ascValues["issuer_id"] {
            ascConfig = ASCKeyConfig(keyID: keyID, issuerID: issuerID)
        }

        return AppConfig(
            slug: slug,
            scheme: scheme,
            teamID: teamID,
            bundleID: bundleID,
            projectPath: projectPath,
            testflightGroup: values["testflight_group"] ?? "External Testers",
            exportMethod: values["export_method"] ?? "app-store",
            asc: ascConfig
        )
    }
}

// MARK: - AppConfigError

public enum AppConfigError: Error, CustomStringConvertible {
    case fileNotFound(String)
    case missingField(slug: String, field: String)
    case unknownApp(String, available: [String])
    case ambiguousApp(available: [String])

    public var description: String {
        switch self {
        case .fileNotFound(let path):
            return "App configuration not found at \(path). Create it with: shikki ship --testflight --setup"
        case .missingField(let slug, let field):
            return "App '\(slug)' is missing required field '\(field)' in apps.toml"
        case .unknownApp(let slug, let available):
            return "Unknown app '\(slug)'. Configured apps: \(available.joined(separator: ", "))"
        case .ambiguousApp(let available):
            return "Multiple apps configured. Use --app \(available.first ?? "<slug>"). Available: \(available.joined(separator: ", "))"
        }
    }
}
