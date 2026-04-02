import ArgumentParser
import Foundation
import ShikkiKit

/// BR-EM-15: Undo via checkpoint.
/// ⏪ shows the last checkpoint and offers to restore it.
///
/// Usage:
///   shi undo           — show last checkpoint info
///   shi undo <uuid>    — (placeholder) restore a specific checkpoint by ID
struct UndoCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "undo",
        abstract: "⏪ Show last checkpoint and offer to restore"
    )

    @Argument(help: "Checkpoint UUID to restore (optional; without it, shows latest)")
    var checkpointID: String?

    /// Injected for testing.
    var checkpointDirectory: String? = nil

    func run() async throws {
        let manager = CheckpointManager(directory: checkpointDirectory)

        guard let checkpoint = try manager.load() else {
            print("\(ANSI.dim)No checkpoint found. Nothing to undo.\(ANSI.reset)")
            print("  \(ANSI.dim)Checkpoints are created automatically during sessions.\(ANSI.reset)")
            return
        }

        // Display checkpoint info
        let formatter = ISO8601DateFormatter()
        let timestampStr = formatter.string(from: checkpoint.timestamp)
        let stateLabel = checkpoint.fsmState.rawValue

        print("\(ANSI.bold)⏪ Last checkpoint\(ANSI.reset)")
        print("  Saved:    \(ANSI.cyan)\(timestampStr)\(ANSI.reset)")
        print("  State:    \(ANSI.yellow)\(stateLabel)\(ANSI.reset)")
        if let snippet = checkpoint.contextSnippet {
            let preview = snippet.prefix(120)
            print("  Context:  \(ANSI.dim)\(preview)\(ANSI.reset)")
        }
        if let stats = checkpoint.sessionStats {
            print("  Branch:   \(ANSI.dim)\(stats.branch)\(ANSI.reset)")
        }
        print()

        if let uuid = checkpointID {
            // Placeholder: actual restore logic delegates to CheckpointManager.restore()
            // when that API is available (BR-EM-15).
            print("\(ANSI.yellow)Restore checkpoint '\(uuid)' — not yet implemented.\(ANSI.reset)")
            print("  \(ANSI.dim)Full restore support coming in ShikiCore Wave 2.\(ANSI.reset)")
        } else {
            // Offer interactive restore
            print("Restore this checkpoint? [y/N] ", terminator: "")
            fflush(stdout)

            guard let response = readLine()?.trimmingCharacters(in: .whitespaces).lowercased(),
                  response == "y" || response == "yes" else {
                print("\(ANSI.dim)No changes made.\(ANSI.reset)")
                return
            }

            // Placeholder — full restore will re-launch tmux layout from checkpoint
            print("\(ANSI.yellow)Checkpoint restore — not yet implemented.\(ANSI.reset)")
            print("  \(ANSI.dim)Full restore support coming in ShikiCore Wave 2.\(ANSI.reset)")
        }
    }
}
