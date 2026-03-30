import ArgumentParser
import Foundation
import ShikkiKit

/// Interactive Observatory TUI — live dashboard for session oversight.
///
/// Examples:
///   shikki observatory                 # launch interactive TUI
///   shikki observatory --snapshot      # one-shot dashboard output
///   shikki observatory --tab reports   # start on reports tab
struct ObservatoryCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "observatory",
        abstract: "Session intelligence dashboard — timeline, decisions, questions, reports"
    )

    @Flag(name: .long, help: "Print a single snapshot and exit (non-interactive)")
    var snapshot: Bool = false

    @Option(name: .long, help: "Starting tab: timeline, decisions, questions, reports")
    var tab: String?

    @Option(name: .long, help: "Key mode: emacs (default), vim, arrows")
    var keys: String = "emacs"

    @Option(name: .long, help: "Base path for decision journal")
    var decisionsPath: String?

    func run() async throws {
        var engine = ObservatoryEngine()

        // Set starting tab
        if let tabStr = tab, let startTab = ObservatoryTab(rawValue: tabStr) {
            while engine.currentTab != startTab {
                engine.nextTab()
            }
        }

        // Load decisions from journal
        let journal = DecisionJournal(basePath: decisionsPath)
        try await loadDecisionsIntoEngine(&engine, journal: journal)

        if snapshot {
            // One-shot mode: render and exit
            let width = TerminalOutput.terminalWidth()
            let height = TerminalOutput.terminalHeight()
            let renderer = ObservatoryRenderer(width: width, height: height)
            let output = renderer.render(engine: engine)
            print(output)
            return
        }

        // Interactive TUI mode
        let keyMode = KeyMode(rawValue: keys) ?? .emacs
        try await runInteractive(engine: &engine, keyMode: keyMode)
    }

    // MARK: - Interactive Loop

    private func runInteractive(engine: inout ObservatoryEngine, keyMode: KeyMode) async throws {
        let rawMode = RawMode()
        defer {
            rawMode.restore()
            TerminalOutput.showCursor()
            TerminalOutput.clearScreen()
        }

        TerminalOutput.hideCursor()

        var running = true

        while running {
            // Render
            let width = TerminalOutput.terminalWidth()
            let height = TerminalOutput.terminalHeight()
            let renderer = ObservatoryRenderer(width: width, height: height)

            TerminalOutput.clearScreen()
            let frame = renderer.render(engine: engine)
            print(frame, terminator: "")
            TerminalOutput.flush()

            // Read input
            let key = TerminalInput.readKey()
            let action = keyMode.mapAction(for: key)

            switch action {
            case .quit:
                running = false
            case .next:
                engine.moveDown()
            case .prev:
                engine.moveUp()
            case .forward:
                engine.nextTab()
            case .back:
                engine.previousTab()
            case .select:
                // Expand/collapse on enter (reports tab)
                // For other tabs, this is a no-op for now
                break
            default:
                // Handle Tab key directly for tab switching
                if key == .tab {
                    engine.nextTab()
                }
            }
        }
    }

    // MARK: - Data Loading

    private func loadDecisionsIntoEngine(_ engine: inout ObservatoryEngine, journal: DecisionJournal) async throws {
        let decisions = try await journal.loadAllDecisions()

        for decision in decisions.suffix(50) {
            let event = decision.toShikkiEvent()
            let significance = EventClassifier.classify(event)
            let icon = ObservatoryHeatmap.icon(for: significance)

            engine.addTimelineEntry(ObservatoryEntry(
                timestamp: decision.timestamp,
                icon: icon,
                significance: significance,
                title: decision.question,
                detail: "\(decision.category.rawValue): \(decision.choice)"
            ))
        }
    }
}
