import Foundation

/// Coordinates inbox data sources and provides a unified view of pending items.
/// The inbox is virtual — no DB table. Items are fetched from multiple sources
/// and sorted by urgency score.
public final class InboxManager: Sendable {
    private let sources: [InboxDataSource]

    public init(
        client: BackendClientProtocol? = nil,
        sources: [InboxDataSource]? = nil,
        shellRunner: ShellRunner = DefaultShellRunner()
    ) {
        if let sources = sources {
            self.sources = sources
        } else {
            var defaultSources: [InboxDataSource] = [
                PRInboxSource(shellRunner: shellRunner),
            ]
            if let client = client {
                let extras: [InboxDataSource] = [
                    DecisionInboxSource(client: client),
                    TaskInboxSource(client: client),
                    GateInboxSource(client: client),
                    SpecInboxSource(shellRunner: shellRunner),
                ]
                defaultSources.append(contentsOf: extras)
            }
            self.sources = defaultSources
        }
    }

    /// Fetch all inbox items from all sources, sorted by urgency score descending.
    public func fetchAll(filters: InboxFilters = InboxFilters()) async throws -> [InboxItem] {
        guard !sources.isEmpty else { throw InboxError.noSourcesConfigured }

        // Fetch from all sources concurrently
        var allItems: [InboxItem] = []

        for source in sources {
            do {
                let items = try await source.fetch(filters: filters)
                allItems.append(contentsOf: items)
            } catch {
                // Log but don't fail — partial results are better than no results.
                // A source being unavailable (e.g. gh not authenticated) shouldn't
                // block the entire inbox.
                continue
            }
        }

        // Apply status filter if specified
        if let statusFilter = filters.status {
            allItems = allItems.filter { $0.status == statusFilter }
        }

        // Sort by urgency score descending (highest urgency first)
        return allItems.sorted { $0.urgencyScore > $1.urgencyScore }
    }

    /// Quick count by type, without full data fetch overhead.
    public func count(filters: InboxFilters = InboxFilters()) async throws -> InboxCount {
        let items = try await fetchAll(filters: filters)

        let prs = items.filter { $0.type == .pr }.count
        let decisions = items.filter { $0.type == .decision }.count
        let specs = items.filter { $0.type == .spec }.count
        let tasks = items.filter { $0.type == .task }.count
        let gates = items.filter { $0.type == .gate }.count

        return InboxCount(prs: prs, decisions: decisions, specs: specs, tasks: tasks, gates: gates)
    }

    /// Extract all PR numbers from inbox items.
    public func prNumbers(filters: InboxFilters = InboxFilters()) async throws -> [Int] {
        let items = try await fetchAll(
            filters: InboxFilters(
                companySlug: filters.companySlug,
                types: [.pr],
                status: filters.status
            )
        )
        return items.compactMap(\.prNumber)
    }

    /// Mark an item as validated. For PRs, this is called after review approval.
    /// BR-I-05: validating a PR in review = validates the inbox item.
    public func markValidated(_ itemId: String) -> InboxItem.ReviewStatus {
        // In v1, status is ephemeral (per-session).
        // ListProgressStore persistence will be added in Wave 5.
        return .validated
    }
}
