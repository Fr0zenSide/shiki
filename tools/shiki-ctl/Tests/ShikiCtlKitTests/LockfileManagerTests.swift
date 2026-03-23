import Foundation
import Testing
@testable import ShikiCtlKit

@Suite("LockfileManager — BR-53")
struct LockfileManagerTests {

    private func makeTempPidPath() -> String {
        let dir = NSTemporaryDirectory() + "shikki-lock-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return "\(dir)/shikki.pid"
    }

    private func cleanup(_ path: String) {
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.removeItem(atPath: dir)
    }

    @Test("Acquire writes PID to lockfile")
    func acquire_writesPidToLockfile() throws {
        let path = makeTempPidPath()
        defer { cleanup(path) }
        let lock = LockfileManager(path: path)

        try lock.acquire()
        #expect(FileManager.default.fileExists(atPath: path))

        let content = try String(contentsOfFile: path, encoding: .utf8)
        let pid = Int(content.trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(pid == Int(ProcessInfo.processInfo.processIdentifier))

        try lock.release()
    }

    @Test("Release removes lockfile")
    func release_removesLockfile() throws {
        let path = makeTempPidPath()
        defer { cleanup(path) }
        let lock = LockfileManager(path: path)

        try lock.acquire()
        #expect(FileManager.default.fileExists(atPath: path))

        try lock.release()
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test("isHeld returns true when lockfile exists with current PID")
    func isHeld_returnsTrueWhenAcquired() throws {
        let path = makeTempPidPath()
        defer { cleanup(path) }
        let lock = LockfileManager(path: path)

        try lock.acquire()
        #expect(lock.isHeld() == true)
        try lock.release()
    }

    @Test("isHeld returns false when no lockfile")
    func isHeld_returnsFalseWhenNoLockfile() {
        let path = makeTempPidPath()
        defer { cleanup(path) }
        let lock = LockfileManager(path: path)

        #expect(lock.isHeld() == false)
    }

    @Test("Stale PID is detected and can be overridden")
    func staleCheck_detectsStalePid() throws {
        let path = makeTempPidPath()
        defer { cleanup(path) }
        let lock = LockfileManager(path: path)

        // Write a PID that doesn't exist (very high PID)
        try "999999999".write(toFile: path, atomically: true, encoding: .utf8)

        #expect(lock.isStale() == true)

        // Should be able to acquire over stale lock
        try lock.acquire()
        #expect(lock.isHeld() == true)
        try lock.release()
    }

    @Test("Non-stale PID (current process) is not considered stale")
    func staleCheck_currentPidNotStale() throws {
        let path = makeTempPidPath()
        defer { cleanup(path) }
        let lock = LockfileManager(path: path)

        try lock.acquire()
        #expect(lock.isStale() == false)
        try lock.release()
    }

    @Test("Acquire fails when lock held by live process")
    func acquire_failsWhenHeldByLiveProcess() throws {
        let path = makeTempPidPath()
        defer { cleanup(path) }

        // Write PID 1 (launchd — always running)
        try "1".write(toFile: path, atomically: true, encoding: .utf8)

        let lock = LockfileManager(path: path)
        #expect(lock.isStale() == false)

        #expect(throws: LockfileError.self) {
            try lock.acquire()
        }
    }

    @Test("Release is safe when no lockfile exists")
    func release_safeWhenNoLockfile() throws {
        let path = makeTempPidPath()
        defer { cleanup(path) }
        let lock = LockfileManager(path: path)

        // Should not throw
        try lock.release()
    }
}
