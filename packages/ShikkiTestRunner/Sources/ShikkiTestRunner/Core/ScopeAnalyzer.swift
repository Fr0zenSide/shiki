// MARK: - ScopeAnalyzer
// Analyzes Swift test files to determine which architecture scope they belong to.
// Parses import statements and type references, maps them against a ScopeManifest.

import Foundation

/// Result of analyzing a single test file.
public struct ScopeAssignment: Sendable, Equatable {
    /// Path to the test file.
    public let filePath: String

    /// The scope this file was assigned to, or nil if unscoped.
    public let scopeName: String?

    /// Import statements found in the file.
    public let imports: [String]

    /// Type references found in the file that matched scope patterns.
    public let matchedTypes: [String]

    /// How the scope was determined.
    public let matchReason: MatchReason

    public enum MatchReason: Sendable, Equatable {
        case importMatch(module: String)
        case typeMatch(type: String)
        case filePatternMatch(pattern: String)
        case unscoped
    }
}

/// Analyzes test files and assigns them to scopes based on a manifest.
public struct ScopeAnalyzer: Sendable {

    private let manifest: ScopeManifest

    public init(manifest: ScopeManifest) {
        self.manifest = manifest
    }

    // MARK: - Public API

    /// Analyze a single test file's content and assign it to a scope.
    /// - Parameters:
    ///   - filePath: Path to the test file (used for file pattern matching).
    ///   - content: The Swift source code content of the file.
    /// - Returns: A scope assignment for this file.
    public func analyze(filePath: String, content: String) -> ScopeAssignment {
        let imports = parseImports(from: content)
        let typeRefs = parseTypeReferences(from: content)

        // Priority 1: File pattern match
        for scope in manifest.scopes {
            for pattern in scope.testFilePatterns {
                if matchesGlobPattern(filePath: filePath, pattern: pattern) {
                    let matched = typeRefs.filter { scope.typePatterns.contains($0) }
                    return ScopeAssignment(
                        filePath: filePath,
                        scopeName: scope.name,
                        imports: imports,
                        matchedTypes: matched,
                        matchReason: .filePatternMatch(pattern: pattern)
                    )
                }
            }
        }

        // Priority 2: Import match
        for scope in manifest.scopes {
            for module in scope.modulePatterns {
                if imports.contains(module) {
                    let matched = typeRefs.filter { scope.typePatterns.contains($0) }
                    return ScopeAssignment(
                        filePath: filePath,
                        scopeName: scope.name,
                        imports: imports,
                        matchedTypes: matched,
                        matchReason: .importMatch(module: module)
                    )
                }
            }
        }

        // Priority 3: Type reference match
        for scope in manifest.scopes {
            for typePattern in scope.typePatterns {
                if typeRefs.contains(typePattern) {
                    let matched = typeRefs.filter { scope.typePatterns.contains($0) }
                    return ScopeAssignment(
                        filePath: filePath,
                        scopeName: scope.name,
                        imports: imports,
                        matchedTypes: matched,
                        matchReason: .typeMatch(type: typePattern)
                    )
                }
            }
        }

        // No match: unscoped
        return ScopeAssignment(
            filePath: filePath,
            scopeName: nil,
            imports: imports,
            matchedTypes: [],
            matchReason: .unscoped
        )
    }

    /// Analyze multiple test files and return assignments for each.
    /// - Parameter files: Array of (filePath, content) tuples.
    /// - Returns: Array of scope assignments, one per file.
    public func analyzeAll(files: [(path: String, content: String)]) -> [ScopeAssignment] {
        files.map { analyze(filePath: $0.path, content: $0.content) }
    }

    // MARK: - Import Parsing

    /// Parse `import` statements from Swift source code.
    /// Handles: `import Foo`, `import struct Foo.Bar`, `@testable import Foo`
    static let importRegex: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"^(?:@testable\s+)?import\s+(?:struct\s+|class\s+|enum\s+|protocol\s+|func\s+|typealias\s+|let\s+|var\s+)?(\w+)"#,
            options: [.anchorsMatchLines]
        )
    }()

    /// Extract module names from import statements.
    public func parseImports(from content: String) -> [String] {
        let nsContent = content as NSString
        let range = NSRange(location: 0, length: nsContent.length)

        let matches = Self.importRegex.matches(in: content, range: range)
        var imports: [String] = []

        for match in matches {
            if match.numberOfRanges > 1 {
                let moduleRange = match.range(at: 1)
                if moduleRange.location != NSNotFound {
                    let module = nsContent.substring(with: moduleRange)
                    if !imports.contains(module) {
                        imports.append(module)
                    }
                }
            }
        }

        return imports.sorted()
    }

    // MARK: - Type Reference Parsing

    /// Parse type references from Swift source code.
    static let typeRefRegex: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"\b([A-Z][a-zA-Z0-9]{2,})\b"#,
            options: []
        )
    }()

    /// Well-known types to exclude from type reference analysis.
    static let excludedTypes: Set<String> = [
        "String", "Int", "Double", "Float", "Bool", "Array", "Dictionary",
        "Set", "Optional", "Result", "Error", "Data", "Date", "URL",
        "UUID", "Codable", "Sendable", "Equatable", "Hashable",
        "Comparable", "Identifiable", "CustomStringConvertible",
        "XCTestCase", "Test", "Suite", "Issue", "Confirmation",
        "XCTAssertEqual", "XCTAssertTrue", "XCTAssertFalse",
        "XCTAssertNil", "XCTAssertNotNil", "XCTAssertThrowsError",
        "XCTFail", "XCTUnwrap", "XCTExpectFailure",
        "NSObject", "NSError", "NSRange", "NSRegularExpression",
        "JSONEncoder", "JSONDecoder", "PropertyListEncoder",
        "FileManager", "ProcessInfo", "Bundle", "NotificationCenter",
        "DispatchQueue", "Task", "TaskGroup",
    ]

    /// Extract type references from Swift source, excluding well-known types.
    public func parseTypeReferences(from content: String) -> [String] {
        let nsContent = content as NSString
        let range = NSRange(location: 0, length: nsContent.length)

        let matches = Self.typeRefRegex.matches(in: content, range: range)
        var types: Set<String> = []

        for match in matches {
            let typeRange = match.range(at: 1)
            if typeRange.location != NSNotFound {
                let typeName = nsContent.substring(with: typeRange)
                if !Self.excludedTypes.contains(typeName) {
                    types.insert(typeName)
                }
            }
        }

        return types.sorted()
    }

    // MARK: - Glob Pattern Matching

    /// Simple glob pattern matching for test file paths.
    func matchesGlobPattern(filePath: String, pattern: String) -> Bool {
        let fileName = (filePath as NSString).lastPathComponent

        if pattern.hasPrefix("**/") {
            let filePattern = String(pattern.dropFirst(3))
            return matchesSimpleGlob(string: fileName, pattern: filePattern)
        }

        if !pattern.contains("/") {
            return matchesSimpleGlob(string: fileName, pattern: pattern)
        }

        return matchesSimpleGlob(string: filePath, pattern: pattern)
    }

    /// Match a string against a simple glob pattern (supports `*` as wildcard).
    func matchesSimpleGlob(string: String, pattern: String) -> Bool {
        let regexPattern = "^"
            + pattern
                .replacingOccurrences(of: ".", with: "\\.")
                .replacingOccurrences(of: "*", with: ".*")
            + "$"

        guard let regex = try? NSRegularExpression(pattern: regexPattern) else {
            return false
        }

        let nsString = string as NSString
        let range = NSRange(location: 0, length: nsString.length)
        return regex.firstMatch(in: string, range: range) != nil
    }
}
