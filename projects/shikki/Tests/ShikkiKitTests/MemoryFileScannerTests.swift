import Foundation
import Testing
@testable import ShikkiKit

@Suite("MemoryFileScanner — file operations and hashing")
struct MemoryFileScannerTests {

    // MARK: - Test Fixtures

    /// Create a temporary directory with test memory files.
    private func createTestDirectory() throws -> (String, () -> Void) {
        let tmpDir = NSTemporaryDirectory() + "shiki-scanner-\(UUID().uuidString)"
        let fm = FileManager.default
        try fm.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)

        // Create test files
        try "# User Identity\nName: Test User".write(
            toFile: "\(tmpDir)/user_identity.md", atomically: true, encoding: .utf8
        )
        try "# Feedback: Testing\nAlways run tests.".write(
            toFile: "\(tmpDir)/feedback_testing.md", atomically: true, encoding: .utf8
        )
        try "# MEMORY.md\nThis is the index.".write(
            toFile: "\(tmpDir)/MEMORY.md", atomically: true, encoding: .utf8
        )
        try "# Project Plan\nSome plan details.".write(
            toFile: "\(tmpDir)/project_test-plan.md", atomically: true, encoding: .utf8
        )
        try "not a markdown".write(
            toFile: "\(tmpDir)/readme.txt", atomically: true, encoding: .utf8
        )

        let cleanup = { let _ = try? fm.removeItem(atPath: tmpDir) }
        return (tmpDir, cleanup)
    }

    // MARK: - listFiles

    @Test("listFiles returns sorted .md files excluding MEMORY.md")
    func listFiles() throws {
        let (dir, cleanup) = try createTestDirectory()
        defer { cleanup() }

        let scanner = MemoryFileScanner(memoryDirectory: dir)
        let files = try scanner.listFiles()

        #expect(files.count == 3)
        #expect(!files.contains("MEMORY.md"))
        #expect(!files.contains("readme.txt"))
        // Sorted alphabetically
        #expect(files == ["feedback_testing.md", "project_test-plan.md", "user_identity.md"])
    }

    @Test("listFiles throws for missing directory")
    func listFilesMissingDir() {
        let scanner = MemoryFileScanner(memoryDirectory: "/nonexistent/\(UUID().uuidString)")
        #expect(throws: MemoryFileScannerError.self) {
            try scanner.listFiles()
        }
    }

    // MARK: - readFile

    @Test("readFile returns file content")
    func readFile() throws {
        let (dir, cleanup) = try createTestDirectory()
        defer { cleanup() }

        let scanner = MemoryFileScanner(memoryDirectory: dir)
        let content = try scanner.readFile("user_identity.md")
        #expect(content.contains("User Identity"))
        #expect(content.contains("Test User"))
    }

    @Test("readFile throws for missing file")
    func readFileMissing() throws {
        let (dir, cleanup) = try createTestDirectory()
        defer { cleanup() }

        let scanner = MemoryFileScanner(memoryDirectory: dir)
        #expect(throws: MemoryFileScannerError.self) {
            try scanner.readFile("nonexistent.md")
        }
    }

    // MARK: - SHA-256 hashing

    @Test("sha256 produces consistent 64-char hex hash")
    func sha256Consistency() {
        let hash = MemoryFileScanner.sha256("hello world")
        #expect(hash.count == 64)
        // Known SHA-256 of "hello world"
        #expect(hash == "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9")
    }

    @Test("sha256 of empty string")
    func sha256Empty() {
        let hash = MemoryFileScanner.sha256("")
        #expect(hash.count == 64)
        #expect(hash == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    @Test("sha256 is deterministic — same input produces same hash")
    func sha256Deterministic() {
        let input = "test content with unicode: \u{1F680}\u{1F389}"
        let hash1 = MemoryFileScanner.sha256(input)
        let hash2 = MemoryFileScanner.sha256(input)
        #expect(hash1 == hash2)
    }

    @Test("contentHash matches sha256 of file content")
    func contentHash() throws {
        let (dir, cleanup) = try createTestDirectory()
        defer { cleanup() }

        let scanner = MemoryFileScanner(memoryDirectory: dir)
        let hash = try scanner.contentHash(of: "user_identity.md")
        let content = try scanner.readFile("user_identity.md")
        let expected = MemoryFileScanner.sha256(content)
        #expect(hash == expected)
    }

    // MARK: - Path utilities

    @Test("fullPath constructs correct path")
    func fullPath() {
        let scanner = MemoryFileScanner(memoryDirectory: "/tmp/memory")
        let path = scanner.fullPath(for: "test.md")
        #expect(path == "/tmp/memory/test.md")
    }

    @Test("hasMemoryIndex detects MEMORY.md")
    func hasMemoryIndex() throws {
        let (dir, cleanup) = try createTestDirectory()
        defer { cleanup() }

        let scanner = MemoryFileScanner(memoryDirectory: dir)
        #expect(scanner.hasMemoryIndex())
    }

    @Test("hasMemoryIndex returns false when absent")
    func noMemoryIndex() throws {
        let tmpDir = NSTemporaryDirectory() + "shiki-no-index-\(UUID().uuidString)"
        let fm = FileManager.default
        try fm.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tmpDir) }

        let scanner = MemoryFileScanner(memoryDirectory: tmpDir)
        #expect(!scanner.hasMemoryIndex())
    }

    @Test("readMemoryIndex returns content")
    func readMemoryIndex() throws {
        let (dir, cleanup) = try createTestDirectory()
        defer { cleanup() }

        let scanner = MemoryFileScanner(memoryDirectory: dir)
        let content = try scanner.readMemoryIndex()
        #expect(content.contains("MEMORY.md"))
    }

    @Test("totalFileCount includes MEMORY.md")
    func totalFileCount() throws {
        let (dir, cleanup) = try createTestDirectory()
        defer { cleanup() }

        let scanner = MemoryFileScanner(memoryDirectory: dir)
        let count = try scanner.totalFileCount()
        #expect(count == 4) // 3 memory files + MEMORY.md
    }

    // MARK: - Error equality

    @Test("MemoryFileScannerError is Equatable")
    func errorEquatable() {
        let a = MemoryFileScannerError.fileNotFound("test.md")
        let b = MemoryFileScannerError.fileNotFound("test.md")
        #expect(a == b)
    }

    @Test("MemoryFileScannerError has descriptive message")
    func errorDescription() {
        let error = MemoryFileScannerError.directoryNotFound("/tmp/missing")
        #expect(error.description.contains("/tmp/missing"))
    }
}
