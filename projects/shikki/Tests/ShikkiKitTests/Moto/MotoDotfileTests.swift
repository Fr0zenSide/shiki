import Foundation
import Testing
@testable import ShikkiKit

@Suite("MotoDotfile Parser")
struct MotoDotfileTests {

    let parser = MotoDotfileParser()

    // MARK: - Full Parse

    @Test("parses a complete .moto file")
    func parseComplete() throws {
        let content = """
        # .moto -- DNS for code
        [project]
        name = "Brainy"
        description = "RSS reader with AI analysis"
        language = "swift"
        license = "MIT"
        repository = "https://github.com/example/brainy"

        [cache]
        endpoint = "https://cache.originate.dev/example/brainy"
        version = "1.2.0"
        commit = "a1b2c3d4"
        schema = "1"
        branches = ["main", "develop"]

        [cache.local]
        path = ".moto-cache/"

        [attribution]
        authors = ["Alice <alice@example.com>", "Bob <bob@example.com>"]
        organization = "Example Corp"
        created = "2024-06-15"
        """

        let dotfile = try parser.parse(content: content)

        #expect(dotfile.project.name == "Brainy")
        #expect(dotfile.project.description == "RSS reader with AI analysis")
        #expect(dotfile.project.language == "swift")
        #expect(dotfile.project.license == "MIT")
        #expect(dotfile.project.repository == "https://github.com/example/brainy")

        #expect(dotfile.cache.endpoint == "https://cache.originate.dev/example/brainy")
        #expect(dotfile.cache.version == "1.2.0")
        #expect(dotfile.cache.commit == "a1b2c3d4")
        #expect(dotfile.cache.schema == "1")
        #expect(dotfile.cache.branches == ["main", "develop"])
        #expect(dotfile.cache.localPath == ".moto-cache/")

        #expect(dotfile.attribution.authors == ["Alice <alice@example.com>", "Bob <bob@example.com>"])
        #expect(dotfile.attribution.organization == "Example Corp")
        #expect(dotfile.attribution.created == "2024-06-15")
    }

    // MARK: - Minimal Parse

    @Test("parses a minimal .moto file with only required fields")
    func parseMinimal() throws {
        let content = """
        [project]
        name = "minimal"
        """

        let dotfile = try parser.parse(content: content)

        #expect(dotfile.project.name == "minimal")
        #expect(dotfile.project.language == "swift")
        #expect(dotfile.project.description == "")
        #expect(dotfile.project.license == nil)
        #expect(dotfile.project.repository == nil)

        #expect(dotfile.cache.endpoint == nil)
        #expect(dotfile.cache.schema == "1")
        #expect(dotfile.cache.branches == ["main"])
        #expect(dotfile.cache.localPath == ".moto-cache/")

        #expect(dotfile.attribution.authors.isEmpty)
        #expect(dotfile.attribution.organization == nil)
    }

    // MARK: - Error Cases

    @Test("throws when project section is missing")
    func missingProjectSection() {
        let content = """
        [cache]
        endpoint = "https://example.com"
        """

        #expect(throws: MotoDotfileError.self) {
            try parser.parse(content: content)
        }
    }

    @Test("throws when project name is missing")
    func missingProjectName() {
        let content = """
        [project]
        language = "swift"
        """

        #expect(throws: MotoDotfileError.self) {
            try parser.parse(content: content)
        }
    }

    @Test("throws for non-existent file")
    func fileNotFound() {
        #expect(throws: MotoDotfileError.self) {
            try parser.parse(at: "/nonexistent/.moto")
        }
    }

    // MARK: - Comments and Whitespace

    @Test("ignores comments and blank lines")
    func commentsAndBlanks() throws {
        let content = """
        # This is a comment

        [project]
        # Another comment
        name = "test"

        # End comment
        """

        let dotfile = try parser.parse(content: content)
        #expect(dotfile.project.name == "test")
    }

    @Test("handles whitespace around equals sign")
    func whitespaceAroundEquals() throws {
        let content = """
        [project]
        name   =   "spaces"
        language="nospaces"
        """

        let dotfile = try parser.parse(content: content)
        #expect(dotfile.project.name == "spaces")
        #expect(dotfile.project.language == "nospaces")
    }

    // MARK: - Array Parsing

    @Test("parses single-element array")
    func singleElementArray() throws {
        let content = """
        [project]
        name = "test"

        [cache]
        branches = ["main"]
        """

        let dotfile = try parser.parse(content: content)
        #expect(dotfile.cache.branches == ["main"])
    }

    @Test("parses empty array")
    func emptyArray() throws {
        let content = """
        [project]
        name = "test"

        [attribution]
        authors = []
        """

        let dotfile = try parser.parse(content: content)
        #expect(dotfile.attribution.authors.isEmpty)
    }

    // MARK: - Serialization

    @Test("serialize round-trips through parse")
    func serializeRoundTrip() throws {
        let original = MotoDotfile(
            project: .init(
                name: "TestProject",
                description: "A test project",
                language: "swift",
                license: "AGPL-3.0",
                repository: "https://github.com/test/project"
            ),
            cache: .init(
                endpoint: "https://cache.example.com/test",
                version: "2.0.0",
                commit: "abc12345",
                schema: "1",
                branches: ["main", "develop"],
                localPath: ".moto-cache/"
            ),
            attribution: .init(
                authors: ["Dev <dev@test.com>"],
                organization: "TestCorp",
                created: "2026-01-01"
            )
        )

        let serialized = parser.serialize(original)
        let reparsed = try parser.parse(content: serialized)

        #expect(reparsed.project.name == original.project.name)
        #expect(reparsed.project.description == original.project.description)
        #expect(reparsed.project.language == original.project.language)
        #expect(reparsed.project.license == original.project.license)
        #expect(reparsed.project.repository == original.project.repository)
        #expect(reparsed.cache.endpoint == original.cache.endpoint)
        #expect(reparsed.cache.version == original.cache.version)
        #expect(reparsed.cache.commit == original.cache.commit)
        #expect(reparsed.cache.schema == original.cache.schema)
        #expect(reparsed.cache.branches == original.cache.branches)
        #expect(reparsed.cache.localPath == original.cache.localPath)
        #expect(reparsed.attribution.authors == original.attribution.authors)
        #expect(reparsed.attribution.organization == original.attribution.organization)
        #expect(reparsed.attribution.created == original.attribution.created)
    }

    @Test("serialize produces TOML with section headers")
    func serializeFormat() {
        let dotfile = MotoDotfile(
            project: .init(name: "TestProj", language: "go"),
            cache: .init(schema: "1"),
            attribution: .init()
        )

        let output = parser.serialize(dotfile)
        #expect(output.contains("[project]"))
        #expect(output.contains("[cache]"))
        #expect(output.contains("[cache.local]"))
        #expect(output.contains("[attribution]"))
        #expect(output.contains("name = \"TestProj\""))
        #expect(output.contains("language = \"go\""))
    }

    // MARK: - Discovery

    @Test("discover finds .moto in the given directory")
    func discoverInCurrentDir() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("moto-discover-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let motoPath = tmpDir.appendingPathComponent(".moto")
        try "[project]\nname = \"test\"".write(to: motoPath, atomically: true, encoding: .utf8)

        let found = parser.discover(from: tmpDir.path)
        #expect(found == motoPath.path)
    }

    @Test("discover walks up to parent directories")
    func discoverWalksUp() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("moto-discover-parent-\(UUID().uuidString)")
        let subDir = tmpDir.appendingPathComponent("sub/deep")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let motoPath = tmpDir.appendingPathComponent(".moto")
        try "[project]\nname = \"parent\"".write(to: motoPath, atomically: true, encoding: .utf8)

        let found = parser.discover(from: subDir.path)
        #expect(found == motoPath.path)
    }

    @Test("discover returns nil when no .moto file exists")
    func discoverReturnsNil() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("moto-discover-none-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let found = parser.discover(from: tmpDir.path)
        #expect(found == nil)
    }

    // MARK: - Codable Conformance

    @Test("MotoDotfile is Codable")
    func codable() throws {
        let dotfile = MotoDotfile(
            project: .init(name: "CodableTest", language: "swift"),
            cache: .init(schema: "1"),
            attribution: .init(authors: ["test"])
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(dotfile)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(MotoDotfile.self, from: data)

        #expect(decoded == dotfile)
    }

    // MARK: - Subsection Parsing

    @Test("parses dotted section headers correctly")
    func dottedSections() throws {
        let content = """
        [project]
        name = "dotted"

        [cache]
        schema = "1"

        [cache.local]
        path = "custom-cache/"
        """

        let dotfile = try parser.parse(content: content)
        #expect(dotfile.cache.localPath == "custom-cache/")
    }

    // MARK: - Internal Parser

    @Test("parseSections groups keys correctly")
    func parseSections() throws {
        let content = """
        [a]
        key1 = "val1"
        key2 = "val2"
        [b]
        key3 = "val3"
        """

        let sections = try parser.parseSections(content)
        #expect(sections["a"]?["key1"]?.stringValue == "val1")
        #expect(sections["a"]?["key2"]?.stringValue == "val2")
        #expect(sections["b"]?["key3"]?.stringValue == "val3")
    }

    @Test("parseValue handles quoted strings")
    func parseValueString() {
        let value = parser.parseValue("\"hello world\"")
        #expect(value.stringValue == "hello world")
    }

    @Test("parseValue handles arrays")
    func parseValueArray() {
        let value = parser.parseValue("[\"a\", \"b\", \"c\"]")
        #expect(value.arrayValue == ["a", "b", "c"])
    }

    @Test("parseValue handles unquoted values")
    func parseValueUnquoted() {
        let value = parser.parseValue("bare_value")
        #expect(value.stringValue == "bare_value")
    }
}
