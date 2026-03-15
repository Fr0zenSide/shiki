import ArgumentParser
import Foundation
import ShikiCtlKit

struct DecideCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "decide",
        abstract: "Answer pending T1 decisions"
    )

    @Option(name: .long, help: "Backend URL")
    var url: String = "http://localhost:3900"

    @Option(name: .long, help: "Answerer identity")
    var answeredBy: String = "shiki-ctl"

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
            print("No pending decisions.")
            return
        }

        // Group by company
        let grouped = Dictionary(grouping: decisions, by: { $0.companySlug ?? "unknown" })

        for (slug, questions) in grouped.sorted(by: { $0.key < $1.key }) {
            print()
            print("\u{1B}[1m## \(slug)\u{1B}[0m")
            for (i, q) in questions.enumerated() {
                let tierColor = q.tier == 1 ? "\u{1B}[31m" : "\u{1B}[33m"
                print("  \(tierColor)T\(q.tier)\u{1B}[0m Q\(i + 1): \(q.question)")
                if let options = q.options {
                    for (key, value) in options.sorted(by: { $0.key < $1.key }) {
                        print("    (\(key)) \(value)")
                    }
                }
                if let context = q.context {
                    print("    \u{1B}[2mContext: \(context)\u{1B}[0m")
                }
            }
        }

        print()
        print("\u{1B}[2mEnter answers one at a time. Type 'skip' to defer, 'quit' to exit.\u{1B}[0m")

        let allDecisions = grouped.sorted(by: { $0.key < $1.key }).flatMap(\.value)

        for (i, decision) in allDecisions.enumerated() {
            let slug = decision.companySlug ?? "?"
            print()
            print("\u{1B}[1m[\(slug)] Q\(i + 1)\u{1B}[0m: \(decision.question)")
            print("Answer: ", terminator: "")

            guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines), !input.isEmpty else {
                continue
            }

            if input.lowercased() == "quit" {
                print("Exiting.")
                break
            }

            if input.lowercased() == "skip" {
                print("  Skipped.")
                continue
            }

            do {
                let answered = try await client.answerDecision(
                    id: decision.id,
                    answer: input,
                    answeredBy: answeredBy
                )
                print("  \u{1B}[32mAnswered\u{1B}[0m (task \(answered.taskId ?? "none") may unblock)")
            } catch {
                print("  \u{1B}[31mFailed:\u{1B}[0m \(error)")
            }
        }

        try await client.shutdown()
    }
}
