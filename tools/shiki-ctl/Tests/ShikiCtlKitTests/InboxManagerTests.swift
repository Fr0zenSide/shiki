import Foundation
import Testing
@testable import ShikiCtlKit

// MARK: - Mock Data Source

final class MockInboxDataSource: InboxDataSource, @unchecked Sendable {
    let sourceType: InboxItem.ItemType
    var items: [InboxItem]
    var shouldThrow: Bool = false

    init(sourceType: InboxItem.ItemType, items: [InboxItem] = []) {
        self.sourceType = sourceType
        self.items = items
    }

    func fetch(filters: InboxFilters) async throws -> [InboxItem] {
        if shouldThrow { throw InboxError.shellCommandFailed(command: "mock", exitCode: 1) }

        var result = items

        // Apply type filter
        if let types = filters.types, !types.contains(sourceType) {
            return []
        }

        // Apply company filter
        if let slug = filters.companySlug {
            result = result.filter { $0.companySlug == slug }
        }

        return result
    }
}

// MARK: - Tests

@Suite("InboxManager — virtual aggregation from multiple sources")
struct InboxManagerTests {

    @Test("fetchAll aggregates items from all sources sorted by urgency")
    func fetchAllAggregates() async throws {
        let prSource = MockInboxDataSource(sourceType: .pr, items: [
            InboxItem(id: "pr:1", type: .pr, title: "Fix tests", age: 3600, urgencyScore: 40),
            InboxItem(id: "pr:2", type: .pr, title: "Add feature", age: 7200, urgencyScore: 60),
        ])
        let decisionSource = MockInboxDataSource(sourceType: .decision, items: [
            InboxItem(id: "decision:abc", type: .decision, title: "Choose DB?", age: 86400, urgencyScore: 80),
        ])

        let manager = InboxManager(sources: [prSource, decisionSource])
        let items = try await manager.fetchAll()

        #expect(items.count == 3)
        // Sorted by urgency descending
        #expect(items[0].id == "decision:abc")
        #expect(items[0].urgencyScore == 80)
        #expect(items[1].id == "pr:2")
        #expect(items[2].id == "pr:1")
    }

    @Test("fetchAll filters by company slug")
    func fetchAllFiltersByCompany() async throws {
        let source = MockInboxDataSource(sourceType: .pr, items: [
            InboxItem(id: "pr:1", type: .pr, title: "Maya PR", age: 3600, companySlug: "maya", urgencyScore: 40),
            InboxItem(id: "pr:2", type: .pr, title: "Shiki PR", age: 3600, companySlug: "shiki", urgencyScore: 50),
        ])

        let manager = InboxManager(sources: [source])
        let items = try await manager.fetchAll(filters: InboxFilters(companySlug: "maya"))

        #expect(items.count == 1)
        #expect(items[0].companySlug == "maya")
    }

    @Test("fetchAll filters by type")
    func fetchAllFiltersByType() async throws {
        let prSource = MockInboxDataSource(sourceType: .pr, items: [
            InboxItem(id: "pr:1", type: .pr, title: "PR", age: 3600, urgencyScore: 40),
        ])
        let decisionSource = MockInboxDataSource(sourceType: .decision, items: [
            InboxItem(id: "decision:1", type: .decision, title: "Decision", age: 3600, urgencyScore: 50),
        ])

        let manager = InboxManager(sources: [prSource, decisionSource])
        let items = try await manager.fetchAll(filters: InboxFilters(types: [.pr]))

        #expect(items.count == 1)
        #expect(items[0].type == .pr)
    }

    @Test("count returns breakdown by type")
    func countReturnsBreakdown() async throws {
        let prSource = MockInboxDataSource(sourceType: .pr, items: [
            InboxItem(id: "pr:1", type: .pr, title: "PR 1", age: 3600, urgencyScore: 40),
            InboxItem(id: "pr:2", type: .pr, title: "PR 2", age: 7200, urgencyScore: 60),
        ])
        let decisionSource = MockInboxDataSource(sourceType: .decision, items: [
            InboxItem(id: "decision:1", type: .decision, title: "Q1", age: 3600, urgencyScore: 50),
        ])

        let manager = InboxManager(sources: [prSource, decisionSource])
        let count = try await manager.count()

        #expect(count.prs == 2)
        #expect(count.decisions == 1)
        #expect(count.total == 3)
    }

    @Test("fetchAll tolerates source failure gracefully")
    func fetchAllToleratesSourceFailure() async throws {
        let workingSource = MockInboxDataSource(sourceType: .pr, items: [
            InboxItem(id: "pr:1", type: .pr, title: "Good PR", age: 3600, urgencyScore: 40),
        ])
        let failingSource = MockInboxDataSource(sourceType: .decision, items: [])
        failingSource.shouldThrow = true

        let manager = InboxManager(sources: [workingSource, failingSource])
        let items = try await manager.fetchAll()

        // Should return items from working source, silently skip failing source
        #expect(items.count == 1)
        #expect(items[0].id == "pr:1")
    }
}
