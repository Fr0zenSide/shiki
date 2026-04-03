import Foundation
import Testing
@testable import ShikkiKit

@Suite("DaemonPIDManager")
struct DaemonPIDManagerTests {

    private func makeTempPidPath() -> String {
        let dir = NSTemporaryDirectory() + "shikki-daemon-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return "\(dir)/daemon.pid"
    }

    private func cleanup(_ path: String) {
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.removeItem(atPath: dir)
    }

    @Test("acquire writes PID file with correct PID")
    func acquire_writesPidFile() throws {
        let path = makeTempPidPath()
        defer { cleanup(path) }
        let manager = DaemonPIDManager(pidPath: path)

        try manager.acquire()

        #expect(FileManager.default.fileExists(atPath: path))
        let content = try String(contentsOfFile: path, encoding: .utf8)
        let pid = Int32(content.trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(pid == ProcessInfo.processInfo.processIdentifier)
    }

    @Test("release removes PID file")
    func release_removesPidFile() throws {
        let path = makeTempPidPath()
        defer { cleanup(path) }
        let manager = DaemonPIDManager(pidPath: path)

        try manager.acquire()
        #expect(FileManager.default.fileExists(atPath: path))

        manager.release()
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test("isRunning returns false when no PID file")
    func isRunning_falseWhenNoPidFile() {
        let path = makeTempPidPath()
        defer { cleanup(path) }
        let manager = DaemonPIDManager(pidPath: path)

        #expect(manager.isRunning() == false)
    }

    @Test("isRunning returns false when PID file has dead process")
    func isRunning_falseWhenDeadProcess() throws {
        let path = makeTempPidPath()
        defer { cleanup(path) }

        // Write a very high PID that doesn't exist
        try "999999999".write(toFile: path, atomically: true, encoding: .utf8)

        let manager = DaemonPIDManager(pidPath: path)
        #expect(manager.isRunning() == false)
    }

    @Test("isRunning returns true when PID file has alive process")
    func isRunning_trueWhenAliveProcess() throws {
        let path = makeTempPidPath()
        defer { cleanup(path) }

        // Write current process PID (always alive)
        let pid = "\(ProcessInfo.processInfo.processIdentifier)"
        try pid.write(toFile: path, atomically: true, encoding: .utf8)

        let manager = DaemonPIDManager(pidPath: path)
        #expect(manager.isRunning() == true)
    }

    @Test("readPID returns nil when no file")
    func readPID_nilWhenNoFile() {
        let path = makeTempPidPath()
        defer { cleanup(path) }
        let manager = DaemonPIDManager(pidPath: path)

        #expect(manager.readPID() == nil)
    }

    @Test("readPID returns PID from file")
    func readPID_returnsPidFromFile() throws {
        let path = makeTempPidPath()
        defer { cleanup(path) }

        try "42".write(toFile: path, atomically: true, encoding: .utf8)

        let manager = DaemonPIDManager(pidPath: path)
        #expect(manager.readPID() == 42)
    }

    @Test("cleanStale removes file with dead PID and returns true")
    func cleanStale_removesDeadPid() throws {
        let path = makeTempPidPath()
        defer { cleanup(path) }

        // Write a PID that doesn't exist
        try "999999999".write(toFile: path, atomically: true, encoding: .utf8)

        let manager = DaemonPIDManager(pidPath: path)
        #expect(manager.cleanStale() == true)
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test("cleanStale returns false when no stale file")
    func cleanStale_falseWhenNoFile() {
        let path = makeTempPidPath()
        defer { cleanup(path) }
        let manager = DaemonPIDManager(pidPath: path)

        #expect(manager.cleanStale() == false)
    }

    @Test("cleanStale returns false when PID is alive")
    func cleanStale_falseWhenAlive() throws {
        let path = makeTempPidPath()
        defer { cleanup(path) }

        // Write current process PID (alive)
        let pid = "\(ProcessInfo.processInfo.processIdentifier)"
        try pid.write(toFile: path, atomically: true, encoding: .utf8)

        let manager = DaemonPIDManager(pidPath: path)
        #expect(manager.cleanStale() == false)
        // File should still exist
        #expect(FileManager.default.fileExists(atPath: path))
    }

    @Test("acquire throws when PID file exists with alive process")
    func acquire_throwsWhenAliveProcess() throws {
        let path = makeTempPidPath()
        defer { cleanup(path) }

        // Write PID 1 (launchd — always running on macOS)
        try "1".write(toFile: path, atomically: true, encoding: .utf8)

        let manager = DaemonPIDManager(pidPath: path)
        #expect(throws: DaemonPIDError.self) {
            try manager.acquire()
        }
    }

    @Test("acquire succeeds over stale PID file")
    func acquire_succeedsOverStalePid() throws {
        let path = makeTempPidPath()
        defer { cleanup(path) }

        // Write a dead PID
        try "999999999".write(toFile: path, atomically: true, encoding: .utf8)

        let manager = DaemonPIDManager(pidPath: path)
        try manager.acquire()

        let content = try String(contentsOfFile: path, encoding: .utf8)
        let pid = Int32(content.trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(pid == ProcessInfo.processInfo.processIdentifier)
    }

    @Test("release is safe when no PID file exists")
    func release_safeWhenNoPidFile() {
        let path = makeTempPidPath()
        defer { cleanup(path) }
        let manager = DaemonPIDManager(pidPath: path)

        // Should not crash
        manager.release()
    }

    @Test("default path is ~/.shikki/daemon.pid")
    func defaultPath() {
        let manager = DaemonPIDManager()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(manager.pidPath == "\(home)/.shikki/daemon.pid")
    }
}
