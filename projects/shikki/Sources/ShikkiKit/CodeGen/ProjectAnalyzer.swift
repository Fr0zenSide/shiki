import Foundation

/// Errors that can occur during project analysis.
public enum ProjectAnalyzerError: Error, LocalizedError, Sendable {
    case projectNotFound(String)
    case gitHashUnavailable

    public var errorDescription: String? {
        switch self {
        case .projectNotFound(let path):
            return "Project directory not found: \(path)"
        case .gitHashUnavailable:
            return "Could not determine git commit hash"
        }
    }
}

/// Analyzes a Swift project directory and produces an ``ArchitectureCache``.
///
/// Uses regex-based parsing (no SwiftSyntax) for speed — targets 80% accuracy in <2s.
public struct ProjectAnalyzer: Sendable {

    public init() {}

    /// Analyze a project at the given path.
    ///
    /// - Parameter projectPath: Absolute path to the project root (must contain Package.swift or Swift sources).
    /// - Returns: A fully populated ``ArchitectureCache``.
    public func analyze(projectPath: String) async throws -> ArchitectureCache {
        let fm = FileManager.default
        let projectURL = URL(fileURLWithPath: projectPath)

        guard fm.fileExists(atPath: projectPath) else {
            throw ProjectAnalyzerError.projectNotFound(projectPath)
        }

        let projectId = projectURL.lastPathComponent
        let gitHash = (try? currentGitHash(at: projectPath)) ?? "unknown"

        // Parse Package.swift
        let packageInfo = parsePackageSwift(at: projectPath)

        // Collect all .swift files
        let swiftFiles = collectSwiftFiles(at: projectPath)

        // Parse all files for declarations
        var allProtocols: [ProtocolDescriptor] = []
        var allTypes: [TypeDescriptor] = []
        var dependencyGraph: [String: Set<String>] = [:]
        var patterns: [CodePattern] = []
        var testFileCount = 0
        var testCount = 0
        var hasSwiftTesting = false
        var hasXCTest = false
        var mockFiles: [String] = []
        var errorFiles: [String] = []
        var endpointFiles: [String] = []
        var firstErrorExample: String?
        var firstMockExample: String?
        var firstEndpointExample: String?
        var fixturePattern: String?

        for filePath in swiftFiles {
            let relativePath = relativize(filePath, from: projectPath)
            let module = inferModule(relativePath: relativePath, targets: packageInfo.targets)

            guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
                continue
            }

            // Track imports for dependency graph
            let imports = parseImports(content)
            if !imports.isEmpty {
                var existing = dependencyGraph[module] ?? []
                existing.formUnion(imports)
                dependencyGraph[module] = existing
            }

            // Parse protocols
            let protocols = parseProtocols(content, file: relativePath, module: module)
            allProtocols.append(contentsOf: protocols)

            // Parse types
            let types = parseTypes(content, file: relativePath, module: module)
            allTypes.append(contentsOf: types)

            // Detect test info
            let isTestFile = relativePath.contains("Tests/")
            if isTestFile {
                testFileCount += 1
                let fileTestCount = countTests(content)
                testCount += fileTestCount
                if content.contains("import Testing") || content.contains("@Test") || content.contains("@Suite") {
                    hasSwiftTesting = true
                }
                if content.contains("import XCTest") || content.contains("XCTestCase") {
                    hasXCTest = true
                }
            }

            // Detect patterns
            if content.contains("MockBackendClient") || content.range(of: #"class Mock\w+"#, options: .regularExpression) != nil
                || content.range(of: #"struct Mock\w+"#, options: .regularExpression) != nil {
                mockFiles.append(relativePath)
                if firstMockExample == nil {
                    firstMockExample = extractMockExample(content)
                }
            }

            if content.range(of: #"enum \w+Error\s*:\s*Error"#, options: .regularExpression) != nil
                || content.range(of: #"enum \w+Error\s*:\s*\w+,\s*LocalizedError"#, options: .regularExpression) != nil {
                errorFiles.append(relativePath)
                if firstErrorExample == nil {
                    firstErrorExample = extractErrorExample(content)
                }
            }

            if content.range(of: #"enum \w+EndPoint"#, options: .regularExpression) != nil
                || content.range(of: #"EndPoint\s*\{"#, options: .regularExpression) != nil {
                endpointFiles.append(relativePath)
                if firstEndpointExample == nil {
                    firstEndpointExample = extractEndpointExample(content)
                }
            }

            // Detect fixture pattern
            if fixturePattern == nil, isTestFile {
                if content.contains("TestFixtures") || content.contains("Fixtures.") {
                    fixturePattern = "TestFixtures helper with static factory methods"
                } else if content.contains("makeTest") || content.range(of: #"func make\w+\("#, options: .regularExpression) != nil {
                    fixturePattern = "Factory methods (make*) in test files"
                }
            }
        }

        // Resolve conformers: for each type, check its conformances against known protocols
        let protocolNames = Set(allProtocols.map(\.name))
        for i in allTypes.indices {
            for conformance in allTypes[i].conformances {
                if protocolNames.contains(conformance) {
                    if let protoIdx = allProtocols.firstIndex(where: { $0.name == conformance }) {
                        if !allProtocols[protoIdx].conformers.contains(allTypes[i].name) {
                            allProtocols[protoIdx].conformers.append(allTypes[i].name)
                        }
                    }
                }
            }
        }

        // Build patterns array
        if !errorFiles.isEmpty {
            patterns.append(CodePattern(
                name: "error_pattern",
                description: "Typed error enums conforming to Error/LocalizedError",
                example: firstErrorExample ?? "enum XxxError: Error, LocalizedError { ... }",
                files: errorFiles
            ))
        }
        if !mockFiles.isEmpty {
            patterns.append(CodePattern(
                name: "mock_pattern",
                description: "Mock types with call tracking and shouldThrow injection",
                example: firstMockExample ?? "class MockXxx: XxxProtocol { var shouldThrow: Error? ... }",
                files: mockFiles
            ))
        }
        if !endpointFiles.isEmpty {
            patterns.append(CodePattern(
                name: "endpoint_pattern",
                description: "Endpoint enums for API routing",
                example: firstEndpointExample ?? "enum XxxEndPoint: EndPoint { ... }",
                files: endpointFiles
            ))
        }

        // Determine test framework
        let framework: String
        if hasSwiftTesting && hasXCTest {
            framework = "mixed"
        } else if hasSwiftTesting {
            framework = "swift-testing"
        } else if hasXCTest {
            framework = "xctest"
        } else {
            framework = "unknown"
        }

        // Detect mock pattern description
        var mockPatternDesc: String?
        if !mockFiles.isEmpty {
            if firstMockExample?.contains("shouldThrow") == true {
                mockPatternDesc = "Mock* with call tracking + shouldThrow"
            } else {
                mockPatternDesc = "Mock* classes/structs"
            }
        }

        let testInfo = TestInfo(
            framework: framework,
            testFiles: testFileCount,
            testCount: testCount,
            mockPattern: mockPatternDesc,
            fixturePattern: fixturePattern
        )

        // Convert dependency graph sets to arrays
        let graphArrays = dependencyGraph.mapValues { Array($0).sorted() }

        return ArchitectureCache(
            projectId: projectId,
            projectPath: projectPath,
            gitHash: gitHash,
            builtAt: Date(),
            packageInfo: packageInfo,
            protocols: allProtocols,
            types: allTypes,
            dependencyGraph: graphArrays,
            patterns: patterns,
            testInfo: testInfo
        )
    }

    // MARK: - Git

    public func currentGitHash(at path: String) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["rev-parse", "HEAD"]
        process.currentDirectoryURL = URL(fileURLWithPath: path)
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ProjectAnalyzerError.gitHashUnavailable
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
    }

    // MARK: - File Collection

    func collectSwiftFiles(at projectPath: String) -> [String] {
        let fm = FileManager.default
        var results: [String] = []

        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: projectPath),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return results
        }

        for case let url as URL in enumerator {
            let path = url.path
            // Skip .build directory and other non-source dirs
            if path.contains("/.build/") || path.contains("/Packages/") {
                continue
            }
            if path.hasSuffix(".swift") {
                results.append(path)
            }
        }

        return results.sorted()
    }

    // MARK: - Package.swift Parsing

    func parsePackageSwift(at projectPath: String) -> PackageInfo {
        let packagePath = "\(projectPath)/Package.swift"
        guard let content = try? String(contentsOfFile: packagePath, encoding: .utf8) else {
            return PackageInfo()
        }

        let name = parsePackageName(content)
        let platforms = parsePlatforms(content)
        let targets = parseTargets(content, projectPath: projectPath)
        let dependencies = parseDependencies(content)

        return PackageInfo(name: name, platforms: platforms, targets: targets, dependencies: dependencies)
    }

    func parsePackageName(_ content: String) -> String {
        // Match: name: "xxx"
        if let match = content.range(of: #"name:\s*"([^"]+)""#, options: .regularExpression) {
            let substring = content[match]
            if let nameMatch = substring.range(of: #""([^"]+)""#, options: .regularExpression) {
                let quoted = content[nameMatch]
                return String(quoted.dropFirst().dropLast())
            }
        }
        return ""
    }

    func parsePlatforms(_ content: String) -> [String] {
        var platforms: [String] = []
        let platformPattern = #"\.(macOS|iOS|tvOS|watchOS|visionOS)\(\.v(\d+(?:_\d+)?)\)"#
        let regex = try? NSRegularExpression(pattern: platformPattern)
        let range = NSRange(content.startIndex..., in: content)
        regex?.enumerateMatches(in: content, range: range) { match, _, _ in
            guard let match else { return }
            if let platformRange = Range(match.range(at: 1), in: content),
               let versionRange = Range(match.range(at: 2), in: content) {
                let platform = content[platformRange]
                let version = content[versionRange].replacingOccurrences(of: "_", with: ".")
                platforms.append("\(platform) \(version)")
            }
        }
        return platforms
    }

    func parseTargets(_ content: String, projectPath: String) -> [TargetInfo] {
        var targets: [TargetInfo] = []
        let fm = FileManager.default

        // Match target declarations
        let targetPatterns: [(String, TargetType)] = [
            (#"\.testTarget\(\s*name:\s*"([^"]+)""#, .test),
            (#"\.executableTarget\(\s*name:\s*"([^"]+)""#, .executable),
            (#"\.target\(\s*name:\s*"([^"]+)""#, .library),
        ]

        for (pattern, type) in targetPatterns {
            let regex = try? NSRegularExpression(pattern: pattern)
            let range = NSRange(content.startIndex..., in: content)
            regex?.enumerateMatches(in: content, range: range) { match, _, _ in
                guard let match,
                      let nameRange = Range(match.range(at: 1), in: content) else { return }
                let name = String(content[nameRange])

                // Determine path
                let path: String
                switch type {
                case .test:
                    path = "Tests/\(name)"
                case .executable, .library:
                    path = "Sources/\(name)"
                }

                // Count source files
                let fullPath = "\(projectPath)/\(path)"
                var sourceFiles = 0
                if let enumerator = fm.enumerator(atPath: fullPath) {
                    for case let file as String in enumerator where file.hasSuffix(".swift") {
                        sourceFiles += 1
                    }
                }

                // Parse target dependencies (simplified)
                let deps = parseTargetDependencies(content, targetName: name)

                targets.append(TargetInfo(
                    name: name,
                    type: type,
                    path: path,
                    dependencies: deps,
                    sourceFiles: sourceFiles
                ))
            }
        }

        return targets
    }

    func parseTargetDependencies(_ content: String, targetName: String) -> [String] {
        // Find the target block and extract dependencies
        // This is a simplified regex approach
        let pattern = #"name:\s*"\#(targetName)"[^)]*dependencies:\s*\[((?:[^\]]|\n)*)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators),
              let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
              let depsRange = Range(match.range(at: 1), in: content)
        else {
            return []
        }

        let depsBlock = String(content[depsRange])
        var deps: [String] = []

        // Match "DependencyName" or .product(name: "X", ...)
        let quotedPattern = #""([^"]+)""#
        let quotedRegex = try? NSRegularExpression(pattern: quotedPattern)
        let depsNSRange = NSRange(depsBlock.startIndex..., in: depsBlock)
        quotedRegex?.enumerateMatches(in: depsBlock, range: depsNSRange) { m, _, _ in
            guard let m, let r = Range(m.range(at: 1), in: depsBlock) else { return }
            let dep = String(depsBlock[r])
            // Skip package names in .product(name:, package:) — only keep first quoted string per .product
            if !deps.contains(dep) {
                deps.append(dep)
            }
        }

        return deps
    }

    func parseDependencies(_ content: String) -> [DependencyInfo] {
        var deps: [DependencyInfo] = []

        // Remote: .package(url: "...", from: "...")
        let remotePattern = #"\.package\(\s*url:\s*"([^"]+)""#
        let remoteRegex = try? NSRegularExpression(pattern: remotePattern)
        let range = NSRange(content.startIndex..., in: content)
        remoteRegex?.enumerateMatches(in: content, range: range) { match, _, _ in
            guard let match,
                  let urlRange = Range(match.range(at: 1), in: content) else { return }
            let url = String(content[urlRange])
            let name = url.split(separator: "/").last.map { String($0) }?.replacingOccurrences(of: ".git", with: "") ?? url
            deps.append(DependencyInfo(name: name, isLocal: false, url: url))
        }

        // Local: .package(path: "...")
        let localPattern = #"\.package\(\s*(?:name:\s*"[^"]*",\s*)?path:\s*"([^"]+)""#
        let localRegex = try? NSRegularExpression(pattern: localPattern)
        localRegex?.enumerateMatches(in: content, range: range) { match, _, _ in
            guard let match,
                  let pathRange = Range(match.range(at: 1), in: content) else { return }
            let path = String(content[pathRange])
            let name = path.split(separator: "/").last.map(String.init) ?? path
            deps.append(DependencyInfo(name: name, isLocal: true, path: path))
        }

        return deps
    }

    // MARK: - Protocol Parsing

    func parseProtocols(_ content: String, file: String, module: String) -> [ProtocolDescriptor] {
        var protocols: [ProtocolDescriptor] = []

        // Match: (public )?(protocol) Name (: Inherited)? {
        let pattern = #"(?:public\s+)?protocol\s+(\w+)(?:\s*:\s*([^\{]+))?\s*\{"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return protocols }

        let range = NSRange(content.startIndex..., in: content)
        regex.enumerateMatches(in: content, range: range) { match, _, _ in
            guard let match,
                  let nameRange = Range(match.range(at: 1), in: content) else { return }
            let name = String(content[nameRange])

            // Extract methods from protocol body
            let methods = extractProtocolMethods(content, protocolName: name)

            protocols.append(ProtocolDescriptor(
                name: name,
                file: file,
                methods: methods,
                conformers: [],
                module: module
            ))
        }

        return protocols
    }

    func extractProtocolMethods(_ content: String, protocolName: String) -> [String] {
        // Find the protocol body using brace matching
        let searchPattern = "protocol \(protocolName)"
        guard let startIdx = content.range(of: searchPattern)?.upperBound else { return [] }

        // Find opening brace
        guard let braceStart = content[startIdx...].firstIndex(of: "{") else { return [] }

        // Simple brace-depth tracking to find the closing brace
        var depth = 1
        var idx = content.index(after: braceStart)
        let endIndex = content.endIndex

        while idx < endIndex && depth > 0 {
            if content[idx] == "{" { depth += 1 }
            else if content[idx] == "}" { depth -= 1 }
            idx = content.index(after: idx)
        }

        guard depth == 0 else { return [] }
        let body = String(content[content.index(after: braceStart)..<content.index(before: idx)])

        // Match func declarations in the body
        var methods: [String] = []
        let funcPattern = #"func\s+\w+\([^)]*\)(?:\s*(?:async\s*)?(?:throws\s*)?(?:->\s*\S+)?)?"#
        if let funcRegex = try? NSRegularExpression(pattern: funcPattern) {
            let bodyRange = NSRange(body.startIndex..., in: body)
            funcRegex.enumerateMatches(in: body, range: bodyRange) { m, _, _ in
                guard let m, let r = Range(m.range, in: body) else { return }
                let sig = String(body[r]).trimmingCharacters(in: .whitespaces)
                methods.append(sig)
            }
        }

        return methods
    }

    // MARK: - Type Parsing

    func parseTypes(_ content: String, file: String, module: String) -> [TypeDescriptor] {
        var types: [TypeDescriptor] = []

        let kindMap: [(String, TypeKind)] = [
            ("struct", .struct),
            ("class", .class),
            ("enum", .enum),
            ("actor", .actor),
        ]

        for (keyword, kind) in kindMap {
            let pattern = #"(public\s+)?(final\s+)?\#(keyword)\s+(\w+)(?:\s*<[^>]+>)?(?:\s*:\s*([^\{]+))?\s*\{"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }

            let range = NSRange(content.startIndex..., in: content)
            regex.enumerateMatches(in: content, range: range) { match, _, _ in
                guard let match,
                      let nameRange = Range(match.range(at: 3), in: content) else { return }
                let name = String(content[nameRange])

                let isPublic = match.range(at: 1).location != NSNotFound

                var conformances: [String] = []
                if match.range(at: 4).location != NSNotFound,
                   let confRange = Range(match.range(at: 4), in: content) {
                    let raw = String(content[confRange])
                    conformances = raw.split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                        .map { component in
                            // Strip generic constraints: "Sendable" stays, "Codable" stays
                            component.components(separatedBy: " ").first ?? component
                        }
                }

                let fields = extractFields(content, typeName: name)

                types.append(TypeDescriptor(
                    name: name,
                    kind: kind,
                    file: file,
                    module: module,
                    fields: fields,
                    conformances: conformances,
                    isPublic: isPublic
                ))
            }
        }

        return types
    }

    func extractFields(_ content: String, typeName: String) -> [String] {
        // Find the type body
        let patterns = [
            "struct \(typeName)",
            "class \(typeName)",
            "enum \(typeName)",
            "actor \(typeName)",
        ]

        var bodyStart: String.Index?
        for pat in patterns {
            if let found = content.range(of: pat) {
                bodyStart = found.upperBound
                break
            }
        }
        guard let start = bodyStart else { return [] }
        guard let braceStart = content[start...].firstIndex(of: "{") else { return [] }

        // Find closing brace (depth tracking)
        var depth = 1
        var idx = content.index(after: braceStart)
        while idx < content.endIndex && depth > 0 {
            if content[idx] == "{" { depth += 1 }
            else if content[idx] == "}" { depth -= 1 }
            idx = content.index(after: idx)
        }
        guard depth == 0 else { return [] }

        let body = String(content[content.index(after: braceStart)..<content.index(before: idx)])

        // Match property declarations: (public )?(let|var) name
        var fields: [String] = []
        let propPattern = #"(?:public\s+)?(?:private\s+)?(?:let|var)\s+(\w+)"#
        if let propRegex = try? NSRegularExpression(pattern: propPattern) {
            let bodyRange = NSRange(body.startIndex..., in: body)
            propRegex.enumerateMatches(in: body, range: bodyRange) { m, _, _ in
                guard let m, let r = Range(m.range(at: 1), in: body) else { return }
                let field = String(body[r])
                // Skip computed properties and coding keys
                if field != "CodingKeys" && !fields.contains(field) {
                    fields.append(field)
                }
            }
        }

        return fields
    }

    // MARK: - Import Parsing

    func parseImports(_ content: String) -> Set<String> {
        var imports: Set<String> = []
        let pattern = #"^import\s+(\w+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else {
            return imports
        }
        let range = NSRange(content.startIndex..., in: content)
        regex.enumerateMatches(in: content, range: range) { match, _, _ in
            guard let match,
                  let nameRange = Range(match.range(at: 1), in: content) else { return }
            imports.insert(String(content[nameRange]))
        }
        return imports
    }

    // MARK: - Test Counting

    func countTests(_ content: String) -> Int {
        var count = 0

        // Swift Testing: @Test
        let testPattern = #"@Test\b"#
        if let regex = try? NSRegularExpression(pattern: testPattern) {
            count += regex.numberOfMatches(in: content, range: NSRange(content.startIndex..., in: content))
        }

        // XCTest: func test*()
        let xctestPattern = #"func\s+test\w+\s*\("#
        if let regex = try? NSRegularExpression(pattern: xctestPattern) {
            count += regex.numberOfMatches(in: content, range: NSRange(content.startIndex..., in: content))
        }

        return count
    }

    // MARK: - Pattern Examples

    func extractErrorExample(_ content: String) -> String? {
        let pattern = #"enum\s+\w+Error[^}]*\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators),
              let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
              let range = Range(match.range, in: content) else { return nil }
        let example = String(content[range])
        // Truncate if too long
        if example.count > 300 {
            return String(example.prefix(300)) + " ... }"
        }
        return example
    }

    func extractMockExample(_ content: String) -> String? {
        // Just grab the class declaration line + a few properties
        let pattern = #"(?:final\s+)?class\s+Mock\w+[^\{]*\{[^}]{0,200}"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators),
              let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
              let range = Range(match.range, in: content) else { return nil }
        return String(content[range]) + " ... }"
    }

    func extractEndpointExample(_ content: String) -> String? {
        let pattern = #"enum\s+\w+EndPoint[^}]*\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators),
              let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
              let range = Range(match.range, in: content) else { return nil }
        let example = String(content[range])
        if example.count > 300 {
            return String(example.prefix(300)) + " ... }"
        }
        return example
    }

    // MARK: - Helpers

    func relativize(_ absolutePath: String, from basePath: String) -> String {
        let base = basePath.hasSuffix("/") ? basePath : basePath + "/"
        if absolutePath.hasPrefix(base) {
            return String(absolutePath.dropFirst(base.count))
        }
        return absolutePath
    }

    func inferModule(relativePath: String, targets: [TargetInfo]) -> String {
        // Match against known target paths
        for target in targets {
            if relativePath.hasPrefix(target.path + "/") || relativePath.hasPrefix(target.path) {
                return target.name
            }
        }
        // Fallback: extract from path
        let components = relativePath.split(separator: "/")
        if components.count >= 2 {
            return String(components[1])
        }
        return "unknown"
    }
}
