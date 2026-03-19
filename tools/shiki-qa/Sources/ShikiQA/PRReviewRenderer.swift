import ShikiCtlKit

enum PRReviewRenderer {

    // MARK: - Render Screen

    static func render(engine: PRReviewEngine) {
        switch engine.currentScreen {
        case .modeSelection:
            renderModeSelection(engine: engine)
        case .riskMap:
            renderRiskMap(engine: engine)
        case .sectionList:
            renderSectionList(engine: engine)
        case .sectionView(let idx):
            renderSectionView(engine: engine, sectionIndex: idx)
        case .commentInput(let idx):
            renderCommentInput(engine: engine, sectionIndex: idx)
        case .summary:
            renderSummary(engine: engine)
        case .done:
            break
        }
    }

    // MARK: - Mode Selection

    private static func renderModeSelection(engine: PRReviewEngine) {
        TerminalOutput.clearScreen()
        let width = TerminalOutput.terminalWidth()

        printHeader(engine.review, width: width)
        print()
        print("  \(ANSI.bold)Review Mode\(ANSI.reset)")
        print("  \(ANSI.dim)\(String(repeating: "\u{2500}", count: 30))\(ANSI.reset)")
        print()
        print("  \(ANSI.cyan)>\(ANSI.reset) \(ANSI.bold)Full review\(ANSI.reset) — read each section, set verdicts")
        print("    \(ANSI.dim)(Press Enter to start)\(ANSI.reset)")
        print()
        printFooter(keys: "[Enter] Start  [q] Quit")
    }

    // MARK: - Risk Map

    private static func renderRiskMap(engine: PRReviewEngine) {
        TerminalOutput.clearScreen()
        let width = TerminalOutput.terminalWidth()

        printHeader(engine.review, width: width)
        print()
        print("  \(ANSI.bold)Risk Triage\(ANSI.reset)")
        print("  \(ANSI.dim)\(String(repeating: "\u{2500}", count: 40))\(ANSI.reset)")
        print()

        let grouped = Dictionary(grouping: engine.riskFiles, by: { $0.risk })

        for level in [RiskLevel.high, .medium, .low, .skip] {
            guard let files = grouped[level], !files.isEmpty else { continue }
            let icon = riskIcon(level)
            let label = riskLabel(level)
            print("  \(icon) \(ANSI.bold)\(label)\(ANSI.reset) (\(files.count) file\(files.count == 1 ? "" : "s"))")
            let maxShow = level == .skip ? 3 : files.count
            for file in files.prefix(maxShow) {
                let reasons = file.reasons.isEmpty ? "" : " \(ANSI.dim)\(file.reasons.first ?? "")\(ANSI.reset)"
                let changes = "\(ANSI.green)+\(file.file.insertions)\(ANSI.reset)/\(ANSI.red)-\(file.file.deletions)\(ANSI.reset)"
                print("    \(TerminalOutput.pad(file.file.path, 45)) \(changes)\(reasons)")
            }
            if files.count > maxShow {
                print("    \(ANSI.dim)... and \(files.count - maxShow) more\(ANSI.reset)")
            }
            print()
        }

        printFooter(keys: "[Enter] Continue to sections  [q] Quit")
    }

    private static func riskIcon(_ level: RiskLevel) -> String {
        switch level {
        case .high:   return "\(ANSI.red)\u{25CF}\(ANSI.reset)"
        case .medium: return "\(ANSI.yellow)\u{25CF}\(ANSI.reset)"
        case .low:    return "\(ANSI.green)\u{25CF}\(ANSI.reset)"
        case .skip:   return "\(ANSI.dim)\u{25CB}\(ANSI.reset)"
        }
    }

    private static func riskLabel(_ level: RiskLevel) -> String {
        switch level {
        case .high:   return "\(ANSI.red)HIGH RISK\(ANSI.reset)"
        case .medium: return "\(ANSI.yellow)MEDIUM\(ANSI.reset)"
        case .low:    return "\(ANSI.green)LOW\(ANSI.reset)"
        case .skip:   return "\(ANSI.dim)SKIP\(ANSI.reset)"
        }
    }

    // MARK: - Section List

    private static func renderSectionList(engine: PRReviewEngine) {
        TerminalOutput.clearScreen()
        let width = TerminalOutput.terminalWidth()

        printHeader(engine.review, width: width)
        print()
        print("  \(ANSI.bold)Sections\(ANSI.reset)")
        print("  \(ANSI.dim)\(String(repeating: "\u{2500}", count: 30))\(ANSI.reset)")

        for (i, section) in engine.review.sections.enumerated() {
            let isSelected = i == engine.selectedIndex
            let prefix = isSelected ? "\(ANSI.cyan)  \u{25B6} " : "    "
            let badge = verdictBadge(engine.state.verdicts[i])
            let title = isSelected
                ? "\(ANSI.bold)\(section.title)\(ANSI.reset)"
                : section.title
            let qCount = section.questions.isEmpty
                ? ""
                : " \(ANSI.dim)(\(section.questions.count)q)\(ANSI.reset)"

            print("\(prefix)\(badge) \(title)\(qCount)\(isSelected ? ANSI.reset : "")")
        }

        print()
        let counts = engine.state.verdictCounts()
        let progress = "\(ANSI.dim)\(engine.state.reviewedCount)/\(engine.review.sections.count) reviewed\(ANSI.reset)"
        let stats = " \(ANSI.green)\(counts.approved)\u{2713}\(ANSI.reset) \(ANSI.yellow)\(counts.comment)\u{270E}\(ANSI.reset) \(ANSI.red)\(counts.requestChanges)\u{2717}\(ANSI.reset)"
        print("  \(progress)\(stats)")
        print()
        printFooter(keys: "[\u{2191}\u{2193}] Navigate  [Enter] Open  [s] Summary  [q] Quit")
    }

    // MARK: - Section View

    private static func renderSectionView(engine: PRReviewEngine, sectionIndex: Int) {
        TerminalOutput.clearScreen()
        let section = engine.review.sections[sectionIndex]
        let width = TerminalOutput.terminalWidth()

        // Section header
        print("  \(ANSI.bold)\(ANSI.cyan)Section \(section.index): \(section.title)\(ANSI.reset)")
        print("  \(ANSI.dim)\(String(repeating: "\u{2550}", count: min(width - 4, 60)))\(ANSI.reset)")
        print()

        // Body content (paginated by terminal height)
        let maxBodyLines = TerminalOutput.terminalHeight() - 12
        let bodyLines = section.body.components(separatedBy: "\n")
        let displayLines = Array(bodyLines.prefix(maxBodyLines))
        for line in displayLines {
            print("  \(line)")
        }
        if bodyLines.count > maxBodyLines {
            print("  \(ANSI.dim)... (\(bodyLines.count - maxBodyLines) more lines)\(ANSI.reset)")
        }

        // Review questions
        if !section.questions.isEmpty {
            print()
            print("  \(ANSI.bold)Review Questions:\(ANSI.reset)")
            for (i, q) in section.questions.enumerated() {
                print("  \(ANSI.yellow)\(i + 1).\(ANSI.reset) \(q.text)")
            }
        }

        // Current verdict
        if let verdict = engine.state.verdicts[sectionIndex] {
            print()
            print("  Current verdict: \(verdictBadge(verdict)) \(verdict.rawValue)")
        }

        print()
        printFooter(keys: "[a] Approve  [c] Comment  [r] Request Changes  [Esc] Back")
    }

    // MARK: - Comment Input

    private static func renderCommentInput(engine: PRReviewEngine, sectionIndex: Int) {
        TerminalOutput.clearScreen()
        let width = TerminalOutput.terminalWidth()
        let section = engine.review.sections[sectionIndex]

        printHeader(engine.review, width: width)
        print("\(ANSI.bold)Comment on: \(section.title)\(ANSI.reset)")
        print(String(repeating: "\u{2500}", count: width))
        print()

        // Show existing comment if any
        if let existing = engine.state.comments[sectionIndex] {
            print("\(ANSI.dim)Previous: \(existing)\(ANSI.reset)")
            print()
        }

        // Show the input buffer with cursor
        print("\(ANSI.bold)Your comment:\(ANSI.reset)")
        print()
        let buffer = engine.commentBuffer
        print("  \(buffer)\(ANSI.inverse) \(ANSI.reset)")
        print()
        print("\(ANSI.dim)[Enter] Save  [Esc] Cancel\(ANSI.reset)")
    }

    // MARK: - Summary

    private static func renderSummary(engine: PRReviewEngine) {
        TerminalOutput.clearScreen()
        let width = TerminalOutput.terminalWidth()

        print("  \(ANSI.bold)Review Summary\(ANSI.reset)")
        print("  \(ANSI.dim)\(String(repeating: "\u{2550}", count: min(width - 4, 60)))\(ANSI.reset)")
        print()

        printHeader(engine.review, width: width)
        print()

        // Section verdicts table
        for section in engine.review.sections {
            let badge = verdictBadge(engine.state.verdicts[section.index])
            let verdictText = engine.state.verdicts[section.index]?.rawValue ?? "pending"
            print("  \(badge) \(TerminalOutput.pad(section.title, 40)) \(verdictText)")
        }

        print()
        let counts = engine.state.verdictCounts()
        let total = engine.review.sections.count
        print("  \(ANSI.bold)Totals:\(ANSI.reset) \(ANSI.green)\(counts.approved) approved\(ANSI.reset), \(ANSI.yellow)\(counts.comment) comments\(ANSI.reset), \(ANSI.red)\(counts.requestChanges) changes requested\(ANSI.reset)")
        let pending = total - engine.state.reviewedCount
        if pending > 0 {
            print("  \(ANSI.dim)\(pending) section(s) not yet reviewed\(ANSI.reset)")
        }

        print()
        printFooter(keys: "[Esc] Back to sections  [q] Quit & save")
    }

    // MARK: - Helpers

    private static func printHeader(_ review: PRReview, width: Int) {
        print("  \(ANSI.bold)\(review.title)\(ANSI.reset)")
        if !review.branch.isEmpty {
            print("  \(ANSI.dim)Branch: \(review.branch) | Files: \(review.filesChanged) | Tests: \(review.testsInfo)\(ANSI.reset)")
        }
    }

    private static func printFooter(keys: String) {
        print("  \(ANSI.dim)\(keys)\(ANSI.reset)")
    }

    private static func verdictBadge(_ verdict: SectionVerdict?) -> String {
        switch verdict {
        case .approved:
            return "\(ANSI.green)\u{2713}\(ANSI.reset)"
        case .comment:
            return "\(ANSI.yellow)\u{270E}\(ANSI.reset)"
        case .requestChanges:
            return "\(ANSI.red)\u{2717}\(ANSI.reset)"
        case nil:
            return "\(ANSI.dim)\u{25CB}\(ANSI.reset)"
        }
    }
}
