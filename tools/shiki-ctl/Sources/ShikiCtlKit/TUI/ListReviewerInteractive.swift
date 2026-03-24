import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// MARK: - Protocols for Testability

/// Abstraction over key input for testing.
public protocol KeySource: Sendable {
    func readKey() -> KeyEvent
}

/// Abstraction over output for testing.
public protocol OutputSink: Sendable {
    func write(_ string: String)
}

/// Real terminal key source.
public struct TerminalKeySource: KeySource, Sendable {
    public init() {}
    public func readKey() -> KeyEvent { TerminalInput.readKey() }
}

/// Real stdout output sink.
public struct StdoutSink: OutputSink, Sendable {
    public init() {}
    public func write(_ string: String) {
        Swift.print(string, terminator: "")
        fflush(stdout)
    }
}

/// Buffer output sink for testing.
public final class BufferSink: OutputSink, @unchecked Sendable {
    private let lock = NSLock()
    private var _lines: [String] = []

    public init() {}

    public func write(_ string: String) {
        lock.lock()
        _lines.append(string)
        lock.unlock()
    }

    public var lines: [String] {
        lock.lock()
        defer { lock.unlock() }
        return _lines
    }

    public var output: String {
        lines.joined()
    }
}

/// Mock key source for testing: returns keys from a predefined sequence.
public final class MockKeySource: KeySource, @unchecked Sendable {
    private let lock = NSLock()
    private var keys: [KeyEvent]
    private var index = 0

    public init(keys: [KeyEvent]) {
        self.keys = keys
    }

    public func readKey() -> KeyEvent {
        lock.lock()
        defer { lock.unlock() }
        guard index < keys.count else { return .char("q") }
        let key = keys[index]
        index += 1
        return key
    }
}

// MARK: - Interactive ListReviewer

/// Interactive terminal list reviewer with keyboard navigation, batch selection,
/// action dispatch, and progress persistence.
public struct InteractiveListReviewer {

    // Immutable
    private let config: ListReviewerConfig
    private let keySource: KeySource
    private let outputSink: OutputSink
    private let progressStore: ListProgressStore
    private let onAction: @Sendable (ListItem, ListReviewerConfig.ListAction) async -> ActionResult

    // TTY override for testing (tests run without a real terminal)
    private let forceTTY: Bool

    // Mutable state
    private var items: [ListItem]
    private var cursorIndex: Int = 0
    private var selectedIds: Set<String> = []
    private var scrollOffset: Int = 0
    private var pinnedIds: [String] = []
    private var reviewedIds: Set<String> = []
    private var isRunning: Bool = false
    private var statusMessage: String? = nil
    private var actionLog: [(itemId: String, action: String, result: ActionResult)] = []
    private var frameHeight: Int = 0

    // MARK: - Initializers

    /// Production initializer using real terminal I/O.
    public init(
        items: [ListItem],
        config: ListReviewerConfig,
        onAction: @escaping @Sendable (ListItem, ListReviewerConfig.ListAction) async -> ActionResult
    ) {
        self.items = items
        self.config = config
        self.onAction = onAction
        self.keySource = TerminalKeySource()
        self.outputSink = StdoutSink()
        self.progressStore = ListProgressStore()
        self.forceTTY = false
    }

    /// Testable initializer with injected dependencies.
    /// `forceTTY` bypasses the isatty() check so tests can run the interactive loop
    /// without a real terminal.
    public init(
        items: [ListItem],
        config: ListReviewerConfig,
        onAction: @escaping @Sendable (ListItem, ListReviewerConfig.ListAction) async -> ActionResult,
        keySource: KeySource,
        outputSink: OutputSink,
        progressStore: ListProgressStore,
        forceTTY: Bool = true
    ) {
        self.items = items
        self.config = config
        self.onAction = onAction
        self.keySource = keySource
        self.outputSink = outputSink
        self.progressStore = progressStore
        self.forceTTY = forceTTY
    }

    // MARK: - Run

    /// Run the interactive list reviewer.
    /// Returns when the user quits or all items are reviewed.
    public mutating func run() async -> ListReviewerResult {
        // Pipe mode detection
        let isTTY = forceTTY || (isatty(STDIN_FILENO) == 1 && isatty(STDOUT_FILENO) == 1)
        guard isTTY else {
            let output = PipeOutput.plain(items: items, config: config)
            outputSink.write(output)
            return ListReviewerResult(
                reviewedCount: items.filter(\.status.isReviewed).count,
                totalCount: items.count,
                actions: []
            )
        }

        // Load progress
        loadProgress()

        // Sort items
        sortItems()

        // Enter raw mode only on real TTY (not when forceTTY is used for tests)
        let realTTY = isatty(STDIN_FILENO) == 1
        let raw: RawMode? = realTTY ? RawMode() : nil
        defer {
            raw?.restore()
            if realTTY { outputSink.write("\u{1B}[?25h") }
        }
        if realTTY { outputSink.write("\u{1B}[?25l") }

        isRunning = true

        // Initial render
        renderFrame()

        // Main loop
        while isRunning {
            let key = keySource.readKey()
            let action = config.keyMode.mapAction(for: key, context: .listReviewer)

            // Clear status message on any keypress
            statusMessage = nil

            guard let action else {
                // Unknown key — ignore
                continue
            }

            await dispatch(action)
            if isRunning { rerenderFrame() }
        }

        // Final save
        saveProgress()

        // Clear frame and show cursor
        clearFrame()

        let reviewedCount = items.filter(\.status.isReviewed).count
        return ListReviewerResult(
            reviewedCount: reviewedCount,
            totalCount: items.count,
            actions: actionLog
        )
    }

    // MARK: - Dispatch

    private mutating func dispatch(_ action: InputAction) async {
        switch action {
        case .next:
            moveCursor(by: 1)
        case .prev:
            moveCursor(by: -1)
        case .first:
            cursorIndex = 0
            adjustScroll()
        case .last:
            cursorIndex = max(items.count - 1, 0)
            adjustScroll()
        case .toggleSelect:
            toggleSelection()
        case .approve:
            await executeAction(label: "approve")
        case .kill:
            await executeAction(label: "kill")
        case .enrich:
            await executeAction(label: "enrich")
        case .defer_:
            await executeAction(label: "defer")
        case .pin:
            togglePin()
        case .undo:
            statusMessage = "undo coming in v1.1"
        case .quit:
            isRunning = false
        case .select:
            // Enter acts as approve on current item
            await executeAction(label: "approve")
        default:
            break
        }
    }

    // MARK: - Navigation

    private mutating func moveCursor(by delta: Int) {
        guard !items.isEmpty else { return }
        let newIndex = cursorIndex + delta
        cursorIndex = max(0, min(newIndex, items.count - 1))
        adjustScroll()
    }

    private mutating func adjustScroll() {
        let visibleRows = viewportHeight()
        if cursorIndex < scrollOffset {
            scrollOffset = cursorIndex
        } else if cursorIndex >= scrollOffset + visibleRows {
            scrollOffset = cursorIndex - visibleRows + 1
        }
    }

    private func viewportHeight() -> Int {
        let termHeight = TerminalOutput.terminalHeight()
        // Reserve: title(1) + separator(1) + empty(1) + progress(1) + empty(1) + legend(1) + status(1) = 7
        return max(termHeight - 7, 5)
    }

    // MARK: - Selection

    private mutating func toggleSelection() {
        guard !items.isEmpty else { return }
        let id = items[cursorIndex].id
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
        // Auto-advance after toggle
        moveCursor(by: 1)
    }

    // MARK: - Pin

    private mutating func togglePin() {
        guard !items.isEmpty else { return }
        let id = items[cursorIndex].id
        if let idx = pinnedIds.firstIndex(of: id) {
            pinnedIds.remove(at: idx)
        } else {
            pinnedIds.append(id)
        }
        sortItems()
        // Keep cursor on same item
        if let newIdx = items.firstIndex(where: { $0.id == id }) {
            cursorIndex = newIdx
            adjustScroll()
        }
    }

    // MARK: - Action Execution

    private mutating func executeAction(label: String) async {
        guard !items.isEmpty else { return }

        guard let action = config.actions.first(where: { $0.label == label }) else { return }

        // Batch mode
        if !selectedIds.isEmpty && action.batchable {
            var successCount = 0
            let sortedSelected = items.filter { selectedIds.contains($0.id) }
            for item in sortedSelected {
                guard action.appliesTo.contains(item.status) else { continue }
                let result = await onAction(item, action)
                actionLog.append((itemId: item.id, action: label, result: result))
                switch result {
                case .success(let newStatus):
                    if let idx = items.firstIndex(where: { $0.id == item.id }) {
                        items[idx] = ListItem(
                            id: item.id,
                            title: item.title,
                            subtitle: item.subtitle,
                            status: newStatus,
                            metadata: item.metadata
                        )
                        reviewedIds.insert(item.id)
                    }
                    successCount += 1
                case .failure(let message):
                    statusMessage = message
                case .noChange:
                    break
                }
            }
            selectedIds.removeAll()
            statusMessage = "\(successCount) items \(label)d"
            saveProgressDebounced()
            return
        }

        // Single item
        let item = items[cursorIndex]
        guard action.appliesTo.contains(item.status) else {
            statusMessage = "\(label) does not apply to \(item.status.rawValue) items"
            return
        }

        let result = await onAction(item, action)
        actionLog.append((itemId: item.id, action: label, result: result))

        switch result {
        case .success(let newStatus):
            items[cursorIndex] = ListItem(
                id: item.id,
                title: item.title,
                subtitle: item.subtitle,
                status: newStatus,
                metadata: item.metadata
            )
            reviewedIds.insert(item.id)
            advanceToNextUnreviewed()
            saveProgressDebounced()
        case .failure(let message):
            statusMessage = message
        case .noChange:
            break
        }
    }

    private mutating func advanceToNextUnreviewed() {
        // Find next unreviewed item after current position
        for i in (cursorIndex + 1)..<items.count {
            if !items[i].status.isReviewed {
                cursorIndex = i
                adjustScroll()
                return
            }
        }
        // Wrap around
        for i in 0..<cursorIndex {
            if !items[i].status.isReviewed {
                cursorIndex = i
                adjustScroll()
                return
            }
        }
        // All reviewed — check if we should quit
        if items.allSatisfy(\.status.isReviewed) {
            isRunning = false
        }
    }

    // MARK: - Sorting

    private mutating func sortItems() {
        switch config.sortMode {
        case .raw:
            break // no reordering
        case .manual:
            // Only pins affect order
            let pinSet = Set(pinnedIds)
            items.sort { a, b in
                let aPin = pinSet.contains(a.id)
                let bPin = pinSet.contains(b.id)
                if aPin && !bPin { return true }
                if !aPin && bPin { return false }
                if aPin && bPin {
                    let aIdx = pinnedIds.firstIndex(of: a.id) ?? 0
                    let bIdx = pinnedIds.firstIndex(of: b.id) ?? 0
                    return aIdx < bIdx
                }
                return false // maintain original order for unpinned
            }
        case .smart:
            let scores = ItemScorer.computeScores(items: items, pins: pinnedIds)
            items = scores.map(\.0)
        }
    }

    // MARK: - Progress

    private func saveProgress() {
        let progress = ListProgress(
            listId: config.listId,
            reviewedItemIds: Array(reviewedIds),
            pinnedOrder: pinnedIds,
            lastIndex: cursorIndex,
            lastUpdated: Date()
        )
        progressStore.save(progress)
    }

    private func saveProgressDebounced() {
        // For now, save immediately. Debounce is a v1.1 optimization.
        saveProgress()
    }

    private mutating func loadProgress() {
        guard let progress = progressStore.load(listId: config.listId) else { return }
        reviewedIds = Set(progress.reviewedItemIds)
        pinnedIds = progress.pinnedOrder
        if progress.lastIndex >= 0 && progress.lastIndex < items.count {
            cursorIndex = progress.lastIndex
        }
    }

    // MARK: - Rendering

    private mutating func renderFrame() {
        let frame = buildFrame()
        frameHeight = frame.count
        let output = frame.joined(separator: "\n") + "\n"
        outputSink.write(output)
    }

    private mutating func rerenderFrame() {
        // Move up by frameHeight lines
        if frameHeight > 0 {
            outputSink.write("\u{1B}[\(frameHeight)A")
        }
        let frame = buildFrame()
        frameHeight = frame.count
        let output = frame.map { "\u{1B}[2K\(line: $0)" }.joined(separator: "\n") + "\n"
        outputSink.write(output)
    }

    private func clearFrame() {
        if frameHeight > 0 {
            outputSink.write("\u{1B}[\(frameHeight)A")
            for _ in 0..<frameHeight {
                outputSink.write("\u{1B}[2K\n")
            }
        }
    }

    private func buildFrame() -> [String] {
        var lines: [String] = []

        // Title
        lines.append(styled(config.title, .bold, .purple))
        lines.append(styled(String(repeating: "\u{2500}", count: min(config.title.count + 4, 60)), .dim))
        lines.append("")

        // Items (viewport)
        let visibleRows = viewportHeight()
        let visibleEnd = min(scrollOffset + visibleRows, items.count)

        if items.isEmpty {
            lines.append(styled("  No items.", .dim))
        } else {
            // Scroll up indicator
            if scrollOffset > 0 {
                lines.append(styled("  ...\(scrollOffset) more above", .dim))
            }

            for i in scrollOffset..<visibleEnd {
                let item = items[i]
                let isCursor = i == cursorIndex
                let isSelected = selectedIds.contains(item.id)
                let isPinned = pinnedIds.contains(item.id)

                let number = String(format: "%2d", i + 1)
                let selectPrefix = isSelected ? "x" : " "
                let pinSuffix = isPinned ? "^" : " "
                let indicator = item.status.indicator

                let urgency = UrgencyCalculator.urgency(for: item, withinScope: items)
                let titleStyle = urgencyStyle(urgency)

                let text = "[\(selectPrefix)\(number)]\(pinSuffix)\(indicator) \(item.title)"

                if isCursor {
                    lines.append(styled(text, .inverse))
                } else {
                    lines.append(styled(text, titleStyle))
                }
            }

            // Scroll down indicator
            let remaining = items.count - visibleEnd
            if remaining > 0 {
                lines.append(styled("  ...\(remaining) more below", .dim))
            }
        }

        // Progress
        if config.showProgress {
            let reviewed = items.filter(\.status.isReviewed).count
            lines.append("")
            lines.append(ListReviewer.progressBar(done: reviewed, total: items.count, width: 20))
        }

        // Status message
        if let msg = statusMessage {
            lines.append(styled("  \(msg)", .yellow))
        } else {
            lines.append("")
        }

        // Action legend
        let legend = "[a]pprove [k]ill [e]nrich [d]efer [Space]select [p]in [q]uit"
        lines.append(styled(legend, .dim))

        return lines
    }

    private func urgencyStyle(_ urgency: UrgencyLevel) -> ANSIStyle {
        switch urgency {
        case .critical: return .red
        case .aging:    return .yellow
        case .ready:    return .green
        case .deferred: return .dim
        }
    }
}

// MARK: - String Interpolation Helper

private extension DefaultStringInterpolation {
    // Just pass through — the `line:` label prevents ambiguity with the compiler
    mutating func appendInterpolation(line value: String) {
        appendLiteral(value)
    }
}
