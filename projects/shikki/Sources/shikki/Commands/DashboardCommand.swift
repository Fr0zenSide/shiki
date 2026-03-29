import ArgumentParser
import Foundation
import ShikkiKit

struct DashboardCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dashboard",
        abstract: "Reactive dashboard — the command center"
    )

    @Option(name: .long, help: "Tmux session name")
    var session: String = "shiki"

    @Flag(name: .long, help: "Show legacy attention-zone view")
    var legacy: Bool = false

    @Flag(name: .long, help: "Single snapshot (no live refresh)")
    var snapshot: Bool = false

    @Flag(name: .long, help: "Reactive mode — subscribe to EventBus for live updates")
    var reactive: Bool = false

    func run() async throws {
        if legacy {
            try await runLegacy()
        } else if snapshot {
            let state = await DashboardRenderer.gatherState(session: session)
            let width = TerminalOutput.terminalWidth()
            print(DashboardRenderer.render(state: state, width: width))
        } else if reactive {
            await runReactive()
        } else {
            await DashboardRenderer.runLive(session: session)
        }
    }

    /// Reactive mode: subscribe to EventBus, update dashboard in real-time.
    private func runReactive() async {
        let eventBus = InProcessEventBus()
        let initialState = await DashboardRenderer.gatherState(session: session)
        let engine = ReactiveDashboardEngine(
            eventBus: eventBus,
            initialState: initialState
        )

        // Start event listener in background
        let listenTask = Task {
            await engine.startListening()
        }

        // Run the TUI loop with engine-driven state
        await ReactiveDashboardLoop.run(
            engine: engine,
            session: session,
            refreshInterval: 2.0
        )

        listenTask.cancel()
    }

    /// Legacy view: sessions sorted by attention zone.
    private func runLegacy() async throws {
        let discoverer = TmuxDiscoverer(sessionName: session)
        let journal = SessionJournal()
        let registry = SessionRegistry(discoverer: discoverer, journal: journal)

        await registry.refresh()
        let snapshot = await DashboardSnapshot.from(registry: registry)

        print("\u{1B}[1m\u{1B}[36mShiki Dashboard\u{1B}[0m")
        print(String(repeating: "\u{2500}", count: 56))

        if snapshot.sessions.isEmpty {
            print("\u{1B}[2mNo active sessions\u{1B}[0m")
        } else {
            print()
            let nameWidth = max(25, snapshot.sessions.map(\.windowName.count).max() ?? 25)

            for session in snapshot.sessions {
                let zone = StatusRenderer.formatAttentionZone(session.attentionZone)
                let name = session.windowName.padding(toLength: nameWidth, withPad: " ", startingAt: 0)
                let state = "\u{1B}[2m\(session.state.rawValue)\u{1B}[0m"
                let company = session.companySlug.map { "\u{1B}[2m(\($0))\u{1B}[0m" } ?? ""
                print("  \(zone) \(name) \(state) \(company)")
            }
        }

        print()
        print("\u{1B}[2m\(snapshot.sessions.count) session(s) at \(snapshot.timestamp.iso8601)\u{1B}[0m")
    }
}
