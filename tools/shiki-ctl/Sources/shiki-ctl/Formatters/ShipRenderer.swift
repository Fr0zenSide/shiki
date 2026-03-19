import Foundation
import ShikiCtlKit

// MARK: - ShipRenderer

/// Renders the Preflight Glow manifest and Silent River status line.
/// All output goes to stderr (stdout may be piped).
enum ShipRenderer {

    // MARK: - Preflight Glow

    /// Render the single-screen preflight manifest.
    static func renderPreflight(
        branch: String,
        target: String,
        currentVersion: String,
        nextVersion: String,
        commitCount: Int,
        isDryRun: Bool,
        why: String?
    ) {
        let mode = isDryRun ? " \u{1B}[33m[DRY RUN]\u{1B}[0m" : ""
        let lines = [
            "",
            "\u{1B}[1m--- Ship Preflight ---\u{1B}[0m\(mode)",
            "",
            "  Branch:   \u{1B}[36m\(branch)\u{1B}[0m",
            "  Target:   \u{1B}[36m\(target)\u{1B}[0m",
            "  Version:  \(currentVersion) -> \u{1B}[1m\(nextVersion)\u{1B}[0m",
            "  Commits:  \(commitCount)",
            why.map { "  Why:      \($0)" } ?? "  Why:      (not provided)",
            "",
            "\u{1B}[2m  8 gates will be evaluated\u{1B}[0m",
            "",
        ]
        for line in lines {
            writeStderr(line)
        }
    }

    // MARK: - Silent River (gate progress)

    /// Render a single gate progress line. Overwrites the previous line.
    static func renderGateProgress(
        gate: String,
        index: Int,
        total: Int,
        elapsed: TimeInterval?,
        result: GateResult?
    ) {
        let prefix = "[\(index + 1)/\(total)]"

        if let result {
            switch result {
            case .pass(let detail):
                let suffix = detail.map { " — \($0)" } ?? ""
                let elapsedStr = elapsed.map { String(format: " (%.1fs)", $0) } ?? ""
                writeStderr("\r\u{1B}[2K  \(prefix) \(gate)... \u{1B}[32m✓\u{1B}[0m\(elapsedStr)\(suffix)")

            case .warn(let reason):
                let elapsedStr = elapsed.map { String(format: " (%.1fs)", $0) } ?? ""
                writeStderr("\r\u{1B}[2K  \(prefix) \(gate)... \u{1B}[33m⚠\u{1B}[0m\(elapsedStr) — \(reason)")

            case .fail(let reason):
                let elapsedStr = elapsed.map { String(format: " (%.1fs)", $0) } ?? ""
                writeStderr("\r\u{1B}[2K  \(prefix) \(gate)... \u{1B}[31m✗\u{1B}[0m\(elapsedStr) — \(reason)")
            }
        } else {
            // In progress
            writeStderr("\r\u{1B}[2K  \(prefix) \(gate)...")
        }
    }

    // MARK: - Summary

    /// Render the final pipeline summary.
    static func renderSummary(result: ShipResult, elapsed: TimeInterval) {
        writeStderr("")
        if result.success {
            writeStderr("\u{1B}[1m\u{1B}[32m--- Ship Complete ---\u{1B}[0m \(String(format: "%.1fs", elapsed))")
            for warning in result.warnings {
                writeStderr("  \u{1B}[33m⚠ \(warning)\u{1B}[0m")
            }
        } else {
            writeStderr("\u{1B}[1m\u{1B}[31m--- Ship Aborted ---\u{1B}[0m \(String(format: "%.1fs", elapsed))")
            if let gate = result.failedGate, let reason = result.failureReason {
                writeStderr("  Failed at: \(gate)")
                writeStderr("  Reason: \(reason)")
            }
        }
        writeStderr("")
    }

    // MARK: - Helpers

    private static func writeStderr(_ message: String) {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
    }
}
