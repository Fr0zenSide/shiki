import Foundation

/// Errors that can occur during spec parsing.
public enum SpecParserError: Error, LocalizedError, Sendable {
    case specNotFound(String)
    case noProtocolsExtracted
    case invalidSpecFormat(String)

    public var errorDescription: String? {
        switch self {
        case .specNotFound(let path):
            return "Spec file not found: \(path)"
        case .noProtocolsExtracted:
            return "No protocol or type declarations found in spec"
        case .invalidSpecFormat(let detail):
            return "Invalid spec format: \(detail)"
        }
    }
}

/// A parsed protocol layer extracted from a TDDP or feature spec.
///
/// Contains the contracts (protocols + types) that agents implement against.
/// This is the output of ``SpecParser`` and input to ``ContractVerifier`` and ``WorkUnitPlanner``.
public struct ProtocolLayer: Sendable, Codable {
    /// Feature name derived from the spec.
    public var featureName: String
    /// Protocols extracted from the spec.
    public var protocols: [ProtocolSpec]
    /// Types (structs, enums, etc.) extracted from the spec.
    public var types: [TypeSpec]
    /// Files that should be created (path + role).
    public var fileSpecs: [FileSpec]
    /// Module/target where this feature belongs.
    public var targetModule: String

    public init(
        featureName: String = "",
        protocols: [ProtocolSpec] = [],
        types: [TypeSpec] = [],
        fileSpecs: [FileSpec] = [],
        targetModule: String = ""
    ) {
        self.featureName = featureName
        self.protocols = protocols
        self.types = types
        self.fileSpecs = fileSpecs
        self.targetModule = targetModule
    }
}

/// A protocol declaration extracted from a spec.
public struct ProtocolSpec: Sendable, Codable {
    public var name: String
    /// Method signatures declared in the spec.
    public var methods: [String]
    /// Associated types if any.
    public var associatedTypes: [String]
    /// Protocol inheritance (e.g. Sendable, Codable).
    public var inherits: [String]
    /// Which file this protocol should live in.
    public var targetFile: String

    public init(
        name: String,
        methods: [String] = [],
        associatedTypes: [String] = [],
        inherits: [String] = [],
        targetFile: String = ""
    ) {
        self.name = name
        self.methods = methods
        self.associatedTypes = associatedTypes
        self.inherits = inherits
        self.targetFile = targetFile
    }
}

/// A type declaration extracted from a spec.
public struct TypeSpec: Sendable, Codable {
    public var name: String
    public var kind: TypeKind
    /// Properties/fields.
    public var fields: [FieldSpec]
    /// Protocol conformances.
    public var conformances: [String]
    /// Which file this type should live in.
    public var targetFile: String

    public init(
        name: String,
        kind: TypeKind = .struct,
        fields: [FieldSpec] = [],
        conformances: [String] = [],
        targetFile: String = ""
    ) {
        self.name = name
        self.kind = kind
        self.fields = fields
        self.conformances = conformances
        self.targetFile = targetFile
    }
}

/// A field within a type spec.
public struct FieldSpec: Sendable, Codable {
    public var name: String
    public var type: String
    public var isOptional: Bool

    public init(name: String, type: String, isOptional: Bool = false) {
        self.name = name
        self.type = type
        self.isOptional = isOptional
    }
}

/// A file to be created as part of the feature.
public struct FileSpec: Sendable, Codable {
    public var path: String
    public var role: FileRole
    /// Brief description of what this file implements.
    public var description: String

    public init(path: String, role: FileRole = .implementation, description: String = "") {
        self.path = path
        self.role = role
        self.description = description
    }
}

/// The role a file plays in the feature.
public enum FileRole: String, Sendable, Codable {
    case `protocol`
    case model
    case implementation
    case test
    case mock
}

/// Parses TDDP / feature spec markdown to extract protocol and type declarations.
///
/// The spec IS the compiler input. No separate "English → protocol" translation.
/// Extracts Swift code blocks containing protocol/struct/enum declarations,
/// plus structured TDDP sections listing files and their contracts.
public struct SpecParser: Sendable {

    public init() {}

    /// Parse a spec file at the given path.
    public func parse(specPath: String) throws -> ProtocolLayer {
        guard FileManager.default.fileExists(atPath: specPath) else {
            throw SpecParserError.specNotFound(specPath)
        }
        let content = try String(contentsOfFile: specPath, encoding: .utf8)
        return try parse(content: content)
    }

    /// Parse spec content directly (for testing or inline specs).
    public func parse(content: String) throws -> ProtocolLayer {
        var layer = ProtocolLayer()

        // Extract feature name from first # heading
        layer.featureName = extractFeatureName(content)

        // Extract target module from spec metadata or default
        layer.targetModule = extractTargetModule(content)

        // Extract Swift code blocks containing declarations
        let codeBlocks = extractSwiftCodeBlocks(content)

        for block in codeBlocks {
            // Parse protocols from code blocks
            let protocols = parseProtocolDeclarations(block)
            layer.protocols.append(contentsOf: protocols)

            // Parse types from code blocks
            let types = parseTypeDeclarations(block)
            layer.types.append(contentsOf: types)
        }

        // Extract file specs from TDDP-style sections
        let fileSpecs = extractFileSpecs(content)
        layer.fileSpecs = fileSpecs

        // Infer target files for protocols/types that don't have explicit targets
        inferTargetFiles(&layer)

        return layer
    }

    // MARK: - Feature Name

    func extractFeatureName(_ content: String) -> String {
        // First # heading
        let pattern = #"^#\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines),
              let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
              let range = Range(match.range(at: 1), in: content)
        else {
            return "Unknown Feature"
        }
        return String(content[range]).trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Target Module

    func extractTargetModule(_ content: String) -> String {
        // Look for "module:" or "target:" in frontmatter or metadata
        let patterns = [
            #"(?:module|target):\s*(\w+)"#,
            #"Target:\s*(\w+)"#,
            #"Module:\s*(\w+)"#,
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
               let range = Range(match.range(at: 1), in: content) {
                return String(content[range])
            }
        }
        return ""
    }

    // MARK: - Code Block Extraction

    func extractSwiftCodeBlocks(_ content: String) -> [String] {
        var blocks: [String] = []

        // Match ```swift ... ``` blocks
        let pattern = #"```swift\s*\n([\s\S]*?)```"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return blocks }

        let range = NSRange(content.startIndex..., in: content)
        regex.enumerateMatches(in: content, range: range) { match, _, _ in
            guard let match,
                  let blockRange = Range(match.range(at: 1), in: content) else { return }
            blocks.append(String(content[blockRange]))
        }

        return blocks
    }

    // MARK: - Protocol Parsing

    func parseProtocolDeclarations(_ code: String) -> [ProtocolSpec] {
        var specs: [ProtocolSpec] = []

        let pattern = #"(?:public\s+)?protocol\s+(\w+)(?:\s*:\s*([^\{]+))?\s*\{"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return specs }

        let range = NSRange(code.startIndex..., in: code)
        regex.enumerateMatches(in: code, range: range) { match, _, _ in
            guard let match,
                  let nameRange = Range(match.range(at: 1), in: code) else { return }
            let name = String(code[nameRange])

            var inherits: [String] = []
            if match.range(at: 2).location != NSNotFound,
               let inheritRange = Range(match.range(at: 2), in: code) {
                inherits = String(code[inheritRange])
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }

            // Extract methods from protocol body
            let methods = extractMethodSignatures(code, declarationName: name, keyword: "protocol")

            // Extract associated types
            let associatedTypes = extractAssociatedTypes(code, protocolName: name)

            specs.append(ProtocolSpec(
                name: name,
                methods: methods,
                associatedTypes: associatedTypes,
                inherits: inherits
            ))
        }

        return specs
    }

    // MARK: - Type Parsing

    func parseTypeDeclarations(_ code: String) -> [TypeSpec] {
        var specs: [TypeSpec] = []

        let kindMap: [(String, TypeKind)] = [
            ("struct", .struct),
            ("class", .class),
            ("enum", .enum),
            ("actor", .actor),
        ]

        for (keyword, kind) in kindMap {
            let pattern = #"(?:public\s+)?(?:final\s+)?\#(keyword)\s+(\w+)(?:\s*<[^>]+>)?(?:\s*:\s*([^\{]+))?\s*\{"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }

            let range = NSRange(code.startIndex..., in: code)
            regex.enumerateMatches(in: code, range: range) { match, _, _ in
                guard let match,
                      let nameRange = Range(match.range(at: 1), in: code) else { return }
                let name = String(code[nameRange])

                var conformances: [String] = []
                if match.range(at: 2).location != NSNotFound,
                   let confRange = Range(match.range(at: 2), in: code) {
                    conformances = String(code[confRange])
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                }

                let fields = extractFieldSpecs(code, typeName: name)

                specs.append(TypeSpec(
                    name: name,
                    kind: kind,
                    fields: fields,
                    conformances: conformances
                ))
            }
        }

        return specs
    }

    // MARK: - Method Extraction

    func extractMethodSignatures(_ code: String, declarationName: String, keyword: String) -> [String] {
        let searchPattern = "\(keyword) \(declarationName)"
        guard let startIdx = code.range(of: searchPattern)?.upperBound else { return [] }
        guard let braceStart = code[startIdx...].firstIndex(of: "{") else { return [] }

        var depth = 1
        var idx = code.index(after: braceStart)
        while idx < code.endIndex && depth > 0 {
            if code[idx] == "{" { depth += 1 }
            else if code[idx] == "}" { depth -= 1 }
            idx = code.index(after: idx)
        }
        guard depth == 0 else { return [] }

        let body = String(code[code.index(after: braceStart)..<code.index(before: idx)])

        var methods: [String] = []
        let funcPattern = #"func\s+\w+\([^)]*\)(?:\s*(?:async\s*)?(?:throws\s*)?(?:->\s*\S+)?)?"#
        if let funcRegex = try? NSRegularExpression(pattern: funcPattern) {
            let bodyRange = NSRange(body.startIndex..., in: body)
            funcRegex.enumerateMatches(in: body, range: bodyRange) { m, _, _ in
                guard let m, let r = Range(m.range, in: body) else { return }
                methods.append(String(body[r]).trimmingCharacters(in: .whitespaces))
            }
        }
        return methods
    }

    // MARK: - Associated Types

    func extractAssociatedTypes(_ code: String, protocolName: String) -> [String] {
        let searchPattern = "protocol \(protocolName)"
        guard let startIdx = code.range(of: searchPattern)?.upperBound else { return [] }
        guard let braceStart = code[startIdx...].firstIndex(of: "{") else { return [] }

        var depth = 1
        var idx = code.index(after: braceStart)
        while idx < code.endIndex && depth > 0 {
            if code[idx] == "{" { depth += 1 }
            else if code[idx] == "}" { depth -= 1 }
            idx = code.index(after: idx)
        }
        guard depth == 0 else { return [] }

        let body = String(code[code.index(after: braceStart)..<code.index(before: idx)])

        var assocTypes: [String] = []
        let pattern = #"associatedtype\s+(\w+)"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let bodyRange = NSRange(body.startIndex..., in: body)
            regex.enumerateMatches(in: body, range: bodyRange) { m, _, _ in
                guard let m, let r = Range(m.range(at: 1), in: body) else { return }
                assocTypes.append(String(body[r]))
            }
        }
        return assocTypes
    }

    // MARK: - Field Specs

    func extractFieldSpecs(_ code: String, typeName: String) -> [FieldSpec] {
        let patterns = [
            "struct \(typeName)",
            "class \(typeName)",
            "enum \(typeName)",
            "actor \(typeName)",
        ]

        var bodyStart: String.Index?
        for pat in patterns {
            if let found = code.range(of: pat) {
                bodyStart = found.upperBound
                break
            }
        }
        guard let start = bodyStart else { return [] }
        guard let braceStart = code[start...].firstIndex(of: "{") else { return [] }

        var depth = 1
        var idx = code.index(after: braceStart)
        while idx < code.endIndex && depth > 0 {
            if code[idx] == "{" { depth += 1 }
            else if code[idx] == "}" { depth -= 1 }
            idx = code.index(after: idx)
        }
        guard depth == 0 else { return [] }

        let body = String(code[code.index(after: braceStart)..<code.index(before: idx)])

        var fields: [FieldSpec] = []
        let propPattern = #"(?:public\s+)?(?:private\s+)?(?:let|var)\s+(\w+)\s*:\s*([^\n=]+)"#
        if let propRegex = try? NSRegularExpression(pattern: propPattern) {
            let bodyRange = NSRange(body.startIndex..., in: body)
            propRegex.enumerateMatches(in: body, range: bodyRange) { m, _, _ in
                guard let m,
                      let nameRange = Range(m.range(at: 1), in: body),
                      let typeRange = Range(m.range(at: 2), in: body) else { return }
                let fieldName = String(body[nameRange])
                let fieldType = String(body[typeRange]).trimmingCharacters(in: .whitespaces)
                let isOptional = fieldType.hasSuffix("?")
                fields.append(FieldSpec(name: fieldName, type: fieldType, isOptional: isOptional))
            }
        }
        return fields
    }

    // MARK: - File Spec Extraction

    func extractFileSpecs(_ content: String) -> [FileSpec] {
        var specs: [FileSpec] = []

        // Match TDDP-style file listings:
        // - Sources/Module/File.swift — description
        // - Tests/Module/FileTests.swift — description
        // Also: → Sources/... or > Sources/...
        let pattern = #"(?:^-\s+|^>\s+|^\u2192\s+|^\d+\.\s+)(\S+\.swift)\s*(?:(?:\u2014|--|:)\s*(.+))?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else {
            return specs
        }

        let range = NSRange(content.startIndex..., in: content)
        regex.enumerateMatches(in: content, range: range) { match, _, _ in
            guard let match,
                  let pathRange = Range(match.range(at: 1), in: content) else { return }
            let path = String(content[pathRange])

            var description = ""
            if match.range(at: 2).location != NSNotFound,
               let descRange = Range(match.range(at: 2), in: content) {
                description = String(content[descRange]).trimmingCharacters(in: .whitespaces)
            }

            let role = inferFileRole(path)
            specs.append(FileSpec(path: path, role: role, description: description))
        }

        return specs
    }

    func inferFileRole(_ path: String) -> FileRole {
        let lower = path.lowercased()
        if lower.contains("test") { return .test }
        if lower.contains("mock") { return .mock }
        if lower.contains("protocol") { return .protocol }
        if lower.contains("model") || lower.contains("dto") || lower.contains("entity") { return .model }
        return .implementation
    }

    // MARK: - Target File Inference

    func inferTargetFiles(_ layer: inout ProtocolLayer) {
        let module = layer.targetModule.isEmpty ? "Sources" : "Sources/\(layer.targetModule)"

        for i in layer.protocols.indices where layer.protocols[i].targetFile.isEmpty {
            layer.protocols[i].targetFile = "\(module)/Protocols/\(layer.protocols[i].name).swift"
        }

        for i in layer.types.indices where layer.types[i].targetFile.isEmpty {
            let subdir = layer.types[i].kind == .enum ? "Models" : "Models"
            layer.types[i].targetFile = "\(module)/\(subdir)/\(layer.types[i].name).swift"
        }
    }
}
