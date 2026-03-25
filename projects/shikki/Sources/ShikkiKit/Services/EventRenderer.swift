import Foundation

// MARK: - EventRenderer Protocol

/// Renders a ShikkiEvent to a string for output.
/// ANSIEventRenderer for TUI, JSONEventRenderer for piping.
public protocol EventRenderer: Sendable {
    func render(_ event: ShikkiEvent) -> String
}

// MARK: - ANSIEventRenderer

/// Renders events as colorized ANSI terminal lines.
/// Format: `[HH:MM:SS] {uuid8} company:agent scope what`
public struct ANSIEventRenderer: EventRenderer {

    public init() {}

    public func render(_ event: ShikkiEvent) -> String {
        let time = formatTimestamp(event.timestamp)
        let uuid8 = String(event.id.uuidString.prefix(8)).lowercased()
        let scope = formatScope(event.scope)
        let type = formatType(event.type)
        let summary = formatPayloadSummary(event)

        let companySlug = extractCompanySlug(from: event)
        let companyColor = Self.colorForCompany(companySlug)

        // [HH:MM:SS] {uuid8} company:scope  type  summary
        var parts: [String] = []
        parts.append("\(ANSI.dim)\(ANSI.white)[\(time)]\(ANSI.reset)")
        parts.append("\(ANSI.dim)\(uuid8)\(ANSI.reset)")
        parts.append("\(companyColor)\(ANSI.bold)\(companySlug)\(ANSI.reset):\(scope)")
        parts.append("\(ANSI.dim)\(ANSI.yellow)\(type)\(ANSI.reset)")
        if !summary.isEmpty {
            parts.append(highlightKeywords(summary))
        }

        return parts.joined(separator: " ")
    }

    // MARK: - Timestamp

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    func formatTimestamp(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }

    // MARK: - Scope

    func formatScope(_ scope: EventScope) -> String {
        switch scope {
        case .global: return "global"
        case .session(let id):
            // Show last part of session id (after colon)
            let parts = id.split(separator: ":")
            return parts.count > 1 ? String(parts.last!) : id
        case .project(let slug): return slug
        case .pr(let number): return "PR#\(number)"
        case .file(let path):
            return URL(fileURLWithPath: path).lastPathComponent
        }
    }

    // MARK: - Event Type

    func formatType(_ type: EventType) -> String {
        switch type {
        case .sessionStart: return "session"
        case .sessionEnd: return "session"
        case .sessionTransition: return "session"
        case .contextCompaction: return "context"
        case .heartbeat: return "heartbeat"
        case .companyDispatched: return "dispatch"
        case .companyStale: return "stale"
        case .companyRelaunched: return "relaunch"
        case .budgetExhausted: return "budget"
        case .decisionPending: return "decision"
        case .decisionAnswered: return "decision"
        case .decisionUnblocked: return "decision"
        case .codeChange: return "code"
        case .testRun: return "test"
        case .buildResult: return "build"
        case .prCacheBuilt: return "pr"
        case .prRiskAssessed: return "pr"
        case .prVerdictSet: return "pr"
        case .prFixSpawned: return "pr"
        case .prFixCompleted: return "pr"
        case .notificationSent: return "notify"
        case .notificationActioned: return "notify"
        case .shipStarted: return "ship"
        case .shipGateStarted: return "ship"
        case .shipGatePassed: return "ship"
        case .shipGateFailed: return "ship"
        case .shipCompleted: return "ship"
        case .shipAborted: return "ship"
        case .codeGenStarted: return "codegen"
        case .codeGenSpecParsed: return "codegen"
        case .codeGenContractVerified: return "codegen"
        case .codeGenPlanCreated: return "codegen"
        case .codeGenAgentDispatched: return "codegen"
        case .codeGenAgentCompleted: return "codegen"
        case .codeGenMergeStarted: return "codegen"
        case .codeGenMergeCompleted: return "codegen"
        case .codeGenFixStarted: return "codegen"
        case .codeGenFixCompleted: return "codegen"
        case .codeGenPipelineCompleted: return "codegen"
        case .codeGenPipelineFailed: return "codegen"
        case .custom(let name): return name
        }
    }

    // MARK: - Payload Summary

    func formatPayloadSummary(_ event: ShikkiEvent) -> String {
        var parts: [String] = []

        // Add type-specific context
        switch event.type {
        case .sessionStart:
            parts.append("started")
        case .sessionEnd:
            parts.append("ended")
        case .companyDispatched:
            if let title = event.payload["title"]?.stringValue {
                parts.append("task: \(title)")
            }
        case .decisionPending:
            if let q = event.payload["question"]?.stringValue {
                parts.append(String(q.prefix(80)))
            }
        case .decisionAnswered:
            parts.append("answered")
        case .testRun:
            if event.payload["passed"] == .bool(true) {
                parts.append("PASSED")
            } else if event.payload["passed"] == .bool(false) {
                parts.append("FAILED")
                if let name = event.payload["testName"]?.stringValue {
                    parts.append("(\(name))")
                }
            }
        case .buildResult:
            if event.payload["success"] == .bool(true) {
                parts.append("PASSED")
            } else if event.payload["success"] == .bool(false) {
                parts.append("FAILED")
            }
        case .shipGatePassed:
            if let gate = event.payload["gate"]?.stringValue {
                parts.append("\(gate) PASSED")
            }
        case .shipGateFailed:
            if let gate = event.payload["gate"]?.stringValue {
                parts.append("\(gate) FAILED")
            }
        case .budgetExhausted:
            parts.append("budget exhausted")
        case .contextCompaction:
            parts.append("compaction")
        case .shipStarted:
            parts.append("started")
        case .shipCompleted:
            parts.append("completed")
        case .shipAborted:
            if let reason = event.payload["reason"]?.stringValue {
                parts.append("aborted: \(reason)")
            }
        default:
            // Include any generic payload keys
            for (key, value) in event.payload.prefix(2) {
                switch value {
                case .string(let s):
                    parts.append("\(key): \(String(s.prefix(60)))")
                case .int(let i):
                    parts.append("\(key): \(i)")
                case .double(let d):
                    parts.append("\(key): \(String(format: "%.1f", d))")
                case .bool(let b):
                    parts.append("\(key): \(b)")
                case .null:
                    break
                }
            }
        }

        return parts.joined(separator: " ")
    }

    // MARK: - Company Color

    /// Deterministic color assignment per company slug.
    /// Named companies get fixed colors; others get a hash-based assignment.
    public static func colorForCompany(_ slug: String) -> String {
        switch slug {
        case "maya": return ANSI.cyan
        case "shiki", "shikki": return ANSI.green
        case "wabisabi": return ANSI.magenta
        case "brainy": return ANSI.yellow
        case "flsh": return ANSI.red
        case "kintsugi": return "\u{1B}[38;5;208m" // orange (256-color)
        case "obyw-one": return ANSI.white
        default:
            // Hash-based color from a palette
            let colors = [ANSI.cyan, ANSI.green, ANSI.magenta, ANSI.yellow, ANSI.red, ANSI.white]
            let hash = abs(slug.hashValue)
            return colors[hash % colors.count]
        }
    }

    // MARK: - Keyword Highlighting

    func highlightKeywords(_ text: String) -> String {
        var result = text
        // Highlight PASSED in green
        result = result.replacingOccurrences(
            of: "PASSED",
            with: "\(ANSI.green)PASSED\(ANSI.reset)"
        )
        // Highlight FAILED in red
        result = result.replacingOccurrences(
            of: "FAILED",
            with: "\(ANSI.red)FAILED\(ANSI.reset)"
        )
        // Highlight blocked in yellow
        result = result.replacingOccurrences(
            of: "blocked",
            with: "\(ANSI.yellow)blocked\(ANSI.reset)"
        )
        // Highlight exhausted in red
        result = result.replacingOccurrences(
            of: "exhausted",
            with: "\(ANSI.red)exhausted\(ANSI.reset)"
        )
        return result
    }

    // MARK: - Extract Company

    func extractCompanySlug(from event: ShikkiEvent) -> String {
        switch event.scope {
        case .project(let slug):
            return slug
        case .session(let id):
            return id.split(separator: ":").first.map(String.init) ?? "system"
        default:
            // Try source
            switch event.source {
            case .orchestrator:
                return "shikki"
            case .agent(_, let name):
                return name ?? "agent"
            case .process(let name):
                return name
            case .human:
                return "human"
            case .system:
                return "system"
            }
        }
    }
}

// MARK: - JSONEventRenderer

/// Renders events as raw JSON lines (one JSON object per line) for piping.
public struct JSONEventRenderer: EventRenderer {

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    public init() {}

    public func render(_ event: ShikkiEvent) -> String {
        guard let data = try? Self.encoder.encode(event),
              let json = String(data: data, encoding: .utf8) else {
            return "{\"error\":\"encoding_failed\",\"id\":\"\(event.id)\"}"
        }
        return json
    }
}
