import ShikkiKit

enum StatusRenderer {

    /// Render the new dispatcher-style status: active, queued, idle groupings.
    static func renderDispatcherStatus(companies: [Company]) {
        let active = companies.filter { ($0.runningTasks ?? 0) > 0 }
        let queued = companies.filter { ($0.runningTasks ?? 0) == 0 && ($0.pendingTasks ?? 0) > 0 }
        let idle = companies.filter { ($0.runningTasks ?? 0) == 0 && ($0.pendingTasks ?? 0) == 0 }

        let total = companies.count
        print("\u{1B}[1mOverview:\u{1B}[0m \(total) companies | \(active.count) active | \(queued.count) queued | \(idle.count) idle")
        print()

        if !active.isEmpty {
            print("\u{1B}[1m\u{1B}[32mActive:\u{1B}[0m")
            for c in active {
                let healthInfo = formatHealthInfo(c)
                let spendInfo = formatSpend(c)
                let projects = c.companyProjects.count
                let projectSuffix = projects > 1 ? " (\(projects) projects)" : ""
                print("  \(pad(c.slug, 20)) \(healthInfo)  \(spendInfo)\(projectSuffix)")
            }
            print()
        }

        if !queued.isEmpty {
            print("\u{1B}[1m\u{1B}[33mQueued:\u{1B}[0m")
            for c in queued {
                let pending = c.pendingTasks ?? 0
                let taskWord = pending == 1 ? "task" : "tasks"
                let spendInfo = formatSpend(c)
                print("  \(pad(c.slug, 20)) \(pending) pending \(taskWord)\(String(repeating: " ", count: max(0, 22 - "\(pending) pending \(taskWord)".count)))  \(spendInfo)")
            }
            print()
        }

        if !idle.isEmpty {
            print("\u{1B}[1m\u{1B}[2mIdle:\u{1B}[0m")
            for c in idle {
                let spendInfo = formatSpend(c)
                print("  \(pad(c.slug, 20)) 0 pending tasks\(String(repeating: " ", count: 7))  \(spendInfo)")
            }
            print()
        }
    }

    /// Legacy table format.
    static func renderCompanyTable(_ companies: [Company]) {
        let header = [
            pad("Slug", 15), pad("Status", 8), pad("Pri", 4),
            pad("Pend", 5), pad("Run", 5), pad("Blk", 5),
            pad("Done", 5), pad("Health", 8),
        ].joined(separator: " ")
        print("\u{1B}[1m\(header)\u{1B}[0m")

        for c in companies {
            let healthColor: String
            switch c.heartbeatStatus {
            case "healthy": healthColor = "\u{1B}[32m"
            case "stale": healthColor = "\u{1B}[33m"
            case "dead": healthColor = "\u{1B}[31m"
            default: healthColor = "\u{1B}[2m"
            }

            let row = [
                pad(c.slug, 15),
                pad(c.status.rawValue, 8),
                pad("\(c.priority)", 4),
                pad("\(c.pendingTasks ?? 0)", 5),
                pad("\(c.runningTasks ?? 0)", 5),
                pad("\(c.blockedTasks ?? 0)", 5),
                pad("\(c.completedTasks ?? 0)", 5),
                "\(healthColor)\(c.heartbeatStatus ?? "unknown")\u{1B}[0m",
            ].joined(separator: " ")
            print(row)
        }
    }

    // MARK: - Attention Zones

    /// Format an attention zone with ANSI gradient: bright for urgent, dim for idle.
    static func formatAttentionZone(_ zone: AttentionZone) -> String {
        switch zone {
        case .merge:   return "\u{1B}[1m\u{1B}[32m MERGE \u{1B}[0m"
        case .respond: return "\u{1B}[1m\u{1B}[31mRESPOND\u{1B}[0m"
        case .review:  return "\u{1B}[1m\u{1B}[33mREVIEW \u{1B}[0m"
        case .pending: return "\u{1B}[33mPENDING\u{1B}[0m"
        case .working: return "\u{1B}[36mWORKING\u{1B}[0m"
        case .idle:    return "\u{1B}[2m  IDLE \u{1B}[0m"
        }
    }

    // MARK: - Helpers

    private static func formatHealthInfo(_ c: Company) -> String {
        let status = c.heartbeatStatus ?? "unknown"
        let color: String
        switch status {
        case "healthy": color = "\u{1B}[32m"
        case "stale": color = "\u{1B}[33m"
        case "dead": color = "\u{1B}[31m"
        default: color = "\u{1B}[2m"
        }
        let running = c.runningTasks ?? 0
        let blocked = c.blockedTasks ?? 0
        var info = "\(color)\(status)\u{1B}[0m"
        if running > 0 { info += ", \(running) running" }
        if blocked > 0 { info += ", \(blocked) blocked" }
        return pad(info, 30)
    }

    private static func formatSpend(_ c: Company) -> String {
        let spent = c.budget.spentTodayUsd
        let daily = c.budget.dailyUsd
        return "$\(String(format: "%.0f", spent))/$\(String(format: "%.0f", daily))"
    }

    static func pad(_ string: String, _ width: Int) -> String {
        // Account for ANSI escape codes when padding
        let visibleLength = string.replacingOccurrences(
            of: "\u{1B}\\[[0-9;]*m", with: "",
            options: .regularExpression
        ).count
        if visibleLength >= width { return string }
        return string + String(repeating: " ", count: width - visibleLength)
    }
}
