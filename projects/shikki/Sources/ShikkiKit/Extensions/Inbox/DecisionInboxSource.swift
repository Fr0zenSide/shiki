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
