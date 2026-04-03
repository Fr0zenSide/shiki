import Foundation
import Testing

@testable import ShikkiKit

@Suite("DaemonLogger")
struct DaemonLoggerTests {
    /// Create a fresh temp log path for each test.
    private func makeTempLogPath() -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shikki-log-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("daemon.log").path
    }

    private func readFile(_ path: String) -> String {
        (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }

    @Test("log writes to file")
    func logWritesToFile() {
        let path = makeTempLogPath()
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }

        let logger = DaemonLogger(logPath: path)
        logger.log("test message")

        let content = readFile(path)
        #expect(content.contains("test message"))
    }

    @Test("log includes timestamp and level")
    func logIncludesTimestampAndLevel() {
        let path = makeTempLogPath()
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }

        let logger = DaemonLogger(logPath: path)
        logger.log("hello world", level: .warning)

        let content = readFile(path)
        #expect(content.contains("[WARNING]"))
        // Timestamp pattern: [YYYY-MM-DD HH:MM:SS.mmm]
        #expect(content.contains("[20"))
        #expect(content.contains("hello world"))
    }

    @Test("log appends multiple messages")
    func logAppendsMultipleMessages() {
        let path = makeTempLogPath()
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }

        let logger = DaemonLogger(logPath: path)
        logger.log("first")
        logger.log("second")
        logger.log("third")

        let content = readFile(path)
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        #expect(lines.count == 3)
        #expect(content.contains("first"))
        #expect(content.contains("third"))
    }

    @Test("log creates parent directories")
    func logCreatesParentDirectories() {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("shikki-log-test-\(UUID().uuidString)")
        let path = base.appendingPathComponent("nested/deep/daemon.log").path
        defer { try? FileManager.default.removeItem(at: base) }

        let logger = DaemonLogger(logPath: path)
        logger.log("deep message")

        #expect(FileManager.default.fileExists(atPath: path))
        #expect(readFile(path).contains("deep message"))
    }

    @Test("log uses correct level strings")
    func logUsesCorrectLevelStrings() {
        let path = makeTempLogPath()
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }

        let logger = DaemonLogger(logPath: path)
        logger.log("d", level: .debug)
        logger.log("i", level: .info)
        logger.log("w", level: .warning)
        logger.log("e", level: .error)

        let content = readFile(path)
        #expect(content.contains("[DEBUG]"))
        #expect(content.contains("[INFO]"))
        #expect(content.contains("[WARNING]"))
        #expect(content.contains("[ERROR]"))
    }

    @Test("rotateIfNeeded rotates when file exceeds maxFileSize")
    func rotateIfNeededRotatesWhenExceeded() {
        let path = makeTempLogPath()
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }

        // Create a logger with tiny maxFileSize (50 bytes)
        let logger = DaemonLogger(logPath: path, maxFileSize: 50, maxFiles: 3)

        // Write enough to exceed 50 bytes
        let bigMessage = String(repeating: "X", count: 60)
        logger.log(bigMessage)

        // Verify current file is larger than 50
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let size = attrs?[.size] as? Int ?? 0
        #expect(size > 50)

        // Rotate
        logger.rotateIfNeeded()

        // After rotation: current file should be gone (moved to .1)
        #expect(!FileManager.default.fileExists(atPath: path))
        #expect(FileManager.default.fileExists(atPath: "\(path).1"))
        #expect(readFile("\(path).1").contains(bigMessage))
    }

    @Test("rotation preserves last N files")
    func rotationPreservesLastNFiles() {
        let path = makeTempLogPath()
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }

        let logger = DaemonLogger(logPath: path, maxFileSize: 50, maxFiles: 3)

        // Simulate 3 rotations
        for i in 1...3 {
            let msg = "rotation-\(i)-" + String(repeating: "X", count: 40)
            logger.log(msg)
            logger.rotateIfNeeded()
        }

        // After 3 rotations: .1, .2, .3 should exist
        #expect(FileManager.default.fileExists(atPath: "\(path).1"))
        #expect(FileManager.default.fileExists(atPath: "\(path).2"))
        #expect(FileManager.default.fileExists(atPath: "\(path).3"))

        // Verify content shifted correctly: .1 has the most recent, .3 has the oldest
        #expect(readFile("\(path).1").contains("rotation-3"))
        #expect(readFile("\(path).2").contains("rotation-2"))
        #expect(readFile("\(path).3").contains("rotation-1"))
    }

    @Test("oldest file deleted on rotation beyond maxFiles")
    func oldestFileDeletedOnRotation() {
        let path = makeTempLogPath()
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }

        let logger = DaemonLogger(logPath: path, maxFileSize: 50, maxFiles: 2)

        // 3 rotations with maxFiles=2 — the oldest should be deleted
        for i in 1...3 {
            let msg = "gen-\(i)-" + String(repeating: "X", count: 40)
            logger.log(msg)
            logger.rotateIfNeeded()
        }

        // .1 and .2 should exist, .3 should not
        #expect(FileManager.default.fileExists(atPath: "\(path).1"))
        #expect(FileManager.default.fileExists(atPath: "\(path).2"))
        #expect(!FileManager.default.fileExists(atPath: "\(path).3"))

        // .1 = most recent (gen-3), .2 = gen-2
        #expect(readFile("\(path).1").contains("gen-3"))
        #expect(readFile("\(path).2").contains("gen-2"))
    }

    @Test("rotateIfNeeded does nothing when file is under maxFileSize")
    func rotateIfNeededNoopWhenUnderSize() {
        let path = makeTempLogPath()
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }

        let logger = DaemonLogger(logPath: path, maxFileSize: 10_000, maxFiles: 3)
        logger.log("small message")
        logger.rotateIfNeeded()

        // File should still exist (not rotated)
        #expect(FileManager.default.fileExists(atPath: path))
        #expect(!FileManager.default.fileExists(atPath: "\(path).1"))
    }

    @Test("rotateIfNeeded does nothing when file does not exist")
    func rotateIfNeededNoopWhenNoFile() {
        let path = makeTempLogPath()
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }

        let logger = DaemonLogger(logPath: path, maxFileSize: 50, maxFiles: 3)
        // Don't write anything
        logger.rotateIfNeeded()

        #expect(!FileManager.default.fileExists(atPath: path))
        #expect(!FileManager.default.fileExists(atPath: "\(path).1"))
    }
}
