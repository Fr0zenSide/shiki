import Foundation
import Testing
@testable import ShikiCtlKit

/// Mock DB sync client for testing.
final class MockDBSync: DBSyncing, @unchecked Sendable {
    var uploadResult = true
    var downloadResult: Checkpoint?
    var uploadCallCount = 0
    var downloadCallCount = 0

    func uploadCheckpoint(_ cp: Checkpoint) async -> Bool {
        uploadCallCount += 1
        return uploadResult
    }

    func downloadCheckpoint(hostname: String) async -> Checkpoint? {
        downloadCallCount += 1
        return downloadResult
    }
}

@Suite("DBSyncClient — BR-25 to BR-29, BR-51")
struct DBSyncClientTests {

    private func makeCheckpoint() -> Checkpoint {
        Checkpoint(
            timestamp: Date(),
            hostname: "test-host",
            fsmState: .running,
            tmuxLayout: TmuxLayout(paneCount: 3, layoutString: "tiled"),
            sessionStats: nil,
            contextSnippet: "test",
            dbSynced: false
        )
    }

    // BR-25: Upload succeeds → true
    @Test("Upload returns true on success")
    func upload_succeeds_returnsTrue() async {
        let mock = MockDBSync()
        mock.uploadResult = true
        let result = await mock.uploadCheckpoint(makeCheckpoint())
        #expect(result == true)
        #expect(mock.uploadCallCount == 1)
    }

    // BR-25: Upload fails → false (soft-fail)
    @Test("Upload returns false on failure (soft-fail)")
    func upload_fails_returnsFalse() async {
        let mock = MockDBSync()
        mock.uploadResult = false
        let result = await mock.uploadCheckpoint(makeCheckpoint())
        #expect(result == false)
    }

    // BR-26: Download returns checkpoint when available
    @Test("Download returns checkpoint when found")
    func download_found_returnsCheckpoint() async {
        let mock = MockDBSync()
        mock.downloadResult = makeCheckpoint()
        let result = await mock.downloadCheckpoint(hostname: "test-host")
        #expect(result != nil)
        #expect(result?.hostname == "test-host")
    }

    // BR-26: Download returns nil when not found
    @Test("Download returns nil when not found")
    func download_notFound_returnsNil() async {
        let mock = MockDBSync()
        mock.downloadResult = nil
        let result = await mock.downloadCheckpoint(hostname: "test-host")
        #expect(result == nil)
    }

    // BR-29: Cold start — no checkpoint in DB
    @Test("Cold start — no checkpoint to download")
    func coldStart_noCheckpoint_returnsNil() async {
        let mock = MockDBSync()
        let result = await mock.downloadCheckpoint(hostname: "new-host")
        #expect(result == nil)
    }

    // Real DBSyncClient initializes without error
    @Test("DBSyncClient initializes with defaults")
    func init_createsClient() {
        let client = DBSyncClient()
        #expect(client.timeoutSeconds == 3)
    }

    // BR-51: Upload to unreachable server returns false (soft-fail)
    @Test("Upload to unreachable server returns false")
    func upload_unreachable_returnsFalse() async {
        // Use a port that's definitely not listening
        let client = DBSyncClient(baseURL: "http://127.0.0.1:1", timeoutSeconds: 1)
        let result = await client.uploadCheckpoint(makeCheckpoint())
        #expect(result == false) // Soft-fail, never throws
    }

    // BR-51: Download from unreachable server returns nil
    @Test("Download from unreachable server returns nil")
    func download_unreachable_returnsNil() async {
        let client = DBSyncClient(baseURL: "http://127.0.0.1:1", timeoutSeconds: 1)
        let result = await client.downloadCheckpoint(hostname: "test")
        #expect(result == nil) // Soft-fail
    }
}
