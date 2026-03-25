import Foundation

/// Scoped testing — run only relevant tests during development (TPDD).
/// Full suite runs once at /pre-pr on the epic branch.
public struct TestScope: Codable, Sendable {
    public let packagePath: String
    public let filterPattern: String
    public let expectedNewTests: Int

    public init(
        packagePath: String,
        filterPattern: String,
        expectedNewTests: Int
    ) {
        self.packagePath = packagePath
        self.filterPattern = filterPattern
        self.expectedNewTests = expectedNewTests
    }

    /// Build the `swift test` command for this scope.
    public var runCommand: String {
        "swift test --package-path \(packagePath) --filter \"\(filterPattern)\""
    }

    /// Validate that the scope is well-formed.
    public var isValid: Bool {
        !packagePath.isEmpty && !filterPattern.isEmpty && expectedNewTests > 0
    }
}
