import Foundation
import Testing
@testable import ShikkiKit

@Suite("EditorRenderer — Editor TUI rendering")
struct EditorRendererTests {

    @Test("Render shows SHIKKI EDITOR title")
    func renderShowsTitle() {
        let engine = EditorEngine()
        let output = EditorRenderer.render(engine: engine, width: 70, height: 20)
        let stripped = TerminalSnapshot.stripANSI(output)
        #expect(stripped.contains("SHIKKI EDITOR"))
    }

    @Test("Render shows line numbers")
    func renderShowsLineNumbers() {
        let engine = EditorEngine(content: "Hello\nWorld")
        let output = EditorRenderer.render(engine: engine, width: 70, height: 20)
        let stripped = TerminalSnapshot.stripANSI(output)
        #expect(stripped.contains("  1"))
        #expect(stripped.contains("  2"))
    }

    @Test("Render shows file path in title bar")
    func renderShowsFilePath() {
        let engine = EditorEngine(content: "test", filePath: "/tmp/feature/auth-flow.md")
        let output = EditorRenderer.render(engine: engine, width: 70, height: 20)
        let stripped = TerminalSnapshot.stripANSI(output)
        #expect(stripped.contains("auth-flow.md"))
    }

    @Test("Render shows dirty indicator when modified")
    func renderShowsDirtyIndicator() {
        var engine = EditorEngine(content: "test")
        _ = engine.handleKey(.char("x"))
        let output = EditorRenderer.render(engine: engine, width: 70, height: 20)
        let stripped = TerminalSnapshot.stripANSI(output)
        #expect(stripped.contains("[modified]"))
    }

    @Test("Render shows footer with keybindings")
    func renderShowsFooter() {
        let engine = EditorEngine()
        let output = EditorRenderer.render(engine: engine, width: 70, height: 20)
        let stripped = TerminalSnapshot.stripANSI(output)
        #expect(stripped.contains("Ctrl-S save"))
        #expect(stripped.contains("Ctrl-P search"))
        #expect(stripped.contains("Esc exit"))
    }

    @Test("Render shows cursor position in footer")
    func renderShowsCursorPosition() {
        let engine = EditorEngine(content: "Hello")
        let output = EditorRenderer.render(engine: engine, width: 70, height: 20)
        let stripped = TerminalSnapshot.stripANSI(output)
        #expect(stripped.contains("Ln 1, Col 1"))
    }

    @Test("Render shows autocomplete items")
    func renderShowsAutocomplete() {
        var engine = EditorEngine()
        _ = engine.handleKey(.char("@"))
        _ = engine.handleKey(.char("S"))

        let items = [
            (label: "@Sensei", description: "CTO review persona"),
            (label: "@SecurityKit", description: "Keychain, AuthPersistence"),
        ]
        let output = EditorRenderer.render(
            engine: engine,
            autocompleteItems: items,
            selectedAutocomplete: 0,
            width: 70,
            height: 20
        )
        let stripped = TerminalSnapshot.stripANSI(output)
        #expect(stripped.contains("@Sensei"))
        #expect(stripped.contains("@SecurityKit"))
        #expect(stripped.contains("AUTOCOMPLETE"))
    }

    @Test("Render shows ghost text")
    func renderShowsGhostText() {
        let engine = EditorEngine()
        let output = EditorRenderer.render(
            engine: engine,
            ghostText: "When / For each / ? / ## ",
            width: 70,
            height: 20
        )
        // Ghost text is rendered in dim ANSI
        let stripped = TerminalSnapshot.stripANSI(output)
        #expect(stripped.contains("When / For each"))
    }

    @Test("Render pads empty area with tilde markers")
    func renderPadsEmptyArea() {
        let engine = EditorEngine(content: "Short")
        let output = EditorRenderer.render(engine: engine, width: 70, height: 20)
        let stripped = TerminalSnapshot.stripANSI(output)
        #expect(stripped.contains("~"))
    }

    @Test("Render shows content of multiline buffer")
    func renderMultilineContent() {
        let engine = EditorEngine(content: "Line one\nLine two\nLine three")
        let output = EditorRenderer.render(engine: engine, width: 70, height: 20)
        let stripped = TerminalSnapshot.stripANSI(output)
        #expect(stripped.contains("Line one"))
        #expect(stripped.contains("Line two"))
        #expect(stripped.contains("Line three"))
    }
}
