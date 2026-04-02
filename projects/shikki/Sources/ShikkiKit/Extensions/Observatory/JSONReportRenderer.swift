import Foundation

/// Renders a Report as JSON output. Pipe-friendly.
public struct JSONReportRenderer: ReportRenderer {

    public init() {}

    public func render(_ report: Report) -> String {
        encodeJSON(report)
    }

    public func renderCODIR(_ report: Report) -> String {
        // CODIR uses the same data but consumers filter client-side
        encodeJSON(report)
    }

    private func encodeJSON(_ report: Report) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(report),
              let json = String(data: data, encoding: .utf8) else {
            return "{\"error\": \"encoding failed\"}"
        }
        return json
    }
}
