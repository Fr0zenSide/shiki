import Foundation
import Testing
@testable import ShikiCtlKit

@Suite("TerminalSnapshot utility")
struct TerminalSnapshotUtilityTests {

    @Test("Capture stdout from closure")
    func captureStdout() {
        let output = TerminalSnapshot.capture {
            print("Hello, snapshot!")
        }
        #expect(output.contains("Hello, snapshot!"))
    }

    @Test("Strip ANSI escape codes")
    func stripANSI() {
        let ansi = "\u{1B}[1m\u{1B}[32mGreen Bold\u{1B}[0m Normal"
        let stripped = TerminalSnapshot.stripANSI(ansi)
        #expect(stripped == "Green Bold Normal")
    }

    @Test("Golden file creation on first run")
    func goldenFileCreation() throws {
        let dir = NSTemporaryDirectory() + "shiki-snap-\(UUID().uuidString)"
        let output = "test output line 1\ntest output line 2\n"

        let result = try TerminalSnapshot.assertSnapshot(
            output, named: "first-run", snapshotDir: dir, record: true
        )

        switch result {
        case .recorded(let path):
            #expect(FileManager.default.fileExists(atPath: path))
            let saved = try String(contentsOfFile: path, encoding: .utf8)
            #expect(saved == TerminalSnapshot.stripANSI(output))
        default:
            Issue.record("Expected .recorded, got \(result)")
        }

        try? FileManager.default.removeItem(atPath: dir)
    }

    @Test("Snapshot match on second run")
    func snapshotMatch() throws {
        let dir = NSTemporaryDirectory() + "shiki-snap-\(UUID().uuidString)"
        let output = "consistent output\n"

        // First run: record
        _ = try TerminalSnapshot.assertSnapshot(
            output, named: "match-test", snapshotDir: dir, record: true
        )

        // Second run: compare
        let result = try TerminalSnapshot.assertSnapshot(
            output, named: "match-test", snapshotDir: dir, record: false
        )
        #expect(result == .matched)

        try? FileManager.default.removeItem(atPath: dir)
    }

    @Test("Snapshot mismatch detected")
    func snapshotMismatch() throws {
        let dir = NSTemporaryDirectory() + "shiki-snap-\(UUID().uuidString)"

        // Record original
        _ = try TerminalSnapshot.assertSnapshot(
            "line one\nline two\n", named: "mismatch-test",
            snapshotDir: dir, record: true
        )

        // Compare with different output
        let result = try TerminalSnapshot.assertSnapshot(
            "line one\nline CHANGED\n", named: "mismatch-test",
            snapshotDir: dir, record: false
        )
        #expect(!result.isMatch)

        try? FileManager.default.removeItem(atPath: dir)
    }
}

@Suite("TUI Renderer Snapshots")
struct RendererSnapshotTests {

    private var snapshotDir: String {
        let testDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
        return "\(testDir)/__Snapshots__/RendererSnapshots"
    }

    @Test("Attention zone labels snapshot")
    func attentionZoneLabels() throws {
        let output = TerminalSnapshot.capture {
            let zones: [AttentionZone] = [.merge, .respond, .review, .pending, .working, .idle]
            for zone in zones {
                print("\(zone.rawValue): \(zone)")
            }
        }
        let result = try TerminalSnapshot.assertSnapshot(
            output, named: "attention-zones", snapshotDir: snapshotDir
        )
        #expect(result.isMatch)
    }

    @Test("Doctor diagnostics snapshot")
    func doctorDiagnostics() throws {
        let results = [
            DiagnosticResult(name: "git", category: .binary, status: .ok, message: "git 2.44 found"),
            DiagnosticResult(name: "tmux", category: .binary, status: .ok, message: "tmux 3.4 found"),
            DiagnosticResult(name: "delta", category: .binary, status: .warning, message: "delta not found", fixCommand: "brew install git-delta"),
            DiagnosticResult(name: "qmd", category: .binary, status: .error, message: "qmd not found"),
        ]

        let output = TerminalSnapshot.capture {
            for result in results {
                let icon: String
                switch result.status {
                case .ok:      icon = "\u{1B}[32m\u{2713}\u{1B}[0m"
                case .warning: icon = "\u{1B}[33m\u{26A0}\u{1B}[0m"
                case .error:   icon = "\u{1B}[31m\u{2717}\u{1B}[0m"
                }
                print("  \(icon) \(result.name.padding(toLength: 8, withPad: " ", startingAt: 0))  \(result.message)")
            }
        }
        let snapResult = try TerminalSnapshot.assertSnapshot(
            output, named: "doctor-diagnostics", snapshotDir: snapshotDir
        )
        #expect(snapResult.isMatch)
    }

    @Test("Dashboard sessions snapshot")
    func dashboardSessions() throws {
        let sessions = [
            DashboardSession(windowName: "maya:spm-wave3", state: .approved, attentionZone: .merge, companySlug: "maya"),
            DashboardSession(windowName: "wabisabi:onboard", state: .working, attentionZone: .working, companySlug: "wabisabi"),
            DashboardSession(windowName: "flsh:mlx", state: .done, attentionZone: .idle, companySlug: "flsh"),
        ]

        let output = TerminalSnapshot.capture {
            for session in sessions {
                let name = session.windowName.padding(toLength: 25, withPad: " ", startingAt: 0)
                let zone = session.attentionZone
                let state = session.state.rawValue
                print("  [\(zone)] \(name) \(state) (\(session.companySlug ?? "-"))")
            }
        }
        let snapResult = try TerminalSnapshot.assertSnapshot(
            output, named: "dashboard-sessions", snapshotDir: snapshotDir
        )
        #expect(snapResult.isMatch)
    }
}
