// ProgressRenderer.swift — Live progress during parallel execution
// Part of ShikkiTestRunner

import Foundation

/// Tracks live progress state for a single scope.
public struct ScopeProgress: Sendable {
    public let scope: TestScope
    public var completed: Int
    public var total: Int
    public var isRunning: Bool
    public var result: ScopeResult?

    public init(scope: TestScope, total: Int = 0) {
        self.scope = scope
        self.completed = 0
        self.total = total
        self.isRunning = false
        self.result = nil
    }
}

/// Output target protocol for terminal rendering. Abstracted for testing.
public protocol TerminalOutput: Sendable {
    func write(_ text: String) async
}

/// Real terminal output that writes to stdout.
public struct StdoutTerminalOutput: TerminalOutput {
    public init() {}

    public func write(_ text: String) async {
        print(text, terminator: "")
        fflush(stdout)
    }
}

/// Actor that renders live progress lines during parallel execution.
///
/// During execution shows:
///   `◇ NATS          running...  [12/57]`
///
/// When scope completes, collapses to one-liner:
///   `◆ Flywheel      0.2s        80/80`
///
/// Uses terminal cursor control (ANSI escape codes) to update in-place.
public actor ProgressRenderer {
    private var scopeStates: [String: ScopeProgress] = [:]
    private var scopeOrder: [String] = []
    private let output: any TerminalOutput
    private var lastRenderedLineCount: Int = 0

    /// Running diamond marker.
    public static let runningMarker = "\u{25C7}"  // ◇
    /// Completed diamond marker.
    public static let completedMarker = "\u{25C6}" // ◆

    public init(output: any TerminalOutput = StdoutTerminalOutput()) {
        self.output = output
    }

    /// Register a scope as started.
    public func scopeStarted(_ scope: TestScope) async {
        let state = ScopeProgress(scope: scope, total: scope.expectedTestCount)
        scopeStates[scope.name] = state
        if !scopeOrder.contains(scope.name) {
            scopeOrder.append(scope.name)
        }
        scopeStates[scope.name]?.isRunning = true
        await render()
    }

    /// Update progress for a running scope.
    public func scopeProgress(_ scope: TestScope, completed: Int, total: Int) async {
        scopeStates[scope.name]?.completed = completed
        scopeStates[scope.name]?.total = total
        await render()
    }

    /// Mark a scope as finished with its result.
    public func scopeFinished(_ scope: TestScope, result: ScopeResult) async {
        scopeStates[scope.name]?.isRunning = false
        scopeStates[scope.name]?.completed = result.total
        scopeStates[scope.name]?.total = result.total
        scopeStates[scope.name]?.result = result
        await render()
    }

    /// Get the current rendered text without ANSI cursor control (for testing).
    public func currentSnapshot() -> String {
        var lines: [String] = []

        for name in scopeOrder {
            guard let state = scopeStates[name] else { continue }
            lines.append(renderLine(state))
        }

        return lines.joined(separator: "\n")
    }

    /// Clear all progress state.
    public func reset() {
        scopeStates.removeAll()
        scopeOrder.removeAll()
        lastRenderedLineCount = 0
    }

    // MARK: - Private Rendering

    private func render() async {
        // Move cursor up to overwrite previous output
        if lastRenderedLineCount > 0 {
            let moveUp = "\u{1B}[\(lastRenderedLineCount)A\u{1B}[0G"
            await output.write(moveUp)
        }

        var lines: [String] = []
        for name in scopeOrder {
            guard let state = scopeStates[name] else { continue }
            lines.append(renderLine(state))
        }

        let text = lines.joined(separator: "\n") + "\n"
        await output.write(text)
        lastRenderedLineCount = lines.count
    }

    private func renderLine(_ state: ScopeProgress) -> String {
        let name = state.scope.name.padding(toLength: 14, withPad: " ", startingAt: 0)

        if let result = state.result {
            // Completed line: ◆ Flywheel      0.2s        80/80
            let duration = formatDuration(result.durationMs)
            let durationPadded = duration.padding(toLength: 10, withPad: " ", startingAt: 0)
            return "\(Self.completedMarker) \(name) \(durationPadded) \(result.passed)/\(result.total)"
        } else if state.isRunning {
            // Running line: ◇ NATS          running...  [12/57]
            let progress = state.total > 0
                ? "[\(state.completed)/\(state.total)]"
                : "[...]"
            return "\(Self.runningMarker) \(name) running...  \(progress)"
        } else {
            // Pending (not yet started)
            return "\(Self.runningMarker) \(name) pending..."
        }
    }

    private func formatDuration(_ ms: Int) -> String {
        if ms < 1000 {
            return "0.\(ms / 100)s"
        } else if ms < 60000 {
            let seconds = Double(ms) / 1000.0
            return String(format: "%.1fs", seconds)
        } else {
            let minutes = ms / 60000
            let seconds = (ms % 60000) / 1000
            return "\(minutes)m\(seconds)s"
        }
    }
}

/// Adapter that bridges ProgressRenderer to the ExecutionProgressDelegate protocol.
public struct ProgressRendererDelegate: ExecutionProgressDelegate {
    private let renderer: ProgressRenderer

    public init(renderer: ProgressRenderer) {
        self.renderer = renderer
    }

    public func scopeStarted(_ scope: TestScope) async {
        await renderer.scopeStarted(scope)
    }

    public func scopeProgress(_ scope: TestScope, completed: Int, total: Int) async {
        await renderer.scopeProgress(scope, completed: completed, total: total)
    }

    public func scopeFinished(_ scope: TestScope, result: ScopeResult) async {
        await renderer.scopeFinished(scope, result: result)
    }
}
