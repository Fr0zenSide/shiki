import Foundation
import Logging

// MARK: - DispatchService

/// Fetches the dispatch queue and launches sessions for ready tasks (BR-11).
/// QoS: default, interval: 60s.
/// Wraps HeartbeatLoop.checkAndDispatch() during the transition period.
public actor DispatchService: ManagedService {
    public nonisolated let id: ServiceID = .dispatchService
    public nonisolated let qos: ServiceQoS = .default
    public nonisolated let interval: Duration = .seconds(60)
    public nonisolated let restartPolicy: RestartPolicy = .onFailure(maxRestarts: 5, backoff: .seconds(10))

    private let heartbeatLoop: HeartbeatLoop
    private let logger: Logger

    public init(
        heartbeatLoop: HeartbeatLoop,
        logger: Logger = Logger(label: "shikki.dispatch-service")
    ) {
        self.heartbeatLoop = heartbeatLoop
        self.logger = logger
    }

    public func tick(snapshot: KernelSnapshot) async throws {
        // Guard: only dispatch when backend is healthy
        guard snapshot.health == .healthy else {
            logger.debug("Skipping dispatch — backend not healthy")
            return
        }

        // Delegate to HeartbeatLoop for backward compat
        try await heartbeatLoop.checkAndDispatch()
    }
}
