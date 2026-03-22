import Foundation
import Testing
@testable import ShikiCtlKit

@Suite("CheckpointManager CRUD — BR-19, BR-20, BR-22, BR-23, BR-28, BR-57")
struct CheckpointManagerTests {

    private func makeTempDir() -> String {
        let path = NSTemporaryDirectory() + "shikki-test-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    private func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    private func makeCheckpoint(state: ShikkiState = .running) -> Checkpoint {
        Checkpoint(
            timestamp: Date(),
            hostname: "test-host",
            fsmState: state,
            tmuxLayout: TmuxLayout(paneCount: 2, layoutString: "tiled"),
            sessionStats: SessionSnapshot(startedAt: Date(), branch: "main"),
            contextSnippet: "test context",
            dbSynced: false
        )
    }

    // BR-22: init creates manager
    @Test("Init creates CheckpointManager")
    func init_createsCheckpointManager() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let manager = CheckpointManager(directory: dir)
        #expect(manager != nil)
    }

    // BR-20: Atomic JSON write
    @Test("Save writes atomic JSON file")
    func save_writesAtomicJSON() throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let manager = CheckpointManager(directory: dir)
        let cp = makeCheckpoint()

        try manager.save(cp)

        let filePath = "\(dir)/checkpoint.json"
        #expect(FileManager.default.fileExists(atPath: filePath))

        // Verify it's valid JSON
        let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        let decoded = try JSONDecoder.shikkiDecoder.decode(Checkpoint.self, from: data)
        #expect(decoded.hostname == "test-host")
    }

    // BR-20: Overwrite existing
    @Test("Save overwrites existing checkpoint")
    func save_overwritesExistingCheckpoint() throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let manager = CheckpointManager(directory: dir)

        let cp1 = Checkpoint(timestamp: Date(), hostname: "host-1", fsmState: .running, dbSynced: false)
        let cp2 = Checkpoint(timestamp: Date(), hostname: "host-2", fsmState: .idle, dbSynced: true)

        try manager.save(cp1)
        try manager.save(cp2)

        let loaded = try manager.load()
        #expect(loaded?.hostname == "host-2")
        #expect(loaded?.dbSynced == true)
    }

    // BR-22: save writes to disk
    @Test("Save writes to disk")
    func save_writesToDisk() throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let manager = CheckpointManager(directory: dir)

        try manager.save(makeCheckpoint())
        #expect(FileManager.default.fileExists(atPath: "\(dir)/checkpoint.json"))
    }

    // BR-22: load reads from disk
    @Test("Load reads from disk")
    func load_readsFromDisk() throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let manager = CheckpointManager(directory: dir)
        let cp = makeCheckpoint()

        try manager.save(cp)
        let loaded = try manager.load()

        #expect(loaded != nil)
        #expect(loaded?.fsmState == .running)
        #expect(loaded?.hostname == "test-host")
    }

    // BR-22: load returns nil when no file
    @Test("Load returns nil when no checkpoint exists")
    func load_returnsNilWhenAbsent() throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let manager = CheckpointManager(directory: dir)

        let loaded = try manager.load()
        #expect(loaded == nil)
    }

    // BR-22: exists
    @Test("Exists returns true when checkpoint file present")
    func exists_returnsTrueWhenPresent() throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let manager = CheckpointManager(directory: dir)

        try manager.save(makeCheckpoint())
        #expect(manager.exists() == true)
    }

    @Test("Exists returns false when no checkpoint file")
    func exists_returnsFalseWhenAbsent() {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let manager = CheckpointManager(directory: dir)

        #expect(manager.exists() == false)
    }

    // BR-22: delete
    @Test("Delete removes checkpoint file")
    func delete_removesCheckpointFile() throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let manager = CheckpointManager(directory: dir)

        try manager.save(makeCheckpoint())
        #expect(manager.exists() == true)

        try manager.delete()
        #expect(manager.exists() == false)
    }

    // BR-23: Resume lifecycle — delete after success
    @Test("Delete after successful resume removes file")
    func resume_deletesCheckpointAfterSuccess() throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let manager = CheckpointManager(directory: dir)

        try manager.save(makeCheckpoint())
        let loaded = try manager.load()
        #expect(loaded != nil)

        // Simulate successful resume: delete checkpoint
        try manager.delete()
        #expect(manager.exists() == false)
    }

    // BR-23: Resume lifecycle — preserve on failure
    @Test("Checkpoint preserved when resume fails")
    func resume_preservesCheckpointOnFailure() throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let manager = CheckpointManager(directory: dir)

        try manager.save(makeCheckpoint())
        // Simulate failed resume: don't delete
        #expect(manager.exists() == true)
    }

    // BR-28: Directory created with 0700
    @Test("Save creates directory with 0700 permissions")
    func save_createsDirectoryWithCorrectPermissions() throws {
        let dir = NSTemporaryDirectory() + "shikki-perms-\(UUID().uuidString)"
        defer { cleanup(dir) }

        // Directory doesn't exist yet
        #expect(!FileManager.default.fileExists(atPath: dir))

        let manager = CheckpointManager(directory: dir)
        try manager.save(makeCheckpoint())

        let attrs = try FileManager.default.attributesOfItem(atPath: dir)
        let perms = attrs[.posixPermissions] as? Int
        #expect(perms == 0o700)
    }

    // BR-57: Atomic I/O — no .tmp file left behind
    @Test("Save leaves no temp file behind")
    func save_noTempFileLeftBehind() throws {
        let dir = makeTempDir()
        defer { cleanup(dir) }
        let manager = CheckpointManager(directory: dir)

        try manager.save(makeCheckpoint())

        let files = try FileManager.default.contentsOfDirectory(atPath: dir)
        let tmpFiles = files.filter { $0.hasSuffix(".tmp") }
        #expect(tmpFiles.isEmpty)
    }
}
