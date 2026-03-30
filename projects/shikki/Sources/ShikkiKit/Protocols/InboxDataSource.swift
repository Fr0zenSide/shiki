import Foundation

/// Protocol for inbox data source adapters.
/// Each adapter fetches items from a specific source (GitHub PRs, decisions, etc.)
/// and maps them to the unified InboxItem model.
public protocol InboxDataSource: Sendable {
    var sourceType: InboxItem.ItemType { get }
    func fetch(filters: InboxFilters) async throws -> [InboxItem]
}
