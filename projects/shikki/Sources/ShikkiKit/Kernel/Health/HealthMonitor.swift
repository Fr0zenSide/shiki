import Foundation
import Logging

// MARK: - HealthMonitor

/// Monitors backend API reachability (BR-09).
/// QoS: critical, interval: 10s.
/// When unhealthy, blocks all non-critical services via canRun(health:).
public actor HealthMonitor: ManagedService {
    public nonisolated let id: ServiceID = .healthMonitor
    public nonisolated let qos: ServiceQoS = .critical
    public nonisolated let interval: Duration = .seconds(10)
    public nonisolated let restartPolicy: RestartPolicy = .always(maxRestarts: 10, backoff: .seconds(5))

    private let client: any BackendClientProtocol
    private let logger: Logger
    private var consecutiveFailures: Int = 0

    public init(
        client: any BackendClientProtocol,
        logger: Logger = Logger(label: "shikki.health-monitor")
    ) {
        self.client = client
        self.logger = logger
    }

    public func tick(snapshot: KernelSnapshot) async throws {
        // HealthMonitor always runs — it IS the health check.
        // The snapshot.health may be stale; we do a fresh check.
        do {
            let healthy = try await client.healthCheck()
            if healthy {
                if consecutiveFailures > 0 {
                    logger.info("Backend recovered after \(consecutiveFailures) failures")
                }
                consecutiveFailures = 0
            } else {
                consecutiveFailures += 1
                logger.warning("Backend unhealthy (consecutive: \(consecutiveFailures))")
            }
        } catch {
            consecutiveFailures += 1
            logger.error("Health check failed: \(error) (consecutive: \(consecutiveFailures))")
            throw error
        }
    }

    /// HealthMonitor always runs, regardless of health status.
    public nonisolated func canRun(health: HealthStatus) -> Bool {
        true
    }
}
