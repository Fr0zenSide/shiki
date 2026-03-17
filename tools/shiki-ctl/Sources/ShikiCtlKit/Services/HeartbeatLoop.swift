import Foundation
import Logging

/// Main orchestrator loop — runs every `interval` seconds, dispatching tasks,
/// checking decisions, cleaning up idle sessions, and relaunching stale ones.
public actor HeartbeatLoop {
    private let client: BackendClient
    private let launcher: ProcessLauncher
    private let notifier: NotificationSender
    private let registry: SessionRegistry
    public let eventBus: InProcessEventBus
    private let interval: Duration
    private let logger: Logger
    private var notifiedDecisionIds: Set<String> = []
    private var previousPendingDecisionIds: Set<String> = []

    public init(
        client: BackendClient,
        launcher: ProcessLauncher,
        notifier: NotificationSender,
        registry: SessionRegistry? = nil,
        eventBus: InProcessEventBus? = nil,
        interval: Duration = .seconds(60),
        logger: Logger = Logger(label: "shiki-ctl.heartbeat")
    ) {
        self.client = client
        self.launcher = launcher
        self.notifier = notifier
        self.registry = registry ?? SessionRegistry(
            discoverer: TmuxDiscoverer(),
            journal: SessionJournal()
        )
        self.eventBus = eventBus ?? InProcessEventBus()
        self.interval = interval
        self.logger = logger
    }

    public func run() async {
        logger.info("Heartbeat loop started (interval: \(interval))")

        while !Task.isCancelled {
            do {
                guard try await client.healthCheck() else {
                    logger.warning("API unreachable, retrying in \(interval)...")
                    try await Task.sleep(for: interval)
                    continue
                }

                await registry.refresh()
                await eventBus.publish(ShikiEvent(
                    source: .orchestrator, type: .heartbeat, scope: .global
                ))
                let pendingDecisions = try await checkDecisions()
                try await checkAnsweredDecisions(currentPending: pendingDecisions)
                try await checkAndDispatch()
                try await cleanupIdleSessions()
                try await checkStaleCompaniesSmart()
            } catch is CancellationError {
                break
            } catch {
                logger.error("Loop error: \(error)")
            }

            do {
                try await Task.sleep(for: interval)
            } catch {
                break
            }
        }

        logger.info("Heartbeat loop stopped")
    }

    // MARK: - Dispatcher (replaces checkSchedule)

    /// Fetch pending tasks from dispatcher_queue and launch sessions for them.
    /// Rate-limited: max 2 concurrent sessions across all companies.
    func checkAndDispatch() async throws {
        let readyTasks = try await client.getDispatcherQueue()
        let runningSessions = await launcher.listRunningSessions()
        let maxConcurrent = 2

        guard runningSessions.count < maxConcurrent else {
            logger.debug("\(runningSessions.count)/\(maxConcurrent) slots full, skipping dispatch")
            return
        }

        let slotsAvailable = maxConcurrent - runningSessions.count

        for task in readyTasks.prefix(slotsAvailable) {
            // Skip if company budget exhausted
            guard task.spentToday < task.budget.dailyUsd else {
                logger.info("\(task.companySlug) budget exhausted ($\(task.spentToday)/$\(task.budget.dailyUsd))")
                continue
            }

            // Skip if outside schedule window
            guard ScheduleEvaluator.isWithinWindow(schedule: task.schedule) else {
                continue
            }

            // Skip if this task already has a running session
            let sessionSlug = task.sessionSlug
            guard !(await launcher.isSessionRunning(slug: sessionSlug)) else {
                continue
            }

            // Skip if this company already has a running session (one at a time per company)
            let runningSessions = await launcher.listRunningSessions()
            let companyHasSession = runningSessions.contains { $0.hasPrefix("\(task.companySlug):") }
            guard !companyHasSession else {
                continue
            }

            let projectPath: String
            if let path = task.projectPath {
                projectPath = path
            } else if let resolved = try? await resolveProjectPath(for: task.companySlug) {
                projectPath = resolved
            } else {
                projectPath = task.companySlug
            }

            logger.info("Dispatching task: \(task.title) → \(task.companySlug) in \(projectPath)")
            try await launcher.launchTaskSession(
                taskId: task.taskId,
                companyId: task.companyId,
                companySlug: task.companySlug,
                title: task.title,
                projectPath: projectPath
            )

            // Register in session registry
            let windowName = TmuxProcessLauncher.windowName(companySlug: task.companySlug, title: task.title)
            let context = TaskContext(
                taskId: task.taskId,
                companySlug: task.companySlug,
                projectPath: projectPath,
                budgetDailyUsd: task.budget.dailyUsd,
                spentTodayUsd: task.spentToday
            )
            await registry.register(
                windowName: windowName, paneId: "", pid: 0,
                context: context
            )
            await eventBus.publish(ShikiEvent(
                source: .orchestrator, type: .companyDispatched,
                scope: .project(slug: task.companySlug),
                payload: ["taskId": .string(task.taskId), "title": .string(task.title)]
            ))
        }
    }

    /// Kill panes for sessions whose tasks are no longer active (completed/failed/cancelled).
    /// Captures session output as a transcript before killing.
    func cleanupIdleSessions() async throws {
        let runningSessions = await launcher.listRunningSessions()
        guard !runningSessions.isEmpty else { return }

        // Get all active tasks to check which sessions are still needed
        let status = try await client.getStatus()
        let activeCompanySlugs = Set(status.activeCompanies.map(\.slug))

        for sessionSlug in runningSessions {
            // Extract company slug from "company:task-short"
            let parts = sessionSlug.split(separator: ":", maxSplits: 1)
            let companySlug = parts.first.map(String.init) ?? sessionSlug
            let taskShort = parts.count > 1 ? String(parts[1]) : sessionSlug

            // If the company is no longer active, capture transcript + kill
            if !activeCompanySlugs.contains(companySlug) {
                logger.info("Cleaning up idle session: \(sessionSlug) (company inactive)")

                // Capture raw output before killing
                await saveTranscript(
                    companySlug: companySlug,
                    taskShort: taskShort,
                    sessionSlug: sessionSlug,
                    phase: "completed"
                )

                try? await launcher.stopSession(slug: sessionSlug)
            }
        }
    }

    /// Capture pane output and save a session transcript to the backend.
    private func saveTranscript(
        companySlug: String, taskShort: String,
        sessionSlug: String, phase: String
    ) async {
        // Capture raw log from tmux pane
        let rawLog: String?
        if let tmuxLauncher = launcher as? TmuxProcessLauncher {
            rawLog = tmuxLauncher.captureSessionOutput(slug: sessionSlug)
        } else {
            rawLog = nil
        }

        // Resolve company ID
        guard let companies = try? await client.getCompanies(),
              let company = companies.first(where: { $0.slug == companySlug }) else {
            logger.warning("Could not resolve company \(companySlug) for transcript")
            return
        }

        let input = SessionTranscriptInput(
            companyId: company.id,
            sessionId: sessionSlug,
            companySlug: companySlug,
            taskTitle: taskShort,
            phase: phase,
            rawLog: rawLog
        )

        do {
            let _: SessionTranscript = try await client.createSessionTranscript(input)
            logger.info("Saved transcript for \(sessionSlug)")
        } catch {
            logger.error("Failed to save transcript for \(sessionSlug): \(error)")
        }
    }

    /// Resolve project path from company config.
    private func resolveProjectPath(for companySlug: String) async throws -> String? {
        let companies = try await client.getCompanies()
        guard let company = companies.first(where: { $0.slug == companySlug }) else { return nil }
        return (company.config["project_path"]?.value as? String)
    }

    // MARK: - Decisions

    /// Notify on new T1 decisions that haven't been seen yet.
    /// Returns the current pending decisions for reuse by checkAnsweredDecisions.
    @discardableResult
    func checkDecisions() async throws -> [Decision] {
        let decisions = try await client.getPendingDecisions()
        let t1 = decisions.filter { $0.tier == 1 }
        let newDecisions = t1.filter { !notifiedDecisionIds.contains($0.id) }

        if !newDecisions.isEmpty {
            // Log summary, not full question text
            let slugs = newDecisions.map { $0.companySlug ?? "?" }
            let grouped = Dictionary(grouping: slugs, by: { $0 }).map { "\($0.key)×\($0.value.count)" }
            logger.info("\(newDecisions.count) new T1 decision(s): \(grouped.joined(separator: ", "))")
        }

        for decision in newDecisions {
            let slug = decision.companySlug ?? "unknown"
            // Truncate question for notification body
            let shortQuestion = String(decision.question.prefix(120))
            do {
                try await notifier.send(
                    title: "T1: \(slug)",
                    body: shortQuestion,
                    priority: .high,
                    tags: ["decision", "t1", slug]
                )
            } catch {
                // Don't let notification failure crash the loop — just log once
                logger.debug("ntfy unreachable for \(slug) decision")
            }
            notifiedDecisionIds.insert(decision.id)
        }

        // Clean up answered decisions from the set
        let pendingIds = Set(decisions.map(\.id))
        notifiedDecisionIds = notifiedDecisionIds.intersection(pendingIds)

        return decisions
    }

    // MARK: - Answered Decisions → Re-dispatch

    /// Detect decisions that were pending last cycle but are now answered.
    /// If the company session that asked the question is dead, re-dispatch happens
    /// via checkAndDispatch() later in the same heartbeat cycle.
    func checkAnsweredDecisions(currentPending: [Decision]) async throws {
        let currentPendingIds = Set(currentPending.map(\.id))

        // Find decisions that disappeared from pending (= answered)
        let answeredIds = previousPendingDecisionIds.subtracting(currentPendingIds)

        if !answeredIds.isEmpty {
            logger.info("\(answeredIds.count) decision(s) answered — checking if re-dispatch needed")

            // Check if any company that had a decision answered has a dead session
            let runningSessions = await launcher.listRunningSessions()
            let runningCompanySlugs = Set(runningSessions.compactMap { slug -> String? in
                slug.split(separator: ":", maxSplits: 1).first.map(String.init)
            })

            // Get ready tasks that might have been unblocked
            let readyTasks = try await client.getDispatcherQueue()
            for task in readyTasks {
                if !runningCompanySlugs.contains(task.companySlug) {
                    logger.info("Company \(task.companySlug) unblocked by answered decision — checkAndDispatch runs next")
                    // checkAndDispatch will handle the actual launch on this same cycle
                }
            }
        }

        previousPendingDecisionIds = currentPendingIds
    }

    // MARK: - Smart Stale Companies

    /// Re-enable stale company detection with smart logic:
    /// Only relaunch if (a) company has pending tasks, (b) no running session exists.
    func checkStaleCompaniesSmart() async throws {
        let stale = try await client.getStaleCompanies()
        guard !stale.isEmpty else { return }

        let runningSessions = await launcher.listRunningSessions()
        let readyTasks = try await client.getDispatcherQueue()
        let companiesWithTasks = Set(readyTasks.map(\.companySlug))

        for company in stale {
            // Skip if company has no pending tasks
            guard companiesWithTasks.contains(company.slug) else {
                logger.debug("Stale company \(company.slug) has no pending tasks — skipping")
                continue
            }

            // Skip if company already has a running session
            let hasSession = runningSessions.contains { $0.hasPrefix("\(company.slug):") }
            guard !hasSession else {
                logger.debug("Stale company \(company.slug) already has running session — skipping")
                continue
            }

            // Skip if budget exhausted
            if let task = readyTasks.first(where: { $0.companySlug == company.slug }) {
                guard task.spentToday < task.budget.dailyUsd else {
                    logger.info("Stale company \(company.slug) budget exhausted — skipping")
                    continue
                }
            }

            let projectPath = (company.config["project_path"]?.value as? String) ?? company.slug
            logger.warning("Stale company \(company.slug) has pending tasks, no session — relaunching")

            try await launcher.launchTaskSession(
                taskId: "",
                companyId: company.id,
                companySlug: company.slug,
                title: company.slug,
                projectPath: projectPath
            )
        }
    }
}
