import Foundation

/// Fetches recent pre-PR gate results and surfaces failed or warning gates
/// as inbox items. Checks the local `~/.shikki/pre-pr-status.json` file
/// persisted by ``PrePRStatusStore``. Failed gates score highest urgency.
public struct GateInboxSource: InboxDataSource {
    public var sourceType: InboxItem.ItemType { .gate }

    private let statusStore: PrePRStatusStore

    public init(client: BackendClientProtocol) {
        self.statusStore = PrePRStatusStore()
    }

    public init(statusStore: PrePRStatusStore) {
        self.statusStore = statusStore
    }

    public func fetch(filters: InboxFilters) async throws -> [InboxItem] {
        if let types = filters.types, !types.contains(.gate) { return [] }

        do {
            guard let status = try statusStore.load() else { return [] }

            let statusAge = max(0, Date().timeIntervalSince(status.timestamp))

            // Only show gates from the last hour (matching PrePRStatus validity window)
            guard statusAge < 3600 else { return [] }

            var items: [InboxItem] = []

            for record in status.gateResults {
                let failed = !record.passed
                let priorityWeight = UrgencyCalculator.gatePriorityWeight(failed: failed)
                let urgency = UrgencyCalculator.score(
                    age: statusAge,
                    priorityWeight: priorityWeight,
                    isBlocking: failed
                )

                let subtitle: String
                if failed {
                    subtitle = "FAILED: \(record.detail ?? "no detail")"
                } else {
                    subtitle = "Passed: \(record.detail ?? "ok")"
                }

                items.append(InboxItem(
                    id: "gate:\(record.gate)",
                    type: .gate,
                    title: "Gate: \(record.gate)",
                    subtitle: subtitle,
                    age: statusAge,
                    companySlug: nil,
                    urgencyScore: urgency,
                    metadata: [
                        "gate": record.gate,
                        "passed": "\(record.passed)",
                        "detail": record.detail ?? "",
                        "branch": status.branch,
                    ]
                ))
            }

            // Only return items if there are failures — passed gates are not actionable
            let hasFailures = items.contains { $0.metadata["passed"] == "false" }
            return hasFailures ? items : []
        } catch {
            // Graceful fallback — status file missing or corrupted
            return []
        }
    }
}
