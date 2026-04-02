import Foundation

// MARK: - FileOperation

/// Filesystem operations a plugin can request.
public enum FileOperation: String, Sendable {
    case read
    case create
    case overwrite
    case delete
}

// MARK: - AccessDecision

/// Result of a sandbox access check.
public enum AccessDecision: Sendable {
    case allowed
    case denied(reason: String)

    /// Convenience check for allowed state.
    public var isAllowed: Bool {
        if case .allowed = self { return true }
        return false
    }
}

// MARK: - SecurityViolation

/// A recorded security violation from a plugin.
public struct SecurityViolation: Sendable, Codable {
    public let pluginId: PluginID
    public let path: String
    public let operation: String
    public let reason: String
    public let timestamp: Date

    public init(
        pluginId: PluginID,
        path: String,
        operation: String,
        reason: String,
        timestamp: Date = Date()
    ) {
        self.pluginId = pluginId
        self.path = path
        self.operation = operation
        self.reason = reason
        self.timestamp = timestamp
    }
}

// MARK: - PluginSandbox

/// Path validation engine that enforces filesystem isolation for plugins.
///
/// Business Rules:
/// - BR-01: Plugins operate within `~/.shikki/plugins/<id>/data/`
/// - BR-02: No file access outside scope without explicit user permission
/// - BR-03: Cannot access secrets (.env, keychain, ~/.aws)
/// - BR-04: Cannot modify ShikkiKit source or binaries
/// - BR-05: Additive-only — no deletion of user project files
/// - BR-06: Manifest must declare all filesystem paths accessed
/// - BR-08: Enterprise certification required for project file access
public struct PluginSandbox: Sendable {

    /// The plugin this sandbox protects.
    public let pluginId: PluginID

    /// The scoped directory this plugin owns: `~/.shikki/plugins/<id>/data/`.
    public let scopeDirectory: String

    /// Paths declared in the manifest that the plugin needs access to.
    public let declaredPaths: [String]

    /// The certification level of this plugin.
    public let certification: CertificationLevel

    public init(
        pluginId: PluginID,
        scopeDirectory: String,
        declaredPaths: [String] = [],
        certification: CertificationLevel = .uncertified
    ) {
        self.pluginId = pluginId
        self.scopeDirectory = scopeDirectory
        self.declaredPaths = declaredPaths
        self.certification = certification
    }

    // MARK: - Secret Patterns

    /// File path patterns that are always blocked regardless of scope or certification.
    private static let secretPatterns: [String] = [
        ".env",
        ".aws/",
        ".ssh/",
        "Keychains/",
        ".gnupg/",
        ".npmrc",
        ".pypirc",
        ".netrc",
        ".docker/config.json",
    ]

    /// Binary and source paths that plugins must never modify.
    private static let protectedPatterns: [String] = [
        "Sources/ShikkiKit/",
        "Sources/shikki/",
        "/usr/local/bin/shikki",
        "/opt/homebrew/bin/shikki",
    ]

    // MARK: - Access Validation

    /// Validate whether a plugin may perform the given operation on the path.
    ///
    /// Evaluation order:
    /// 1. Always block secret files (BR-03)
    /// 2. Always block ShikkiKit source/binaries (BR-04)
    /// 3. Allow operations within the plugin's scoped directory (BR-01)
    /// 4. Block deletion outside scope (BR-05)
    /// 5. Check declared paths with enterprise certification (BR-06 + BR-08)
    /// 6. Deny everything else (BR-02)
    public func validateAccess(path: String, operation: FileOperation) -> AccessDecision {
        let resolved = resolvePath(path)

        // BR-03: Secret files are always blocked
        if isSecretPath(resolved) {
            return .denied(reason: "Access to secret/credential file is always blocked: \(resolved)")
        }

        // BR-04: ShikkiKit source and binary paths are protected
        if isProtectedPath(resolved) {
            return .denied(reason: "Access to ShikkiKit source or binary is blocked: \(resolved)")
        }

        // BR-01: Operations within the scoped directory are allowed
        let resolvedScope = resolvePath(scopeDirectory)
        if resolved.hasPrefix(resolvedScope + "/") || resolved == resolvedScope {
            return .allowed
        }

        // BR-05: Deletion outside scope is always denied
        if operation == .delete {
            return .denied(reason: "Delete operation outside plugin scope is blocked: \(resolved)")
        }

        // BR-06 + BR-08: Declared paths require enterprise certification
        if isDeclaredPath(resolved) {
            if certification >= .enterpriseSafe {
                // Enterprise certified plugins may access declared paths (read/create/overwrite only)
                return .allowed
            } else {
                return .denied(
                    reason: "Access to declared path requires enterprise certification (current: \(certification.rawValue)): \(resolved)"
                )
            }
        }

        // BR-02: Everything else is denied
        return .denied(reason: "Access outside plugin scope is blocked: \(resolved)")
    }

    // MARK: - Path Resolution

    /// Resolve a path by expanding `~`, collapsing `..` traversals, and resolving symlinks.
    ///
    /// Symlinks are resolved so that a link inside the scope directory pointing outside
    /// is caught by the containment check. Mirrors TemplateRegistry's canonical path pattern.
    private func resolvePath(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        // Use URL to resolve .., ., and symlinks
        let url = URL(fileURLWithPath: expanded)
        return url.standardized.resolvingSymlinksInPath().path
    }

    // MARK: - Pattern Matching

    /// Check if a path matches any secret/credential pattern.
    private func isSecretPath(_ resolvedPath: String) -> Bool {
        for pattern in Self.secretPatterns {
            // Check if the pattern appears as a path component
            if pattern.hasSuffix("/") {
                // Directory pattern: check if path contains the directory
                if resolvedPath.contains("/\(pattern)") || resolvedPath.contains("/\(pattern.dropLast())") {
                    return true
                }
            } else {
                // File pattern: check exact filename or path suffix
                let filename = (resolvedPath as NSString).lastPathComponent
                if filename == pattern {
                    return true
                }
                // Also match paths ending with the pattern (e.g., /path/to/.env)
                if resolvedPath.hasSuffix("/\(pattern)") {
                    return true
                }
            }
        }
        return false
    }

    /// Check if a path matches any protected source/binary pattern.
    private func isProtectedPath(_ resolvedPath: String) -> Bool {
        for pattern in Self.protectedPatterns {
            if resolvedPath.contains(pattern) {
                return true
            }
        }
        return false
    }

    /// Check if a path falls under any declared path prefix.
    private func isDeclaredPath(_ resolvedPath: String) -> Bool {
        for declared in declaredPaths {
            let resolvedDeclared = resolvePath(declared)
            if resolvedPath.hasPrefix(resolvedDeclared + "/") || resolvedPath == resolvedDeclared {
                return true
            }
        }
        return false
    }
}
