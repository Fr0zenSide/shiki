import Foundation
import Testing
@testable import ShikiCtlKit

@Suite("Palette rendering")
struct PaletteRendererTests {

    // MARK: - Test Helpers

    private func sampleResults() -> [PaletteResult] {
        [
            PaletteResult(
                id: "session:maya:spm-wave3", title: "maya:spm-wave3",
                subtitle: "working", category: "session",
                icon: "*", score: 0
            ),
            PaletteResult(
                id: "session:wabisabi:onboard", title: "wabisabi:onboard",
                subtitle: "prOpen", category: "session",
                icon: "^", score: 1
            ),
            PaletteResult(
                id: "cmd:status", title: "status",
                subtitle: "Show orchestrator overview", category: "command",
                icon: ">", score: 2
            ),
            PaletteResult(
                id: "cmd:doctor", title: "doctor",
                subtitle: "Diagnose environment", category: "command",
                icon: ">", score: 3
            ),
        ]
    }

    // MARK: - Tests

    @Test("Render with results shows grouped output")
    func renderWithResults() {
        let results = sampleResults()
        let output = TerminalSnapshot.capture {
            PaletteRenderer.render(
                query: "ma",
                results: results,
                selectedIndex: 0,
                scope: nil,
                width: 60,
                height: 20
            )
        }
        let stripped = TerminalSnapshot.stripANSI(output)

        // Should contain category headers
        #expect(stripped.contains("SESSION"))
        #expect(stripped.contains("COMMAND"))

        // Should contain result titles
        #expect(stripped.contains("maya:spm-wave3"))
        #expect(stripped.contains("wabisabi:onboard"))
        #expect(stripped.contains("status"))
        #expect(stripped.contains("doctor"))

        // Should contain query in search bar
        #expect(stripped.contains("ma"))

        // Should contain footer hints
        #expect(stripped.contains("navigate"))
        #expect(stripped.contains("Esc"))
    }

    @Test("Render with empty results shows 'no results'")
    func renderEmpty() {
        let output = TerminalSnapshot.capture {
            PaletteRenderer.render(
                query: "zzzznotfound",
                results: [],
                selectedIndex: 0,
                scope: nil,
                width: 60,
                height: 20
            )
        }
        let stripped = TerminalSnapshot.stripANSI(output)
        #expect(stripped.contains("No results"))
    }

    @Test("Render with scope indicator shows scope")
    func renderWithScope() {
        let results = sampleResults()
        let output = TerminalSnapshot.capture {
            PaletteRenderer.render(
                query: "maya",
                results: results,
                selectedIndex: 0,
                scope: "session",
                width: 60,
                height: 20
            )
        }
        let stripped = TerminalSnapshot.stripANSI(output)
        #expect(stripped.contains("session"))
    }

    @Test("Selected item is highlighted")
    func selectedHighlighted() {
        let results = sampleResults()
        // Render with item at index 2 selected (first command)
        let output = TerminalSnapshot.capture {
            PaletteRenderer.render(
                query: "",
                results: results,
                selectedIndex: 2,
                scope: nil,
                width: 60,
                height: 20
            )
        }
        // The raw ANSI output should contain the inverse escape for the selected item
        #expect(output.contains(ANSI.inverse))
    }

    @Test("Prefix mode indicator shown")
    func prefixIndicator() {
        let results = [
            PaletteResult(
                id: "cmd:status", title: "status",
                subtitle: "Show orchestrator overview", category: "command",
                icon: ">", score: 0
            ),
        ]
        let output = TerminalSnapshot.capture {
            PaletteRenderer.render(
                query: ">status",
                results: results,
                selectedIndex: 0,
                scope: nil,
                width: 60,
                height: 20
            )
        }
        let stripped = TerminalSnapshot.stripANSI(output)
        // The search bar should show the raw query including prefix
        #expect(stripped.contains(">status"))
    }

    @Test("Category grouping preserves order")
    func categoryGrouping() {
        let results = sampleResults()
        let output = TerminalSnapshot.capture {
            PaletteRenderer.render(
                query: "",
                results: results,
                selectedIndex: 0,
                scope: nil,
                width: 60,
                height: 20
            )
        }
        let stripped = TerminalSnapshot.stripANSI(output)

        // SESSION header should appear before COMMAND header
        guard let sessionPos = stripped.range(of: "SESSION")?.lowerBound,
              let commandPos = stripped.range(of: "COMMAND")?.lowerBound else {
            Issue.record("Expected both SESSION and COMMAND headers")
            return
        }
        #expect(sessionPos < commandPos)
    }
}
