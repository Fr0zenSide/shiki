import Testing
import Foundation
@testable import ShikiCtlKit

/// BR-L-04: Hybrid ordering — composite score, user pins override.
@Suite("ListReviewer Ordering — BR-L-04")
struct ListReviewerOrderingTests {

    // MARK: - Tests

    @Test("P0 item scores higher than P1 — BR-L-04")
    func p0HigherThanP1() {
        let items = [
            ListItem(id: "low", title: "P1 item", metadata: ["priority": "P1"]),
            ListItem(id: "high", title: "P0 item", metadata: ["priority": "P0"]),
        ]

        let scored = ItemScorer.computeScores(items: items, pins: [])
        let ids = scored.map(\.0.id)

        // P0 should sort first
        #expect(ids.first == "high")
    }

    @Test("Pinned item always sorts first regardless of priority — BR-L-04")
    func pinnedItemAlwaysFirst() {
        let items = [
            ListItem(id: "p0", title: "P0 unpinned", metadata: ["priority": "P0"]),
            ListItem(id: "p3", title: "P3 pinned", metadata: ["priority": "P3"]),
        ]

        let scored = ItemScorer.computeScores(items: items, pins: ["p3"])
        let ids = scored.map(\.0.id)

        // Pinned P3 sorts above unpinned P0
        #expect(ids.first == "p3")
    }

    @Test("Pin order is respected among pinned items — BR-L-04")
    func pinnedOrderIsRespected() {
        let items = [
            ListItem(id: "a", title: "A"),
            ListItem(id: "b", title: "B"),
            ListItem(id: "c", title: "C"),
        ]

        // Pin order: c first, then a
        let scored = ItemScorer.computeScores(items: items, pins: ["c", "a"])
        let ids = scored.map(\.0.id)

        #expect(ids[0] == "c") // first pinned
        #expect(ids[1] == "a") // second pinned
        #expect(ids[2] == "b") // unpinned
    }

    @Test("Raw sort mode preserves original order — BR-L-04")
    func rawModeNoReorder() async {
        let items = [
            ListItem(id: "c", title: "C", metadata: ["priority": "P0"]),
            ListItem(id: "a", title: "A", metadata: ["priority": "P3"]),
            ListItem(id: "b", title: "B", metadata: ["priority": "P1"]),
        ]

        // With raw mode and immediate quit, items should stay in original order
        let sink = BufferSink()
        let keys: [KeyEvent] = [.char("q")]

        let config = ListReviewerConfig(
            title: "Raw Order",
            listId: "raw-test",
            sortMode: .raw
        )

        let tmpFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("shiki-test-\(UUID().uuidString)")
            .appendingPathComponent("list-progress.json")

        var reviewer = InteractiveListReviewer(
            items: items,
            config: config,
            onAction: { _, _ in .noChange },
            keySource: MockKeySource(keys: keys),
            outputSink: sink,
            progressStore: ListProgressStore(filePath: tmpFile)
        )

        _ = await reviewer.run()

        let output = stripANSI(sink.output)
        // C should appear before A, A before B (original order preserved)
        let cPos = output.range(of: "C")?.lowerBound
        let aPos = output.range(of: " A")?.lowerBound
        let bPos = output.range(of: " B")?.lowerBound

        #expect(cPos != nil)
        #expect(aPos != nil)
        #expect(bPos != nil)
        if let c = cPos, let a = aPos, let b = bPos {
            #expect(c < a)
            #expect(a < b)
        }
    }
}
