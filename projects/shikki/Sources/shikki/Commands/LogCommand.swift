import ArgumentParser
import Foundation
import ShikkiKit

/// Real-time event stream — runs in foreground (for tmux pane).
/// Subscribes to events via the EventTransport abstraction (WS today, NATS tomorrow).
struct LogCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "log",
        abstract: "Real-time event stream from the Shiki event bus"
    )

    @Option(name: .long, help: "Filter by company slug or event type (e.g. 'maya', 'dispatch')")
    var filter: String?

    @Flag(name: .long, help: "Raw JSON output for piping")
    var json: Bool = false

    @Option(name: .long, help: "Backend WebSocket URL")
    var wsUrl: String = "ws://localhost:3900/ws"

    @Flag(name: .long, help: "Use in-process event bus instead of WebSocket (for local testing)")
    var local: Bool = false

    func run() async throws {
        let renderer: EventRenderer = json ? JSONEventRenderer() : ANSIEventRenderer()
        let channel = filter ?? ""

        // Header (only for ANSI mode)
        if !json {
            let filterLabel = filter ?? "all"
            print("\(ANSI.bold)\(ANSI.cyan)Shikki\(ANSI.reset) \(ANSI.dim)event log\(ANSI.reset) [\(filterLabel)]")
            print("\(ANSI.dim)Transport: WebSocket → \(wsUrl)\(ANSI.reset)")
            print("\(ANSI.dim)Press Ctrl-C to stop\(ANSI.reset)")
            print()
        }

        guard let url = URL(string: wsUrl) else {
            print("\(ANSI.red)Invalid WebSocket URL: \(wsUrl)\(ANSI.reset)")
            throw ExitCode(1)
        }

        let transport = WebSocketEventTransport(url: url)

        // Show connection status in ANSI mode
        if !json {
            await transport.setStatusCallback { status in
                switch status {
                case .connecting:
                    FileHandle.standardError.write(Data("\(ANSI.dim)\(ANSI.yellow)[connecting...]\(ANSI.reset)\r".utf8))
                case .connected:
                    FileHandle.standardError.write(Data("\(ANSI.dim)\(ANSI.green)[connected]   \(ANSI.reset)\n".utf8))
                case .reconnecting(let attempt):
                    FileHandle.standardError.write(Data("\(ANSI.dim)\(ANSI.red)[reconnecting #\(attempt)...]\(ANSI.reset)\r".utf8))
                case .disconnected:
                    FileHandle.standardError.write(Data("\(ANSI.dim)\(ANSI.red)[disconnected]\(ANSI.reset)\n".utf8))
                }
            }
        }

        // Subscribe and render loop
        let stream = transport.subscribe(to: channel)
        for await event in stream {
            let line = renderer.render(event)
            print(line)
            fflush(stdout)
        }
    }
}

// MARK: - Convenience for setting status callback on actor

extension WebSocketEventTransport {
    func setStatusCallback(_ callback: @escaping @Sendable (ConnectionStatus) -> Void) async {
        self.onStatusChange = callback
    }
}
