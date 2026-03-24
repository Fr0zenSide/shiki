import ArgumentParser
import Foundation
import ShikiCtlKit

/// Reads multiline input from stdin.
/// Submission: an empty line (press Enter twice) finalizes input.
/// When pasting multiline text, lines are collected until an empty line appears.
/// Single-line answers (like "skip", "quit", or short replies) work naturally — just type and press Enter twice.
private func readMultilineInput() -> String {
    var lines: [String] = []
    while let line = readLine(strippingNewline: true) {
        if line.isEmpty && !lines.isEmpty {
            // Empty line after content = submit
            break
        }
        if line.isEmpty && lines.isEmpty {
            // Empty line with no content = skip
            break
        }
        lines.append(line)
    }
    return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
}

struct DecideCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "decide",
        abstract: "Answer pending decisions with ListReviewer TUI"
    )

    @Option(name: .long, help: "Backend URL")
    var url: String = "http://localhost:3900"

    @Option(name: .long, help: "Answerer identity")
    var answeredBy: String = "shiki-ctl"

    @Option(name: .long, help: "Filter by company slug")
    var company: String?

    @Flag(name: .long, help: "Output as JSON (pipe mode)")
    var json: Bool = false

    @Flag(name: .long, help: "Classic sequential mode (no ListReviewer)")
    var classic: Bool = false

    func run() async throws {
        let client = BackendClient(baseURL: url)

        let decisions: [Decision]
        do {
            decisions = try await client.getPendingDecisions()
        } catch {
            try? await client.shutdown()
            throw error
        }

        guard !decisions.isEmpty else {
            try await client.shutdown()
            if json {
                Swift.print("[]")
            } else {
                Swift.print("No pending decisions.")
            }
            return
        }

        // Filter by company if scoped
        let filtered: [Decision]
        if let scope = company {
            filtered = decisions.filter {
                ($0.companySlug ?? "").lowercased() == scope.lowercased()
                    || ($0.companyName ?? "").lowercased() == scope.lowercased()
            }
            guard !filtered.isEmpty else {
                try await client.shutdown()
                if json {
                    Swift.print("[]")
                } else {
                    Swift.print("No pending decisions for '\(scope)'.")
                }
                return
            }
        } else {
            filtered = decisions
        }

        // JSON pipe mode — render and exit
        if json {
            let items = DecideListReviewer.toListItems(filtered, companyScope: company)
            Swift.print(ListReviewer.renderJSON(items: items))
            try await client.shutdown()
            return
        }

        // Classic mode — original sequential UX
        if classic {
            try await runClassic(decisions: filtered, client: client)
            return
        }

        // ListReviewer mode — the new interactive TUI
        try await runListReviewer(decisions: filtered, client: client)
    }

    // MARK: - ListReviewer Mode

    private func runListReviewer(decisions: [Decision], client: BackendClient) async throws {
        var progress = DecideListReviewer.loadProgress() ?? DecideProgress()
        let config = DecideListReviewer.makeConfig(companyScope: company)

        var items = DecideListReviewer.toListItems(decisions, progress: progress, companyScope: company)

        // Render list
        ListReviewer.render(items: items, config: config)
        Swift.print()

        // Build a lookup from item id to decision
        let decisionMap = Dictionary(uniqueKeysWithValues: decisions.map { ($0.id, $0) })

        // Walk through pending items one by one
        let pendingItems = items.filter { !$0.status.isReviewed }
        guard !pendingItems.isEmpty else {
            Swift.print(styled("All decisions already reviewed.", .green))
            try await client.shutdown()
            return
        }

        Swift.print(styled(
            "Multiline input: press Enter twice (empty line) to submit.",
            .dim
        ))
        Swift.print()

        var actionLog: [(itemId: String, action: String)] = []

        for pending in pendingItems {
            guard let decision = decisionMap[pending.id] else { continue }

            // Show detail
            ListReviewer.renderDetail(item: pending, config: config)
            Swift.print()

            // Show options if available
            if let options = decision.options {
                for (key, value) in options.sorted(by: { $0.key < $1.key }) {
                    Swift.print("    (\(key)) \(value)")
                }
                Swift.print()
            }

            Swift.print(styled("Action [a]nswer [d]efer [k]ill [n]ext [q]uit: ", .dim), terminator: "")
            fflush(stdout)

            guard let actionInput = readLine()?.trimmingCharacters(in: .whitespaces).lowercased(),
                  let firstChar = actionInput.first else {
                continue
            }

            switch firstChar {
            case "a":
                // Answer — prompt for answer text
                Swift.print(styled("Answer (empty line to submit):", .dim))
                let answer = readMultilineInput()
                guard !answer.isEmpty else {
                    Swift.print(styled("  Skipped (empty answer).", .dim))
                    continue
                }

                do {
                    let answered = try await client.answerDecision(
                        id: decision.id,
                        answer: answer,
                        answeredBy: answeredBy
                    )
                    Swift.print(styled(
                        "  Answered (task \(answered.taskId ?? "none") may unblock)",
                        .green
                    ))
                    DecideListReviewer.recordAction(
                        progress: &progress,
                        decisionId: decision.id,
                        action: "answered",
                        answer: answer
                    )
                    actionLog.append((itemId: decision.id, action: "answered"))
                } catch {
                    Swift.print(styled("  Failed: \(error)", .red))
                }

            case "d":
                // Defer
                Swift.print(styled("  Deferred.", .dim))
                DecideListReviewer.recordAction(
                    progress: &progress,
                    decisionId: decision.id,
                    action: "deferred"
                )
                actionLog.append((itemId: decision.id, action: "deferred"))

            case "k":
                // Dismiss (kill)
                Swift.print(styled("  Dismissed.", .dim))
                DecideListReviewer.recordAction(
                    progress: &progress,
                    decisionId: decision.id,
                    action: "dismissed"
                )
                actionLog.append((itemId: decision.id, action: "dismissed"))

            case "n":
                // Next — skip without recording
                continue

            case "q":
                // Quit
                Swift.print("Exiting.")
                break

            default:
                Swift.print(styled("  Unknown action '\(firstChar)', skipping.", .dim))
                continue
            }

            // Break out of loop on quit
            if firstChar == "q" { break }

            Swift.print()
        }

        // Save progress
        try? DecideListReviewer.saveProgress(progress)

        // Final summary
        items = DecideListReviewer.toListItems(decisions, progress: progress, companyScope: company)
        Swift.print()
        Swift.print(styled("Session summary:", .bold))
        let reviewed = items.filter(\.status.isReviewed).count
        Swift.print(ListReviewer.progressBar(done: reviewed, total: items.count))
        if !actionLog.isEmpty {
            let answered = actionLog.filter { $0.action == "answered" }.count
            let deferred = actionLog.filter { $0.action == "deferred" }.count
            let dismissed = actionLog.filter { $0.action == "dismissed" }.count
            Swift.print(styled(
                "  \(answered) answered, \(deferred) deferred, \(dismissed) dismissed",
                .dim
            ))
        }

        try await client.shutdown()
    }

    // MARK: - Classic Mode (backward compatible)

    private func runClassic(decisions: [Decision], client: BackendClient) async throws {
        // Group by company
        let grouped = Dictionary(grouping: decisions, by: { $0.companySlug ?? "unknown" })

        for (slug, questions) in grouped.sorted(by: { $0.key < $1.key }) {
            Swift.print()
            Swift.print("\u{1B}[1m## \(slug)\u{1B}[0m")
            for (i, q) in questions.enumerated() {
                let tierColor = q.tier == 1 ? "\u{1B}[31m" : "\u{1B}[33m"
                Swift.print("  \(tierColor)T\(q.tier)\u{1B}[0m Q\(i + 1): \(q.question)")
                if let options = q.options {
                    for (key, value) in options.sorted(by: { $0.key < $1.key }) {
                        Swift.print("    (\(key)) \(value)")
                    }
                }
                if let context = q.context {
                    Swift.print("    \u{1B}[2mContext: \(context)\u{1B}[0m")
                }
            }
        }

        Swift.print()
        Swift.print("\u{1B}[2mMultiline input: press Enter twice (empty line) to submit. 'skip' to defer, 'quit' to exit.\u{1B}[0m")

        let allDecisions = grouped.sorted(by: { $0.key < $1.key }).flatMap(\.value)

        for (i, decision) in allDecisions.enumerated() {
            let slug = decision.companySlug ?? "?"
            Swift.print()
            Swift.print("\u{1B}[1m[\(slug)] Q\(i + 1)\u{1B}[0m: \(decision.question)")
            Swift.print("\u{1B}[2mAnswer (empty line to submit):\u{1B}[0m")

            let input = readMultilineInput()

            guard !input.isEmpty else {
                continue
            }

            if input.lowercased() == "quit" {
                Swift.print("Exiting.")
                break
            }

            if input.lowercased() == "skip" {
                Swift.print("  Skipped.")
                continue
            }

            do {
                let answered = try await client.answerDecision(
                    id: decision.id,
                    answer: input,
                    answeredBy: answeredBy
                )
                Swift.print("  \u{1B}[32mAnswered\u{1B}[0m (task \(answered.taskId ?? "none") may unblock)")
            } catch {
                Swift.print("  \u{1B}[31mFailed:\u{1B}[0m \(error)")
            }
        }

        try await client.shutdown()
    }
}
