import Foundation

/// Event emitted when a CLI command completes execution.
///
/// Bridges `CommandLogEntry` (JSONL persistence) with the event bus.
/// Can be converted to a `ShikkiEvent` for the observable data stream.
public struct CommandInvokedEvent: Codable, Sendable {
    /// The command that was invoked (e.g. "shi inbox", "shi spec").
    public let command: String
    /// Workspace name (detected from cwd), if any.
    public let workspace: String?
    /// Execution time in milliseconds.
    public let durationMs: Int
    /// Process exit code (0 = success).
    public let exitCode: Int32
    /// When the command was invoked.
    public let timestamp: Date

    public init(
        command: String,
        workspace: String?,
        durationMs: Int,
        exitCode: Int32,
        timestamp: Date = Date()
    ) {
        self.command = command
        self.workspace = workspace
        self.durationMs = durationMs
        self.exitCode = exitCode
        self.timestamp = timestamp
    }
}
