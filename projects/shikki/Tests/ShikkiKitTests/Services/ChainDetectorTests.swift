import Foundation
import Testing
@testable import ShikkiKit

// MARK: - ChainDetectorTests

@Suite("ChainDetector — repeated command sequence detection")
struct ChainDetectorTests {

    // MARK: - Helpers

    private static let baseDate = ISO8601DateFormatter.standard.date(
        from: "2026-04-04T10:00:00Z"
    )!

    /// Build entries with a fixed gap between each command.
    private func makeEntries(
        commands: [String],
        gapSeconds: TimeInterval = 2,
        startDate: Date = ChainDetectorTests.baseDate,
        ws: String? = "ws-test",
        exit: Int32 = 0
    ) -> [CommandLogEntry] {
        commands.enumerated().map { index, cmd in
            let ts = ISO8601DateFormatter.standard.string(
                from: startDate.addingTimeInterval(Double(index) * gapSeconds)
            )
            return CommandLogEntry(
                ts: ts,
                cmd: cmd,
                ws: ws,
                duration_ms: 100,
                exit: exit
            )
        }
    }

    // MARK: - Empty & Single

    @Test("empty entries returns empty chains")
    func emptyEntries_returnsEmpty() {
        let result = ChainDetector.detect(entries: [])
        #expect(result.isEmpty)
    }

    @Test("single command returns no chains")
    func singleCommand_noChains() {
        let entries = makeEntries(commands: ["shi inbox"])
        let result = ChainDetector.detect(entries: entries, minOccurrences: 1)
        #expect(result.isEmpty)
    }

    // MARK: - Basic Detection

    @Test("two identical sequences detected when count meets minOccurrences")
    func twoIdenticalSequences_detected() {
        // Chain: [spec, review] repeated 3 times
        var entries: [CommandLogEntry] = []
        for i in 0..<3 {
            let start = ChainDetectorTests.baseDate.addingTimeInterval(Double(i) * 20)
            entries.append(contentsOf: makeEntries(
                commands: ["shi spec", "shi review"],
                gapSeconds: 2,
                startDate: start
            ))
        }
        let result = ChainDetector.detect(entries: entries, minOccurrences: 3)
        let specReview = result.first { $0.commands == ["shi spec", "shi review"] }
        #expect(specReview != nil)
        #expect(specReview?.count == 3)
    }

    // MARK: - Gap Boundary

    @Test("commands with gap > maxGapSeconds are separate sessions")
    func largeGap_separateSessions() {
        // Two commands with 10s gap — exceeds default 5s
        let entries = makeEntries(
            commands: ["shi spec", "shi review"],
            gapSeconds: 10
        )
        let result = ChainDetector.detect(entries: entries, minOccurrences: 1)
        // Each command is its own session of length 1 — no chains of length >= 2
        #expect(result.isEmpty)
    }

    @Test("commands with gap < maxGapSeconds are same chain")
    func smallGap_sameChain() {
        // Two commands with 3s gap — within default 5s
        var entries: [CommandLogEntry] = []
        for i in 0..<3 {
            let start = ChainDetectorTests.baseDate.addingTimeInterval(Double(i) * 20)
            entries.append(contentsOf: makeEntries(
                commands: ["shi spec", "shi ship"],
                gapSeconds: 3,
                startDate: start
            ))
        }
        let result = ChainDetector.detect(entries: entries, minOccurrences: 3)
        let chain = result.first { $0.commands == ["shi spec", "shi ship"] }
        #expect(chain != nil)
    }

    // MARK: - Chain of 3

    @Test("chain of 3 commands detected")
    func chainOfThree_detected() {
        var entries: [CommandLogEntry] = []
        for i in 0..<3 {
            let start = ChainDetectorTests.baseDate.addingTimeInterval(Double(i) * 30)
            entries.append(contentsOf: makeEntries(
                commands: ["shi spec", "shi review", "shi ship"],
                gapSeconds: 2,
                startDate: start
            ))
        }
        let result = ChainDetector.detect(entries: entries, minOccurrences: 3)
        let chain = result.first { $0.commands == ["shi spec", "shi review", "shi ship"] }
        #expect(chain != nil)
        #expect(chain?.count == 3)
    }

    // MARK: - Subchains

    @Test("longer chain contains shorter subchains")
    func longerChain_containsShorterSubchains() {
        var entries: [CommandLogEntry] = []
        for i in 0..<3 {
            let start = ChainDetectorTests.baseDate.addingTimeInterval(Double(i) * 30)
            entries.append(contentsOf: makeEntries(
                commands: ["a", "b", "c"],
                gapSeconds: 2,
                startDate: start
            ))
        }
        let result = ChainDetector.detect(entries: entries, minOccurrences: 3)
        let fullChain = result.first { $0.commands == ["a", "b", "c"] }
        let subAB = result.first { $0.commands == ["a", "b"] }
        let subBC = result.first { $0.commands == ["b", "c"] }
        #expect(fullChain != nil)
        #expect(subAB != nil)
        #expect(subBC != nil)
    }

    // MARK: - Workspace Independence

    @Test("different workspaces do not break chains")
    func differentWorkspaces_chainsStillDetected() {
        var entries: [CommandLogEntry] = []
        let workspaces: [String?] = ["ws-a", "ws-b", nil]
        for (i, ws) in workspaces.enumerated() {
            let start = ChainDetectorTests.baseDate.addingTimeInterval(Double(i) * 20)
            entries.append(contentsOf: makeEntries(
                commands: ["shi spec", "shi review"],
                gapSeconds: 2,
                startDate: start,
                ws: ws
            ))
        }
        let result = ChainDetector.detect(entries: entries, minOccurrences: 3)
        let chain = result.first { $0.commands == ["shi spec", "shi review"] }
        #expect(chain != nil)
        #expect(chain?.count == 3)
    }

    // MARK: - Failed Commands

    @Test("failed commands still counted in chains")
    func failedCommands_stillCounted() {
        var entries: [CommandLogEntry] = []
        for i in 0..<3 {
            let start = ChainDetectorTests.baseDate.addingTimeInterval(Double(i) * 20)
            entries.append(contentsOf: makeEntries(
                commands: ["shi spec", "shi review"],
                gapSeconds: 2,
                startDate: start,
                exit: i == 1 ? 1 : 0
            ))
        }
        let result = ChainDetector.detect(entries: entries, minOccurrences: 3)
        let chain = result.first { $0.commands == ["shi spec", "shi review"] }
        #expect(chain != nil)
        #expect(chain?.count == 3)
    }

    // MARK: - Sorting

    @Test("results sorted by count descending")
    func results_sortedByCountDescending() {
        // Chain A appears 5 times, Chain B appears 3 times
        var entries: [CommandLogEntry] = []
        for i in 0..<5 {
            let start = ChainDetectorTests.baseDate.addingTimeInterval(Double(i) * 20)
            entries.append(contentsOf: makeEntries(
                commands: ["a", "b"],
                gapSeconds: 2,
                startDate: start
            ))
        }
        for i in 0..<3 {
            let start = ChainDetectorTests.baseDate.addingTimeInterval(200 + Double(i) * 20)
            entries.append(contentsOf: makeEntries(
                commands: ["x", "y"],
                gapSeconds: 2,
                startDate: start
            ))
        }
        let result = ChainDetector.detect(entries: entries, minOccurrences: 3)
        // Filter to length-2 chains only for this comparison
        let length2 = result.filter { $0.commands.count == 2 }
        guard length2.count >= 2 else {
            Issue.record("Expected at least 2 chains, got \(length2.count)")
            return
        }
        #expect(length2[0].count >= length2[1].count)
    }

    // MARK: - minOccurrences = 1

    @Test("minOccurrences = 1 returns all chains")
    func minOccurrencesOne_returnsAll() {
        let entries = makeEntries(
            commands: ["shi spec", "shi review"],
            gapSeconds: 2
        )
        let result = ChainDetector.detect(entries: entries, minOccurrences: 1)
        let chain = result.first { $0.commands == ["shi spec", "shi review"] }
        #expect(chain != nil)
        #expect(chain?.count == 1)
    }

    // MARK: - Custom maxGapSeconds

    @Test("custom maxGapSeconds works")
    func customMaxGap_works() {
        // With default 5s gap, 8s gap breaks chain. With 10s gap, it doesn't.
        var entries: [CommandLogEntry] = []
        for i in 0..<3 {
            let start = ChainDetectorTests.baseDate.addingTimeInterval(Double(i) * 30)
            entries.append(contentsOf: makeEntries(
                commands: ["shi spec", "shi ship"],
                gapSeconds: 8,
                startDate: start
            ))
        }

        // Default 5s — should not detect (8s gap breaks sessions)
        let defaultResult = ChainDetector.detect(entries: entries, minOccurrences: 3)
        let noChain = defaultResult.first { $0.commands == ["shi spec", "shi ship"] }
        #expect(noChain == nil)

        // Custom 10s — should detect
        let customResult = ChainDetector.detect(
            entries: entries,
            maxGapSeconds: 10,
            minOccurrences: 3
        )
        let found = customResult.first { $0.commands == ["shi spec", "shi ship"] }
        #expect(found != nil)
    }

    // MARK: - lastSeen

    @Test("lastSeen reflects the most recent occurrence")
    func lastSeen_mostRecentOccurrence() {
        var entries: [CommandLogEntry] = []
        let dates = [
            "2026-04-04T10:00:00Z",
            "2026-04-04T10:00:02Z",
            "2026-04-04T11:00:00Z",
            "2026-04-04T11:00:02Z",
            "2026-04-04T12:00:00Z",
            "2026-04-04T12:00:02Z",
        ]
        let cmds = ["shi spec", "shi review"]
        for (i, ts) in dates.enumerated() {
            entries.append(CommandLogEntry(
                ts: ts,
                cmd: cmds[i % 2],
                ws: "ws",
                duration_ms: 100,
                exit: 0
            ))
        }
        let result = ChainDetector.detect(entries: entries, minOccurrences: 1)
        let chain = result.first { $0.commands == ["shi spec", "shi review"] }
        #expect(chain != nil)
        // The last occurrence starts at 12:00:00Z, so lastSeen should be from the last entry
        let expected = ISO8601DateFormatter.standard.date(from: "2026-04-04T12:00:02Z")!
        #expect(chain?.lastSeen == expected)
    }

    // MARK: - Edge: minChainLength

    @Test("minChainLength = 3 ignores length-2 chains")
    func minChainLength3_ignoresLength2() {
        var entries: [CommandLogEntry] = []
        for i in 0..<5 {
            let start = ChainDetectorTests.baseDate.addingTimeInterval(Double(i) * 20)
            entries.append(contentsOf: makeEntries(
                commands: ["a", "b"],
                gapSeconds: 2,
                startDate: start
            ))
        }
        let result = ChainDetector.detect(
            entries: entries,
            minChainLength: 3,
            minOccurrences: 1
        )
        #expect(result.isEmpty)
    }

    // MARK: - Equatable conformance

    @Test("DetectedChain is Equatable")
    func detectedChain_equatable() {
        let a = DetectedChain(
            commands: ["a", "b"],
            count: 3,
            lastSeen: ChainDetectorTests.baseDate
        )
        let b = DetectedChain(
            commands: ["a", "b"],
            count: 3,
            lastSeen: ChainDetectorTests.baseDate
        )
        #expect(a == b)
    }
}
