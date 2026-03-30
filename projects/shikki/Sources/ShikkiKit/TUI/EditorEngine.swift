import Foundation

// MARK: - EditorBuffer

/// Minimal text buffer with cursor management for the editor mode.
/// Handles line-based editing with insert, delete, and navigation.
public struct EditorBuffer: Sendable, Equatable {
    /// Lines of text in the buffer.
    public private(set) var lines: [String]
    /// Cursor row (0-based).
    public private(set) var cursorRow: Int
    /// Cursor column (0-based).
    public private(set) var cursorCol: Int
    /// Whether the buffer has been modified since last save.
    public private(set) var isDirty: Bool

    public init(content: String = "") {
        if content.isEmpty {
            self.lines = [""]
        } else {
            self.lines = content.components(separatedBy: "\n")
        }
        self.cursorRow = 0
        self.cursorCol = 0
        self.isDirty = false
    }

    /// The full text content of the buffer.
    public var text: String {
        lines.joined(separator: "\n")
    }

    /// Current line at cursor position.
    public var currentLine: String {
        guard cursorRow < lines.count else { return "" }
        return lines[cursorRow]
    }

    /// Total line count.
    public var lineCount: Int { lines.count }

    // MARK: - Text Insertion

    /// Insert a character at the cursor position.
    public mutating func insert(_ char: Character) {
        guard cursorRow < lines.count else { return }
        var line = lines[cursorRow]
        let index = line.index(line.startIndex, offsetBy: min(cursorCol, line.count))
        line.insert(char, at: index)
        lines[cursorRow] = line
        cursorCol += 1
        isDirty = true
    }

    /// Insert a string at the cursor position.
    public mutating func insertText(_ text: String) {
        for char in text {
            if char == "\n" {
                insertNewline()
            } else {
                insert(char)
            }
        }
    }

    /// Insert a newline, splitting the current line at the cursor.
    public mutating func insertNewline() {
        guard cursorRow < lines.count else { return }
        let line = lines[cursorRow]
        let splitIndex = line.index(line.startIndex, offsetBy: min(cursorCol, line.count))
        let before = String(line[..<splitIndex])
        let after = String(line[splitIndex...])
        lines[cursorRow] = before
        lines.insert(after, at: cursorRow + 1)
        cursorRow += 1
        cursorCol = 0
        isDirty = true
    }

    // MARK: - Deletion

    /// Delete the character before the cursor (backspace).
    public mutating func deleteBackward() {
        if cursorCol > 0 {
            guard cursorRow < lines.count else { return }
            var line = lines[cursorRow]
            let deleteIndex = line.index(line.startIndex, offsetBy: cursorCol - 1)
            line.remove(at: deleteIndex)
            lines[cursorRow] = line
            cursorCol -= 1
            isDirty = true
        } else if cursorRow > 0 {
            // Merge with previous line
            let currentLine = lines[cursorRow]
            let prevLineLen = lines[cursorRow - 1].count
            lines[cursorRow - 1] += currentLine
            lines.remove(at: cursorRow)
            cursorRow -= 1
            cursorCol = prevLineLen
            isDirty = true
        }
    }

    /// Delete the character at the cursor (forward delete).
    public mutating func deleteForward() {
        guard cursorRow < lines.count else { return }
        let line = lines[cursorRow]
        if cursorCol < line.count {
            var mutableLine = line
            let deleteIndex = mutableLine.index(mutableLine.startIndex, offsetBy: cursorCol)
            mutableLine.remove(at: deleteIndex)
            lines[cursorRow] = mutableLine
            isDirty = true
        } else if cursorRow < lines.count - 1 {
            // Merge next line into current
            lines[cursorRow] += lines[cursorRow + 1]
            lines.remove(at: cursorRow + 1)
            isDirty = true
        }
    }

    // MARK: - Cursor Movement

    /// Move cursor up one line.
    public mutating func moveUp() {
        guard cursorRow > 0 else { return }
        cursorRow -= 1
        clampCol()
    }

    /// Move cursor down one line.
    public mutating func moveDown() {
        guard cursorRow < lines.count - 1 else { return }
        cursorRow += 1
        clampCol()
    }

    /// Move cursor left one character.
    public mutating func moveLeft() {
        if cursorCol > 0 {
            cursorCol -= 1
        } else if cursorRow > 0 {
            cursorRow -= 1
            cursorCol = lines[cursorRow].count
        }
    }

    /// Move cursor right one character.
    public mutating func moveRight() {
        let lineLen = cursorRow < lines.count ? lines[cursorRow].count : 0
        if cursorCol < lineLen {
            cursorCol += 1
        } else if cursorRow < lines.count - 1 {
            cursorRow += 1
            cursorCol = 0
        }
    }

    /// Move cursor to the beginning of the current line.
    public mutating func moveToLineStart() {
        cursorCol = 0
    }

    /// Move cursor to the end of the current line.
    public mutating func moveToLineEnd() {
        guard cursorRow < lines.count else { return }
        cursorCol = lines[cursorRow].count
    }

    /// Move cursor to the beginning of the buffer.
    public mutating func moveToStart() {
        cursorRow = 0
        cursorCol = 0
    }

    /// Move cursor to the end of the buffer.
    public mutating func moveToEnd() {
        cursorRow = max(0, lines.count - 1)
        cursorCol = lines[cursorRow].count
    }

    /// Mark the buffer as saved (not dirty).
    public mutating func markSaved() {
        isDirty = false
    }

    /// Replace the entire buffer content.
    public mutating func replaceAll(with content: String) {
        if content.isEmpty {
            self.lines = [""]
        } else {
            self.lines = content.components(separatedBy: "\n")
        }
        cursorRow = 0
        cursorCol = 0
        isDirty = false
    }

    // MARK: - Word at Cursor

    /// Extract the word being typed at the cursor (for autocomplete triggers).
    /// Returns text from the last whitespace/trigger before cursor to cursor.
    public func wordAtCursor() -> String {
        guard cursorRow < lines.count else { return "" }
        let line = lines[cursorRow]
        guard cursorCol > 0, cursorCol <= line.count else { return "" }
        let prefix = String(line.prefix(cursorCol))
        // Walk backwards to find word start
        var start = prefix.endIndex
        for i in prefix.indices.reversed() {
            if prefix[i] == " " { break }
            start = i
        }
        return String(prefix[start...])
    }

    // MARK: - Private

    private mutating func clampCol() {
        guard cursorRow < lines.count else { return }
        cursorCol = min(cursorCol, lines[cursorRow].count)
    }
}

// MARK: - EditorTrigger

/// Inline trigger detected while editing.
public enum EditorTrigger: Sendable, Equatable {
    /// `@` autocomplete for agents, packages, personas.
    case atMention(partial: String)
    /// `/d:`, `/f:`, `/m:` inline search.
    case inlineSearch(prefix: String, query: String)
    /// `#` scope reference.
    case scopeRef(partial: String)
}

// MARK: - EditorEngine

/// Editor mode engine: manages the buffer, detects inline triggers,
/// and coordinates with the command palette for augmented editing.
public struct EditorEngine: Sendable {
    public private(set) var buffer: EditorBuffer
    public private(set) var filePath: String?
    public private(set) var activeTrigger: EditorTrigger?
    /// Visible line offset for scrolling.
    public private(set) var scrollOffset: Int

    public init(content: String = "", filePath: String? = nil) {
        self.buffer = EditorBuffer(content: content)
        self.filePath = filePath
        self.activeTrigger = nil
        self.scrollOffset = 0
    }

    // MARK: - File Operations

    /// Load content from a file path.
    public mutating func load(from path: String) throws {
        let content = try String(contentsOfFile: path, encoding: .utf8)
        buffer.replaceAll(with: content)
        filePath = path
    }

    /// Save buffer content to the associated file path.
    public mutating func save() throws {
        guard let path = filePath else {
            throw EditorError.noFilePath
        }
        try buffer.text.write(toFile: path, atomically: true, encoding: .utf8)
        buffer.markSaved()
    }

    /// Save buffer content to a specific path.
    public mutating func save(to path: String) throws {
        try buffer.text.write(toFile: path, atomically: true, encoding: .utf8)
        filePath = path
        buffer.markSaved()
    }

    // MARK: - Input Handling

    /// Process a key event, returning whether a trigger was activated.
    public mutating func handleKey(_ key: KeyEvent) -> EditorAction {
        switch key {
        case .char(let c):
            buffer.insert(c)
            updateTrigger()
            return activeTrigger != nil ? .triggerActivated : .edited

        case .enter:
            if activeTrigger != nil {
                return .triggerAccepted
            }
            buffer.insertNewline()
            clearTrigger()
            return .edited

        case .backspace:
            buffer.deleteBackward()
            updateTrigger()
            return .edited

        case .tab:
            if activeTrigger != nil {
                return .triggerAccepted
            }
            // Insert spaces (tab = 4 spaces)
            buffer.insertText("    ")
            return .edited

        case .up:
            if activeTrigger != nil {
                return .triggerNavigateUp
            }
            buffer.moveUp()
            adjustScroll()
            return .navigated

        case .down:
            if activeTrigger != nil {
                return .triggerNavigateDown
            }
            buffer.moveDown()
            adjustScroll()
            return .navigated

        case .left:
            buffer.moveLeft()
            clearTrigger()
            return .navigated

        case .right:
            buffer.moveRight()
            clearTrigger()
            return .navigated

        case .escape:
            if activeTrigger != nil {
                clearTrigger()
                return .triggerDismissed
            }
            return .quit

        default:
            return .none
        }
    }

    /// Accept the current autocomplete/trigger suggestion by inserting text.
    public mutating func acceptTriggerCompletion(_ completion: String) {
        guard let trigger = activeTrigger else { return }
        // Remove the partial text that triggered autocomplete
        let partial: String
        switch trigger {
        case .atMention(let p): partial = "@" + p
        case .inlineSearch(let prefix, let query): partial = "/" + prefix + query
        case .scopeRef(let p): partial = "#" + p
        }
        // Delete the partial from the buffer
        for _ in 0..<partial.count {
            buffer.deleteBackward()
        }
        // Insert the completion
        buffer.insertText(completion)
        clearTrigger()
    }

    // MARK: - Scroll Management

    /// Adjust scroll offset to keep cursor visible.
    public mutating func adjustScroll(viewportHeight: Int = 20) {
        if buffer.cursorRow < scrollOffset {
            scrollOffset = buffer.cursorRow
        }
        if buffer.cursorRow >= scrollOffset + viewportHeight {
            scrollOffset = buffer.cursorRow - viewportHeight + 1
        }
    }

    /// Visible line range for the current scroll position.
    public func visibleRange(viewportHeight: Int) -> Range<Int> {
        let start = scrollOffset
        let end = min(scrollOffset + viewportHeight, buffer.lineCount)
        return start..<end
    }

    // MARK: - Trigger Detection

    /// Update the active trigger based on the word at cursor.
    private mutating func updateTrigger() {
        let word = buffer.wordAtCursor()

        if word.hasPrefix("@") && word.count > 1 {
            activeTrigger = .atMention(partial: String(word.dropFirst()))
        } else if word.hasPrefix("/") && word.count > 1 {
            let afterSlash = String(word.dropFirst())
            if let colonIdx = afterSlash.firstIndex(of: ":") {
                let prefix = String(afterSlash[..<colonIdx]) + ":"
                let query = String(afterSlash[afterSlash.index(after: colonIdx)...])
                activeTrigger = .inlineSearch(prefix: prefix, query: query)
            } else {
                activeTrigger = .inlineSearch(prefix: "", query: afterSlash)
            }
        } else if word.hasPrefix("#") && word.count > 1 {
            activeTrigger = .scopeRef(partial: String(word.dropFirst()))
        } else {
            activeTrigger = nil
        }
    }

    /// Clear the active trigger.
    public mutating func clearTrigger() {
        activeTrigger = nil
    }

    // MARK: - Private

    private mutating func adjustScroll() {
        adjustScroll(viewportHeight: 20)
    }
}

// MARK: - EditorAction

/// Result of processing a key event in the editor.
public enum EditorAction: Sendable, Equatable {
    case none
    case edited
    case navigated
    case triggerActivated
    case triggerAccepted
    case triggerNavigateUp
    case triggerNavigateDown
    case triggerDismissed
    case quit
}

// MARK: - EditorError

public enum EditorError: Error, Sendable, Equatable {
    case noFilePath
    case readFailed(String)
    case writeFailed(String)
}
