import Foundation
import Testing

@testable import ShikkiKit

@Suite("DaemonPIDManager")
struct DaemonLifecycleTests {
    /// Create a fresh temp directory for each test.
    private func makeTempPIDPath() -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shikki-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("daemon.pid").path
    }

    @Test("readPID returns correct value from file")
    func readPIDReturnsCorrectValue() {
        let path = makeTempPIDPath()
        try? "42".write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }

        let manager = DaemonPIDManager(pidPath: path)
        #expect(manager.readPID() == 42)
    }

    @Test("readPID returns nil when file is absent")
    func readPIDReturnsNilWhenAbsent() {
        let path = makeTempPIDPath()
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }

        let manager = DaemonPIDManager(pidPath: path)
        #expect(manager.readPID() == nil)
    }

    @Test("readPID returns nil for corrupt file")
    func readPIDReturnsNilForCorruptFile() {
        let path = makeTempPIDPath()
        try? "not-a-number".write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }

        let manager = DaemonPIDManager(pidPath: path)
        #expect(manager.readPID() == nil)
    }

    @Test("isRunning returns true for alive PID (current process)")
    func isRunningReturnsTrueForAlive() {
        let path = makeTempPIDPath()
        let myPID = ProcessInfo.processInfo.processIdentifier
        try? "\(myPID)".write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }

        let manager = DaemonPIDManager(pidPath: path)
        #expect(manager.isRunning() == true)
    }

    @Test("isRunning returns false for dead PID")
    func isRunningReturnsFalseForDeadPID() {
        let path = makeTempPIDPath()
        // PID 99999 is almost certainly not running
        try? "99999".write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }

        let manager = DaemonPIDManager(pidPath: path)
        #expect(manager.isRunning() == false)
    }

    @Test("isRunning returns false when no PID file exists")
    func isRunningReturnsFalseWhenNoPIDFile() {
        let path = makeTempPIDPath()
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }

        let manager = DaemonPIDManager(pidPath: path)
        #expect(manager.isRunning() == false)
    }

    @Test("cleanStale removes the PID file")
    func cleanStaleRemovesPIDFile() {
        let path = makeTempPIDPath()
        try? "99999".write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }

        let manager = DaemonPIDManager(pidPath: path)
        #expect(FileManager.default.fileExists(atPath: path))

        manager.cleanStale()
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test("cleanStale is safe when file does not exist")
    func cleanStaleNoopWhenAbsent() {
        let path = makeTempPIDPath()
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }

        let manager = DaemonPIDManager(pidPath: path)
        // Should not throw
        manager.cleanStale()
        #expect(!FileManager.default.fileExists(atPath: path))
    }
}
