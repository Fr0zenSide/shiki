import Foundation
import Logging

// MARK: - SessionSupervisor

/// Cleans up idle sessions and captures transcripts (BR-12).
/// QoS: utility, interval: 120s.
/// Wraps HeartbeatLoop.cleanupIdleSessions() during the transition period.
public actor SessionSupervisor: ManagedService {
    public nonisolated let id: ServiceID = .sessionSupervisor
    public nonisolated let qos: ServiceQoS = .utility
    public nonisolated let interval: Duration = .seconds(120)
    public nonisolated let restartPolicy: RestartPolicy = .onFailure(maxRestarts: 3, backoff: .seconds(30))

    private let heartbeatLoop: HeartbeatLoop
    private let logger: Logger

    public init(
        heartbeatLoop: HeartbeatLoop,
        logger: Logger = Logger(label: "shikki.session-supervisor")
    ) {
        self.heartbeatLoop = heartbeatLoop
        self.logger = logger
    }

    public func tick(snapshot: KernelSnapshot) async throws {
        // Guard: need healthy backend to check active companies
        guard snapshot.health == .healthy else {
            logger.debug("Skipping session cleanup — backend not healthy")
            return
        }

        // Delegate to HeartbeatLoop for backward compat
        try await heartbeatLoop.cleanupIdleSessions()
    }
}
