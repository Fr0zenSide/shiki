import Foundation
import Testing
@testable import ShikkiKit

@Suite("DaemonEventEmitter")
struct DaemonEventEmitterTests {

    @Test("emitStarted produces correct JSON payload")
    func emitStartedPayload() async throws {
        let recorder = RequestRecorder()
        let emitter = DaemonEventEmitter(
            backendURL: "http://localhost:3900",
            urlSessionProvider: recorder
        )

        await emitter.emitStarted(
            pid: 12345,
            services: [.healthMonitor, .natsServer],
            mode: .persistent
        )

        let captured = recorder.lastBody
        #expect(captured != nil)

        guard let data = captured else { return }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["type"] as? String == "daemon_started")

        let payload = json?["payload"] as? [String: Any]
        // pid is emitted as Int (from Int32 widening in JSONSerialization)
        #expect(payload?["pid"] as? Int == 12345)
        #expect(payload?["mode"] as? String == "persistent")

        let services = payload?["services"] as? [String]
        #expect(services?.contains("healthMonitor") == true)
        #expect(services?.contains("natsServer") == true)
    }

    @Test("emitStopped produces correct JSON payload")
    func emitStoppedPayload() async throws {
        let recorder = RequestRecorder()
        let emitter = DaemonEventEmitter(
            backendURL: "http://localhost:3900",
            urlSessionProvider: recorder
        )

        await emitter.emitStopped(uptime: 3600.0)

        let captured = recorder.lastBody
        #expect(captured != nil)

        guard let data = captured else { return }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["type"] as? String == "daemon_stopped")

        let payload = json?["payload"] as? [String: Any]
        #expect(payload?["uptime_seconds"] as? Double == 3600.0)
    }

    @Test("Event includes hostname")
    func eventIncludesHostname() async throws {
        let recorder = RequestRecorder()
        let emitter = DaemonEventEmitter(
            backendURL: "http://localhost:3900",
            urlSessionProvider: recorder
        )

        await emitter.emitStarted(
            pid: 1,
            services: [.healthMonitor],
            mode: .persistent
        )

        guard let data = recorder.lastBody else {
            #expect(Bool(false), "No request body captured")
            return
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let payload = json?["payload"] as? [String: Any]
        let hostname = payload?["hostname"] as? String
        #expect(hostname != nil)
        #expect(!hostname!.isEmpty)
    }

    @Test("Event includes timestamp in ISO 8601 format")
    func eventIncludesTimestamp() async throws {
        let recorder = RequestRecorder()
        let emitter = DaemonEventEmitter(
            backendURL: "http://localhost:3900",
            urlSessionProvider: recorder
        )

        await emitter.emitStarted(
            pid: 1,
            services: [],
            mode: .scheduled
        )

        guard let data = recorder.lastBody else {
            #expect(Bool(false), "No request body captured")
            return
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let payload = json?["payload"] as? [String: Any]
        let timestamp = payload?["timestamp"] as? String
        #expect(timestamp != nil)

        // Verify ISO 8601 format
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let parsed = formatter.date(from: timestamp!)
        #expect(parsed != nil, "Timestamp should be valid ISO 8601")
    }

    @Test("emitStopped includes hostname and timestamp")
    func emitStoppedIncludesMetadata() async throws {
        let recorder = RequestRecorder()
        let emitter = DaemonEventEmitter(
            backendURL: "http://localhost:3900",
            urlSessionProvider: recorder
        )

        await emitter.emitStopped(uptime: 120.5)

        guard let data = recorder.lastBody else {
            #expect(Bool(false), "No request body captured")
            return
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let payload = json?["payload"] as? [String: Any]
        #expect(payload?["hostname"] as? String != nil)
        #expect(payload?["timestamp"] as? String != nil)
    }

    @Test("Emitter uses correct backend URL")
    func emitterUsesCorrectURL() async {
        let recorder = RequestRecorder()
        let emitter = DaemonEventEmitter(
            backendURL: "http://custom:9999",
            urlSessionProvider: recorder
        )

        await emitter.emitStarted(pid: 1, services: [], mode: .persistent)

        #expect(recorder.lastURL?.absoluteString == "http://custom:9999/api/data-sync")
    }
}

// MARK: - RequestRecorder

/// Test double that captures HTTP request bodies without making real network calls.
/// Uses an internal actor for thread-safe storage in async contexts.
final class RequestRecorder: DaemonEventHTTPProvider, Sendable {
    private let storage = RecorderStorage()

    var lastBody: Data? {
        storage.lastBodySync
    }

    var lastURL: URL? {
        storage.lastURLSync
    }

    func sendEvent(to url: URL, body: Data) async {
        await storage.record(url: url, body: body)
    }
}

/// Actor-isolated storage for `RequestRecorder`.
private actor RecorderStorage {
    private var _lastBody: Data?
    private var _lastURL: URL?

    /// Synchronous access via nonisolated unsafe for test assertions
    /// (tests run sequentially after await, so this is safe).
    nonisolated var lastBodySync: Data? {
        // Use a brief task to read -- but for testing simplicity,
        // we store in an Atomic-like pattern.
        _storage_lastBody
    }

    nonisolated var lastURLSync: URL? {
        _storage_lastURL
    }

    // Using nonisolated(unsafe) for test-only synchronous reads.
    // Safe because tests await the emitter call before reading.
    nonisolated(unsafe) private var _storage_lastBody: Data?
    nonisolated(unsafe) private var _storage_lastURL: URL?

    func record(url: URL, body: Data) {
        _lastBody = body
        _lastURL = url
        _storage_lastBody = body
        _storage_lastURL = url
    }
}
