import Foundation

// MARK: - VersionBumper

/// Determines next semver version from conventional commit messages.
/// Parses commit prefixes: BREAKING/! -> major, feat -> minor, fix/chore/refactor -> patch.
public struct VersionBumper: Sendable {

    public init() {}

    /// Compute the next version from a base version and commit messages.
    /// - Parameters:
    ///   - from: Current semver string (e.g. "1.2.3")
    ///   - commits: Array of commit subject lines
    ///   - override: Manual version override (takes precedence)
    /// - Returns: Next version string
    public func bump(from version: String, commits: [String], override: String? = nil) -> String {
        if let override {
            return override
        }

        let components = parseVersion(version)
        let bumpType = detectBumpType(commits: commits)

        switch bumpType {
        case .major:
            return "\(components.major + 1).0.0"
        case .minor:
            return "\(components.major).\(components.minor + 1).0"
        case .patch:
            return "\(components.major).\(components.minor).\(components.patch + 1)"
        }
    }

    // MARK: - Private

    private enum BumpType {
        case major, minor, patch
    }

    private struct SemVer {
        let major: Int
        let minor: Int
        let patch: Int
    }

    private func parseVersion(_ version: String) -> SemVer {
        let cleaned = version.replacingOccurrences(of: "v", with: "")
        let parts = cleaned.split(separator: ".").compactMap { Int($0) }
        return SemVer(
            major: parts.count > 0 ? parts[0] : 0,
            minor: parts.count > 1 ? parts[1] : 0,
            patch: parts.count > 2 ? parts[2] : 0
        )
    }

    private func detectBumpType(commits: [String]) -> BumpType {
        var hasFeature = false

        for commit in commits {
            let lowered = commit.lowercased()

            if lowered.contains("breaking change") {
                return .major
            }

            if commit.range(of: #"^\w+!:"#, options: .regularExpression) != nil {
                return .major
            }

            if commit.hasPrefix("feat:") || commit.hasPrefix("feat(") {
                hasFeature = true
            }
        }

        return hasFeature ? .minor : .patch
    }
}
