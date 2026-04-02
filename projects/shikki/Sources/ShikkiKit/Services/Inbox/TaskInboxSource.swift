import Foundation

/// Fetches pending and in-progress tasks from the backend dispatcher queue
/// and surfaces them as inbox items. Blocking tasks score highest urgency.
public struct TaskInboxSource: InboxDataSource {
    public var sourceType: InboxItem.ItemType { .task }

    private let client: BackendClientProtocol

    public init(client: BackendClientProtocol) {
        self.client = client
    }

    public func fetch(filters: InboxFilters) async throws -> [InboxItem] {
        if let types = filters.types, !types.contains(.task) { return [] }

        do {
            let tasks = try await client.getDispatcherQueue()

            return tasks.compactMap { task in
                let company = task.companySlug

                // Apply company filter
                if let slugFilter = filters.companySlug, company != slugFilter {
                    return nil
                }

                // Higher task priority (lower number) = more urgent
                let priorityWeight = UrgencyCalculator.taskPriorityWeight(priority: task.taskPriority)

                // Tasks with priority 0 are considered blocking
                let isBlocking = task.taskPriority == 0

                // No createdAt on DispatcherTask — use zero age
                let age: TimeInterval = 0
                let urgency = UrgencyCalculator.score(
                    age: age,
                    priorityWeight: priorityWeight,
                    isBlocking: isBlocking
                )

                return InboxItem(
                    id: "task:\(task.taskId)",
                    type: .task,
                    title: task.title,
                    subtitle: task.companySlug,
                    age: age,
                    companySlug: company,
                    urgencyScore: urgency,
                    metadata: [
                        "taskPriority": "\(task.taskPriority)",
                        "companyId": task.companyId,
                        "companySlug": task.companySlug,
                        "status": task.status,
                        "projectPath": task.projectPath ?? "",
                    ]
                )
            }
        } catch {
            // Graceful fallback — backend unavailable
            return []
        }
    }
}
