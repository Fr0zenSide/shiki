import Foundation
import Logging

/// Main orchestrator loop — runs every `interval` seconds, dispatching tasks,
/// checking decisions, cleaning up idle sessions, and relaunching stale ones.
public actor HeartbeatLoop {
    private let client: BackendClient
    private let launcher: ProcessLauncher
    private let notifier: NotificationSender
    private let interval: Duration
    private let logger: Logger
    private var notifiedDecisionIds: Set<String> = []

    public init(
        client: BackendClient,
        launcher: ProcessLauncher,
        notifier: NotificationSender,
        interval: Duration = .seconds(60),
        logger: Logger = Logger(label: "shiki-ctl.heartbeat")
    ) {
        self.client = client
        self.launcher = launcher
        self.notifier = notifier
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

                try await checkDecisions()
                try await checkStaleCompanies()
                try await checkAndDispatch()
                try await cleanupIdleSessions()
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
    func checkAndDispatch() async throws {
        let readyTasks = try await client.getDispatcherQueue()

        for task in readyTasks {
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
    func checkDecisions() async throws {
        let decisions = try await client.getPendingDecisions()
        let t1 = decisions.filter { $0.tier == 1 }
        let newDecisions = t1.filter { !notifiedDecisionIds.contains($0.id) }

        for decision in newDecisions {
            let slug = decision.companySlug ?? "unknown"
            logger.info("T1 decision pending: [\(slug)] \(decision.question)")
            try await notifier.send(
                title: "T1 Decision: \(slug)",
                body: decision.question,
                priority: .high,
                tags: ["decision", "t1", slug]
            )
            notifiedDecisionIds.insert(decision.id)
        }

        // Clean up answered decisions from the set
        let pendingIds = Set(decisions.map(\.id))
        notifiedDecisionIds = notifiedDecisionIds.intersection(pendingIds)
    }

    // MARK: - Stale Companies

    /// Detect and relaunch stale company sessions.
    func checkStaleCompanies() async throws {
        let stale = try await client.getStaleCompanies()
        for company in stale {
            let projectPath = (company.config["project_path"]?.value as? String) ?? company.slug
            logger.warning("Stale company detected: \(company.slug) — relaunching")

            // Find and kill any existing sessions for this company
            let runningSessions = await launcher.listRunningSessions()
            for sessionSlug in runningSessions where sessionSlug.hasPrefix("\(company.slug):") {
                try? await launcher.stopSession(slug: sessionSlug)
            }

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
