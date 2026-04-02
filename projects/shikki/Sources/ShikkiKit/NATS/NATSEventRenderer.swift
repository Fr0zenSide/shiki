import Foundation

// MARK: - NATSRenderFormat

/// Output format for the NATS event renderer.
public enum NATSRenderFormat: String, Sendable {
    case compact  // One-line ANSI (default for `shi log`)
    case detail   // Multi-line with payload details
    case json     // Raw JSON for piping
}

// MARK: - NATSEventRenderer

/// Significance-aware event renderer for the NATS event stream.
///
/// Wraps the existing ANSIEventRenderer / JSONEventRenderer and adds:
/// - EventSignificance classification via EventClassifier
/// - Bold/red for critical events, dim for noise
/// - Minimum significance filtering
/// - Detail format (multi-line) for verbose mode
/// - Replay styling (dim prefix for historical events)
public struct NATSEventRenderer: EventRenderer, Sendable {
    private let format: NATSRenderFormat
    private let minLevel: EventSignificance
    private let ansiRenderer: ANSIEventRenderer
    private let jsonRenderer: JSONEventRenderer

    public init(
        format: NATSRenderFormat = .compact,
        minLevel: EventSignificance = .noise
    ) {
        self.format = format
        self.minLevel = minLevel
        self.ansiRenderer = ANSIEventRenderer()
        self.jsonRenderer = JSONEventRenderer()
    }

    /// Render an event. Returns nil if below minimum significance level.
    public func render(_ event: ShikkiEvent) -> String {
        let significance = EventClassifier.classify(event)

        // Filter by minimum level
        guard significance >= minLevel else {
            return ""  // Caller should skip empty strings
        }

        switch format {
        case .json:
            return jsonRenderer.render(event)
        case .compact:
            return renderCompact(event, significance: significance)
        case .detail:
            return renderDetail(event, significance: significance)
        }
    }

    /// Render with replay styling (dim prefix to distinguish historical events).
    public func renderReplay(_ event: ShikkiEvent) -> String {
        let line = render(event)
        guard !line.isEmpty else { return "" }

        if format == .json { return line } // JSON is always raw

        return "\(ANSI.dim)\(line)\(ANSI.reset)"
    }

    // MARK: - Compact Format

    /// One-line format with significance-aware styling.
    /// Critical: bold red prefix. Alert: red prefix. Milestone: green prefix.
    /// Noise: dim. Background: normal dim. Progress+: normal.
    private func renderCompact(_ event: ShikkiEvent, significance: EventSignificance) -> String {
        let base = ansiRenderer.render(event)

        switch significance {
        case .critical:
            return "\(ANSI.bold)\(ANSI.red)!\(ANSI.reset) \(base)"
        case .alert:
            return "\(ANSI.red)!\(ANSI.reset) \(base)"
        case .milestone:
            return "\(ANSI.green)*\(ANSI.reset) \(base)"
        case .decision:
            return "\(ANSI.yellow)?\(ANSI.reset) \(base)"
        case .noise:
            return "\(ANSI.dim)\(stripANSI(base))\(ANSI.reset)"
        case .background:
            return "\(ANSI.dim)\(stripANSI(base))\(ANSI.reset)"
        case .progress:
            return base
        }
    }

    // MARK: - Detail Format

    /// Multi-line format with full payload and metadata.
    private func renderDetail(_ event: ShikkiEvent, significance: EventSignificance) -> String {
        var lines: [String] = []

        // Header line (same as compact but with significance badge)
        let badge = significanceBadge(significance)
        let time = event.timestamp.timeOnly
        let companySlug = ansiRenderer.extractCompanySlug(from: event)
        let companyColor = ANSIEventRenderer.colorForCompany(companySlug)
        let typeLabel = ansiRenderer.formatType(event.type)
        let scopeLabel = ansiRenderer.formatScope(event.scope)

        lines.append("\(badge) \(ANSI.dim)[\(time)]\(ANSI.reset) \(companyColor)\(ANSI.bold)\(companySlug)\(ANSI.reset):\(scopeLabel) \(ANSI.dim)\(ANSI.yellow)\(typeLabel)\(ANSI.reset)")

        // Payload
        if !event.payload.isEmpty {
            for (key, value) in event.payload.sorted(by: { $0.key < $1.key }) {
                let valueStr: String
                switch value {
                case .string(let s): valueStr = s
                case .int(let i): valueStr = "\(i)"
                case .double(let d): valueStr = String(format: "%.2f", d)
                case .bool(let b): valueStr = "\(b)"
                case .null: valueStr = "null"
                }
                lines.append("  \(ANSI.dim)\(key):\(ANSI.reset) \(valueStr)")
            }
        }

        // Metadata
        if let meta = event.metadata {
            if let branch = meta.branch {
                lines.append("  \(ANSI.dim)branch:\(ANSI.reset) \(branch)")
            }
            if let commit = meta.commitHash {
                lines.append("  \(ANSI.dim)commit:\(ANSI.reset) \(String(commit.prefix(8)))")
            }
            if let duration = meta.duration {
                lines.append("  \(ANSI.dim)duration:\(ANSI.reset) \(String(format: "%.1fs", duration))")
            }
            if let tags = meta.tags, !tags.isEmpty {
                lines.append("  \(ANSI.dim)tags:\(ANSI.reset) \(tags.joined(separator: ", "))")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Significance Badge

    private func significanceBadge(_ significance: EventSignificance) -> String {
        switch significance {
        case .critical: return "\(ANSI.bold)\(ANSI.red)[CRITICAL]\(ANSI.reset)"
        case .alert: return "\(ANSI.red)[ALERT]\(ANSI.reset)"
        case .milestone: return "\(ANSI.green)[MILESTONE]\(ANSI.reset)"
        case .decision: return "\(ANSI.yellow)[DECISION]\(ANSI.reset)"
        case .progress: return "\(ANSI.cyan)[PROGRESS]\(ANSI.reset)"
        case .background: return "\(ANSI.dim)[BG]\(ANSI.reset)"
        case .noise: return "\(ANSI.dim)[...]\(ANSI.reset)"
        }
    }
}

// MARK: - EventSignificance Parsing

extension EventSignificance {
    /// Parse a significance level from a CLI string (case-insensitive).
    /// Returns nil if the string doesn't match any known level.
    public init?(cliString: String) {
        switch cliString.lowercased() {
        case "noise": self = .noise
        case "background", "bg": self = .background
        case "progress": self = .progress
        case "milestone": self = .milestone
        case "decision": self = .decision
        case "alert": self = .alert
        case "critical": self = .critical
        default: return nil
        }
    }
}
