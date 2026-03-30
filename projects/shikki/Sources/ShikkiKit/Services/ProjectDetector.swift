import Foundation

// MARK: - DetectedProject

/// Result of scanning a directory for project characteristics.
public struct DetectedProject: Sendable, Equatable {
    public let language: ProjectLanguage
    public let framework: ProjectFramework?
    public let buildSystem: BuildSystem?
    public let hasGit: Bool
    public let hasTests: Bool
    public let name: String

    public init(
        language: ProjectLanguage,
        framework: ProjectFramework? = nil,
        buildSystem: BuildSystem? = nil,
        hasGit: Bool = false,
        hasTests: Bool = false,
        name: String = ""
    ) {
        self.language = language
        self.framework = framework
        self.buildSystem = buildSystem
        self.hasGit = hasGit
        self.hasTests = hasTests
        self.name = name
    }
}

// MARK: - ProjectLanguage

public enum ProjectLanguage: String, Sendable, CaseIterable, Equatable, CustomStringConvertible {
    case swift
    case typescript
    case python
    case rust
    case go
    case ruby
    case kotlin
    case java
    case unknown

    public var description: String { rawValue }

    public var displayName: String {
        switch self {
        case .swift: "Swift"
        case .typescript: "TypeScript"
        case .python: "Python"
        case .rust: "Rust"
        case .go: "Go"
        case .ruby: "Ruby"
        case .kotlin: "Kotlin"
        case .java: "Java"
        case .unknown: "Unknown"
        }
    }
}

// MARK: - ProjectFramework

public enum ProjectFramework: String, Sendable, Equatable, CustomStringConvertible {
    case swiftUI
    case uiKit
    case vapor
    case nextjs
    case express
    case django
    case flask
    case fastAPI
    case actixWeb
    case tokio
    case gin
    case rails
    case springBoot
    case ktor

    public var description: String { rawValue }

    public var displayName: String {
        switch self {
        case .swiftUI: "SwiftUI"
        case .uiKit: "UIKit"
        case .vapor: "Vapor"
        case .nextjs: "Next.js"
        case .express: "Express"
        case .django: "Django"
        case .flask: "Flask"
        case .fastAPI: "FastAPI"
        case .actixWeb: "Actix Web"
        case .tokio: "Tokio"
        case .gin: "Gin"
        case .rails: "Rails"
        case .springBoot: "Spring Boot"
        case .ktor: "Ktor"
        }
    }
}

// MARK: - BuildSystem

public enum BuildSystem: String, Sendable, Equatable, CustomStringConvertible {
    case spm
    case xcodebuild
    case npm
    case yarn
    case pnpm
    case cargo
    case goMod
    case gradle
    case maven
    case bundler
    case pip
    case poetry

    public var description: String { rawValue }

    public var displayName: String {
        switch self {
        case .spm: "Swift Package Manager"
        case .xcodebuild: "Xcode Build"
        case .npm: "npm"
        case .yarn: "Yarn"
        case .pnpm: "pnpm"
        case .cargo: "Cargo"
        case .goMod: "Go Modules"
        case .gradle: "Gradle"
        case .maven: "Maven"
        case .bundler: "Bundler"
        case .pip: "pip"
        case .poetry: "Poetry"
        }
    }
}

// MARK: - ProjectDetector

/// Scans a directory to detect language, framework, and build system.
/// Pure filesystem checks -- no process spawning.
public struct ProjectDetector: Sendable {

    // FileManager is not Sendable, use nonisolated(unsafe) for the shared default instance
    nonisolated(unsafe) private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Detect project characteristics at the given path.
    public func detect(at path: String) -> DetectedProject {
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent

        let language = detectLanguage(at: path)
        let framework = detectFramework(at: path, language: language)
        let buildSystem = detectBuildSystem(at: path, language: language)
        let hasGit = fileExists(path, ".git")
        let hasTests = detectTests(at: path, language: language)

        return DetectedProject(
            language: language,
            framework: framework,
            buildSystem: buildSystem,
            hasGit: hasGit,
            hasTests: hasTests,
            name: name
        )
    }

    // MARK: - Language Detection

    func detectLanguage(at path: String) -> ProjectLanguage {
        // Check for marker files in priority order
        if fileExists(path, "Package.swift") { return .swift }
        if fileExists(path, "Cargo.toml") { return .rust }
        if fileExists(path, "go.mod") { return .go }
        if fileExists(path, "package.json") {
            // Check for TypeScript marker
            if fileExists(path, "tsconfig.json") { return .typescript }
            return .typescript // Default to TS for modern JS projects
        }
        if fileExists(path, "Gemfile") { return .ruby }
        if fileExists(path, "build.gradle") || fileExists(path, "build.gradle.kts") {
            if fileExists(path, "src/main/kotlin") { return .kotlin }
            return .java
        }
        if fileExists(path, "pom.xml") { return .java }
        if fileExists(path, "pyproject.toml") || fileExists(path, "setup.py") || fileExists(path, "requirements.txt") {
            return .python
        }
        // Check for xcodeproj/xcworkspace (Swift without SPM)
        if hasFileWithExtension(path, "xcodeproj") || hasFileWithExtension(path, "xcworkspace") {
            return .swift
        }
        return .unknown
    }

    // MARK: - Framework Detection

    func detectFramework(at path: String, language: ProjectLanguage) -> ProjectFramework? {
        switch language {
        case .swift:
            return detectSwiftFramework(at: path)
        case .typescript:
            return detectTSFramework(at: path)
        case .python:
            return detectPythonFramework(at: path)
        case .rust:
            return detectRustFramework(at: path)
        case .go:
            return detectGoFramework(at: path)
        case .ruby:
            if fileExists(path, "config/routes.rb") { return .rails }
            return nil
        case .kotlin:
            return detectKotlinFramework(at: path)
        case .java:
            return detectJavaFramework(at: path)
        case .unknown:
            return nil
        }
    }

    private func detectSwiftFramework(at path: String) -> ProjectFramework? {
        // Check Package.swift for Vapor
        if let content = readFile(path, "Package.swift") {
            if content.contains("vapor") || content.contains("Vapor") { return .vapor }
        }
        // Check for SwiftUI vs UIKit
        if directoryExists(path, "Sources") || directoryExists(path, "src") {
            // SPM project -- check for SwiftUI imports in source files
            return nil
        }
        if hasFileWithExtension(path, "xcodeproj") {
            // iOS/macOS app -- default to SwiftUI for modern projects
            return .swiftUI
        }
        return nil
    }

    private func detectTSFramework(at path: String) -> ProjectFramework? {
        if let content = readFile(path, "package.json") {
            if content.contains("\"next\"") { return .nextjs }
            if content.contains("\"express\"") { return .express }
        }
        if fileExists(path, "next.config.js") || fileExists(path, "next.config.ts") || fileExists(path, "next.config.mjs") {
            return .nextjs
        }
        return nil
    }

    private func detectPythonFramework(at path: String) -> ProjectFramework? {
        if fileExists(path, "manage.py") { return .django }
        if let content = readFile(path, "pyproject.toml") {
            if content.contains("fastapi") { return .fastAPI }
            if content.contains("flask") { return .flask }
            if content.contains("django") { return .django }
        }
        if let content = readFile(path, "requirements.txt") {
            if content.contains("fastapi") { return .fastAPI }
            if content.contains("Flask") || content.contains("flask") { return .flask }
            if content.contains("Django") || content.contains("django") { return .django }
        }
        return nil
    }

    private func detectRustFramework(at path: String) -> ProjectFramework? {
        if let content = readFile(path, "Cargo.toml") {
            if content.contains("actix-web") { return .actixWeb }
            if content.contains("tokio") { return .tokio }
        }
        return nil
    }

    private func detectGoFramework(at path: String) -> ProjectFramework? {
        if let content = readFile(path, "go.mod") {
            if content.contains("gin-gonic/gin") { return .gin }
        }
        return nil
    }

    private func detectKotlinFramework(at path: String) -> ProjectFramework? {
        if let content = readFile(path, "build.gradle.kts") {
            if content.contains("ktor") { return .ktor }
            if content.contains("spring-boot") { return .springBoot }
        }
        return nil
    }

    private func detectJavaFramework(at path: String) -> ProjectFramework? {
        if let content = readFile(path, "build.gradle") {
            if content.contains("spring-boot") { return .springBoot }
        }
        if let content = readFile(path, "pom.xml") {
            if content.contains("spring-boot") { return .springBoot }
        }
        return nil
    }

    // MARK: - Build System Detection

    func detectBuildSystem(at path: String, language: ProjectLanguage) -> BuildSystem? {
        switch language {
        case .swift:
            if fileExists(path, "Package.swift") { return .spm }
            if hasFileWithExtension(path, "xcodeproj") { return .xcodebuild }
            return nil
        case .typescript:
            if fileExists(path, "pnpm-lock.yaml") { return .pnpm }
            if fileExists(path, "yarn.lock") { return .yarn }
            if fileExists(path, "package-lock.json") || fileExists(path, "package.json") { return .npm }
            return nil
        case .python:
            if fileExists(path, "pyproject.toml") {
                if let content = readFile(path, "pyproject.toml"), content.contains("[tool.poetry]") {
                    return .poetry
                }
            }
            return .pip
        case .rust:
            return .cargo
        case .go:
            return .goMod
        case .ruby:
            return .bundler
        case .kotlin, .java:
            if fileExists(path, "build.gradle") || fileExists(path, "build.gradle.kts") { return .gradle }
            if fileExists(path, "pom.xml") { return .maven }
            return nil
        case .unknown:
            return nil
        }
    }

    // MARK: - Test Detection

    func detectTests(at path: String, language: ProjectLanguage) -> Bool {
        switch language {
        case .swift:
            return directoryExists(path, "Tests")
        case .typescript:
            return directoryExists(path, "__tests__")
                || directoryExists(path, "test")
                || directoryExists(path, "tests")
        case .python:
            return directoryExists(path, "tests")
                || directoryExists(path, "test")
        case .rust:
            // Rust tests are inline, but check for tests/ directory too
            return directoryExists(path, "tests")
        case .go:
            // Go tests are _test.go files, check for tests dir as hint
            return directoryExists(path, "tests") || directoryExists(path, "test")
        case .ruby:
            return directoryExists(path, "spec") || directoryExists(path, "test")
        case .kotlin, .java:
            return directoryExists(path, "src/test")
        case .unknown:
            return false
        }
    }

    // MARK: - File System Helpers

    private func fileExists(_ base: String, _ name: String) -> Bool {
        fileManager.fileExists(atPath: (base as NSString).appendingPathComponent(name))
    }

    private func directoryExists(_ base: String, _ name: String) -> Bool {
        var isDir: ObjCBool = false
        let path = (base as NSString).appendingPathComponent(name)
        return fileManager.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    private func hasFileWithExtension(_ base: String, _ ext: String) -> Bool {
        guard let contents = try? fileManager.contentsOfDirectory(atPath: base) else { return false }
        return contents.contains { ($0 as NSString).pathExtension == ext }
    }

    private func readFile(_ base: String, _ name: String) -> String? {
        let path = (base as NSString).appendingPathComponent(name)
        return try? String(contentsOfFile: path, encoding: .utf8)
    }
}
