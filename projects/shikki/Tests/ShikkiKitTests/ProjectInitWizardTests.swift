import Foundation
import Testing
@testable import ShikkiKit

@Suite("ProjectInitWizard")
struct ProjectInitWizardTests {

    private let wizard = ProjectInitWizard()

    // MARK: - Helpers

    private func makeProject(
        files: [String] = [],
        directories: [String] = [],
        fileContents: [String: String] = [:]
    ) throws -> String {
        let base = NSTemporaryDirectory() + "shikki-init-\(UUID().uuidString)"
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

    // MARK: - Basic Init

    @Test("initialize creates .moto file")
    func initCreatesMoto() throws {
        let path = try makeProject(
            files: ["Package.swift"],
            directories: [".git", "Tests"]
        )
        defer { cleanup(path) }

        let result = try wizard.initialize(at: path)

        #expect(result.filesCreated.contains(".moto"))
        #expect(result.motoFile.language == "swift")

        // Verify file exists on disk
        let motoPath = (path as NSString).appendingPathComponent(".moto")
        #expect(FileManager.default.fileExists(atPath: motoPath))
    }

    @Test("initialize creates .shikki directory")
    func initCreatesShikkiDir() throws {
        let path = try makeProject(files: ["Package.swift"])
        defer { cleanup(path) }

        let result = try wizard.initialize(at: path)

        #expect(result.filesCreated.contains(".shikki/"))
        let shikkiDir = (path as NSString).appendingPathComponent(".shikki")
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: shikkiDir, isDirectory: &isDir))
        #expect(isDir.boolValue)
    }

    @Test("initialize creates cache.json")
    func initCreatesCache() throws {
        let path = try makeProject(files: ["Cargo.toml"])
        defer { cleanup(path) }

        let result = try wizard.initialize(at: path)

        #expect(result.filesCreated.contains(".shikki/cache.json"))
        let cachePath = (path as NSString)
            .appendingPathComponent(".shikki")
            .appending("/cache.json")
        #expect(FileManager.default.fileExists(atPath: cachePath))
    }

    @Test("initialize creates settings.json")
    func initCreatesSettings() throws {
        let path = try makeProject(files: ["go.mod"])
        defer { cleanup(path) }

        let result = try wizard.initialize(at: path)

        #expect(result.filesCreated.contains(".shikki/settings.json"))
    }

    // MARK: - Error Cases

    @Test("initialize fails if .moto already exists without force")
    func initFailsIfMotoExists() throws {
        let path = try makeProject(files: ["Package.swift", ".moto"])
        defer { cleanup(path) }

        #expect(throws: InitError.motoFileAlreadyExists) {
            try wizard.initialize(at: path)
        }
    }

    @Test("initialize succeeds with force even if .moto exists")
    func initSucceedsWithForce() throws {
        let path = try makeProject(files: ["Package.swift", ".moto"])
        defer { cleanup(path) }

        let result = try wizard.initialize(at: path, force: true)
        #expect(result.filesCreated.contains(".moto"))
    }

    @Test("initialize fails for nonexistent directory")
    func initFailsNonexistentDir() {
        let fakePath = "/nonexistent/path/\(UUID().uuidString)"
        #expect(throws: InitError.directoryNotFound(fakePath)) {
            try wizard.initialize(at: fakePath)
        }
    }

    // MARK: - Warnings

    @Test("warns when no git repository detected")
    func warnsNoGit() throws {
        let path = try makeProject(files: ["Package.swift"])
        defer { cleanup(path) }

        let result = try wizard.initialize(at: path)
        #expect(result.warnings.contains { $0.contains("git") })
    }

    @Test("warns when no test directory detected")
    func warnsNoTests() throws {
        let path = try makeProject(files: ["Package.swift"])
        defer { cleanup(path) }

        let result = try wizard.initialize(at: path)
        #expect(result.warnings.contains { $0.contains("test") })
    }

    @Test("warns for unknown language")
    func warnsUnknownLanguage() throws {
        let path = try makeProject()
        defer { cleanup(path) }

        let result = try wizard.initialize(at: path)
        #expect(result.warnings.contains { $0.contains("language") })
    }

    @Test("no warnings for fully detected project")
    func noWarningsFullProject() throws {
        let path = try makeProject(
            files: ["Package.swift"],
            directories: [".git", "Tests"]
        )
        defer { cleanup(path) }

        let result = try wizard.initialize(at: path)
        #expect(result.warnings.isEmpty)
    }

    // MARK: - Template Application

    @Test("ios template sets framework and architecture")
    func iosTemplate() throws {
        let path = try makeProject(
            files: ["Package.swift"],
            directories: [".git", "Tests"]
        )
        defer { cleanup(path) }

        let result = try wizard.initialize(at: path, template: "ios")
        #expect(result.motoFile.framework == "swiftUI")
        #expect(result.motoFile.architecture?.pattern == "MVVM+Coordinator")
    }

    @Test("web template sets nextjs framework")
    func webTemplate() throws {
        let path = try makeProject(
            files: ["package.json", "tsconfig.json"],
            directories: [".git", "tests"]
        )
        defer { cleanup(path) }

        let result = try wizard.initialize(at: path, template: "web")
        #expect(result.motoFile.framework == "nextjs")
        #expect(result.motoFile.architecture?.pattern == "Pages/App Router")
    }

    @Test("cli template sets Command pattern")
    func cliTemplate() throws {
        let path = try makeProject(
            files: ["Package.swift"],
            directories: [".git", "Tests"]
        )
        defer { cleanup(path) }

        let result = try wizard.initialize(at: path, template: "cli")
        #expect(result.motoFile.architecture?.pattern == "Command")
    }

    @Test("unknown template does not crash")
    func unknownTemplate() throws {
        let path = try makeProject(
            files: ["Package.swift"],
            directories: [".git", "Tests"]
        )
        defer { cleanup(path) }

        let result = try wizard.initialize(at: path, template: "nonexistent")
        #expect(result.motoFile.language == "swift")
    }

    // MARK: - Moto File Content Verification

    @Test("written .moto file can be parsed back")
    func motoRoundTrip() throws {
        let path = try makeProject(
            files: ["Package.swift"],
            directories: [".git", "Tests"]
        )
        defer { cleanup(path) }

        let result = try wizard.initialize(at: path)

        let motoPath = (path as NSString).appendingPathComponent(".moto")
        let content = try String(contentsOfFile: motoPath, encoding: .utf8)
        let parsed = MotoFile.parse(from: content)

        #expect(parsed != nil)
        #expect(parsed?.name == result.motoFile.name)
        #expect(parsed?.language == result.motoFile.language)
    }

    // MARK: - Detect Only

    @Test("detect returns project info without writing files")
    func detectOnly() throws {
        let path = try makeProject(
            files: ["Cargo.toml"],
            directories: [".git", "tests"],
            fileContents: ["Cargo.toml": "[dependencies]\nactix-web = \"4\""]
        )
        defer { cleanup(path) }

        let detected = wizard.detect(at: path)

        #expect(detected.language == .rust)
        #expect(detected.framework == .actixWeb)
        #expect(detected.buildSystem == .cargo)
        #expect(detected.hasGit)
        #expect(detected.hasTests)

        // Nothing written
        let motoPath = (path as NSString).appendingPathComponent(".moto")
        #expect(!FileManager.default.fileExists(atPath: motoPath))
    }
}
