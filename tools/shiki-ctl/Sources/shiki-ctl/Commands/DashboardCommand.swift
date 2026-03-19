import ArgumentParser
import Foundation
import ShikiCtlKit

struct DashboardCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dashboard",
        abstract: "Show all sessions sorted by attention zone"
    )

    @Option(name: .long, help: "Tmux session name")
    var session: String = "shiki"

    func run() async throws {
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
        print("\u{1B}[2m\(snapshot.sessions.count) session(s) at \(ISO8601DateFormatter().string(from: snapshot.timestamp))\u{1B}[0m")
    }
}
