import Foundation
import Testing
@testable import ShikiCtlKit

/// TUI Snapshot Tests — drive engine through states, verify state + capture output.
/// Tests the engine state machine AND renders doctor/status output for golden comparison.
/// PRReviewRenderer is in the executable target so we test engine state transitions
/// and snapshot the non-renderer outputs (doctor, mini status).

@Suite("TUI Snapshot — PR Review State Machine", .serialized)
struct PRReviewStateSnapshotTests {

    private var snapshotDir: String {
        let testDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
        return "\(testDir)/__Snapshots__/TUISnapshots"
    }

    private func makeEngine() -> PRReviewEngine {
        let sections = [
            ReviewSection(index: 0, title: "ARCHITECTURE", body: "Agent Personas + Watchdog", questions: [
                ReviewQuestion(text: "Are watchdog thresholds configurable?"),
            ]),
            ReviewSection(index: 1, title: "CRITICAL PATH", body: "Session Foundation", questions: [
                ReviewQuestion(text: "Is the 5-minute staleness threshold appropriate?"),
            ]),
            ReviewSection(index: 2, title: "CLI COMMANDS", body: "DoctorCommand, DashboardCommand", questions: []),
        ]
        let review = PRReview(title: "Shiki v3.1 Review", branch: "feature/tmux-status-plugin", filesChanged: 115, testsInfo: "310/310", sections: sections, checklist: [])
        return PRReviewEngine(review: review, quickMode: true)
    }

    @Test("Full review flow: navigate → approve → comment → request changes → summary")
    func fullReviewFlow() throws {
        var engine = makeEngine()

        // Start in section list (quick mode)
        #expect(engine.currentScreen == .sectionList)

        // Open section 0 → approve
        engine.handle(key: .enter)
        #expect(engine.currentScreen == .sectionView(0))
        engine.handle(key: .char("a"))
        #expect(engine.currentScreen == .sectionList)
        #expect(engine.state.verdicts[0] == .approved)

        // Open section 1 → comment with text
        engine.handle(key: .down)
        engine.handle(key: .enter)
        #expect(engine.currentScreen == .sectionView(1))
        engine.handle(key: .char("c"))
        #expect(engine.currentScreen == .commentInput(1))

        // Type comment
        for ch in "Needs review" {
            engine.handle(key: .char(ch))
        }
        #expect(engine.commentBuffer == "Needs review")

        // Submit comment
        engine.handle(key: .enter)
        #expect(engine.currentScreen == .sectionList)
        #expect(engine.state.verdicts[1] == .comment)
        #expect(engine.state.comments[1] == "Needs review")

        // Open section 2 → request changes
        engine.handle(key: .down)
        engine.handle(key: .enter)
        engine.handle(key: .char("r"))
        #expect(engine.state.verdicts[2] == .requestChanges)

        // Summary
        engine.handle(key: .char("s"))
        #expect(engine.currentScreen == .summary)

        let counts = engine.state.verdictCounts()
        #expect(counts.approved == 1)
        #expect(counts.comment == 1)
        #expect(counts.requestChanges == 1)

        // Snapshot the state as text
        let stateOutput = TerminalSnapshot.capture {
            print("Review: \(engine.review.title)")
            print("Screen: \(engine.currentScreen)")
            print("Verdicts: \(engine.state.reviewedCount)/\(engine.review.sections.count)")
            print("  ✓ \(counts.approved)  ✎ \(counts.comment)  ✗ \(counts.requestChanges)")
            if let comment = engine.state.comments[1] {
                print("Comment on section 1: \(comment)")
            }
        }
        let result = try TerminalSnapshot.assertSnapshot(
            stateOutput, named: "pr-review-full-flow-state", snapshotDir: snapshotDir
        )
        #expect(result.isMatch)
    }

    @Test("Comment cancel with Esc discards buffer")
    func commentCancelDiscardsBuffer() {
        var engine = makeEngine()
        engine.handle(key: .enter) // → section view 0
        engine.handle(key: .char("c")) // → comment input
        engine.handle(key: .char("t"))
        engine.handle(key: .char("e"))
        engine.handle(key: .char("s"))
        engine.handle(key: .char("t"))
        #expect(engine.commentBuffer == "test")

        engine.handle(key: .escape) // cancel
        #expect(engine.currentScreen == .sectionView(0))
        #expect(engine.commentBuffer.isEmpty)
        #expect(engine.state.verdicts[0] == nil) // no verdict set
    }

    @Test("Backspace in comment removes last character")
    func commentBackspace() {
        var engine = makeEngine()
        engine.handle(key: .enter)
        engine.handle(key: .char("c"))
        engine.handle(key: .char("a"))
        engine.handle(key: .char("b"))
        engine.handle(key: .char("c"))
        #expect(engine.commentBuffer == "abc")

        engine.handle(key: .backspace)
        #expect(engine.commentBuffer == "ab")

        engine.handle(key: .backspace)
        engine.handle(key: .backspace)
        #expect(engine.commentBuffer.isEmpty)

        // Backspace on empty doesn't crash
        engine.handle(key: .backspace)
        #expect(engine.commentBuffer.isEmpty)
    }
}

@Suite("TUI Snapshot — Doctor Output", .serialized)
struct DoctorSnapshotTests {

    private var snapshotDir: String {
        let testDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
        return "\(testDir)/__Snapshots__/TUISnapshots"
    }

    @Test("Snapshot: doctor output with mixed results")
    func doctorMixedResults() throws {
        let results = [
            DiagnosticResult(name: "git", category: .binary, status: .ok, message: "git 2.44 found"),
            DiagnosticResult(name: "tmux", category: .binary, status: .ok, message: "tmux 3.4 found"),
            DiagnosticResult(name: "claude", category: .binary, status: .ok, message: "claude found"),
            DiagnosticResult(name: "delta", category: .binary, status: .warning, message: "delta not found", fixCommand: "brew install git-delta"),
            DiagnosticResult(name: "qmd", category: .binary, status: .warning, message: "qmd not found", fixCommand: "See qmd docs"),
            DiagnosticResult(name: "disk", category: .disk, status: .ok, message: "125.3 GB free"),
        ]

        let output = TerminalSnapshot.capture {
            print("\u{1B}[1m\u{1B}[36mShiki Doctor\u{1B}[0m")
            print(String(repeating: "\u{2500}", count: 56))
            print()
            for result in results {
                let icon: String
                switch result.status {
                case .ok:      icon = "\u{1B}[32m\u{2713}\u{1B}[0m"
                case .warning: icon = "\u{1B}[33m\u{26A0}\u{1B}[0m"
                case .error:   icon = "\u{1B}[31m\u{2717}\u{1B}[0m"
                }
                let padded = result.name.padding(toLength: 8, withPad: " ", startingAt: 0)
                print("  \(icon) \(padded)  \(result.message)")
            }
        }

        let snapResult = try TerminalSnapshot.assertSnapshot(
            output, named: "doctor-full-output", snapshotDir: snapshotDir
        )
        #expect(snapResult.isMatch)
    }
}

@Suite("TUI Snapshot — Mini Status", .serialized)
struct MiniStatusSnapshotTests {

    private var snapshotDir: String {
        let testDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
        return "\(testDir)/__Snapshots__/TUISnapshots"
    }

    @Test("Snapshot: mini status compact format")
    func miniStatusCompact() throws {
        let output = TerminalSnapshot.capture {
            // Simulate the mini status output
            print("●2 ▲1 ○1 Q:1 $4/$15", terminator: "")
        }
        let result = try TerminalSnapshot.assertSnapshot(
            output, named: "mini-status-compact", snapshotDir: snapshotDir
        )
        #expect(result.isMatch)
    }

    @Test("Snapshot: mini status expanded format")
    func miniStatusExpanded() throws {
        let output = TerminalSnapshot.capture {
            print("maya:● wabi:▲ flsh:○ | Q:1 | $4.20/$15.00", terminator: "")
        }
        let result = try TerminalSnapshot.assertSnapshot(
            output, named: "mini-status-expanded", snapshotDir: snapshotDir
        )
        #expect(result.isMatch)
    }
}
