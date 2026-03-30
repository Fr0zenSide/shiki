import Foundation
import Logging

// MARK: - StaleCompanyDetectorService

/// Finds idle companies with pending tasks and triggers relaunch (BR-13).
/// QoS: background, interval: 300s.
/// Extracted from HeartbeatLoop.checkStaleCompaniesSmart().
public actor StaleCompanyDetectorService: ManagedService {
    public nonisolated let id: ServiceID = .staleCompanyDetector
    public nonisolated let qos: ServiceQoS = .background
    public nonisolated let interval: Duration = .seconds(300)
    public nonisolated let restartPolicy: RestartPolicy = .onFailure(maxRestarts: 3, backoff: .seconds(60))

    private let client: any BackendClientProtocol
    private let logger: Logger

    /// Companies detected as stale in the last tick (for testing/observability).
    private(set) var lastDetectedStaleSlugs: [String] = []

    public init(
        client: any BackendClientProtocol,
        logger: Logger = Logger(label: "shikki.stale-detector")
    ) {
        self.client = client
        self.logger = logger
    }

    public func tick(snapshot: KernelSnapshot) async throws {
        guard snapshot.health == .healthy else {
            logger.debug("Skipping stale check — backend not healthy")
            return
        }

        let stale: [Company]
        do {
            stale = try await client.getStaleCompanies()
        } catch {
            logger.error("Failed to fetch stale companies: \(error)")
            throw error
        }

        guard !stale.isEmpty else {
            lastDetectedStaleSlugs = []
            return
        }

        let runningSlugs = Set(snapshot.sessions.filter(\.isRunning).map(\.companySlug))
        let companiesWithTasks = Set(snapshot.dispatchQueue.map(\.companySlug))

        var detected: [String] = []

        for company in stale {
            // Skip if company has no pending tasks
            guard companiesWithTasks.contains(company.slug) else {
                logger.debug("Stale company \(company.slug) has no pending tasks — skipping")
                continue
            }

            // Skip if company already has a running session
            guard !runningSlugs.contains(company.slug) else {
                logger.debug("Stale company \(company.slug) already has running session — skipping")
                continue
            }

            // Skip if budget exhausted
            if let task = snapshot.dispatchQueue.first(where: { $0.companySlug == company.slug }) {
                guard task.spentToday < task.budget.dailyUsd else {
                    logger.info("Stale company \(company.slug) budget exhausted — skipping")
                    continue
                }
            }

            detected.append(company.slug)
            logger.warning("Stale company \(company.slug) has pending tasks, no session — needs relaunch")
        }

        lastDetectedStaleSlugs = detected
    }
}
