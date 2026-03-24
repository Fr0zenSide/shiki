import Foundation

/// Manages the backlog curation lifecycle.
///
/// The backlog is the first stage of the Shikki flow — raw ideas are sorted,
/// enriched with context, and promoted to readiness for spec/decide/run.
///
/// State machine: raw -> enriched -> ready -> (task_queue via dispatch)
/// Kill: any state except killed -> killed (terminal, archived not deleted)
/// Defer: any state except killed -> deferred (parking state)
/// Un-defer: deferred -> enriched (safe default)
public final class BacklogManager: Sendable {
    private let client: BackendClientProtocol

    public init(client: BackendClientProtocol) {
        self.client = client
    }

    // MARK: - List

    /// List active backlog items (raw + enriched + ready by default).
    public func listActive(companyId: String? = nil, sort: BacklogSort? = nil) async throws -> [BacklogItem] {
        try await client.listBacklogItems(status: nil, companyId: companyId, tags: nil, sort: sort)
    }

    /// List items filtered by status.
    public func list(status: BacklogItem.Status?, companyId: String? = nil, sort: BacklogSort? = nil) async throws -> [BacklogItem] {
        try await client.listBacklogItems(status: status, companyId: companyId, tags: nil, sort: sort)
    }

    // MARK: - Add (BR-F-01: every item starts raw)

    /// Quick add a new backlog item. Always starts in `raw` status.
    public func add(
        title: String,
        companyId: String? = nil,
        sourceType: BacklogItem.SourceType = .manual,
        sourceRef: String? = nil,
        priority: Int? = nil,
        tags: [String] = []
    ) async throws -> BacklogItem {
        try await client.createBacklogItem(
            title: title,
            description: nil,
            companyId: companyId,
            sourceType: sourceType,
            sourceRef: sourceRef,
            priority: priority,
            tags: tags
        )
    }

    // MARK: - Enrich (BR-F-02: raw -> enriched requires context addition)

    /// Enrich a backlog item with context notes. Transitions raw -> enriched.
    /// Requires at least one of: notes, tags, or description.
    public func enrich(
        id: String,
        notes: String,
        tags: [String]? = nil,
        description: String? = nil
    ) async throws -> BacklogItem {
        // BR-F-02: Validate that at least one context addition is provided
        let hasNotes = !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasTags = tags != nil && !(tags?.isEmpty ?? true)
        let hasDescription = description != nil && !(description?.isEmpty ?? true)

        guard hasNotes || hasTags || hasDescription else {
            throw BacklogError.enrichmentRequired
        }

        return try await client.enrichBacklogItem(
            id: id,
            notes: notes,
            tags: tags,
            description: description
        )
    }

    // MARK: - Promote

    /// Promote an item to `ready` status. Item is now eligible for decide/spec.
    public func promote(id: String) async throws -> BacklogItem {
        try await client.updateBacklogItem(
            id: id,
            status: .ready,
            priority: nil,
            sortOrder: nil,
            tags: nil,
            description: nil
        )
    }

    // MARK: - Kill (BR-F-12: killable from any state, archived not deleted)

    /// Kill a backlog item with a reason. Terminal state.
    public func kill(id: String, reason: String) async throws -> BacklogItem {
        guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BacklogError.killReasonRequired
        }
        return try await client.killBacklogItem(id: id, reason: reason)
    }

    // MARK: - Defer (BR-F-13: deferrable from any state except running/shipped/killed)

    /// Defer a backlog item (park it for later).
    public func `defer`(id: String) async throws -> BacklogItem {
        try await client.updateBacklogItem(
            id: id,
            status: .deferred,
            priority: nil,
            sortOrder: nil,
            tags: nil,
            description: nil
        )
    }

    /// Un-defer: move back to enriched (safe default per spec).
    public func undefer(id: String) async throws -> BacklogItem {
        try await client.updateBacklogItem(
            id: id,
            status: .enriched,
            priority: nil,
            sortOrder: nil,
            tags: nil,
            description: nil
        )
    }

    // MARK: - Reorder

    /// Batch reorder items by setting sort_order.
    public func reorder(_ items: [(id: String, sortOrder: Int)]) async throws {
        try await client.reorderBacklogItems(items)
    }

    // MARK: - Count

    /// Count items by optional status and company filter.
    public func count(status: BacklogItem.Status? = nil, companyId: String? = nil) async throws -> Int {
        try await client.getBacklogCount(status: status, companyId: companyId)
    }

    // MARK: - Update

    /// Update priority, tags, or description on a backlog item.
    public func update(
        id: String,
        priority: Int? = nil,
        sortOrder: Int? = nil,
        tags: [String]? = nil,
        description: String? = nil
    ) async throws -> BacklogItem {
        try await client.updateBacklogItem(
            id: id,
            status: nil,
            priority: priority,
            sortOrder: sortOrder,
            tags: tags,
            description: description
        )
    }
}

// MARK: - Errors

public enum BacklogError: Error, CustomStringConvertible {
    case enrichmentRequired
    case killReasonRequired
    case invalidTransition(from: BacklogItem.Status, to: BacklogItem.Status)

    public var description: String {
        switch self {
        case .enrichmentRequired:
            "BR-F-02: Enrichment requires at least one context addition (notes, tags, or description)"
        case .killReasonRequired:
            "Kill reason is required (archived for history)"
        case .invalidTransition(let from, let to):
            "Invalid transition: \(from.rawValue) -> \(to.rawValue)"
        }
    }
}
