// MARK: - ChangedScopeDetector.swift
// ShikkiTestRunner — Map changed files (from git diff) to affected scopes.
// Uses ScopeAnalyzer to determine which scopes need re-testing.

import Foundation

/// Detects which test scopes are affected by a set of changed files.
///
/// Given output from `git diff --name-only`, determines the minimal set of scopes
/// that must be tested. For PR gates, also expands to include dependent scopes.
public struct ChangedScopeDetector: Sendable {

    private let analyzer: ScopeAnalyzer
    private let manifest: ScopeManifest

    public init(manifest: ScopeManifest) {
        self.manifest = manifest
        self.analyzer = ScopeAnalyzer(manifest: manifest)
    }

    // MARK: - Public API

    /// Determine which scopes are directly affected by changed files.
    ///
    /// Maps each changed file to its scope by analyzing the file's path against
    /// the manifest's patterns. For source files (not test files), checks which
    /// scope owns the module/type patterns matching the file path. For test files,
    /// uses the ScopeAnalyzer's standard file-pattern matching.
    ///
    /// - Parameters:
    ///   - changedFiles: List of file paths from `git diff --name-only`.
    ///   - manifest: The scope manifest to match against.
    /// - Returns: De-duplicated array of affected scope definitions.
    public func affectedScopes(changedFiles: [String]) -> [ScopeDefinition] {
        var affectedNames: Set<String> = []

        for file in changedFiles {
            if let scopeName = scopeForFile(file) {
                affectedNames.insert(scopeName)
            }
        }

        // Preserve manifest order for deterministic output
        return manifest.scopes.filter { affectedNames.contains($0.name) }
    }

    /// Determine affected scopes plus their dependents (reverse dependencies).
    ///
    /// Used for PR gates where you want to test not just the changed scopes,
    /// but also every scope that depends on them. For example, if "kernel" changed,
    /// also test "tui" and "ship" if they declare `dependsOn: ["kernel"]`.
    ///
    /// - Parameters:
    ///   - changedFiles: List of file paths from `git diff --name-only`.
    ///   - manifest: The scope manifest to match against.
    /// - Returns: De-duplicated array of affected + dependent scope definitions.
    public func affectedWithDeps(changedFiles: [String]) -> [ScopeDefinition] {
        let directlyAffected = affectedScopes(changedFiles: changedFiles)
        var allAffectedNames: Set<String> = Set(directlyAffected.map(\.name))

        // Expand: for each directly affected scope, find its dependents
        // Use a worklist to handle transitive dependencies
        var worklist = directlyAffected.map(\.name)
        while !worklist.isEmpty {
            let current = worklist.removeFirst()
            let dependents = manifest.dependents(of: current)
            for dep in dependents {
                if !allAffectedNames.contains(dep.name) {
                    allAffectedNames.insert(dep.name)
                    worklist.append(dep.name)
                }
            }
        }

        // Preserve manifest order
        return manifest.scopes.filter { allAffectedNames.contains($0.name) }
    }

    // MARK: - File to Scope Mapping

    /// Map a single changed file to its scope name.
    ///
    /// Handles both test files and source files:
    /// - Test files: matched via ScopeAnalyzer's file-pattern matching
    /// - Source files: matched by checking if the file path contains module/type pattern names
    ///
    /// Returns nil if the file doesn't match any scope.
    func scopeForFile(_ filePath: String) -> String? {
        let fileName = (filePath as NSString).lastPathComponent

        // Strategy 1: Match test files via file patterns
        for scope in manifest.scopes {
            for pattern in scope.testFilePatterns {
                if analyzer.matchesGlobPattern(filePath: filePath, pattern: pattern) {
                    return scope.name
                }
            }
        }

        // Strategy 2: Match source files by module/type name in path
        // e.g., "Sources/ShikkiKit/Services/EventBus.swift" → "nats" (EventBus is a type pattern)
        let fileBaseName = (fileName as NSString).deletingPathExtension

        for scope in manifest.scopes {
            // Check if the file name matches a type pattern
            for typePattern in scope.typePatterns {
                if fileBaseName == typePattern
                    || fileBaseName.hasPrefix(typePattern)
                    || fileBaseName.hasSuffix(typePattern)
                {
                    return scope.name
                }
            }

            // Check if the file path contains a module pattern directory
            for modulePattern in scope.modulePatterns {
                if filePath.contains("/\(modulePattern)/")
                    || filePath.contains("/\(modulePattern).")
                {
                    return scope.name
                }
            }
        }

        // Strategy 3: Check directory-based hints
        // e.g., "Sources/Observatory/DecisionJournal.swift" → "observatory"
        let pathComponents = filePath.split(separator: "/").map(String.init)
        for scope in manifest.scopes {
            let scopeNameLower = scope.name.lowercased()
            for component in pathComponents {
                if component.lowercased() == scopeNameLower {
                    return scope.name
                }
            }
        }

        return nil
    }

    /// Extract scope names from a list of scope definitions.
    public static func scopeNames(from scopes: [ScopeDefinition]) -> [String] {
        scopes.map(\.name)
    }
}
