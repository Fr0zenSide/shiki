import Foundation
import Testing
@testable import ShikkiKit

@Suite("ProjectDetector")
struct ProjectDetectorTests {

    private let detector = ProjectDetector()

    // MARK: - Helpers

    /// Create a temporary directory with the given files/directories.
    private func makeProject(
        files: [String] = [],
        directories: [String] = [],
        fileContents: [String: String] = [:]
    ) throws -> String {
        let base = NSTemporaryDirectory() + "shikki-test-\(UUID().uuidString)"
        let fm = FileManager.default
        try fm.createDirectory(atPath: base, withIntermediateDirectories: true)

        for dir in directories {
            let dirPath = (base as NSString).appendingPathComponent(dir)
            try fm.createDirectory(atPath: dirPath, withIntermediateDirectories: true)
        }

        for file in files {
            let filePath = (base as NSString).appendingPathComponent(file)
            let parentDir = (filePath as NSString).deletingLastPathComponent
            if !fm.fileExists(atPath: parentDir) {
                try fm.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
            }
            let content = fileContents[file] ?? ""
            fm.createFile(atPath: filePath, contents: content.data(using: .utf8))
        }

        return base
    }

    private func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: - Language Detection

    @Test("detects Swift from Package.swift")
    func detectSwift() throws {
        let path = try makeProject(files: ["Package.swift"])
        defer { cleanup(path) }

        let result = detector.detect(at: path)
        #expect(result.language == .swift)
        #expect(result.buildSystem == .spm)
    }

    @Test("detects Rust from Cargo.toml")
    func detectRust() throws {
        let path = try makeProject(files: ["Cargo.toml"])
        defer { cleanup(path) }

        let result = detector.detect(at: path)
        #expect(result.language == .rust)
        #expect(result.buildSystem == .cargo)
    }

    @Test("detects Go from go.mod")
    func detectGo() throws {
        let path = try makeProject(files: ["go.mod"])
        defer { cleanup(path) }

        let result = detector.detect(at: path)
        #expect(result.language == .go)
        #expect(result.buildSystem == .goMod)
    }

    @Test("detects TypeScript from tsconfig.json + package.json")
    func detectTypeScript() throws {
        let path = try makeProject(files: ["package.json", "tsconfig.json"])
        defer { cleanup(path) }

        let result = detector.detect(at: path)
        #expect(result.language == .typescript)
    }

    @Test("detects Python from pyproject.toml")
    func detectPython() throws {
        let path = try makeProject(files: ["pyproject.toml"])
        defer { cleanup(path) }

        let result = detector.detect(at: path)
        #expect(result.language == .python)
    }

    @Test("detects Ruby from Gemfile")
    func detectRuby() throws {
        let path = try makeProject(files: ["Gemfile"])
        defer { cleanup(path) }

        let result = detector.detect(at: path)
        #expect(result.language == .ruby)
        #expect(result.buildSystem == .bundler)
    }

    @Test("detects Java from pom.xml")
    func detectJava() throws {
        let path = try makeProject(files: ["pom.xml"])
        defer { cleanup(path) }

        let result = detector.detect(at: path)
        #expect(result.language == .java)
        #expect(result.buildSystem == .maven)
    }

    @Test("detects Kotlin from build.gradle.kts with kotlin src")
    func detectKotlin() throws {
        let path = try makeProject(
            files: ["build.gradle.kts"],
            directories: ["src/main/kotlin"]
        )
        defer { cleanup(path) }

        let result = detector.detect(at: path)
        #expect(result.language == .kotlin)
        #expect(result.buildSystem == .gradle)
    }

    @Test("returns unknown for empty directory")
    func detectUnknown() throws {
        let path = try makeProject()
        defer { cleanup(path) }

        let result = detector.detect(at: path)
        #expect(result.language == .unknown)
        #expect(result.buildSystem == nil)
    }

    // MARK: - Framework Detection

    @Test("detects Vapor in Swift Package.swift")
    func detectVapor() throws {
        let path = try makeProject(
            files: ["Package.swift"],
            fileContents: ["Package.swift": """
            let package = Package(
                dependencies: [.package(url: "https://github.com/vapor/vapor.git", from: "4.0.0")]
            )
            """]
        )
        defer { cleanup(path) }

        let result = detector.detect(at: path)
        #expect(result.language == .swift)
        #expect(result.framework == .vapor)
    }

    @Test("detects Next.js from package.json")
    func detectNextJS() throws {
        let path = try makeProject(
            files: ["package.json", "tsconfig.json"],
            fileContents: ["package.json": """
            { "dependencies": { "next": "14.0.0", "react": "18.0.0" } }
            """]
        )
        defer { cleanup(path) }

        let result = detector.detect(at: path)
        #expect(result.framework == .nextjs)
    }

    @Test("detects Django from manage.py")
    func detectDjango() throws {
        let path = try makeProject(files: ["manage.py", "requirements.txt"])
        defer { cleanup(path) }

        let result = detector.detect(at: path)
        #expect(result.framework == .django)
    }

    @Test("detects Rails from config/routes.rb")
    func detectRails() throws {
        let path = try makeProject(
            files: ["Gemfile", "config/routes.rb"],
            directories: ["config"]
        )
        defer { cleanup(path) }

        let result = detector.detect(at: path)
        #expect(result.framework == .rails)
    }

    @Test("detects Actix Web from Cargo.toml")
    func detectActixWeb() throws {
        let path = try makeProject(
            files: ["Cargo.toml"],
            fileContents: ["Cargo.toml": """
            [dependencies]
            actix-web = "4"
            """]
        )
        defer { cleanup(path) }

        let result = detector.detect(at: path)
        #expect(result.framework == .actixWeb)
    }

    // MARK: - Build System Detection

    @Test("detects pnpm from pnpm-lock.yaml")
    func detectPnpm() throws {
        let path = try makeProject(files: ["package.json", "tsconfig.json", "pnpm-lock.yaml"])
        defer { cleanup(path) }

        let result = detector.detect(at: path)
        #expect(result.buildSystem == .pnpm)
    }

    @Test("detects yarn from yarn.lock")
    func detectYarn() throws {
        let path = try makeProject(files: ["package.json", "tsconfig.json", "yarn.lock"])
        defer { cleanup(path) }

        let result = detector.detect(at: path)
        #expect(result.buildSystem == .yarn)
    }

    @Test("detects poetry from pyproject.toml")
    func detectPoetry() throws {
        let path = try makeProject(
            files: ["pyproject.toml"],
            fileContents: ["pyproject.toml": """
            [tool.poetry]
            name = "myproject"
            version = "0.1.0"
            """]
        )
        defer { cleanup(path) }

        let result = detector.detect(at: path)
        #expect(result.buildSystem == .poetry)
    }

    // MARK: - Git & Tests Detection

    @Test("detects git repository")
    func detectGit() throws {
        let path = try makeProject(directories: [".git"])
        defer { cleanup(path) }

        let result = detector.detect(at: path)
        #expect(result.hasGit)
    }

    @Test("detects Tests directory for Swift")
    func detectSwiftTests() throws {
        let path = try makeProject(
            files: ["Package.swift"],
            directories: ["Tests"]
        )
        defer { cleanup(path) }

        let result = detector.detect(at: path)
        #expect(result.hasTests)
    }

    @Test("detects spec directory for Ruby")
    func detectRubyTests() throws {
        let path = try makeProject(
            files: ["Gemfile"],
            directories: ["spec"]
        )
        defer { cleanup(path) }

        let result = detector.detect(at: path)
        #expect(result.hasTests)
    }

    // MARK: - Project Name

    @Test("uses directory name as project name")
    func projectNameFromDir() throws {
        let path = try makeProject(files: ["Package.swift"])
        defer { cleanup(path) }

        let result = detector.detect(at: path)
        #expect(result.name.hasPrefix("shikki-test-"))
    }
}
