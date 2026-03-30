import Foundation
import Logging

// MARK: - AggregatedReport

/// Time-windowed metrics produced by `NATSReportAggregator`.
/// Overlays on top of the existing `Report` (which queries ShikiDB).
/// This struct captures real-time NATS-sourced counters.
public struct AggregatedReport: Sendable, Codable, Equatable {
    /// Per-company live metrics.
    public let companies: [CompanyLiveMetrics]
    /// Global event counts per time window.
    public let globalCounts: [String: Int]
    /// Global event rates per time window (events/sec).
    public let globalRates: [String: Double]
    /// Agent utilization summaries.
    public let agents: [AgentUtilization]
    /// Timestamp when the report was generated.
    public let generatedAt: Date
    /// How long the aggregator has been running.
    public let uptimeSeconds: Double

    public init(
        companies: [CompanyLiveMetrics],
        globalCounts: [String: Int],
        globalRates: [String: Double],
        agents: [AgentUtilization],
        generatedAt: Date,
        uptimeSeconds: Double
    ) {
        self.companies = companies
        self.globalCounts = globalCounts
        self.globalRates = globalRates
        self.agents = agents
        self.generatedAt = generatedAt
        self.uptimeSeconds = uptimeSeconds
    }
}

// MARK: - CompanyLiveMetrics

/// Live metrics for a single company, collected from NATS events.
public struct CompanyLiveMetrics: Sendable, Codable, Equatable {
    public let slug: String
    /// Event counts per time window (e.g. "1m" -> 12, "5m" -> 45).
    public let eventCounts: [String: Int]
    /// Count of agent completion events observed.
    public let agentCompletions: Int
    /// Count of gate results observed (passed + failed).
    public let gateResults: GateResultCounts
    /// Average decision latency in seconds (time from pending to answered).
    public let avgDecisionLatencySeconds: Double?

    public init(
        slug: String,
        eventCounts: [String: Int],
        agentCompletions: Int,
        gateResults: GateResultCounts,
        avgDecisionLatencySeconds: Double?
    ) {
        self.slug = slug
        self.eventCounts = eventCounts
        self.agentCompletions = agentCompletions
        self.gateResults = gateResults
        self.avgDecisionLatencySeconds = avgDecisionLatencySeconds
    }
}

// MARK: - GateResultCounts

/// Counts of gate pass/fail events.
public struct GateResultCounts: Sendable, Codable, Equatable {
    public let passed: Int
    public let failed: Int

    public init(passed: Int, failed: Int) {
        self.passed = passed
        self.failed = failed
    }

    public var total: Int { passed + failed }
    public var passRate: Int {
        guard total > 0 else { return 0 }
        return (passed * 100) / total
    }
}

// MARK: - DecisionTiming

/// Tracks decision pending/answered pairs for latency computation.
struct DecisionTiming: Sendable {
    let pendingAt: Date
    var answeredAt: Date?

    var latencySeconds: Double? {
        guard let answered = answeredAt else { return nil }
        return answered.timeIntervalSince(pendingAt)
    }
}

// MARK: - NATSReportAggregator

/// Actor that subscribes to `shikki.events.>` and aggregates live metrics
/// from the NATS event stream.
///
/// Maintains:
/// - Per-company event counts via `NATSMetricsCollector`
/// - Agent completion tracking
/// - Gate pass/fail counters
/// - Decision latency (pending -> answered timing)
///
/// Produces `AggregatedReport` snapshots on demand.
public actor NATSReportAggregator {
    private let nats: NATSClientProtocol
    private let collector: NATSMetricsCollector
    private let logger: Logger
    private var task: Task<Void, Never>?
    private let startedAt: Date

    /// Per-company gate counters.
    private var gateResults: [String: GateResultCounts] = [:]

    /// Per-company agent completion counters.
    private var agentCompletions: [String: Int] = [:]

    /// Decision timing for latency tracking. Key: decision ID (from payload).
    private var decisionTimings: [String: DecisionTiming] = [:]

    /// Total events processed.
    private var processedCount: Int = 0

    public init(
        nats: NATSClientProtocol,
        collector: NATSMetricsCollector = NATSMetricsCollector(),
        logger: Logger = Logger(label: "shikki.report-aggregator"),
        startedAt: Date = Date()
    ) {
        self.nats = nats
        self.collector = collector
        self.logger = logger
        self.startedAt = startedAt
    }

    // MARK: - Lifecycle

    /// Start subscribing to all events and aggregating metrics.
    public func start() async throws {
        if !(await nats.isConnected) {
            try await nats.connect()
        }

        let stream = nats.subscribe(subject: NATSSubjectMapper.allEvents)

        task = Task { [weak self] in
            for await message in stream {
                if Task.isCancelled { break }
                await self?.processMessage(message)
            }
        }
    }

    /// Stop the aggregator and disconnect from NATS.
    public func stop() async {
        task?.cancel()
        task = nil
        await nats.disconnect()
    }

    /// Whether the aggregator is currently running.
    public var isRunning: Bool { task != nil && !(task?.isCancelled ?? true) }

    /// Total events processed since start.
    public var totalProcessed: Int { processedCount }

    // MARK: - Snapshot

    /// Generate an aggregated report snapshot.
    public func snapshot(now: Date = Date()) async -> AggregatedReport {
        // Per-company metrics
        let companyCounts = await collector.allCompanyCounts(window: .fiveMinutes, now: now)
        let companyMetrics: [CompanyLiveMetrics] = companyCounts.keys.sorted().map { slug in
            var eventCounts: [String: Int] = [:]
            for window in TimeWindow.allCases {
                Task { @MainActor in }  // noop — just to satisfy structure
            }
            // We need to query each window synchronously within this actor
            eventCounts = [:]  // Will be populated below
            return CompanyLiveMetrics(
                slug: slug,
                eventCounts: eventCounts,
                agentCompletions: agentCompletions[slug] ?? 0,
                gateResults: gateResults[slug] ?? GateResultCounts(passed: 0, failed: 0),
                avgDecisionLatencySeconds: averageDecisionLatency(company: slug)
            )
        }

        // We need to build per-company metrics with async collector calls
        var enrichedMetrics: [CompanyLiveMetrics] = []
        for slug in companyCounts.keys.sorted() {
            var eventCounts: [String: Int] = [:]
            for window in TimeWindow.allCases {
                eventCounts[window.rawValue] = await collector.companyCount(
                    company: slug, window: window, now: now
                )
            }
            let metric = CompanyLiveMetrics(
                slug: slug,
                eventCounts: eventCounts,
                agentCompletions: agentCompletions[slug] ?? 0,
                gateResults: gateResults[slug] ?? GateResultCounts(passed: 0, failed: 0),
                avgDecisionLatencySeconds: averageDecisionLatency(company: slug)
            )
            enrichedMetrics.append(metric)
        }

        // Global metrics
        var globalCounts: [String: Int] = [:]
        var globalRates: [String: Double] = [:]
        for window in TimeWindow.allCases {
            globalCounts[window.rawValue] = await collector.globalCount(window: window, now: now)
            globalRates[window.rawValue] = await collector.globalRate(window: window, now: now)
        }

        let agents = await collector.allAgentUtilization()
        let uptime = now.timeIntervalSince(startedAt)

        return AggregatedReport(
            companies: enrichedMetrics,
            globalCounts: globalCounts,
            globalRates: globalRates,
            agents: agents,
            generatedAt: now,
            uptimeSeconds: uptime
        )
    }

    // MARK: - Processing

    /// Process a single NATS message, updating all counters.
    private func processMessage(_ message: NATSMessage) async {
        processedCount += 1

        // Record in collector for rate/count tracking
        await collector.record(subject: message.subject, at: Date())

        // Decode event for semantic processing
        guard let event = NATSEventTransport.decodeEvent(from: message) else {
            return
        }

        let company = NATSMetricsCollector.extractCompany(from: message.subject) ?? "unknown"

        // Track agent events
        switch event.type {
        case .codeGenAgentDispatched, .companyDispatched:
            if let agentId = extractAgentId(from: event) {
                await collector.recordAgent(
                    agentId: agentId, company: company, event: .dispatched
                )
            }

        case .codeGenAgentCompleted:
            agentCompletions[company] = (agentCompletions[company] ?? 0) + 1
            if let agentId = extractAgentId(from: event) {
                let duration = event.metadata?.duration
                await collector.recordAgent(
                    agentId: agentId, company: company, event: .completed,
                    duration: duration
                )
            }

        case .shipGatePassed:
            let current = gateResults[company] ?? GateResultCounts(passed: 0, failed: 0)
            gateResults[company] = GateResultCounts(passed: current.passed + 1, failed: current.failed)

        case .shipGateFailed:
            let current = gateResults[company] ?? GateResultCounts(passed: 0, failed: 0)
            gateResults[company] = GateResultCounts(passed: current.passed, failed: current.failed + 1)

        case .decisionPending:
            if let decisionId = extractDecisionId(from: event) {
                decisionTimings[decisionId] = DecisionTiming(pendingAt: event.timestamp)
            }

        case .decisionAnswered:
            if let decisionId = extractDecisionId(from: event) {
                decisionTimings[decisionId]?.answeredAt = event.timestamp
            }

        default:
            break
        }
    }

    // MARK: - Payload Extraction

    private func extractAgentId(from event: ShikkiEvent) -> String? {
        if case .string(let id) = event.payload["agent_id"] {
            return id
        }
        if case .agent(let id, _) = event.source {
            return id
        }
        return nil
    }

    private func extractDecisionId(from event: ShikkiEvent) -> String? {
        if case .string(let id) = event.payload["decision_id"] {
            return id
        }
        return nil
    }

    // MARK: - Decision Latency

    /// Compute average decision latency for a company.
    /// Only considers decisions that have been answered.
    private func averageDecisionLatency(company: String) -> Double? {
        let answered = decisionTimings.values.compactMap(\.latencySeconds)
        guard !answered.isEmpty else { return nil }
        return answered.reduce(0.0, +) / Double(answered.count)
    }

    // MARK: - Maintenance

    /// Prune old data from the collector.
    public func prune(now: Date = Date()) async {
        await collector.prune(now: now)
    }

    /// Access the underlying collector for direct queries.
    public func metricsCollector() -> NATSMetricsCollector {
        collector
    }
}
