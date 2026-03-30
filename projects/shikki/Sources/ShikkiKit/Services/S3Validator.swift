import Foundation

// MARK: - S3 Diagnostic

/// A diagnostic message from S3 validation.
public struct S3Diagnostic: Codable, Sendable, Equatable {
    public enum Severity: String, Codable, Sendable {
        case error
        case warning
        case hint
    }

    public let line: Int
    public let severity: Severity
    public let message: String

    public init(line: Int, severity: Severity, message: String) {
        self.line = line
        self.severity = severity
        self.message = message
    }
}

/// Result of validating an S3 document.
public struct S3ValidationResult: Codable, Sendable {
    public let diagnostics: [S3Diagnostic]
    public let isValid: Bool

    public var errors: [S3Diagnostic] {
        diagnostics.filter { $0.severity == .error }
    }

    public var warnings: [S3Diagnostic] {
        diagnostics.filter { $0.severity == .warning }
    }

    public var hints: [S3Diagnostic] {
        diagnostics.filter { $0.severity == .hint }
    }

    public init(diagnostics: [S3Diagnostic]) {
        self.diagnostics = diagnostics
        self.isValid = !diagnostics.contains { $0.severity == .error }
    }
}

// MARK: - S3 Validator

/// Validates S3 (Shiki Spec Syntax) documents for structural correctness.
///
/// Checks:
/// - `When` blocks end with `:`
/// - `->` / `→` assertions appear inside a `When` block
/// - `if` conditions appear inside a `When` block
/// - `for each` has `[list]`
/// - `depending on` has case lines
/// - `?` concerns are well-formed
/// - Empty scenarios (When with no assertions)
public enum S3Validator {

    public static func validate(_ markdown: String) -> S3ValidationResult {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var diagnostics: [S3Diagnostic] = []
        var insideWhen = false
        var insideForEach = false
        var insideDependingOn = false
        var whenHasContent = false
        var dependingOnHasCase = false
        var lastWhenLine = 0
        var hasTitle = false
        var whenCount = 0
        var forEachHasList = false

        for (index, line) in lines.enumerated() {
            let lineNum = index + 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip blank lines
            if trimmed.isEmpty { continue }

            // H1 title
            if trimmed.hasPrefix("# ") && !trimmed.hasPrefix("## ") {
                hasTitle = true
                continue
            }

            // H2 section header
            if trimmed.hasPrefix("## ") {
                if insideWhen && !whenHasContent {
                    diagnostics.append(S3Diagnostic(
                        line: lastWhenLine,
                        severity: .warning,
                        message: "When block has no assertions or conditions"
                    ))
                }
                if insideDependingOn && !dependingOnHasCase {
                    diagnostics.append(S3Diagnostic(
                        line: lineNum,
                        severity: .warning,
                        message: "depending on block has no cases"
                    ))
                }
                insideWhen = false
                insideDependingOn = false
                continue
            }

            // Annotation line
            if trimmed.hasPrefix("@") && !trimmed.hasPrefix("@:") {
                continue
            }

            // Concern line
            if trimmed.hasPrefix("? ") {
                if insideWhen && !whenHasContent {
                    diagnostics.append(S3Diagnostic(
                        line: lastWhenLine,
                        severity: .warning,
                        message: "When block has no assertions or conditions"
                    ))
                }
                insideWhen = false
                insideDependingOn = false
                continue
            }

            // Concern metadata
            if trimmed.hasPrefix("expect:") || trimmed.hasPrefix("edge case:") || trimmed.hasPrefix("severity:") {
                continue
            }

            // For each
            if trimmed.lowercased().hasPrefix("for each ") {
                if insideWhen && !whenHasContent {
                    diagnostics.append(S3Diagnostic(
                        line: lastWhenLine,
                        severity: .warning,
                        message: "When block has no assertions or conditions"
                    ))
                }
                insideWhen = false
                insideForEach = true
                insideDependingOn = false

                let rest = String(trimmed.dropFirst(9))
                forEachHasList = rest.contains("[") && rest.contains("]")
                if !forEachHasList {
                    diagnostics.append(S3Diagnostic(
                        line: lineNum,
                        severity: .error,
                        message: "for each requires [list] — e.g., for each item in [a, b, c]:"
                    ))
                }
                if !rest.lowercased().contains(" in ") {
                    diagnostics.append(S3Diagnostic(
                        line: lineNum,
                        severity: .error,
                        message: "for each requires 'in' keyword — e.g., for each item in [list]:"
                    ))
                }
                continue
            }

            // When block
            if trimmed.lowercased().hasPrefix("when ") {
                // Check if inside a for-each (sub-when is OK)
                if insideForEach {
                    if !trimmed.hasSuffix(":") {
                        diagnostics.append(S3Diagnostic(
                            line: lineNum,
                            severity: .error,
                            message: "When block missing trailing colon"
                        ))
                    }
                    insideWhen = true
                    whenHasContent = false
                    lastWhenLine = lineNum
                    whenCount += 1
                    continue
                }

                if insideWhen && !whenHasContent {
                    diagnostics.append(S3Diagnostic(
                        line: lastWhenLine,
                        severity: .warning,
                        message: "When block has no assertions or conditions"
                    ))
                }
                if insideDependingOn && !dependingOnHasCase {
                    diagnostics.append(S3Diagnostic(
                        line: lineNum,
                        severity: .warning,
                        message: "depending on block has no cases"
                    ))
                }

                if !trimmed.hasSuffix(":") {
                    diagnostics.append(S3Diagnostic(
                        line: lineNum,
                        severity: .error,
                        message: "When block missing trailing colon"
                    ))
                }
                insideWhen = true
                insideForEach = false
                insideDependingOn = false
                whenHasContent = false
                lastWhenLine = lineNum
                whenCount += 1
                continue
            }

            // Then sequence step
            if trimmed.lowercased().hasPrefix("then ") && trimmed.hasSuffix(":") {
                if !insideWhen {
                    diagnostics.append(S3Diagnostic(
                        line: lineNum,
                        severity: .error,
                        message: "then step outside of a When block"
                    ))
                }
                continue
            }

            // Depending on
            if trimmed.lowercased().hasPrefix("depending on ") {
                if !insideWhen {
                    diagnostics.append(S3Diagnostic(
                        line: lineNum,
                        severity: .error,
                        message: "depending on outside of a When block"
                    ))
                }
                insideDependingOn = true
                dependingOnHasCase = false
                whenHasContent = true
                continue
            }

            // Depending on case: "value" -> outcome
            if insideDependingOn && (trimmed.contains("\u{2192}") || trimmed.contains("->")) {
                dependingOnHasCase = true
                whenHasContent = true
                continue
            }

            // If condition
            if trimmed.lowercased().hasPrefix("if ") && trimmed.hasSuffix(":") {
                if !insideWhen && !insideForEach {
                    diagnostics.append(S3Diagnostic(
                        line: lineNum,
                        severity: .error,
                        message: "if condition outside of a When block"
                    ))
                }
                whenHasContent = true
                continue
            }

            // Otherwise
            if trimmed.lowercased() == "otherwise:" {
                if !insideWhen {
                    diagnostics.append(S3Diagnostic(
                        line: lineNum,
                        severity: .error,
                        message: "otherwise outside of a When block"
                    ))
                }
                whenHasContent = true
                continue
            }

            // Assertion (→ or ->)
            if trimmed.hasPrefix("\u{2192} ") || trimmed.hasPrefix("-> ") {
                if !insideWhen && !insideForEach {
                    diagnostics.append(S3Diagnostic(
                        line: lineNum,
                        severity: .error,
                        message: "assertion outside of a When block"
                    ))
                }
                whenHasContent = true
                continue
            }
        }

        // Final flush
        if insideWhen && !whenHasContent {
            diagnostics.append(S3Diagnostic(
                line: lastWhenLine,
                severity: .warning,
                message: "When block has no assertions or conditions"
            ))
        }
        if insideDependingOn && !dependingOnHasCase {
            diagnostics.append(S3Diagnostic(
                line: lastWhenLine,
                severity: .warning,
                message: "depending on block has no cases"
            ))
        }

        // Global hints
        if !hasTitle {
            diagnostics.append(S3Diagnostic(
                line: 1,
                severity: .hint,
                message: "No title found — add a # Title at the top"
            ))
        }
        if whenCount == 0 {
            diagnostics.append(S3Diagnostic(
                line: 1,
                severity: .hint,
                message: "No When blocks found — this spec has no test scenarios"
            ))
        }

        return S3ValidationResult(diagnostics: diagnostics.sorted { $0.line < $1.line })
    }
}
