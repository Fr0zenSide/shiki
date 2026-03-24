import Testing
import Foundation
@testable import ShikiCtlKit

/// BR-L-03: Progress persists to local JSON. Resume from last index on relaunch.
@Suite("ListReviewer Persistence — BR-L-03")
struct ListReviewerPersistenceTests {

    // MARK: - Helpers

    private func makeTmpStore() -> (ListProgressStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shiki-test-\(UUID().uuidString)")
        let file = dir.appendingPathComponent("list-progress.json")
        return (ListProgressStore(filePath: file), file)
    }

    // MARK: - Tests

    @Test("Save and load round-trip preserves all fields — BR-L-03")
    func saveAndLoadRoundTrip() {
        let (store, _) = makeTmpStore()
        let progress = ListProgress(
            listId: "inbox",
            reviewedItemIds: ["pr-27", "pr-28"],
            pinnedOrder: ["pr-29"],
            lastIndex: 2,
            lastUpdated: Date(timeIntervalSince1970: 1_711_200_000) // fixed date
        )

        store.save(progress)
        let loaded = store.load(listId: "inbox")

        #expect(loaded != nil)
        #expect(loaded?.listId == "inbox")
        #expect(loaded?.reviewedItemIds == ["pr-27", "pr-28"])
        #expect(loaded?.pinnedOrder == ["pr-29"])
        #expect(loaded?.lastIndex == 2)
    }

    @Test("Resume from lastIndex on relaunch — BR-L-03")
    func resumeFromLastIndex() async {
        let (store, _) = makeTmpStore()

        // Save progress with lastIndex = 2
        let progress = ListProgress(
            listId: "resume-test",
            reviewedItemIds: ["item-0", "item-1"],
            pinnedOrder: [],
            lastIndex: 2,
            lastUpdated: Date()
        )
        store.save(progress)

        // Create a reviewer that reads progress and immediately quits
        let items = (0..<5).map { i in
            ListItem(id: "item-\(i)", title: "Item \(i)", status: .pending)
        }

        let collector = ActionCollector()
        let keys: [KeyEvent] = [
            .char("a"), // approve whatever item the cursor is on
            .char("q"),
        ]

        let config = ListReviewerConfig(
            title: "Resume Test",
            listId: "resume-test",
            sortMode: .raw
        )

        var reviewer = InteractiveListReviewer(
            items: items,
            config: config,
            onAction: { item, _ in
                collector.append(item.id)
                return .success(newStatus: .validated)
            },
            keySource: MockKeySource(keys: keys),
            outputSink: BufferSink(),
            progressStore: store
        )

        _ = await reviewer.run()

        // Cursor should have resumed at index 2
        #expect(collector.items == ["item-2"])
    }

    @Test("Progress persists across sessions — BR-L-03")
    func progressPersistsAcrossSessions() {
        let (store, _) = makeTmpStore()

        // Save two different lists
        store.save(ListProgress(
            listId: "list-a",
            reviewedItemIds: ["a1"],
            pinnedOrder: [],
            lastIndex: 1,
            lastUpdated: Date()
        ))
        store.save(ListProgress(
            listId: "list-b",
            reviewedItemIds: ["b1", "b2"],
            pinnedOrder: ["b3"],
            lastIndex: 3,
            lastUpdated: Date()
        ))

        // Both should be independently loadable
        let a = store.load(listId: "list-a")
        let b = store.load(listId: "list-b")

        #expect(a?.reviewedItemIds == ["a1"])
        #expect(b?.reviewedItemIds == ["b1", "b2"])
        #expect(b?.pinnedOrder == ["b3"])

        // Clear one, the other survives
        store.clear(listId: "list-a")
        #expect(store.load(listId: "list-a") == nil)
        #expect(store.load(listId: "list-b") != nil)
    }
}
