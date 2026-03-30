import Foundation

/// Fetches pending decisions from the backend API and maps them to InboxItems.
public struct DecisionInboxSource: InboxDataSource {
    public var sourceType: InboxItem.ItemType { .decision }

    private let client: BackendClientProtocol

    public init(client: BackendClientProtocol) {
        self.client = client
    }

    public func fetch(filters: InboxFilters) async throws -> [InboxItem] {
        if let types = filters.types, !types.contains(.decision) { return [] }

        let decisions = try await client.getPendingDecisions()

        return decisions.compactMap { decision in
            let company = decision.companySlug

            // Apply company filter
            if let slugFilter = filters.companySlug, company != slugFilter {
                return nil
            }

            let age = parseAge(from: decision.createdAt)
            let priorityWeight = UrgencyCalculator.decisionPriorityWeight(tier: decision.tier)
            // Decisions with a taskId where that task might be blocked = blocking
            let isBlocking = decision.taskId != nil
            let urgency = UrgencyCalculator.score(age: age, priorityWeight: priorityWeight, isBlocking: isBlocking)

            return InboxItem(
                id: "decision:\(decision.id)",
                type: .decision,
                title: decision.question,
                subtitle: decision.context,
                age: age,
                companySlug: company,
                urgencyScore: urgency,
                metadata: [
                    "tier": "\(decision.tier)",
                    "taskId": decision.taskId ?? "",
                    "companyName": decision.companyName ?? "",
                ]
            )
        }
    }
}

/// Fetches completed but unreviewed tasks from the backend API.
public struct TaskInboxSource: InboxDataSource {
    public var sourceType: InboxItem.ItemType { .task }

    private let client: BackendClientProtocol

    public init(client: BackendClientProtocol) {
        self.client = client
    }

    public func fetch(filters: InboxFilters) async throws -> [InboxItem] {
        if let types = filters.types, !types.contains(.task) { return [] }

        // The backend doesn't have a dedicated completed-unreviewed endpoint,
        // so we fetch via dispatcher queue and filter client-side.
        // In v1, this source returns empty — it requires task_queue API extensions
        // that will be added when the backlog manager backend is implemented.
        return []
    }
}

/// Fetches ship gate results (completed/failed pipeline runs).
public struct GateInboxSource: InboxDataSource {
    public var sourceType: InboxItem.ItemType { .gate }

    private let client: BackendClientProtocol

    public init(client: BackendClientProtocol) {
        self.client = client
    }

    public func fetch(filters: InboxFilters) async throws -> [InboxItem] {
        if let types = filters.types, !types.contains(.gate) { return [] }

        // Gate source requires pipeline_runs API which will be added
        // when the ship pipeline backend is fully connected.
        // In v1, this source returns empty.
        return []
    }
}

/// Fetches specs awaiting review from backlog items with status=ready + associated spec file.
public struct SpecInboxSource: InboxDataSource {
    public var sourceType: InboxItem.ItemType { .spec }

    private let shellRunner: ShellRunner

    public init(shellRunner: ShellRunner = DefaultShellRunner()) {
        self.shellRunner = shellRunner
    }

    public func fetch(filters: InboxFilters) async throws -> [InboxItem] {
        if let types = filters.types, !types.contains(.spec) { return [] }

        // Spec source requires backlog_items API (ready items with spec files).
        // In v1, this source returns empty — will be populated when
        // BacklogManager + backend Wave 1 are implemented.
        return []
    }
}

// MARK: - Date Parsing Helper

func parseAge(from isoString: String) -> TimeInterval {
    if let date = ISO8601DateFormatter.precise.date(from: isoString) {
        return max(0, Date().timeIntervalSince(date))
    }
    if let date = ISO8601DateFormatter.standard.date(from: isoString) {
        return max(0, Date().timeIntervalSince(date))
    }
    return 0
}
