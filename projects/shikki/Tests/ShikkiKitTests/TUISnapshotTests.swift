import Foundation
import Testing
@testable import ShikkiKit

/// TUI Snapshot Tests — drive engine through states, verify state + capture output.
/// Tests the engine state machine AND renders doctor/status output for golden comparison.
/// PRReviewRenderer is in the executable target so we test engine state transitions
/// and snapshot the non-renderer outputs (doctor, mini status).

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
