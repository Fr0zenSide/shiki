import ArgumentParser
import Foundation
import ShikkiKit
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

struct SearchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Open the command palette (fuzzy search sessions, commands, features, branches)",
        aliases: ["/"]
    )

    @Argument(help: "Initial search query")
    var query: String?

    func run() async throws {
        // Non-interactive fallback
        guard isatty(STDIN_FILENO) == 1 else {
            printNonInteractive()
            return
        }

        // Build palette engine with all sources
        let workspaceRoot = findWorkspaceRoot() ?? "."
        let registry = SessionRegistry(
            discoverer: TmuxDiscoverer(),
            journal: SessionJournal()
        )

        let engine = PaletteEngine(sources: [
            SessionSource(registry: registry),
            CommandSource(),
            FeatureSource(workspaceRoot: workspaceRoot),
            BranchSource(workspaceRoot: workspaceRoot),
        ])

        // State
        var currentQuery = query ?? ""
        var selectedIndex = 0
        var results: [PaletteResult] = []
        var scope: String? = nil

        // Initial search
        let initial = await engine.searchWithPrefix(rawQuery: currentQuery)
        switch initial {
        case .results(let r): results = r
        case .scopeChange(let s): scope = s
        }

        // Enter raw mode
        let raw = RawMode()
        defer {
            raw.restore()
            TerminalOutput.showCursor()
        }

        TerminalOutput.hideCursor()

        // Render loop
        while true {
            TerminalOutput.clearScreen()
            PaletteRenderer.render(
                query: currentQuery,
                results: results,
                selectedIndex: selectedIndex,
                scope: scope
            )

            let key = TerminalInput.readKey()

            switch key {
            case .escape:
                TerminalOutput.clearScreen()
                return

            case .up:
                if selectedIndex > 0 { selectedIndex -= 1 }

            case .down:
                if selectedIndex < results.count - 1 { selectedIndex += 1 }

            case .tab:
                // Cycle through scope prefixes
                let prefixes = ["", "s:", ">", "f:", "b:"]
                if let currentPrefix = prefixes.first(where: { currentQuery.hasPrefix($0) && !$0.isEmpty }) {
                    let idx = prefixes.firstIndex(of: currentPrefix) ?? 0
                    let nextIdx = (idx + 1) % prefixes.count
                    // Strip current prefix and add next
                    let stripped = String(currentQuery.dropFirst(currentPrefix.count))
                    currentQuery = prefixes[nextIdx] + stripped
                } else {
                    // No prefix currently — add first one
                    currentQuery = "s:" + currentQuery
                }
                selectedIndex = 0
                let searchResult = await engine.searchWithPrefix(rawQuery: currentQuery)
                switch searchResult {
                case .results(let r): results = r; scope = nil
                case .scopeChange(let s): scope = s; results = []
                }

            case .enter:
                guard selectedIndex < results.count else { continue }
                let selected = results[selectedIndex]
                TerminalOutput.clearScreen()
                TerminalOutput.showCursor()
                raw.restore()
                executeAction(for: selected)
                return

            case .backspace:
                if !currentQuery.isEmpty {
                    currentQuery.removeLast()
                    selectedIndex = 0
                    let searchResult = await engine.searchWithPrefix(rawQuery: currentQuery)
                    switch searchResult {
                    case .results(let r): results = r; scope = nil
                    case .scopeChange(let s): scope = s; results = []
                    }
                }

            case .char(let c):
                currentQuery.append(c)
                selectedIndex = 0
                let searchResult = await engine.searchWithPrefix(rawQuery: currentQuery)
                switch searchResult {
                case .results(let r): results = r; scope = nil
                case .scopeChange(let s): scope = s; results = []
                }

            default:
                continue
            }
        }
    }

    // MARK: - Action Execution

    private func executeAction(for result: PaletteResult) {
        switch result.category {
        case "session":
            // Attach to tmux session
            let windowName = result.title
            let shikiPath = resolveShikiBinary()
            execCommand(shikiPath, arguments: [shikiPath, "attach", windowName])

        case "command":
            // Run shiki subcommand
            let shikiPath = resolveShikiBinary()
            execCommand(shikiPath, arguments: [shikiPath, result.title])

        case "feature":
            // Open feature file in editor
            let editor = ProcessInfo.processInfo.environment["EDITOR"] ?? "less"
            let path = "features/\(result.title).md"
            execCommand("/usr/bin/env", arguments: ["/usr/bin/env", editor, path])

        case "branch":
            // Checkout branch
            execCommand("/usr/bin/env", arguments: ["/usr/bin/env", "git", "checkout", result.title])

        default:
            print("\(ANSI.dim)Selected: \(result.title)\(ANSI.reset)")
        }
    }

    // MARK: - Helpers

    private func resolveShikiBinary() -> String {
        let binaryPath = ProcessInfo.processInfo.arguments.first ?? "/usr/local/bin/shiki"
        return (binaryPath as NSString).resolvingSymlinksInPath
    }

    private func execCommand(_ path: String, arguments: [String]) {
        let cArgs = arguments.map { strdup($0) } + [nil]
        defer { cArgs.forEach { free($0) } }
        execv(path, cArgs)
        // If execv returns, it failed
        fputs("Failed to exec: \(path)\n", stderr)
    }

    private func findWorkspaceRoot() -> String? {
        var dir = FileManager.default.currentDirectoryPath
        while dir != "/" {
            if FileManager.default.fileExists(atPath: "\(dir)/.git") {
                return dir
            }
            dir = (dir as NSString).deletingLastPathComponent
        }
        return nil
    }

    private func printNonInteractive() {
        print("\(ANSI.dim)Command palette requires an interactive terminal.\(ANSI.reset)")
        print("Usage: shiki search [query]")
    }
}
