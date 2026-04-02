import Foundation
import Logging

// MARK: - ProjectTemplate

/// A reusable project template that can be installed and applied.
public struct ProjectTemplate: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let description: String
    public let version: String
    public let author: String
    public let language: String
    public let tags: [String]
    public let motoOverrides: MotoFile?
    public let files: [TemplateFile]

    public init(
        id: String,
        name: String,
        description: String,
        version: String = "1.0.0",
        author: String = "shikki",
        language: String = "any",
        tags: [String] = [],
        motoOverrides: MotoFile? = nil,
        files: [TemplateFile] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.version = version
        self.author = author
        self.language = language
        self.tags = tags
        self.motoOverrides = motoOverrides
        self.files = files
    }
}

// MARK: - TemplateFile

/// A file to be created when applying a template.
public struct TemplateFile: Codable, Sendable, Equatable {
    public let relativePath: String
    public let content: String
    public let executable: Bool

    public init(relativePath: String, content: String, executable: Bool = false) {
        self.relativePath = relativePath
        self.content = content
        self.executable = executable
    }
}

// MARK: - TemplateSource

/// Where a template was installed from.
public enum TemplateSource: String, Codable, Sendable, Equatable {
    case builtin
    case local
    case github
}

// MARK: - InstalledTemplate

/// A template that has been installed in the local registry.
public struct InstalledTemplate: Codable, Sendable, Equatable {
    public let template: ProjectTemplate
    public let source: TemplateSource
    public let installedAt: Date
    public let sourceURL: String?

    public init(
        template: ProjectTemplate,
        source: TemplateSource,
        installedAt: Date = Date(),
        sourceURL: String? = nil
    ) {
        self.template = template
        self.source = source
        self.installedAt = installedAt
        self.sourceURL = sourceURL
    }
}

// MARK: - RegistryError

public enum RegistryError: Error, Sendable, Equatable {
    case templateNotFound(String)
    case templateAlreadyInstalled(String)
    case invalidTemplate(String)
    case installFailed(String)
    case registryCorrupted
    case pathTraversal(String)
    case executableNotAllowed(String)
}

// MARK: - TemplateRegistry

/// Local registry of installed project templates.
/// Stores templates as JSON in `~/.config/shikki/templates/`.
public struct TemplateRegistry: Sendable {

    private let registryPath: String
    nonisolated(unsafe) private let fileManager: FileManager
    private let logger: Logger

    /// Default registry location.
    public static var defaultPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return (home as NSString).appendingPathComponent(".config/shikki/templates")
    }

    public init(
        registryPath: String? = nil,
        fileManager: FileManager = .default,
        logger: Logger = Logger(label: "shikki.template-registry")
    ) {
        self.registryPath = registryPath ?? Self.defaultPath
        self.fileManager = fileManager
        self.logger = logger
    }

    // MARK: - Public API

    /// List all installed templates.
    public func listInstalled() throws -> [InstalledTemplate] {
        let indexPath = (registryPath as NSString).appendingPathComponent("index.json")
        guard fileManager.fileExists(atPath: indexPath) else {
            return builtinTemplates().map { InstalledTemplate(template: $0, source: .builtin) }
        }

        guard let data = fileManager.contents(atPath: indexPath),
              let installed = try? JSONDecoder().decode([InstalledTemplate].self, from: data) else {
            throw RegistryError.registryCorrupted
        }

        // Merge builtins with installed
        var merged = builtinTemplates().map { InstalledTemplate(template: $0, source: .builtin) }
        for item in installed where !merged.contains(where: { $0.template.id == item.template.id }) {
            merged.append(item)
        }
        return merged.sorted { $0.template.name < $1.template.name }
    }

    /// Get a template by ID.
    public func get(id: String) throws -> InstalledTemplate {
        let all = try listInstalled()
        guard let found = all.first(where: { $0.template.id == id }) else {
            throw RegistryError.templateNotFound(id)
        }
        return found
    }

    /// Search templates by query (matches name, description, tags).
    public func search(query: String) throws -> [InstalledTemplate] {
        let lowered = query.lowercased()
        return try listInstalled().filter { item in
            item.template.name.lowercased().contains(lowered)
            || item.template.description.lowercased().contains(lowered)
            || item.template.tags.contains { $0.lowercased().contains(lowered) }
            || item.template.language.lowercased().contains(lowered)
        }
    }

    /// Install a template from a JSON definition.
    public func install(template: ProjectTemplate, source: TemplateSource, sourceURL: String? = nil) throws {
        var installed = loadIndex()

        // Check for duplicate
        if installed.contains(where: { $0.template.id == template.id }) {
            throw RegistryError.templateAlreadyInstalled(template.id)
        }

        // Validate template
        guard !template.name.isEmpty, !template.id.isEmpty else {
            throw RegistryError.invalidTemplate("Template must have a name and ID")
        }

        let entry = InstalledTemplate(
            template: template,
            source: source,
            sourceURL: sourceURL
        )
        installed.append(entry)

        try ensureRegistryDir()
        try saveIndex(installed)
    }

    /// Uninstall a template by ID. Builtins cannot be uninstalled.
    public func uninstall(id: String) throws {
        var installed = loadIndex()

        // Cannot uninstall builtins
        if builtinTemplates().contains(where: { $0.id == id }) {
            throw RegistryError.invalidTemplate("Cannot uninstall built-in template: \(id)")
        }

        guard installed.contains(where: { $0.template.id == id }) else {
            throw RegistryError.templateNotFound(id)
        }

        installed.removeAll { $0.template.id == id }
        try saveIndex(installed)
    }

    /// Apply a template to a directory.
    /// Returns the list of files created.
    ///
    /// - Parameters:
    ///   - templateId: The template to apply.
    ///   - path: Target directory.
    ///   - force: Overwrite existing files (does NOT bypass path or executable validation).
    ///   - allowExecutables: Allow creating files with the executable bit set. Defaults to `false`.
    public func apply(templateId: String, to path: String, force: Bool = false, allowExecutables: Bool = false) throws -> [String] {
        let entry = try get(id: templateId)
        let template = entry.template

        // Validation loop — runs BEFORE any file I/O
        for file in template.files {
            try validateRelativePath(file.relativePath, targetDir: path)

            // Resolve canonical path in pre-validation to prevent TOCTOU symlink injection
            let filePath = (path as NSString).appendingPathComponent(file.relativePath)
            try resolveCanonicalPath(filePath, targetDir: path)

            if file.executable && !allowExecutables {
                throw RegistryError.executableNotAllowed(file.relativePath)
            }
        }

        var created: [String] = []

        // Apply template files (only reached if all validations pass)
        for file in template.files {
            let filePath = (path as NSString).appendingPathComponent(file.relativePath)

            let dir = (filePath as NSString).deletingLastPathComponent

            // Create directory structure
            if !fileManager.fileExists(atPath: dir) {
                try fileManager.createDirectory(atPath: dir, withIntermediateDirectories: true)
            }

            // Skip existing files unless force
            if fileManager.fileExists(atPath: filePath) && !force {
                continue
            }

            // Substitute template variables
            let content = substituteVariables(file.content, projectName: URL(fileURLWithPath: path).lastPathComponent)
            try content.write(toFile: filePath, atomically: true, encoding: .utf8)

            if file.executable {
                logger.warning("Creating executable file from template: \(file.relativePath)")
                try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: filePath)
            }

            created.append(file.relativePath)
        }

        return created
    }

    // MARK: - Built-in Templates

    /// The default set of built-in templates that ship with Shikki.
    public func builtinTemplates() -> [ProjectTemplate] {
        [
            swiftCLITemplate,
            swiftLibraryTemplate,
            iosAppTemplate,
            typescriptAPITemplate,
            rustCLITemplate,
        ]
    }

    private var swiftCLITemplate: ProjectTemplate {
        ProjectTemplate(
            id: "swift-cli",
            name: "Swift CLI",
            description: "Swift Package Manager CLI tool with ArgumentParser",
            version: "1.0.0",
            author: "shikki",
            language: "swift",
            tags: ["cli", "swift", "spm", "argumentparser"],
            motoOverrides: MotoFile(
                name: "{{PROJECT_NAME}}",
                language: "swift",
                buildSystem: "spm",
                testCommand: "swift test",
                buildCommand: "swift build",
                lintCommand: "swiftlint",
                architecture: MotoFile.Architecture(
                    pattern: "Command",
                    sourceRoot: "Sources",
                    testRoot: "Tests"
                )
            ),
            files: [
                TemplateFile(
                    relativePath: "Package.swift",
                    content: """
                    // swift-tools-version: 6.0
                    import PackageDescription

                    let package = Package(
                        name: "{{PROJECT_NAME}}",
                        platforms: [.macOS(.v14)],
                        dependencies: [
                            .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
                        ],
                        targets: [
                            .executableTarget(
                                name: "{{PROJECT_NAME}}",
                                dependencies: [
                                    .product(name: "ArgumentParser", package: "swift-argument-parser"),
                                ]
                            ),
                            .testTarget(
                                name: "{{PROJECT_NAME}}Tests",
                                dependencies: ["{{PROJECT_NAME}}"]
                            ),
                        ]
                    )
                    """
                ),
                TemplateFile(
                    relativePath: "Sources/{{PROJECT_NAME}}/{{PROJECT_NAME}}.swift",
                    content: """
                    import ArgumentParser

                    @main
                    struct {{PROJECT_NAME}}: ParsableCommand {
                        static let configuration = CommandConfiguration(
                            abstract: "{{PROJECT_NAME}} — a Shikki-powered CLI tool"
                        )

                        func run() throws {
                            // Your code here
                        }
                    }
                    """
                ),
            ]
        )
    }

    private var swiftLibraryTemplate: ProjectTemplate {
        ProjectTemplate(
            id: "swift-library",
            name: "Swift Library",
            description: "Swift Package Manager library with tests",
            version: "1.0.0",
            author: "shikki",
            language: "swift",
            tags: ["library", "swift", "spm"],
            motoOverrides: MotoFile(
                name: "{{PROJECT_NAME}}",
                language: "swift",
                buildSystem: "spm",
                testCommand: "swift test",
                buildCommand: "swift build",
                architecture: MotoFile.Architecture(
                    pattern: "Modular",
                    sourceRoot: "Sources",
                    testRoot: "Tests"
                )
            ),
            files: []
        )
    }

    private var iosAppTemplate: ProjectTemplate {
        ProjectTemplate(
            id: "ios-app",
            name: "iOS App",
            description: "SwiftUI iOS application with MVVM+Coordinator pattern",
            version: "1.0.0",
            author: "shikki",
            language: "swift",
            tags: ["ios", "swiftui", "mvvm", "coordinator"],
            motoOverrides: MotoFile(
                name: "{{PROJECT_NAME}}",
                language: "swift",
                framework: "swiftUI",
                buildSystem: "xcodebuild",
                testCommand: "xcodebuild test",
                buildCommand: "xcodebuild build",
                architecture: MotoFile.Architecture(
                    pattern: "MVVM+Coordinator",
                    sourceRoot: "Sources",
                    testRoot: "Tests"
                )
            ),
            files: []
        )
    }

    private var typescriptAPITemplate: ProjectTemplate {
        ProjectTemplate(
            id: "ts-api",
            name: "TypeScript API",
            description: "TypeScript REST API with Express and testing",
            version: "1.0.0",
            author: "shikki",
            language: "typescript",
            tags: ["api", "typescript", "express", "rest"],
            motoOverrides: MotoFile(
                name: "{{PROJECT_NAME}}",
                language: "typescript",
                framework: "express",
                buildSystem: "npm",
                testCommand: "npm test",
                buildCommand: "npm run build",
                lintCommand: "npx eslint .",
                architecture: MotoFile.Architecture(
                    pattern: "MVC",
                    sourceRoot: "src",
                    testRoot: "tests"
                )
            ),
            files: []
        )
    }

    private var rustCLITemplate: ProjectTemplate {
        ProjectTemplate(
            id: "rust-cli",
            name: "Rust CLI",
            description: "Rust command-line tool with clap",
            version: "1.0.0",
            author: "shikki",
            language: "rust",
            tags: ["cli", "rust", "cargo", "clap"],
            motoOverrides: MotoFile(
                name: "{{PROJECT_NAME}}",
                language: "rust",
                buildSystem: "cargo",
                testCommand: "cargo test",
                buildCommand: "cargo build --release",
                lintCommand: "cargo clippy",
                architecture: MotoFile.Architecture(
                    pattern: "Command",
                    sourceRoot: "src",
                    testRoot: "tests"
                )
            ),
            files: []
        )
    }

    // MARK: - Path Validation

    /// Validate that a relative path contains no `..` components (BR-01).
    private func validateRelativePath(_ relativePath: String, targetDir: String) throws {
        let components = (relativePath as NSString).pathComponents
        for component in components {
            if component == ".." {
                throw RegistryError.pathTraversal(relativePath)
            }
        }
    }

    /// Resolve the canonical (real) path and verify it stays within the target directory (BR-02).
    /// Catches symlink-based escapes where the relative path looks safe but resolves outside.
    @discardableResult
    private func resolveCanonicalPath(_ filePath: String, targetDir: String) throws -> String {
        // Resolve the target directory to its canonical form
        let canonicalTarget = URL(fileURLWithPath: targetDir).standardized.resolvingSymlinksInPath().path

        // For the file path, resolve as far as possible:
        // Walk up until we find an existing ancestor, resolve that, then re-append the rest.
        let fileURL = URL(fileURLWithPath: filePath).standardized
        var current = fileURL
        var suffixComponents: [String] = []

        while !fileManager.fileExists(atPath: current.path) && current.path != "/" {
            suffixComponents.insert(current.lastPathComponent, at: 0)
            current = current.deletingLastPathComponent()
        }

        let resolvedAncestor = current.resolvingSymlinksInPath().path
        var canonicalFile = resolvedAncestor
        for component in suffixComponents {
            canonicalFile = (canonicalFile as NSString).appendingPathComponent(component)
        }

        // The canonical file path must start with the canonical target directory
        guard canonicalFile.hasPrefix(canonicalTarget + "/") || canonicalFile == canonicalTarget else {
            throw RegistryError.pathTraversal(fileURL.lastPathComponent)
        }

        return canonicalFile
    }

    // MARK: - Variable Substitution

    func substituteVariables(_ content: String, projectName: String) -> String {
        content.replacingOccurrences(of: "{{PROJECT_NAME}}", with: projectName)
    }

    // MARK: - Persistence

    private func ensureRegistryDir() throws {
        if !fileManager.fileExists(atPath: registryPath) {
            try fileManager.createDirectory(atPath: registryPath, withIntermediateDirectories: true)
        }
    }

    private func loadIndex() -> [InstalledTemplate] {
        let indexPath = (registryPath as NSString).appendingPathComponent("index.json")
        guard let data = fileManager.contents(atPath: indexPath),
              let installed = try? JSONDecoder().decode([InstalledTemplate].self, from: data) else {
            return []
        }
        return installed
    }

    private func saveIndex(_ items: [InstalledTemplate]) throws {
        let indexPath = (registryPath as NSString).appendingPathComponent("index.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(items)
        try data.write(to: URL(fileURLWithPath: indexPath))
    }
}
