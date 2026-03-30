import Foundation
import Testing
@testable import ShikkiKit

@Suite("EditorBuffer — Text buffer with cursor management")
struct EditorBufferTests {

    @Test("Empty buffer has one empty line")
    func emptyBuffer() {
        let buf = EditorBuffer()
        #expect(buf.lines == [""])
        #expect(buf.cursorRow == 0)
        #expect(buf.cursorCol == 0)
        #expect(!buf.isDirty)
    }

    @Test("Buffer initialized with multiline content")
    func multilineInit() {
        let buf = EditorBuffer(content: "Line 1\nLine 2\nLine 3")
        #expect(buf.lineCount == 3)
        #expect(buf.lines[0] == "Line 1")
        #expect(buf.lines[2] == "Line 3")
    }

    @Test("Insert character at cursor")
    func insertChar() {
        var buf = EditorBuffer()
        buf.insert("H")
        buf.insert("i")
        #expect(buf.text == "Hi")
        #expect(buf.cursorCol == 2)
        #expect(buf.isDirty)
    }

    @Test("Insert newline splits line")
    func insertNewline() {
        var engine = EditorEngine(content: "Hello World")
        // Move cursor to position 5 (after "Hello")
        for _ in 0..<5 { _ = engine.handleKey(.right) }
        _ = engine.handleKey(.enter)
        #expect(engine.buffer.lineCount == 2)
        #expect(engine.buffer.lines[0] == "Hello")
        #expect(engine.buffer.lines[1] == " World")
    }

    @Test("Delete backward removes character")
    func deleteBackward() {
        var buf = EditorBuffer(content: "Hi")
        // Move cursor to end
        buf.insert("!") // Now "Hi!" with cursor at col 3... but cursor starts at 0
        // Let's use a fresh approach
        var engine = EditorEngine(content: "abc")
        _ = engine.handleKey(.right)
        _ = engine.handleKey(.right)
        _ = engine.handleKey(.right) // cursor at end
        _ = engine.handleKey(.backspace)
        #expect(engine.buffer.text == "ab")
    }

    @Test("Delete backward at line start merges with previous line")
    func deleteBackwardMerge() {
        var engine = EditorEngine(content: "Line1\nLine2")
        // Move to start of line 2
        _ = engine.handleKey(.down)
        _ = engine.handleKey(.backspace) // should merge
        #expect(engine.buffer.lineCount == 1)
        #expect(engine.buffer.text == "Line1Line2")
    }

    @Test("Cursor movement: up/down")
    func cursorUpDown() {
        var engine = EditorEngine(content: "AAA\nBBB\nCCC")
        _ = engine.handleKey(.down)
        #expect(engine.buffer.cursorRow == 1)
        _ = engine.handleKey(.down)
        #expect(engine.buffer.cursorRow == 2)
        _ = engine.handleKey(.up)
        #expect(engine.buffer.cursorRow == 1)
    }

    @Test("Cursor movement: left/right")
    func cursorLeftRight() {
        var engine = EditorEngine(content: "ABC")
        _ = engine.handleKey(.right)
        _ = engine.handleKey(.right)
        #expect(engine.buffer.cursorCol == 2)
        _ = engine.handleKey(.left)
        #expect(engine.buffer.cursorCol == 1)
    }

    @Test("Buffer text property returns joined lines")
    func textProperty() {
        let buf = EditorBuffer(content: "A\nB\nC")
        #expect(buf.text == "A\nB\nC")
    }

    @Test("Replace all resets buffer")
    func replaceAll() {
        var buf = EditorBuffer(content: "old content")
        buf.replaceAll(with: "new content")
        #expect(buf.text == "new content")
        #expect(buf.cursorRow == 0)
        #expect(buf.cursorCol == 0)
        #expect(!buf.isDirty)
    }

    @Test("Mark saved clears dirty flag")
    func markSaved() {
        var buf = EditorBuffer()
        buf.insert("x")
        #expect(buf.isDirty)
        buf.markSaved()
        #expect(!buf.isDirty)
    }

    @Test("Word at cursor detects partial word")
    func wordAtCursor() {
        var engine = EditorEngine(content: "hello @Sen")
        // Move cursor to end of line
        for _ in 0..<10 { _ = engine.handleKey(.right) }
        let word = engine.buffer.wordAtCursor()
        #expect(word == "@Sen")
    }

    @Test("Current line returns line at cursor row")
    func currentLine() {
        let buf = EditorBuffer(content: "Line 1\nLine 2")
        #expect(buf.currentLine == "Line 1")
    }
}

@Suite("EditorEngine — Editor mode with triggers")
struct EditorEngineTests {

    @Test("Engine starts with empty buffer")
    func emptyEngine() {
        let engine = EditorEngine()
        #expect(engine.buffer.text == "")
        #expect(engine.filePath == nil)
        #expect(engine.activeTrigger == nil)
    }

    @Test("Engine with initial content")
    func initialContent() {
        let engine = EditorEngine(content: "Hello", filePath: "/tmp/test.md")
        #expect(engine.buffer.text == "Hello")
        #expect(engine.filePath == "/tmp/test.md")
    }

    @Test("Typing characters returns .edited")
    func typingReturnsEdited() {
        var engine = EditorEngine()
        let action = engine.handleKey(.char("A"))
        #expect(action == .edited)
        #expect(engine.buffer.text == "A")
    }

    @Test("@ trigger activates autocomplete")
    func atTriggerActivates() {
        var engine = EditorEngine()
        _ = engine.handleKey(.char("@"))
        _ = engine.handleKey(.char("S"))
        let action = engine.handleKey(.char("e"))
        #expect(action == .triggerActivated)
        if case .atMention(let partial) = engine.activeTrigger {
            #expect(partial == "Se")
        } else {
            Issue.record("Expected atMention trigger")
        }
    }

    @Test("/ trigger activates inline search")
    func slashTriggerActivates() {
        var engine = EditorEngine()
        _ = engine.handleKey(.char("/"))
        _ = engine.handleKey(.char("d"))
        let action = engine.handleKey(.char(":"))
        #expect(action == .triggerActivated)
        if case .inlineSearch(let prefix, _) = engine.activeTrigger {
            #expect(prefix == "d:")
        } else {
            Issue.record("Expected inlineSearch trigger")
        }
    }

    @Test("# trigger activates scope ref")
    func hashTriggerActivates() {
        var engine = EditorEngine()
        _ = engine.handleKey(.char("#"))
        let action = engine.handleKey(.char("m"))
        #expect(action == .triggerActivated)
        if case .scopeRef(let partial) = engine.activeTrigger {
            #expect(partial == "m")
        } else {
            Issue.record("Expected scopeRef trigger")
        }
    }

    @Test("Escape dismisses active trigger")
    func escapeDismissesTrigger() {
        var engine = EditorEngine()
        _ = engine.handleKey(.char("@"))
        _ = engine.handleKey(.char("S"))
        #expect(engine.activeTrigger != nil)
        let action = engine.handleKey(.escape)
        #expect(action == .triggerDismissed)
        #expect(engine.activeTrigger == nil)
    }

    @Test("Escape without trigger returns quit")
    func escapeReturnsQuit() {
        var engine = EditorEngine()
        let action = engine.handleKey(.escape)
        #expect(action == .quit)
    }

    @Test("Tab with active trigger returns triggerAccepted")
    func tabAcceptsTrigger() {
        var engine = EditorEngine()
        _ = engine.handleKey(.char("@"))
        _ = engine.handleKey(.char("S"))
        let action = engine.handleKey(.tab)
        #expect(action == .triggerAccepted)
    }

    @Test("Tab without trigger inserts spaces")
    func tabInsertsSpaces() {
        var engine = EditorEngine()
        let action = engine.handleKey(.tab)
        #expect(action == .edited)
        #expect(engine.buffer.text == "    ")
    }

    @Test("Accept trigger completion replaces partial text")
    func acceptTriggerCompletion() {
        var engine = EditorEngine()
        _ = engine.handleKey(.char("@"))
        _ = engine.handleKey(.char("S"))
        _ = engine.handleKey(.char("e"))
        engine.acceptTriggerCompletion("@Sensei")
        #expect(engine.buffer.text == "@Sensei")
        #expect(engine.activeTrigger == nil)
    }

    @Test("Scroll adjustment keeps cursor visible")
    func scrollAdjustment() {
        var engine = EditorEngine(content: (0..<30).map { "Line \($0)" }.joined(separator: "\n"))
        // Move cursor to line 25
        for _ in 0..<25 { _ = engine.handleKey(.down) }
        engine.adjustScroll(viewportHeight: 10)
        #expect(engine.scrollOffset > 0)
        let range = engine.visibleRange(viewportHeight: 10)
        #expect(range.contains(25))
    }

    @Test("Visible range respects viewport height")
    func visibleRange() {
        let engine = EditorEngine(content: (0..<50).map { "Line \($0)" }.joined(separator: "\n"))
        let range = engine.visibleRange(viewportHeight: 10)
        #expect(range.count == 10)
    }

    @Test("Save and load round-trip")
    func saveLoadRoundTrip() throws {
        let tmpPath = NSTemporaryDirectory() + "shiki-editor-test-\(UUID().uuidString).txt"
        defer { try? FileManager.default.removeItem(atPath: tmpPath) }

        var engine = EditorEngine(content: "Hello\nWorld")
        try engine.save(to: tmpPath)
        #expect(!engine.buffer.isDirty)
        #expect(engine.filePath == tmpPath)

        var engine2 = EditorEngine()
        try engine2.load(from: tmpPath)
        #expect(engine2.buffer.text == "Hello\nWorld")
        #expect(engine2.filePath == tmpPath)
    }

    @Test("Save without path throws error")
    func saveWithoutPath() {
        var engine = EditorEngine(content: "test")
        #expect(throws: EditorError.self) {
            try engine.save()
        }
    }

    @Test("Up/down with active trigger returns trigger navigation")
    func triggerNavigation() {
        var engine = EditorEngine()
        _ = engine.handleKey(.char("@"))
        _ = engine.handleKey(.char("S"))
        let upAction = engine.handleKey(.up)
        #expect(upAction == .triggerNavigateUp)
        // Reset trigger
        engine.clearTrigger()
        _ = engine.handleKey(.char("@"))
        _ = engine.handleKey(.char("S"))
        let downAction = engine.handleKey(.down)
        #expect(downAction == .triggerNavigateDown)
    }
}
