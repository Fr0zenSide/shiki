import Foundation

/// Errors from `.moto` dotfile parsing.
public enum MotoDotfileError: Error, LocalizedError, Sendable {
    case fileNotFound(String)
    case invalidFormat(String)
    case missingSectionHeader(String)
    case missingRequiredField(section: String, field: String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return ".moto file not found at: \(path)"
        case .invalidFormat(let detail):
            return "Invalid .moto format: \(detail)"
        case .missingSectionHeader(let section):
            return "Missing required section: [\(section)]"
        case .missingRequiredField(let section, let field):
            return "Missing required field '\(field)' in [\(section)]"
        }
    }
}

/// Parsed representation of a `.moto` dotfile.
///
/// The `.moto` file is a TOML pointer to the project's pre-computed
/// architecture cache. It declares project identity, cache endpoint,
/// and attribution metadata.
///
/// Example `.moto` file:
/// ```toml
/// [project]
/// name = "Brainy"
/// description = "RSS reader with AI analysis"
/// language = "swift"
///
/// [cache]
/// endpoint = "https://cache.originate.dev/example/brainy"
/// version = "1.2.0"
/// commit = "a1b2c3d4"
/// schema = "1"
///
/// [cache.local]
/// path = ".moto-cache/"
///
/// [attribution]
/// authors = ["Alice <alice@example.com>"]
/// organization = "Example Corp"
/// ```
public struct MotoDotfile: Sendable, Codable, Equatable {
    public var project: ProjectSection
    public var cache: CacheSection
    public var attribution: AttributionSection

    public init(
        project: ProjectSection,
        cache: CacheSection,
        attribution: AttributionSection
    ) {
        self.project = project
        self.cache = cache
        self.attribution = attribution
    }

    // MARK: - Sections

    public struct ProjectSection: Sendable, Codable, Equatable {
        public var name: String
        public var description: String
        public var language: String
        public var license: String?
        public var repository: String?

        public init(
            name: String,
            description: String = "",
            language: String = "swift",
            license: String? = nil,
            repository: String? = nil
        ) {
            self.name = name
            self.description = description
            self.language = language
            self.license = license
            self.repository = repository
        }
    }

    public struct CacheSection: Sendable, Codable, Equatable {
        public var endpoint: String?
        public var version: String?
        public var commit: String?
        public var schema: String
        public var branches: [String]
        public var localPath: String

        public init(
            endpoint: String? = nil,
            version: String? = nil,
            commit: String? = nil,
            schema: String = "1",
            branches: [String] = ["main"],
            localPath: String = ".moto-cache/"
        ) {
            self.endpoint = endpoint
            self.version = version
            self.commit = commit
            self.schema = schema
            self.branches = branches
            self.localPath = localPath
        }
    }

    public struct AttributionSection: Sendable, Codable, Equatable {
        public var authors: [String]
        public var organization: String?
        public var created: String?

        public init(
            authors: [String] = [],
            organization: String? = nil,
            created: String? = nil
        ) {
            self.authors = authors
            self.organization = organization
            self.created = created
        }
    }
}

// MARK: - Parser

/// Lightweight TOML parser for `.moto` dotfiles.
///
/// Supports the subset of TOML used by `.moto`:
/// - `[section]` and `[section.subsection]` headers
/// - `key = "value"` string assignments
/// - `key = ["a", "b"]` inline string arrays
///
/// Does NOT support full TOML (no integers, booleans, dates, nested tables, etc.).
/// This is intentional — `.moto` files use only strings and string arrays.
public struct MotoDotfileParser: Sendable {

    public init() {}

    /// Parse a `.moto` file from disk.
    public func parse(at path: String) throws -> MotoDotfile {
        guard FileManager.default.fileExists(atPath: path) else {
            throw MotoDotfileError.fileNotFound(path)
        }
        let content = try String(contentsOfFile: path, encoding: .utf8)
        return try parse(content: content)
    }

    /// Parse `.moto` content from a string.
    public func parse(content: String) throws -> MotoDotfile {
        let sections = try parseSections(content)

        // [project] — required
        guard let projectDict = sections["project"] else {
            throw MotoDotfileError.missingSectionHeader("project")
        }
        guard let name = projectDict["name"]?.stringValue else {
            throw MotoDotfileError.missingRequiredField(section: "project", field: "name")
        }

        let project = MotoDotfile.ProjectSection(
            name: name,
            description: projectDict["description"]?.stringValue ?? "",
            language: projectDict["language"]?.stringValue ?? "swift",
            license: projectDict["license"]?.stringValue,
            repository: projectDict["repository"]?.stringValue
        )

        // [cache] — optional, defaults applied
        let cacheDict = sections["cache"] ?? [:]
        let cacheLocalDict = sections["cache.local"] ?? [:]

        let branchesValue = cacheDict["branches"]
        let branches: [String]
        if let arr = branchesValue?.arrayValue {
            branches = arr
        } else {
            branches = ["main"]
        }

        let cache = MotoDotfile.CacheSection(
            endpoint: cacheDict["endpoint"]?.stringValue,
            version: cacheDict["version"]?.stringValue,
            commit: cacheDict["commit"]?.stringValue,
            schema: cacheDict["schema"]?.stringValue ?? "1",
            branches: branches,
            localPath: cacheLocalDict["path"]?.stringValue ?? ".moto-cache/"
        )

        // [attribution] — optional
        let attrDict = sections["attribution"] ?? [:]
        let authorsValue = attrDict["authors"]
        let authors: [String]
        if let arr = authorsValue?.arrayValue {
            authors = arr
        } else {
            authors = []
        }

        let attribution = MotoDotfile.AttributionSection(
            authors: authors,
            organization: attrDict["organization"]?.stringValue,
            created: attrDict["created"]?.stringValue
        )

        return MotoDotfile(project: project, cache: cache, attribution: attribution)
    }

    /// Generate `.moto` TOML content from a dotfile struct.
    public func serialize(_ dotfile: MotoDotfile) -> String {
        var lines: [String] = [
            "# .moto -- DNS for code",
            "# This file tells AI agents where to find the project's architecture cache.",
            "",
            "[project]",
            "name = \"\(dotfile.project.name)\"",
        ]

        if !dotfile.project.description.isEmpty {
            lines.append("description = \"\(dotfile.project.description)\"")
        }
        lines.append("language = \"\(dotfile.project.language)\"")
        if let license = dotfile.project.license {
            lines.append("license = \"\(license)\"")
        }
        if let repo = dotfile.project.repository {
            lines.append("repository = \"\(repo)\"")
        }

        lines.append("")
        lines.append("[cache]")
        if let endpoint = dotfile.cache.endpoint {
            lines.append("endpoint = \"\(endpoint)\"")
        }
        if let version = dotfile.cache.version {
            lines.append("version = \"\(version)\"")
        }
        if let commit = dotfile.cache.commit {
            lines.append("commit = \"\(commit)\"")
        }
        lines.append("schema = \"\(dotfile.cache.schema)\"")
        let branchList = dotfile.cache.branches.map { "\"\($0)\"" }.joined(separator: ", ")
        lines.append("branches = [\(branchList)]")

        lines.append("")
        lines.append("[cache.local]")
        lines.append("path = \"\(dotfile.cache.localPath)\"")

        lines.append("")
        lines.append("[attribution]")
        if !dotfile.attribution.authors.isEmpty {
            let authorList = dotfile.attribution.authors.map { "\"\($0)\"" }.joined(separator: ", ")
            lines.append("authors = [\(authorList)]")
        }
        if let org = dotfile.attribution.organization {
            lines.append("organization = \"\(org)\"")
        }
        if let created = dotfile.attribution.created {
            lines.append("created = \"\(created)\"")
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }

    // MARK: - Internal TOML Parsing

    enum TOMLValue: Sendable {
        case string(String)
        case array([String])

        var stringValue: String? {
            if case .string(let s) = self { return s }
            return nil
        }

        var arrayValue: [String]? {
            if case .array(let a) = self { return a }
            return nil
        }
    }

    func parseSections(_ content: String) throws -> [String: [String: TOMLValue]] {
        var sections: [String: [String: TOMLValue]] = [:]
        var currentSection = ""

        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip comments and blank lines
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            // Section header: [section] or [section.subsection]
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                currentSection = String(trimmed.dropFirst().dropLast())
                    .trimmingCharacters(in: .whitespaces)
                if sections[currentSection] == nil {
                    sections[currentSection] = [:]
                }
                continue
            }

            // Key-value pair: key = value
            guard let equalsIndex = trimmed.firstIndex(of: "=") else {
                continue
            }

            let key = String(trimmed[trimmed.startIndex..<equalsIndex])
                .trimmingCharacters(in: .whitespaces)
            let rawValue = String(trimmed[trimmed.index(after: equalsIndex)...])
                .trimmingCharacters(in: .whitespaces)

            let value = parseValue(rawValue)

            if sections[currentSection] == nil {
                sections[currentSection] = [:]
            }
            sections[currentSection]?[key] = value
        }

        return sections
    }

    func parseValue(_ raw: String) -> TOMLValue {
        // Array: ["a", "b", "c"]
        if raw.hasPrefix("[") && raw.hasSuffix("]") {
            let inner = String(raw.dropFirst().dropLast())
            let elements = inner.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .map { stripQuotes($0) }
            return .array(elements)
        }

        // Quoted string: "value"
        return .string(stripQuotes(raw))
    }

    func stripQuotes(_ s: String) -> String {
        if s.count >= 2 && s.hasPrefix("\"") && s.hasSuffix("\"") {
            return String(s.dropFirst().dropLast())
        }
        return s
    }
}

// MARK: - Discovery

extension MotoDotfileParser {

    /// Discover a `.moto` file by walking up from the given path.
    ///
    /// Checks the given directory and each parent until the filesystem root.
    /// Returns `nil` if no `.moto` file is found.
    public func discover(from startPath: String) -> String? {
        let fm = FileManager.default
        var current = URL(fileURLWithPath: startPath)

        // If the start path is a file, start from its parent directory
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: startPath, isDirectory: &isDir), !isDir.boolValue {
            current = current.deletingLastPathComponent()
        }

        while current.path != "/" && current.path != "" {
            let motoPath = current.appendingPathComponent(".moto").path
            if fm.fileExists(atPath: motoPath) {
                return motoPath
            }
            current = current.deletingLastPathComponent()
        }

        // Check root
        let rootMoto = "/.moto"
        if fm.fileExists(atPath: rootMoto) {
            return rootMoto
        }

        return nil
    }
}
