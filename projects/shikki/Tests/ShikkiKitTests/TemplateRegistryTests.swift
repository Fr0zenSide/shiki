import Foundation
import Testing
@testable import ShikkiKit

@Suite("TemplateRegistry")
struct TemplateRegistryTests {

    // MARK: - Helpers

    private func makeRegistryDir() throws -> String {
        let base = NSTemporaryDirectory() + "shikki-templates-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
        return base
    }

    private func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    private func makeRegistry(path: String? = nil) throws -> (TemplateRegistry, String) {
        let dir = try path.map { $0 } ?? makeRegistryDir()
        let registry = TemplateRegistry(registryPath: dir)
        return (registry, dir)
    }

    private func sampleTemplate(
        id: String = "test-template",
        name: String = "Test Template",
        language: String = "swift"
    ) -> ProjectTemplate {
        ProjectTemplate(
            id: id,
            name: name,
            description: "A test template for unit tests",
            version: "1.0.0",
            author: "test",
            language: language,
            tags: ["test", "sample"],
            files: [
                TemplateFile(
                    relativePath: "README.md",
                    content: "# {{PROJECT_NAME}}\n\nCreated with Shikki."
                ),
            ]
        )
    }

    // MARK: - Built-in Templates

    @Test("lists built-in templates by default")
    func builtinTemplates() throws {
        let (registry, dir) = try makeRegistry()
        defer { cleanup(dir) }

        let templates = try registry.listInstalled()
        #expect(templates.count >= 5)
        #expect(templates.allSatisfy { $0.source == .builtin })
    }

    @Test("built-in templates include swift-cli")
    func builtinSwiftCLI() throws {
        let (registry, dir) = try makeRegistry()
        defer { cleanup(dir) }

        let templates = try registry.listInstalled()
        #expect(templates.contains { $0.template.id == "swift-cli" })
    }

    @Test("built-in templates include ios-app")
    func builtinIOSApp() throws {
        let (registry, dir) = try makeRegistry()
        defer { cleanup(dir) }

        let templates = try registry.listInstalled()
        #expect(templates.contains { $0.template.id == "ios-app" })
    }

    @Test("built-in templates include ts-api")
    func builtinTSAPI() throws {
        let (registry, dir) = try makeRegistry()
        defer { cleanup(dir) }

        let templates = try registry.listInstalled()
        #expect(templates.contains { $0.template.id == "ts-api" })
    }

    @Test("built-in templates include rust-cli")
    func builtinRustCLI() throws {
        let (registry, dir) = try makeRegistry()
        defer { cleanup(dir) }

        let templates = try registry.listInstalled()
        #expect(templates.contains { $0.template.id == "rust-cli" })
    }

    // MARK: - Get

    @Test("get returns built-in template by ID")
    func getBuiltin() throws {
        let (registry, dir) = try makeRegistry()
        defer { cleanup(dir) }

        let item = try registry.get(id: "swift-cli")
        #expect(item.template.name == "Swift CLI")
        #expect(item.source == .builtin)
    }

    @Test("get throws for unknown ID")
    func getUnknown() throws {
        let (registry, dir) = try makeRegistry()
        defer { cleanup(dir) }

        #expect(throws: RegistryError.templateNotFound("nonexistent")) {
            try registry.get(id: "nonexistent")
        }
    }

    // MARK: - Search

    @Test("search finds templates by name")
    func searchByName() throws {
        let (registry, dir) = try makeRegistry()
        defer { cleanup(dir) }

        let results = try registry.search(query: "swift")
        #expect(results.count >= 2)  // swift-cli, swift-library
    }

    @Test("search finds templates by tag")
    func searchByTag() throws {
        let (registry, dir) = try makeRegistry()
        defer { cleanup(dir) }

        let results = try registry.search(query: "cli")
        #expect(results.count >= 2)  // swift-cli, rust-cli
    }

    @Test("search finds templates by language")
    func searchByLanguage() throws {
        let (registry, dir) = try makeRegistry()
        defer { cleanup(dir) }

        let results = try registry.search(query: "rust")
        #expect(results.count >= 1)
    }

    @Test("search returns empty for no match")
    func searchNoMatch() throws {
        let (registry, dir) = try makeRegistry()
        defer { cleanup(dir) }

        let results = try registry.search(query: "xyznonexistent")
        #expect(results.isEmpty)
    }

    @Test("search is case insensitive")
    func searchCaseInsensitive() throws {
        let (registry, dir) = try makeRegistry()
        defer { cleanup(dir) }

        let results = try registry.search(query: "SWIFT")
        #expect(!results.isEmpty)
    }

    // MARK: - Install

    @Test("install adds template to registry")
    func installTemplate() throws {
        let (registry, dir) = try makeRegistry()
        defer { cleanup(dir) }

        let template = sampleTemplate()
        try registry.install(template: template, source: .local)

        let all = try registry.listInstalled()
        #expect(all.contains { $0.template.id == "test-template" })
    }

    @Test("install fails for duplicate ID")
    func installDuplicate() throws {
        let (registry, dir) = try makeRegistry()
        defer { cleanup(dir) }

        let template = sampleTemplate()
        try registry.install(template: template, source: .local)

        #expect(throws: RegistryError.templateAlreadyInstalled("test-template")) {
            try registry.install(template: template, source: .local)
        }
    }

    @Test("install fails for empty name")
    func installInvalidName() throws {
        let (registry, dir) = try makeRegistry()
        defer { cleanup(dir) }

        let template = ProjectTemplate(id: "bad", name: "", description: "invalid")
        #expect(throws: RegistryError.invalidTemplate("Template must have a name and ID")) {
            try registry.install(template: template, source: .local)
        }
    }

    @Test("install fails for empty ID")
    func installInvalidID() throws {
        let (registry, dir) = try makeRegistry()
        defer { cleanup(dir) }

        let template = ProjectTemplate(id: "", name: "Bad", description: "invalid")
        #expect(throws: RegistryError.invalidTemplate("Template must have a name and ID")) {
            try registry.install(template: template, source: .local)
        }
    }

    @Test("install preserves source URL")
    func installWithURL() throws {
        let (registry, dir) = try makeRegistry()
        defer { cleanup(dir) }

        let template = sampleTemplate(id: "url-test", name: "URL Test")
        try registry.install(template: template, source: .github, sourceURL: "https://github.com/example/template")

        let item = try registry.get(id: "url-test")
        #expect(item.source == .github)
        #expect(item.sourceURL == "https://github.com/example/template")
    }

    // MARK: - Uninstall

    @Test("uninstall removes template")
    func uninstallTemplate() throws {
        let (registry, dir) = try makeRegistry()
        defer { cleanup(dir) }

        let template = sampleTemplate()
        try registry.install(template: template, source: .local)
        try registry.uninstall(id: "test-template")

        let all = try registry.listInstalled()
        #expect(!all.contains { $0.template.id == "test-template" && $0.source == .local })
    }

    @Test("uninstall fails for built-in template")
    func uninstallBuiltin() throws {
        let (registry, dir) = try makeRegistry()
        defer { cleanup(dir) }

        #expect {
            try registry.uninstall(id: "swift-cli")
        } throws: { error in
            guard let regError = error as? RegistryError else { return false }
            if case .invalidTemplate = regError { return true }
            return false
        }
    }

    @Test("uninstall fails for unknown template")
    func uninstallUnknown() throws {
        let (registry, dir) = try makeRegistry()
        defer { cleanup(dir) }

        #expect(throws: RegistryError.templateNotFound("nonexistent")) {
            try registry.uninstall(id: "nonexistent")
        }
    }

    // MARK: - Apply

    @Test("apply creates template files")
    func applyCreatesFiles() throws {
        let (registry, dir) = try makeRegistry()
        defer { cleanup(dir) }

        let template = sampleTemplate()
        try registry.install(template: template, source: .local)

        let projectDir = NSTemporaryDirectory() + "shikki-apply-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        defer { cleanup(projectDir) }

        let created = try registry.apply(templateId: "test-template", to: projectDir)
        #expect(created.contains("README.md"))

        // Verify file exists and has substituted content
        let readmePath = (projectDir as NSString).appendingPathComponent("README.md")
        let content = try String(contentsOfFile: readmePath, encoding: .utf8)
        let projectName = URL(fileURLWithPath: projectDir).lastPathComponent
        #expect(content.contains(projectName))
    }

    @Test("apply skips existing files without force")
    func applySkipsExisting() throws {
        let (registry, dir) = try makeRegistry()
        defer { cleanup(dir) }

        let template = sampleTemplate()
        try registry.install(template: template, source: .local)

        let projectDir = NSTemporaryDirectory() + "shikki-apply-skip-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        defer { cleanup(projectDir) }

        // Create existing file
        let readmePath = (projectDir as NSString).appendingPathComponent("README.md")
        try "existing content".write(toFile: readmePath, atomically: true, encoding: .utf8)

        let created = try registry.apply(templateId: "test-template", to: projectDir)
        #expect(created.isEmpty)

        // Verify original content preserved
        let content = try String(contentsOfFile: readmePath, encoding: .utf8)
        #expect(content == "existing content")
    }

    @Test("apply overwrites with force")
    func applyOverwritesWithForce() throws {
        let (registry, dir) = try makeRegistry()
        defer { cleanup(dir) }

        let template = sampleTemplate()
        try registry.install(template: template, source: .local)

        let projectDir = NSTemporaryDirectory() + "shikki-apply-force-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        defer { cleanup(projectDir) }

        // Create existing file
        let readmePath = (projectDir as NSString).appendingPathComponent("README.md")
        try "old content".write(toFile: readmePath, atomically: true, encoding: .utf8)

        let created = try registry.apply(templateId: "test-template", to: projectDir, force: true)
        #expect(created.contains("README.md"))

        // Verify content was overwritten
        let content = try String(contentsOfFile: readmePath, encoding: .utf8)
        #expect(content != "old content")
    }

    @Test("apply fails for unknown template")
    func applyUnknownTemplate() throws {
        let (registry, dir) = try makeRegistry()
        defer { cleanup(dir) }

        #expect(throws: RegistryError.templateNotFound("nonexistent")) {
            try registry.apply(templateId: "nonexistent", to: "/tmp")
        }
    }

    // MARK: - Variable Substitution

    @Test("substitutes PROJECT_NAME variable")
    func substituteVariable() throws {
        let (registry, dir) = try makeRegistry()
        defer { cleanup(dir) }

        let result = registry.substituteVariables("Hello {{PROJECT_NAME}}!", projectName: "MyApp")
        #expect(result == "Hello MyApp!")
    }

    @Test("substitutes multiple occurrences")
    func substituteMultiple() throws {
        let (registry, dir) = try makeRegistry()
        defer { cleanup(dir) }

        let result = registry.substituteVariables("{{PROJECT_NAME}} is {{PROJECT_NAME}}", projectName: "Foo")
        #expect(result == "Foo is Foo")
    }

    // MARK: - Persistence

    @Test("installed templates persist across registry instances")
    func persistence() throws {
        let dir = try makeRegistryDir()
        defer { cleanup(dir) }

        // Install with first instance
        let registry1 = TemplateRegistry(registryPath: dir)
        let template = sampleTemplate()
        try registry1.install(template: template, source: .local)

        // Read with second instance
        let registry2 = TemplateRegistry(registryPath: dir)
        let all = try registry2.listInstalled()
        #expect(all.contains { $0.template.id == "test-template" })
    }

    // MARK: - ProjectTemplate Equatable

    @Test("ProjectTemplate equatable works")
    func templateEquatable() {
        let a = ProjectTemplate(id: "a", name: "A", description: "desc")
        let b = ProjectTemplate(id: "a", name: "A", description: "desc")
        let c = ProjectTemplate(id: "c", name: "C", description: "other")
        #expect(a == b)
        #expect(a != c)
    }

    // MARK: - TemplateFile

    @Test("TemplateFile defaults to non-executable")
    func templateFileDefaults() {
        let file = TemplateFile(relativePath: "test.txt", content: "hello")
        #expect(!file.executable)
    }

    @Test("TemplateFile executable flag works")
    func templateFileExecutable() {
        let file = TemplateFile(relativePath: "run.sh", content: "#!/bin/bash", executable: true)
        #expect(file.executable)
    }

    // MARK: - Path Sanitization (BR-01 through BR-05)

    @Test("apply with valid paths works correctly")
    func applyValidPaths() throws {
        let (registry, dir) = try makeRegistry()
        defer { cleanup(dir) }

        let template = ProjectTemplate(
            id: "safe-template",
            name: "Safe Template",
            description: "Template with safe paths",
            files: [
                TemplateFile(relativePath: "src/main.swift", content: "// main"),
                TemplateFile(relativePath: "Tests/MainTests.swift", content: "// tests"),
            ]
        )
        try registry.install(template: template, source: .local)

        let projectDir = NSTemporaryDirectory() + "shikki-safe-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        defer { cleanup(projectDir) }

        let created = try registry.apply(templateId: "safe-template", to: projectDir)
        #expect(created.count == 2)
        #expect(created.contains("src/main.swift"))
        #expect(created.contains("Tests/MainTests.swift"))
    }

    @Test("apply rejects path traversal with ..")
    func applyRejectsPathTraversal() throws {
        let (registry, dir) = try makeRegistry()
        defer { cleanup(dir) }

        let template = ProjectTemplate(
            id: "evil-traversal",
            name: "Evil Traversal",
            description: "Template with path traversal",
            files: [
                TemplateFile(relativePath: "../../../etc/passwd", content: "pwned"),
            ]
        )
        try registry.install(template: template, source: .local)

        let projectDir = NSTemporaryDirectory() + "shikki-traversal-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        defer { cleanup(projectDir) }

        #expect(throws: RegistryError.pathTraversal("../../../etc/passwd")) {
            try registry.apply(templateId: "evil-traversal", to: projectDir)
        }

        // Verify no file was written
        let evilPath = (projectDir as NSString)
            .deletingLastPathComponent
            .appending("/../../../etc/passwd")
        #expect(!FileManager.default.fileExists(atPath: evilPath))
    }

    @Test("apply rejects executable when allowExecutables is false")
    func applyRejectsExecutable() throws {
        let (registry, dir) = try makeRegistry()
        defer { cleanup(dir) }

        let template = ProjectTemplate(
            id: "exec-template",
            name: "Exec Template",
            description: "Template with executable file",
            files: [
                TemplateFile(relativePath: "run.sh", content: "#!/bin/bash\necho hello", executable: true),
            ]
        )
        try registry.install(template: template, source: .local)

        let projectDir = NSTemporaryDirectory() + "shikki-exec-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        defer { cleanup(projectDir) }

        #expect(throws: RegistryError.executableNotAllowed("run.sh")) {
            try registry.apply(templateId: "exec-template", to: projectDir)
        }

        // Verify no file was written
        let runPath = (projectDir as NSString).appendingPathComponent("run.sh")
        #expect(!FileManager.default.fileExists(atPath: runPath))
    }

    @Test("apply allows executable when allowExecutables is true")
    func applyAllowsExecutable() throws {
        let (registry, dir) = try makeRegistry()
        defer { cleanup(dir) }

        let template = ProjectTemplate(
            id: "exec-allowed",
            name: "Exec Allowed",
            description: "Template with executable file",
            files: [
                TemplateFile(relativePath: "run.sh", content: "#!/bin/bash\necho hello", executable: true),
            ]
        )
        try registry.install(template: template, source: .local)

        let projectDir = NSTemporaryDirectory() + "shikki-exec-ok-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        defer { cleanup(projectDir) }

        let created = try registry.apply(templateId: "exec-allowed", to: projectDir, allowExecutables: true)
        #expect(created.contains("run.sh"))

        // Verify file has executable permissions
        let runPath = (projectDir as NSString).appendingPathComponent("run.sh")
        let attrs = try FileManager.default.attributesOfItem(atPath: runPath)
        let perms = attrs[.posixPermissions] as? Int
        #expect(perms == 0o755)
    }

    @Test("apply rejects symlink escape outside target directory")
    func applyRejectsSymlinkEscape() throws {
        let (registry, dir) = try makeRegistry()
        defer { cleanup(dir) }

        let template = ProjectTemplate(
            id: "symlink-escape",
            name: "Symlink Escape",
            description: "Template targeting a symlink that escapes",
            files: [
                TemplateFile(relativePath: "escape/payload.txt", content: "pwned"),
            ]
        )
        try registry.install(template: template, source: .local)

        let projectDir = NSTemporaryDirectory() + "shikki-symlink-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        defer { cleanup(projectDir) }

        // Create a symlink inside projectDir that points outside
        let outsideDir = NSTemporaryDirectory() + "shikki-outside-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: outsideDir, withIntermediateDirectories: true)
        defer { cleanup(outsideDir) }

        let symlinkPath = (projectDir as NSString).appendingPathComponent("escape")
        try FileManager.default.createSymbolicLink(atPath: symlinkPath, withDestinationPath: outsideDir)

        #expect {
            try registry.apply(templateId: "symlink-escape", to: projectDir)
        } throws: { error in
            guard let regError = error as? RegistryError else { return false }
            if case .pathTraversal = regError { return true }
            return false
        }

        // Verify no file was written outside
        let payloadPath = (outsideDir as NSString).appendingPathComponent("payload.txt")
        #expect(!FileManager.default.fileExists(atPath: payloadPath))
    }

    @Test("force flag does NOT bypass path traversal validation")
    func forceDoesNotBypassPathValidation() throws {
        let (registry, dir) = try makeRegistry()
        defer { cleanup(dir) }

        let template = ProjectTemplate(
            id: "force-evil",
            name: "Force Evil",
            description: "Traversal with force",
            files: [
                TemplateFile(relativePath: "../../etc/passwd", content: "pwned"),
            ]
        )
        try registry.install(template: template, source: .local)

        let projectDir = NSTemporaryDirectory() + "shikki-force-evil-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        defer { cleanup(projectDir) }

        #expect(throws: RegistryError.pathTraversal("../../etc/passwd")) {
            try registry.apply(templateId: "force-evil", to: projectDir, force: true)
        }
    }

    @Test("apply rejects multiple traversal patterns")
    func applyRejectsMultipleTraversalPatterns() throws {
        let (registry, dir) = try makeRegistry()
        defer { cleanup(dir) }

        let evilPaths = [
            "a/../../../etc/passwd",
            "..",
            "./../../etc/shadow",
        ]

        for (index, evilPath) in evilPaths.enumerated() {
            let template = ProjectTemplate(
                id: "evil-\(index)",
                name: "Evil \(index)",
                description: "Traversal pattern \(index)",
                files: [
                    TemplateFile(relativePath: evilPath, content: "pwned"),
                ]
            )
            try registry.install(template: template, source: .local)

            let projectDir = NSTemporaryDirectory() + "shikki-evil-\(index)-\(UUID().uuidString)"
            try FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
            defer { cleanup(projectDir) }

            #expect {
                try registry.apply(templateId: "evil-\(index)", to: projectDir)
            } throws: { error in
                guard let regError = error as? RegistryError else { return false }
                if case .pathTraversal = regError { return true }
                return false
            }
        }
    }
}
