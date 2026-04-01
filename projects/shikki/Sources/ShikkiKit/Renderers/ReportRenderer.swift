import Foundation

/// Protocol for rendering a Report to a string output.
public protocol ReportRenderer: Sendable {
    func render(_ report: Report) -> String
    func renderCODIR(_ report: Report) -> String
}
