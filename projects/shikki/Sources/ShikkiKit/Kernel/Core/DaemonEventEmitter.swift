import Foundation
import Logging

/// Protocol for HTTP transport used by `DaemonEventEmitter`.
///
/// Abstracted for testability -- tests inject a `RequestRecorder` instead
/// of making real network calls.
public protocol DaemonEventHTTPProvider: Sendable {
    func sendEvent(to url: URL, body: Data) async
}

/// Default HTTP provider using `URLSession`.
///
/// Fire-and-forget: logs a warning on failure, never throws.
struct URLSessionEventProvider: DaemonEventHTTPProvider {
    func sendEvent(to url: URL, body: Data) async {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 5

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                let logger = Logger(label: "shikki.daemon-event")
                logger.warning("Event POST failed: HTTP \(http.statusCode)")
            }
        } catch {
            let logger = Logger(label: "shikki.daemon-event")
            logger.warning("Event POST error: \(error.localizedDescription)")
        }
    }
}

/// Emits daemon lifecycle events to ShikiDB via the data-sync endpoint.
///
/// Events are fire-and-forget: failures are logged as warnings but never crash
/// the daemon. Uses `URLSession` by default; accepts a `DaemonEventHTTPProvider`
/// for testing.
public struct DaemonEventEmitter: Sendable {
    private let backendURL: String
    private let provider: DaemonEventHTTPProvider
    private let hostname: String

    /// Create an emitter targeting the given backend.
    ///
    /// - Parameters:
    ///   - backendURL: Base URL for the ShikiDB backend (default: `http://localhost:3900`).
    ///   - urlSessionProvider: HTTP provider for sending events. Pass a test double in tests.
    public init(
        backendURL: String = "http://localhost:3900",
        urlSessionProvider: DaemonEventHTTPProvider? = nil
    ) {
        self.backendURL = backendURL
        self.provider = urlSessionProvider ?? URLSessionEventProvider()
        self.hostname = ProcessInfo.processInfo.hostName
    }

    /// Emit a `daemon_started` event with PID, hostname, service list, and mode.
    ///
    /// - Parameters:
    ///   - pid: Process ID of the daemon.
    ///   - services: List of active service identifiers.
    ///   - mode: Daemon operating mode (persistent or scheduled).
    public func emitStarted(pid: Int32, services: [ServiceID], mode: DaemonMode) async {
        let payload: [String: Any] = [
            "pid": Int(pid),
            "hostname": hostname,
            "services": services.map(\.rawValue),
            "mode": mode.rawValue,
            "timestamp": iso8601Now(),
        ]
        await send(type: "daemon_started", payload: payload)
    }

    /// Emit a `daemon_stopped` event with uptime duration.
    ///
    /// - Parameter uptime: Duration the daemon was running, in seconds.
    public func emitStopped(uptime: TimeInterval) async {
        let payload: [String: Any] = [
            "hostname": hostname,
            "uptime_seconds": uptime,
            "timestamp": iso8601Now(),
        ]
        await send(type: "daemon_stopped", payload: payload)
    }

    // MARK: - Private

    private func send(type: String, payload: [String: Any]) async {
        let envelope: [String: Any] = [
            "type": type,
            "payload": payload,
        ]

        guard let url = URL(string: "\(backendURL)/api/data-sync") else { return }

        do {
            let data = try JSONSerialization.data(withJSONObject: envelope, options: [])
            await provider.sendEvent(to: url, body: data)
        } catch {
            let logger = Logger(label: "shikki.daemon-event")
            logger.warning("Failed to serialize event: \(error.localizedDescription)")
        }
    }

    private func iso8601Now() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
