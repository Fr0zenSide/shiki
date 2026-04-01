import Foundation
import Logging

// MARK: - DecisionMonitorService

/// Polls pending decisions, notifies via ntfy, detects answered decisions (BR-10).
/// QoS: userInitiated, interval: 30s.
/// Extracted from HeartbeatLoop.checkDecisions() + checkAnsweredDecisions().
public actor DecisionMonitorService: ManagedService {
    public nonisolated let id: ServiceID = .decisionMonitor
    public nonisolated let qos: ServiceQoS = .userInitiated
    public nonisolated let interval: Duration = .seconds(30)
    public nonisolated let restartPolicy: RestartPolicy = .onFailure(maxRestarts: 5, backoff: .seconds(5))

    private let notifier: NotificationSender
    private let logger: Logger

    /// Decision IDs for which we already sent a notification.
    private var notifiedDecisionIds: Set<String> = []

    /// Pending decision IDs from the previous tick — used to detect answered decisions.
    private var previousPendingIds: Set<String> = []

    /// IDs of decisions answered since last tick.
    private(set) var lastAnsweredIds: Set<String> = []

    public init(
        notifier: NotificationSender,
        logger: Logger = Logger(label: "shikki.decision-monitor")
    ) {
        self.notifier = notifier
        self.logger = logger
    }

    public func tick(snapshot: KernelSnapshot) async throws {
        guard snapshot.health == .healthy else {
            logger.debug("Skipping decision check — backend not healthy")
            return
        }

        let pending = snapshot.pendingDecisions
        let pendingIds = Set(pending.map(\.id))

        // Detect answered decisions (were pending last tick, gone now)
        lastAnsweredIds = previousPendingIds.subtracting(pendingIds)
        if !lastAnsweredIds.isEmpty {
            logger.info("\(lastAnsweredIds.count) decision(s) answered since last tick")
        }

        // Notify on new T1 decisions
        let t1 = pending.filter { $0.tier == 1 }
        let newDecisions = t1.filter { !notifiedDecisionIds.contains($0.id) }

        for decision in newDecisions {
            let slug = decision.companySlug ?? "unknown"
            let shortQuestion = String(decision.question.prefix(120))

            do {
                try await notifier.send(
                    title: "T1: \(slug)",
                    body: shortQuestion,
                    priority: .high,
                    tags: ["decision", "t1", slug]
                )
            } catch {
                logger.debug("ntfy unreachable for \(slug) decision")
            }

            notifiedDecisionIds.insert(decision.id)
        }

        // Prune stale entries
        notifiedDecisionIds = notifiedDecisionIds.intersection(pendingIds)
        previousPendingIds = pendingIds
    }

    /// Number of pending decisions from the last tick.
    public var pendingCount: Int { previousPendingIds.count }

    /// Number of notifications sent (for testing).
    public var notifiedCount: Int { notifiedDecisionIds.count }
}
