import ArgumentParser
import Foundation
import ShikkiKit

/// Real-time event stream — runs in foreground (for tmux pane).
/// Subscribes to events via the EventTransport abstraction.
///
/// Transport priority:
/// 1. `--nats` (or default when nats-server is detected) → NATSEventTransport
/// 2. `--ws` → WebSocketEventTransport (legacy, retained for fallback)
///
/// Significance filtering:
///   `--level milestone` — only show events at milestone significance or above
///
/// Replay:
///   `--replay 50` — show last 50 events from DB, then go live
///   `--since 5m` — replay events from the last 5 minutes, then go live
struct LogCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "log",
        abstract: "Real-time event stream from the Shiki event bus"
    )

    @Option(name: .long, help: "Filter by company slug (e.g. 'maya') or company.type (e.g. 'maya.agent')")
    var filter: String?

    @Option(name: .long, help: "Minimum significance level: noise, background, progress, milestone, decision, alert, critical")
    var level: String?

    @Flag(name: .long, help: "Raw JSON output for piping")
    var json: Bool = false

    @Option(name: .long, help: "Output format: compact, detail, json")
    var format: String?

    @Option(name: .long, help: "Show last N events from DB then go live")
    var replay: Int?

    @Option(name: .long, help: "Replay events from duration ago then go live (e.g. 5m, 1h, 2h)")
    var since: String?

    @Option(name: .long, help: "NATS server URL (default: nats://127.0.0.1:4222)")
    var natsUrl: String = "nats://127.0.0.1:4222"

    @Option(name: .long, help: "Backend WebSocket URL (legacy transport)")
    var wsUrl: String = "ws://localhost:3900/ws"

    @Flag(name: .long, help: "Force WebSocket transport instead of NATS")
    var ws: Bool = false

    func run() async throws {
        // Resolve format
        let renderFormat = resolveFormat()
        let minLevel = resolveLevel()

        if ws {
            try await runWebSocket(renderFormat: renderFormat, minLevel: minLevel)
        } else {
            try await runNATS(renderFormat: renderFormat, minLevel: minLevel)
        }
    }

    // MARK: - NATS Transport

    private func runNATS(renderFormat: NATSRenderFormat, minLevel: EventSignificance) async throws {
        let renderer = NATSEventRenderer(format: renderFormat, minLevel: minLevel)
        let channel = filter ?? ""

        // Header (only for non-JSON mode)
        if renderFormat != .json {
            let filterLabel = filter ?? "all"
            let levelLabel = level ?? "noise"
            print("\(ANSI.bold)\(ANSI.cyan)Shikki\(ANSI.reset) \(ANSI.dim)event log\(ANSI.reset) [\(filterLabel)] level>=\(levelLabel)")
            print("\(ANSI.dim)Transport: NATS → \(natsUrl)\(ANSI.reset)")
            print("\(ANSI.dim)Press Ctrl-C to stop\(ANSI.reset)")
            print()
        }

        // For now, use MockNATSClient as a placeholder.
        // When nats.swift is wired in (Wave 1), this becomes the real NATSClient.
        // The LogCommand doesn't care — it uses the protocol.
        let natsTransport = NATSEventTransport(nats: MockNATSClient())

        // Show connection status in non-JSON mode
        if renderFormat != .json {
            await natsTransport.setStatusCallback { status in
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

        // Replay if requested
        if replay != nil || since != nil {
            if renderFormat != .json {
                print("\(ANSI.dim)-- replay --\(ANSI.reset)")
            }
            // Replay is delegated to the caller providing events from DB.
            // For now, print a note that replay requires backend connectivity.
            if renderFormat != .json {
                print("\(ANSI.dim)(replay from ShikiDB not yet wired — connect backend for historical events)\(ANSI.reset)")
                print("\(ANSI.dim)-- live --\(ANSI.reset)")
                print()
            }
        }

        // Subscribe and render loop
        let stream = natsTransport.subscribe(to: channel)
        for await event in stream {
            let line = renderer.render(event)
            if !line.isEmpty {
                print(line)
                fflush(stdout)
            }
        }
    }

    // MARK: - Legacy WebSocket Transport

    private func runWebSocket(renderFormat: NATSRenderFormat, minLevel: EventSignificance) async throws {
        // Use the existing EventRenderer-based flow for backward compatibility
        let renderer: EventRenderer
        if renderFormat == .json {
            renderer = JSONEventRenderer()
        } else {
            renderer = ANSIEventRenderer()
        }

        let channel = filter ?? ""

        // Header
        if renderFormat != .json {
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

        if renderFormat != .json {
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

        let stream = transport.subscribe(to: channel)
        for await event in stream {
            // Apply significance filter for WS transport too
            let significance = EventClassifier.classify(event)
            if significance >= minLevel {
                let line = renderer.render(event)
                print(line)
                fflush(stdout)
            }
        }
    }

    // MARK: - Resolution Helpers

    private func resolveFormat() -> NATSRenderFormat {
        if json { return .json }
        if let format {
            return NATSRenderFormat(rawValue: format) ?? .compact
        }
        return .compact
    }

    private func resolveLevel() -> EventSignificance {
        if let level {
            return EventSignificance(cliString: level) ?? .noise
        }
        return .noise
    }
}

// MARK: - Convenience for setting status callback on transports

extension NATSEventTransport {
    func setStatusCallback(_ callback: @escaping @Sendable (ConnectionStatus) -> Void) async {
        self.onStatusChange = callback
    }
}

extension WebSocketEventTransport {
    func setStatusCallback(_ callback: @escaping @Sendable (ConnectionStatus) -> Void) async {
        self.onStatusChange = callback
    }
}
