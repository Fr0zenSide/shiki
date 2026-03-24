import Testing
import Foundation
@testable import ShikiCtlKit

/// Thread-safe collector for action callbacks in tests.
final class ActionCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var _items: [String] = []

    func append(_ item: String) {
        lock.lock()
        _items.append(item)
        lock.unlock()
    }

    var items: [String] {
        lock.lock()
        defer { lock.unlock() }
        return _items
    }

    var count: Int { items.count }
}

/// BR-L-01: Batch selection with Space key. Visual checkbox indicator [x].
/// BR-L-02: Batch action applies sequentially to all selected items.
@Suite("ListReviewer Batch — BR-L-01, BR-L-02")
struct ListReviewerBatchTests {

    // MARK: - Helpers

    private func makeConfig(listId: String = "test-batch") -> ListReviewerConfig {
        ListReviewerConfig(
            title: "Batch Test",
            listId: listId,
            showProgress: true,
            keyMode: .emacs,
            sortMode: .raw
        )
    }

    private func pendingItems(_ count: Int) -> [ListItem] {
        (0..<count).map { i in
            ListItem(id: "item-\(i)", title: "Item \(i)", status: .pending)
        }
    }

    private func makeStore() -> ListProgressStore {
        let tmpFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("shiki-test-\(UUID().uuidString)")
            .appendingPathComponent("list-progress.json")
        return ListProgressStore(filePath: tmpFile)
    }

    // MARK: - Tests

    @Test("Space toggles item selection — BR-L-01")
    func spaceTogglesSelection() async {
        let items = pendingItems(3)
        let collector = ActionCollector()

        // Press space on item 0, then space on item 1, then 'a' to approve batch, then 'q'
        let keys: [KeyEvent] = [
            .space,     // select item 0, auto-advance to 1
            .space,     // select item 1, auto-advance to 2
            .char("a"), // approve batch (items 0 and 1)
            .char("q"), // quit
        ]

        var reviewer = InteractiveListReviewer(
            items: items,
            config: makeConfig(),
            onAction: { item, action in
                collector.append(item.id)
                return .success(newStatus: .validated)
            },
            keySource: MockKeySource(keys: keys),
            outputSink: BufferSink(),
            progressStore: makeStore()
        )

        let result = await reviewer.run()

        // Both items should have been actioned
        #expect(collector.count == 2)
        #expect(collector.items.contains("item-0"))
        #expect(collector.items.contains("item-1"))
        #expect(result.reviewedCount >= 2)
    }

    @Test("Double space deselects item — BR-L-01")
    func doubleSpaceDeselects() async {
        let items = pendingItems(3)
        let collector = ActionCollector()

        // Space on 0 (select), up to go back to 0, space again (deselect), then approve (single item at cursor 1), quit
        let keys: [KeyEvent] = [
            .space,     // select item 0, cursor moves to 1
            .up,        // back to item 0
            .space,     // deselect item 0, cursor moves to 1
            .char("a"), // approve just item 1 (no batch, cursor is on 1)
            .char("q"),
        ]

        var reviewer = InteractiveListReviewer(
            items: items,
            config: makeConfig(),
            onAction: { item, action in
                collector.append(item.id)
                return .success(newStatus: .validated)
            },
            keySource: MockKeySource(keys: keys),
            outputSink: BufferSink(),
            progressStore: makeStore()
        )

        _ = await reviewer.run()

        // Only item-1 should have been actioned (single, not batch)
        #expect(collector.items == ["item-1"])
    }

    @Test("Batch action calls onAction for each selected item sequentially — BR-L-02")
    func batchSequentialExecution() async {
        let items = pendingItems(4)
        let collector = ActionCollector()

        // Select items 0, 1, 2 then approve
        let keys: [KeyEvent] = [
            .space,     // select 0
            .space,     // select 1
            .space,     // select 2
            .char("a"), // batch approve
            .char("q"),
        ]

        var reviewer = InteractiveListReviewer(
            items: items,
            config: makeConfig(),
            onAction: { item, action in
                collector.append(item.id)
                return .success(newStatus: .validated)
            },
            keySource: MockKeySource(keys: keys),
            outputSink: BufferSink(),
            progressStore: makeStore()
        )

        _ = await reviewer.run()

        // Sequential order preserved
        #expect(collector.items == ["item-0", "item-1", "item-2"])
    }

    @Test("Batch skips non-applicable items — BR-L-02")
    func batchSkipsNonApplicable() async {
        // Mix of pending and already validated items
        let items = [
            ListItem(id: "a", title: "Pending A", status: .pending),
            ListItem(id: "b", title: "Validated B", status: .validated),
            ListItem(id: "c", title: "Pending C", status: .pending),
        ]
        let collector = ActionCollector()

        let keys: [KeyEvent] = [
            .space,     // select a (pending)
            .space,     // select b (validated)
            .space,     // select c (pending)
            .char("a"), // batch approve — should skip b (already validated, approve doesn't apply)
            .char("q"),
        ]

        var reviewer = InteractiveListReviewer(
            items: items,
            config: makeConfig(),
            onAction: { item, action in
                collector.append(item.id)
                return .success(newStatus: .validated)
            },
            keySource: MockKeySource(keys: keys),
            outputSink: BufferSink(),
            progressStore: makeStore()
        )

        _ = await reviewer.run()

        // Only pending items should have been actioned
        #expect(collector.items == ["a", "c"])
    }

    @Test("Non-batchable action ignores batch selection — BR-L-02")
    func nonBatchableActionIgnoresBatch() async {
        let items = pendingItems(3)
        let collector = ActionCollector()

        // Select items 0 and 1, then press 'e' (enrich, non-batchable)
        let keys: [KeyEvent] = [
            .space,     // select 0, move to 1
            .space,     // select 1, move to 2
            .up,        // back to 1
            .char("e"), // enrich — not batchable, applies to single item at cursor (1)
            .char("q"),
        ]

        let config = makeConfig()

        var reviewer = InteractiveListReviewer(
            items: items,
            config: config,
            onAction: { item, action in
                collector.append("\(item.id):\(action.label)")
                return .noChange
            },
            keySource: MockKeySource(keys: keys),
            outputSink: BufferSink(),
            progressStore: makeStore()
        )

        _ = await reviewer.run()

        // Enrich is not batchable — should only apply to current cursor item
        #expect(collector.items == ["item-1:enrich"])
    }
}
