import Foundation
import Logging

/// Aggregates report metrics from ShikiDB (via BackendClient) and local git repos.
///
/// - BR-R-01: Daily and weekly auto-reports
/// - BR-R-02: LOC, PRs, tasks, budget
/// - BR-R-03: Historical reconstruction from agent_events
/// - BR-R-04: CODIR mode — aggregates only, no individual worker metrics
/// - BR-P-03: Reports auto-scope to recipient's company
/// - BR-P-04: Worker struggles visible only to direct manager, never CODIR
public struct ReportAggregator: Sendable {
    private let client: BackendClientProtocol
    private let gitRoots: [String: String]  // company slug -> git root path
    private let logger: Logger

    public init(
        client: BackendClientProtocol,
        gitRoots: [String: String] = [:],
        logger: Logger = Logger(label: "shikki.report")
    ) {
        self.client = client
        self.gitRoots = gitRoots
        self.logger = logger
    }

    /// Aggregate a report for the given time range and scope.
    public func aggregate(
        range: ReportTimeRange,
        scope: ReportScope,
        now: Date = Date()
    ) async throws -> Report {
        let resolved = range.resolve(now: now)
        let startISO = resolved.start.iso8601
        let endISO = resolved.end.iso8601

        // Fetch companies to know what we're reporting on
        let allCompanies = try await client.getCompanies(status: nil)
        let filteredCompanies = filterCompanies(allCompanies, scope: scope)

        // Build per-company metrics
        var companyMetricsList: [CompanyMetrics] = []
        for company in filteredCompanies {
            let metrics = try await buildCompanyMetrics(
                company: company,
                startISO: startISO,
                endISO: endISO
            )
            companyMetricsList.append(metrics)
        }

        // Compute totals
        let totals = computeTotals(from: companyMetricsList)

        // Get blocked tasks
        let blocked = try await fetchBlocked(scope: scope)

        // Get pending decisions count
        let pendingDecisions = try await fetchPendingDecisions(scope: scope)

        // Session metrics
        let sessions = try await fetchSessionMetrics(
            scope: scope,
            startISO: startISO,
            endISO: endISO
        )

        let label: String
        switch range {
        case .daily: label = "daily"
        case .weekly: label = "weekly"
        case .sprint: label = "sprint"
        case .custom: label = "custom"
        }

        let scopeLabel: String
        switch scope {
        case .workspace: scopeLabel = "workspace"
        case .company(let slug): scopeLabel = "company:\(slug)"
        case .project(let slug): scopeLabel = "project:\(slug)"
        }

        return Report(
            timeRange: ReportDateRange(start: startISO, end: endISO, label: label),
            scope: scopeLabel,
            companies: companyMetricsList,
            totals: totals,
            blocked: blocked,
            pendingDecisions: pendingDecisions,
            sessions: sessions,
            compactions: 0  // populated from NATS counters in future
        )
    }

    // MARK: - Private

    private func filterCompanies(_ companies: [Company], scope: ReportScope) -> [Company] {
        switch scope {
        case .workspace:
            return companies
        case .company(let slug):
            return companies.filter { $0.slug == slug }
        case .project(let slug):
            return companies.filter { $0.projectSlug == slug }
        }
    }

    private func buildCompanyMetrics(
        company: Company,
        startISO: String,
        endISO: String
    ) async throws -> CompanyMetrics {
        // Get daily report for basic task/decision/spend data
        let dailyReport = try await client.getDailyReport(date: nil)
        let companyReport = dailyReport.perCompany.first { $0.slug == company.slug }

        // LOC from git
        let loc = gitLOC(companySlug: company.slug, since: startISO, until: endISO)

        // PR count from daily report
        let prCount = dailyReport.prsCreated.filter { $0.projectSlug == company.slug }.count

        return CompanyMetrics(
            slug: company.slug,
            displayName: company.displayName,
            tasksCompleted: companyReport?.tasksCompleted ?? (company.completedTasks ?? 0),
            tasksTotal: (company.pendingTasks ?? 0) + (company.runningTasks ?? 0)
                + (company.completedTasks ?? 0) + (company.blockedTasks ?? 0),
            tasksFailed: companyReport?.tasksFailed ?? 0,
            prsMerged: prCount,
            locAdded: loc.added,
            locDeleted: loc.deleted,
            budgetSpent: companyReport?.spendUsd ?? company.budget.spentTodayUsd,
            agentCount: company.runningTasks ?? 0,
            avgContextPct: 0  // from NATS/agent_events in future
        )
    }

    private func computeTotals(from companies: [CompanyMetrics]) -> Totals {
        Totals(
            tasksCompleted: companies.reduce(0) { $0 + $1.tasksCompleted },
            tasksTotal: companies.reduce(0) { $0 + $1.tasksTotal },
            tasksFailed: companies.reduce(0) { $0 + $1.tasksFailed },
            prsMerged: companies.reduce(0) { $0 + $1.prsMerged },
            locAdded: companies.reduce(0) { $0 + $1.locAdded },
            locDeleted: companies.reduce(0) { $0 + $1.locDeleted },
            budgetSpent: companies.reduce(0.0) { $0 + $1.budgetSpent },
            agentCount: companies.reduce(0) { $0 + $1.agentCount }
        )
    }

    private func fetchBlocked(scope: ReportScope) async throws -> [BlockedItem] {
        let dailyReport = try await client.getDailyReport(date: nil)
        let filtered: [DailyReport.BlockedTask]
        switch scope {
        case .workspace:
            filtered = dailyReport.blocked
        case .company(let slug):
            filtered = dailyReport.blocked.filter { $0.companySlug == slug }
        case .project:
            filtered = dailyReport.blocked  // project-level filtering TBD
        }
        return filtered.map {
            BlockedItem(
                companySlug: $0.companySlug,
                title: $0.title,
                taskId: $0.status,  // using status as identifier for now
                reason: $0.question
            )
        }
    }

    private func fetchPendingDecisions(scope: ReportScope) async throws -> Int {
        let decisions = try await client.getPendingDecisions()
        switch scope {
        case .workspace:
            return decisions.count
        case .company:
            // Decision model has companyId — filter by scope
            return decisions.count  // TODO: filter when Decision has company slug
        case .project:
            return decisions.count
        }
    }

    private func fetchSessionMetrics(
        scope: ReportScope,
        startISO: String,
        endISO: String
    ) async throws -> SessionMetrics {
        let slug: String?
        switch scope {
        case .workspace: slug = nil
        case .company(let s): slug = s
        case .project: slug = nil
        }
        let transcripts = try await client.getSessionTranscripts(
            companySlug: slug, taskId: nil, limit: 500
        )
        let totalMinutes = transcripts.compactMap(\.durationMinutes).reduce(0, +)
        return SessionMetrics(count: transcripts.count, totalDurationMinutes: totalMinutes)
    }

    // MARK: - Git LOC

    /// Parse `git log --numstat` output to compute lines added/deleted.
    /// Public for testing.
    public static func parseGitNumstat(_ output: String) -> (added: Int, deleted: Int) {
        var added = 0
        var deleted = 0
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "\t")
            guard parts.count >= 2 else { continue }
            // Binary files show "-" for added/deleted
            if let a = Int(parts[0]), let d = Int(parts[1]) {
                added += a
                deleted += d
            }
        }
        return (added, deleted)
    }

    private func gitLOC(companySlug: String, since: String, until: String) -> (added: Int, deleted: Int) {
        guard let root = gitRoots[companySlug] else {
            return (0, 0)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "git", "-C", root, "log",
            "--since=\(since)", "--until=\(until)",
            "--numstat", "--pretty=format:",
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(data: data, encoding: .utf8) ?? ""
            return Self.parseGitNumstat(output)
        } catch {
            logger.warning("git log failed for \(companySlug): \(error)")
            return (0, 0)
        }
    }
}
