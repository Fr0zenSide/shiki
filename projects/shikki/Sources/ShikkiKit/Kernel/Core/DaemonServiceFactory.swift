import Foundation
import Logging

// MARK: - DaemonConfig

/// Configuration for daemon service creation.
public struct DaemonConfig: Sendable {

    /// NATS server URL.
    public let natsURL: String

    /// Backend API URL.
    public let backendURL: String

    /// Workspace root path.
    public let workspacePath: String

    public init(
        natsURL: String = "nats://localhost:4222",
        backendURL: String = "http://localhost:3900",
        workspacePath: String? = nil
    ) {
        self.natsURL = natsURL
        self.backendURL = backendURL
        self.workspacePath = workspacePath
            ?? FileManager.default.homeDirectoryForCurrentUser.path
    }
}

// MARK: - DaemonServiceFactory

/// Creates ManagedService arrays for daemon operation modes.
///
/// Persistent mode: full service set for 24/7 operation.
/// Scheduled mode: lightweight set for periodic task execution.
public enum DaemonServiceFactory {

    /// Create all core services for persistent daemon mode.
    ///
    /// Returns 6 services:
    /// - `.natsServer` — NATS server lifecycle management
    /// - `.healthMonitor` — backend health checks
    /// - `.eventPersister` — event persistence to DB
    /// - `.sessionSupervisor` — idle session cleanup
    /// - `.staleCompanyDetector` — stale company relaunch
    /// - `.taskScheduler` — scheduled task evaluation
    public static func createPersistentServices(config: DaemonConfig) -> [any ManagedService] {
        let client = BackendClient(baseURL: config.backendURL)
        let discoverer = NoOpSessionDiscoverer()
        let journal = SessionJournal()
        let registry = SessionRegistry(discoverer: discoverer, journal: journal)
        let eventBus = InProcessEventBus()
        let notifier = NoOpNotificationSender()
        let heartbeatLoop = HeartbeatLoop(
            client: client,
            launcher: NoOpProcessLauncher(),
            notifier: notifier,
            registry: registry,
            eventBus: eventBus
        )
        let natsManager = NATSServerManager(
            processLauncher: SystemProcessLauncher()
        )

        return [
            NATSManagedService(manager: natsManager),
            HealthMonitor(client: client),
            EventPersisterManagedService(),
            SessionSupervisor(heartbeatLoop: heartbeatLoop),
            StaleCompanyDetectorService(client: client),
            TaskSchedulerManagedService(),
        ]
    }

    /// Create lightweight services for scheduled mode.
    ///
    /// Returns 2 services:
    /// - `.taskScheduler` — scheduled task evaluation
    /// - `.staleCompanyDetector` — stale company relaunch
    public static func createScheduledServices(config: DaemonConfig) -> [any ManagedService] {
        let client = BackendClient(baseURL: config.backendURL)

        return [
            TaskSchedulerManagedService(),
            StaleCompanyDetectorService(client: client),
        ]
    }
}

// MARK: - TaskSchedulerManagedService

/// Adapter wrapping TaskSchedulerService as a ManagedService for the kernel.
/// Bridges the standalone TaskSchedulerService into the kernel lifecycle.
actor TaskSchedulerManagedService: ManagedService {
    nonisolated let id: ServiceID = .taskScheduler
    nonisolated let qos: ServiceQoS = .default
    nonisolated let interval: Duration = .seconds(60)
    nonisolated let restartPolicy: RestartPolicy = .onFailure(maxRestarts: 5, backoff: .seconds(10))

    private let scheduler: TaskSchedulerService

    init(scheduler: TaskSchedulerService = TaskSchedulerService()) {
        self.scheduler = scheduler
    }

    func tick(snapshot: KernelSnapshot) async throws {
        guard snapshot.health == .healthy else { return }
        _ = await scheduler.tick()
    }
}

// MARK: - EventPersisterManagedService

/// ManagedService adapter for event persistence.
/// Periodically flushes buffered events to the backend DB.
///
/// Currently a stub — full implementation will connect to ShikkiDBEventLogger
/// once the event bus is wired into the daemon lifecycle.
actor EventPersisterManagedService: ManagedService {
    nonisolated let id: ServiceID = .eventPersister
    nonisolated let qos: ServiceQoS = .utility
    nonisolated let interval: Duration = .seconds(30)
    nonisolated let restartPolicy: RestartPolicy = .onFailure(maxRestarts: 3, backoff: .seconds(15))

    private let logger: Logger

    init(logger: Logger = Logger(label: "shikki.event-persister")) {
        self.logger = logger
    }

    func tick(snapshot: KernelSnapshot) async throws {
        guard snapshot.health == .healthy else {
            logger.debug("Skipping event persistence — backend not healthy")
            return
        }
        // Stub: full implementation will flush buffered events here
        logger.trace("Event persister tick (stub)")
    }
}

// MARK: - NoOpProcessLauncher

/// No-op process launcher for headless daemon mode.
/// The daemon doesn't launch tmux sessions directly.
struct NoOpProcessLauncher: ProcessLauncher {
    func launchTaskSession(taskId: String, companyId: String, companySlug: String,
                           title: String, projectPath: String) async throws {}
    func isSessionRunning(slug: String) async -> Bool { false }
    func stopSession(slug: String) async throws {}
    func listRunningSessions() async -> [String] { [] }
}

// MARK: - NoOpSessionDiscoverer

/// No-op session discoverer for headless daemon mode.
/// The daemon doesn't discover tmux sessions.
struct NoOpSessionDiscoverer: SessionDiscoverer {
    func discover() async -> [DiscoveredSession] { [] }
}

// MARK: - DaemonSnapshotProvider

/// Minimal KernelSnapshotProvider for daemon mode.
/// Uses BackendClient directly without session tracking overhead.
public struct DaemonSnapshotProvider: KernelSnapshotProvider {
    private let client: any BackendClientProtocol

    public init(client: any BackendClientProtocol) {
        self.client = client
    }

    public func fetchSnapshot() async -> KernelSnapshot {
        do {
            guard try await client.healthCheck() else {
                return .unreachable
            }

            let companies = (try? await client.getCompanies()) ?? []
            let queue = (try? await client.getDispatcherQueue()) ?? []
            let decisions = (try? await client.getPendingDecisions()) ?? []

            return KernelSnapshot(
                health: .healthy,
                companies: companies,
                dispatchQueue: queue,
                pendingDecisions: decisions,
                fetchedAt: Date()
            )
        } catch {
            return KernelSnapshot(health: .unreachable, fetchedAt: Date())
        }
    }
}
