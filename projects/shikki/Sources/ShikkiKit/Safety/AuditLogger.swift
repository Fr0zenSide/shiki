import Foundation
import Logging

// MARK: - AuditStore

/// Protocol for persisting and querying audit events.
/// Implementations: InMemoryAuditStore (now), PostgresAuditStore (future).
public protocol AuditStore: Sendable {
    func append(_ event: AuditEvent) async throws
    func query(_ query: AuditQuery) async throws -> [AuditEvent]
    func count() async -> Int
}

// MARK: - InMemoryAuditStore

/// In-memory audit store for single-user / testing.
public actor InMemoryAuditStore: AuditStore {
    private var events: [AuditEvent] = []

    public init() {}

    public func append(_ event: AuditEvent) async throws {
        events.append(event)
    }

    public func query(_ query: AuditQuery) async throws -> [AuditEvent] {
        let filtered = events.filter { query.matches($0) }
        let sorted = filtered.sorted { $0.timestamp > $1.timestamp }
        return Array(sorted.prefix(query.limit))
    }

    public func count() async -> Int {
        events.count
    }

    /// Clear all events (for testing).
    public func clear() {
        events.removeAll()
    }
}

// MARK: - AuditLogger

/// MCP middleware that logs all tool calls with 5W1H context.
/// SOC 2 / ISO 27001 readiness: every action is traceable.
///
/// Usage:
/// ```swift
/// let logger = AuditLogger(store: InMemoryAuditStore())
/// let event = logger.logToolCall(userId: "bob", toolName: "search", ...)
/// let report = try await logger.generateReport(query: AuditQuery(userId: "bob"))
/// ```
public actor AuditLogger {
    private let store: AuditStore
    private let securityDetector: SecurityPatternDetector?
    private let budgetACL: BudgetACL?
    private let logger: Logger

    public init(
        store: AuditStore,
        securityDetector: SecurityPatternDetector? = nil,
        budgetACL: BudgetACL? = nil,
        logger: Logger = Logger(label: "shikki.audit-logger")
    ) {
        self.store = store
        self.securityDetector = securityDetector
        self.budgetACL = budgetACL
        self.logger = logger
    }

    // MARK: - Tool Call Logging

    /// Log a tool call with full 5W1H context.
    /// Optionally runs budget check and security analysis.
    /// Returns the audit event and any budget check result.
    @discardableResult
    public func logToolCall(
        userId: String,
        toolName: String,
        parameters: [String: String] = [:],
        projectSlug: String? = nil,
        workspaceId: String? = nil,
        context: String? = nil,
        sessionId: String? = nil,
        parentEventId: UUID? = nil,
        estimatedCostUsd: Double? = nil,
        outcome: AuditOutcome = .success
    ) async throws -> (event: AuditEvent, budgetCheck: BudgetCheckResult?) {
        // Budget check (if ACL and cost provided)
        var budgetResult: BudgetCheckResult?
        var effectiveOutcome = outcome
        if let acl = budgetACL, let cost = estimatedCostUsd {
            budgetResult = await acl.check(
                userId: userId,
                workspaceId: workspaceId,
                toolName: toolName,
                estimatedCostUsd: cost
            )
            if case .blocked(let reason) = budgetResult {
                effectiveOutcome = .blocked(reason: reason)
            }
        }

        // Create audit event
        let event = AuditEvent(
            userId: userId,
            toolName: toolName,
            parameters: parameters,
            projectSlug: projectSlug,
            workspaceId: workspaceId,
            context: context,
            sessionId: sessionId,
            parentEventId: parentEventId,
            outcome: effectiveOutcome
        )

        // Persist
        try await store.append(event)

        // Feed security detector
        if let detector = securityDetector {
            let isMemoryRead = toolName.lowercased().contains("search")
                || toolName.lowercased().contains("get")
                || toolName.lowercased().contains("read")

            let record = SecurityEventRecord(
                eventId: event.id,
                userId: userId,
                toolName: toolName,
                projectSlug: projectSlug,
                timestamp: event.timestamp,
                isMemoryRead: isMemoryRead
            )
            await detector.record(record)
        }

        // Record spend (if allowed and cost provided)
        if let acl = budgetACL, let cost = estimatedCostUsd {
            if case .allowed = budgetResult {
                await acl.recordSpend(
                    userId: userId,
                    workspaceId: workspaceId,
                    toolName: toolName,
                    costUsd: cost
                )
            }
        }

        return (event: event, budgetCheck: budgetResult)
    }

    // MARK: - Queries

    /// Query the audit trail.
    public func query(_ query: AuditQuery) async throws -> [AuditEvent] {
        try await store.query(query)
    }

    /// Generate a compliance report.
    public func generateReport(query: AuditQuery) async throws -> AuditReport {
        let events = try await store.query(query)
        return AuditReport(query: query, events: events)
    }

    /// Total event count in the store.
    public func eventCount() async -> Int {
        await store.count()
    }

    // MARK: - Security

    /// Run security pattern detection and return new incidents.
    public func detectSecurityAnomalies() async -> [SecurityIncident] {
        guard let detector = securityDetector else { return [] }
        return await detector.detect()
    }
}

// MARK: - AuditReportFormatter

/// Formats audit reports for different output targets.
public enum AuditReportFormatter {

    /// Render as plain text (TUI-friendly).
    public static func renderText(_ report: AuditReport) -> String {
        var lines: [String] = []
        lines.append("Audit Report")
        lines.append("Generated: \(iso8601(report.generatedAt))")
        lines.append("Total events: \(report.totalCount)")
        lines.append("Unique users: \(report.uniqueUsers.sorted().joined(separator: ", "))")
        lines.append("Unique tools: \(report.uniqueTools.sorted().joined(separator: ", "))")
        lines.append("")

        let outcomes = report.outcomeCounts
        lines.append("Outcomes: success=\(outcomes["success"] ?? 0), failure=\(outcomes["failure"] ?? 0), blocked=\(outcomes["blocked"] ?? 0)")
        lines.append("")

        lines.append("Events:")
        for event in report.events.prefix(50) {
            let outcomeStr: String
            switch event.outcome {
            case .success: outcomeStr = "OK"
            case .failure(let r): outcomeStr = "FAIL: \(r)"
            case .blocked(let r): outcomeStr = "BLOCKED: \(r)"
            }
            lines.append("  [\(iso8601(event.timestamp))] \(event.userId) -> \(event.toolName) [\(outcomeStr)]")
        }

        if report.totalCount > 50 {
            lines.append("  ... and \(report.totalCount - 50) more")
        }

        return lines.joined(separator: "\n")
    }

    /// Render as JSON (pipe-friendly).
    public static func renderJSON(_ report: AuditReport) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let payload = AuditReportJSON(
            generatedAt: report.generatedAt,
            totalCount: report.totalCount,
            uniqueUsers: report.uniqueUsers.sorted(),
            uniqueTools: report.uniqueTools.sorted(),
            outcomeCounts: report.outcomeCounts,
            events: report.events
        )

        let data = try encoder.encode(payload)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

// MARK: - AuditReportJSON (Codable wrapper)

struct AuditReportJSON: Codable, Sendable {
    let generatedAt: Date
    let totalCount: Int
    let uniqueUsers: [String]
    let uniqueTools: [String]
    let outcomeCounts: [String: Int]
    let events: [AuditEvent]
}
