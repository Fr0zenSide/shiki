import Foundation

// MARK: - ServiceID

/// Unique identifier for each managed service in the kernel.
public enum ServiceID: String, Sendable, Hashable, CaseIterable {
    case healthMonitor
    case decisionMonitor
    case dispatchService
    case taskScheduler
    case sessionSupervisor
    case staleCompanyDetector
    case eventPersister
    case recovery
}

// MARK: - ServiceQoS

/// Quality-of-service tier for managed services.
/// Lower raw value = higher priority. Critical services run first.
public enum ServiceQoS: Int, Sendable, Comparable, CaseIterable {
    case critical = 0
    case userInitiated = 1
    case `default` = 2
    case utility = 3
    case background = 4

    public static func < (lhs: ServiceQoS, rhs: ServiceQoS) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Default leeway tolerance per QoS tier (like macOS NSTimer.tolerance).
    /// Critical: no leeway. Background: generous coalescing window.
    public var defaultLeeway: Duration {
        switch self {
        case .critical: .zero
        case .userInitiated: .seconds(2)
        case .default: .seconds(5)
        case .utility: .seconds(10)
        case .background: .seconds(30)
        }
    }
}

// MARK: - RestartPolicy

/// Determines how the kernel restarts a failed service.
public enum RestartPolicy: Sendable {
    case always(maxRestarts: Int, backoff: Duration)
    case onFailure(maxRestarts: Int, backoff: Duration)
    case once
}

// MARK: - ManagedService Protocol

/// A service managed by the ShikkiKernel.
/// Each service declares its identity, priority, cadence, and restart behavior.
/// The kernel calls `tick(snapshot:)` at the declared interval.
public protocol ManagedService: Actor {
    /// Unique service identifier.
    nonisolated var id: ServiceID { get }

    /// Quality of service — determines execution priority within a tick.
    nonisolated var qos: ServiceQoS { get }

    /// How often this service should tick.
    nonisolated var interval: Duration { get }

    /// Timer coalescing tolerance. Services due within ±leeway of each other
    /// fire in the same tick, sharing a single KernelSnapshot.
    nonisolated var leeway: Duration { get }

    /// How the kernel handles service failures.
    nonisolated var restartPolicy: RestartPolicy { get }

    /// Called by the kernel each time this service is due.
    /// - Parameter snapshot: Batched backend data shared across all services in this tick.
    func tick(snapshot: KernelSnapshot) async throws

    /// Whether this service is allowed to run given the current health status.
    /// Critical services (e.g., HealthMonitor) run even when degraded.
    nonisolated func canRun(health: HealthStatus) -> Bool
}

// MARK: - Default Implementations

extension ManagedService {
    /// Default leeway derived from QoS tier.
    public nonisolated var leeway: Duration { qos.defaultLeeway }

    /// Default: only run when healthy. Override for critical services.
    public nonisolated func canRun(health: HealthStatus) -> Bool {
        switch health {
        case .healthy:
            return true
        case .degraded, .unreachable:
            return qos == .critical
        }
    }
}
