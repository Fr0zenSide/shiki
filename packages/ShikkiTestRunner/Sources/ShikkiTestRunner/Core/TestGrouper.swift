// MARK: - TestGrouper
// Groups test files into named scopes using ScopeAnalyzer + ScopeManifest.
// Ensures every test file appears in exactly one scope (or "unscoped" safety net).

import Foundation

/// A grouped set of test files belonging to one scope.
public struct TestGroup: Sendable, Equatable {
    /// Scope name (e.g. "nats", "kernel", "unscoped").
    public let scopeName: String

    /// Test files in this group.
    public let files: [String]

    /// Dependencies for this scope (types/modules it touches).
    public let dependencies: [String]

    /// Expected test count (estimated from file analysis, zero if unknown).
    public let expectedTestCount: Int

    public init(
        scopeName: String,
        files: [String],
        dependencies: [String],
        expectedTestCount: Int = 0
    ) {
        self.scopeName = scopeName
        self.files = files
        self.dependencies = dependencies
        self.expectedTestCount = expectedTestCount
    }
}

/// Summary of scope listing for display.
public struct ScopeListing: Sendable, Equatable {
    public let scopeName: String
    public let fileCount: Int
    public let expectedTestCount: Int
    public let dependencies: [String]
}

/// Groups test files into architecture-scoped groups.
public struct TestGrouper: Sendable {

    private let analyzer: ScopeAnalyzer
    private let manifest: ScopeManifest

    public init(manifest: ScopeManifest) {
        self.manifest = manifest
        self.analyzer = ScopeAnalyzer(manifest: manifest)
    }

    // MARK: - Grouping

    /// Group test files into scopes.
    /// - Parameter files: Array of (filePath, content) tuples for all test files.
    /// - Returns: Array of test groups, one per scope (plus "unscoped" if any leftovers).
    public func group(files: [(path: String, content: String)]) -> [TestGroup] {
        let assignments = analyzer.analyzeAll(files: files)
        return buildGroups(from: assignments)
    }

    /// Group test files using pre-computed assignments.
    /// - Parameter assignments: Scope assignments from ScopeAnalyzer.
    /// - Returns: Array of test groups.
    public func buildGroups(from assignments: [ScopeAssignment]) -> [TestGroup] {
        // Bucket assignments by scope name
        var scopeBuckets: [String: [ScopeAssignment]] = [:]

        for assignment in assignments {
            let key = assignment.scopeName ?? "unscoped"
            scopeBuckets[key, default: []].append(assignment)
        }

        // Build groups preserving manifest order, then append unscoped
        var groups: [TestGroup] = []

        for scopeDef in manifest.scopes {
            if let bucket = scopeBuckets[scopeDef.name] {
                let testCount = estimateTestCount(files: bucket)
                let group = TestGroup(
                    scopeName: scopeDef.name,
                    files: bucket.map(\.filePath).sorted(),
                    dependencies: (scopeDef.modulePatterns + scopeDef.typePatterns).sorted(),
                    expectedTestCount: testCount
                )
                groups.append(group)
                scopeBuckets.removeValue(forKey: scopeDef.name)
            }
        }

        // Add unscoped group if any files didn't match
        if let unscoped = scopeBuckets["unscoped"], !unscoped.isEmpty {
            let testCount = estimateTestCount(files: unscoped)
            groups.append(TestGroup(
                scopeName: "unscoped",
                files: unscoped.map(\.filePath).sorted(),
                dependencies: [],
                expectedTestCount: testCount
            ))
        }

        return groups
    }

    // MARK: - Verification

    /// Verification result for scope coverage.
    public struct VerificationResult: Sendable, Equatable {
        /// Whether all files are accounted for (each in exactly one scope).
        public let isComplete: Bool

        /// Files appearing in no scope.
        public let unscopedFiles: [String]

        /// Files appearing in multiple scopes (should not happen with first-match-wins).
        public let duplicateFiles: [String]

        /// Total number of files analyzed.
        public let totalFiles: Int

        /// Number of scopes with at least one file.
        public let activeScopeCount: Int
    }

    /// Verify that every test file appears in exactly one scope.
    /// - Parameter files: Array of (filePath, content) tuples.
    /// - Returns: Verification result.
    public func verify(files: [(path: String, content: String)]) -> VerificationResult {
        let assignments = analyzer.analyzeAll(files: files)
        return verifyAssignments(assignments, totalFiles: files.count)
    }

    /// Verify pre-computed assignments.
    public func verifyAssignments(
        _ assignments: [ScopeAssignment], totalFiles: Int
    ) -> VerificationResult {
        var fileToScope: [String: String] = [:]
        var unscopedFiles: [String] = []
        var duplicateFiles: [String] = []
        var activeScopes: Set<String> = []

        for assignment in assignments {
            if let scopeName = assignment.scopeName {
                if fileToScope[assignment.filePath] != nil {
                    duplicateFiles.append(assignment.filePath)
                }
                fileToScope[assignment.filePath] = scopeName
                activeScopes.insert(scopeName)
            } else {
                unscopedFiles.append(assignment.filePath)
            }
        }

        return VerificationResult(
            isComplete: unscopedFiles.isEmpty && duplicateFiles.isEmpty,
            unscopedFiles: unscopedFiles.sorted(),
            duplicateFiles: duplicateFiles.sorted(),
            totalFiles: totalFiles,
            activeScopeCount: activeScopes.count
        )
    }

    // MARK: - Scope Listing

    /// List available scopes with file/test counts.
    /// - Parameter files: Array of (filePath, content) tuples (optional: pass empty for manifest-only listing).
    /// - Returns: Array of scope listings.
    public func listScopes(
        files: [(path: String, content: String)] = []
    ) -> [ScopeListing] {
        if files.isEmpty {
            // Manifest-only listing (no file analysis)
            return manifest.scopes.map { scope in
                ScopeListing(
                    scopeName: scope.name,
                    fileCount: 0,
                    expectedTestCount: 0,
                    dependencies: (scope.modulePatterns + scope.typePatterns).sorted()
                )
            }
        }

        let groups = group(files: files)
        return groups.map { group in
            ScopeListing(
                scopeName: group.scopeName,
                fileCount: group.files.count,
                expectedTestCount: group.expectedTestCount,
                dependencies: group.dependencies
            )
        }
    }

    /// Filter groups to only include the named scopes.
    /// - Parameters:
    ///   - groups: All test groups.
    ///   - scopeNames: Names of scopes to include.
    /// - Returns: Filtered groups matching the requested names.
    public func filterScopes(
        groups: [TestGroup], scopeNames: Set<String>
    ) -> [TestGroup] {
        groups.filter { scopeNames.contains($0.scopeName) }
    }

    // MARK: - Test Count Estimation

    /// Estimate test count from file content by counting test function patterns.
    private func estimateTestCount(files: [ScopeAssignment]) -> Int {
        // Simple heuristic: not exact, just a reasonable estimate.
        // Real count comes from running the tests.
        return files.count * 8  // rough average of ~8 tests per file
    }

    /// Count test functions in Swift source content.
    /// Recognizes both XCTest (`func test*`) and Swift Testing (`@Test func`).
    public static func countTestFunctions(in content: String) -> Int {
        let nsContent = content as NSString
        let range = NSRange(location: 0, length: nsContent.length)

        var count = 0

        // XCTest pattern: func testSomething
        if let xcTestRegex = try? NSRegularExpression(
            pattern: #"func\s+test\w+\s*\("#,
            options: [.anchorsMatchLines]
        ) {
            count += xcTestRegex.numberOfMatches(in: content, range: range)
        }

        // Swift Testing pattern: @Test func
        if let swiftTestRegex = try? NSRegularExpression(
            pattern: #"@Test\s+(?:func|")"#,
            options: [.anchorsMatchLines]
        ) {
            count += swiftTestRegex.numberOfMatches(in: content, range: range)
        }

        return count
    }
}
