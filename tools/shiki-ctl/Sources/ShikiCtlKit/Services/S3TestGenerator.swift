import Foundation

/// Generates Swift Testing @Test functions from parsed S3 specifications.
public enum S3TestGenerator {

    /// Generate a Swift test file from an S3 spec.
    public static func generate(_ spec: S3Spec) -> String {
        var lines: [String] = []

        lines.append("import Foundation")
        lines.append("import Testing")
        lines.append("")

        let suiteName = spec.title
        let structName = suiteName.replacingOccurrences(of: " ", with: "") + "Tests"

        lines.append("@Suite(\"\(suiteName)\")")
        lines.append("struct \(structName) {")

        for section in spec.sections {
            lines.append("")
            lines.append("    // MARK: - \(section.title)")

            for scenario in section.scenarios {
                lines.append("")
                generateScenario(scenario, into: &lines)
            }
        }

        // Generate tests from concerns with expectations
        let testConcerns = spec.concerns.filter { $0.expectation != nil }
        if !testConcerns.isEmpty {
            lines.append("")
            lines.append("    // MARK: - Edge Cases (from Concerns)")
            for concern in testConcerns {
                lines.append("")
                generateConcernTest(concern, into: &lines)
            }
        }

        lines.append("}")
        lines.append("")

        return lines.joined(separator: "\n")
    }

    private static func generateScenario(_ scenario: S3Scenario, into lines: inout [String]) {
        if scenario.conditions.isEmpty && scenario.loopVariable == nil {
            // Simple scenario — one test
            let testName = sanitizeTestName(scenario.context)
            lines.append("    @Test(\"\(capitalize(scenario.context))\")")
            lines.append("    func \(testName)() {")
            for assertion in scenario.assertions {
                lines.append("        // \(assertion)")
            }
            lines.append("    }")
        } else if let loopVar = scenario.loopVariable, let values = scenario.loopValues {
            // Parameterized test
            let valuesStr = values.map { "\"\($0)\"" }.joined(separator: ", ")
            for condition in scenario.conditions {
                let testName = sanitizeTestName(condition.condition)
                lines.append("    @Test(\"\(capitalize(condition.condition))\", arguments: [\(valuesStr)])")
                lines.append("    func \(testName)(\(loopVar): String) {")
                for assertion in condition.assertions {
                    lines.append("        // \(assertion)")
                }
                lines.append("    }")
                lines.append("")
            }
        } else {
            // Scenario with conditions — one test per condition
            // First, standalone assertions as one test
            if !scenario.assertions.isEmpty {
                let testName = sanitizeTestName(scenario.context)
                lines.append("    @Test(\"\(capitalize(scenario.context))\")")
                lines.append("    func \(testName)() {")
                for assertion in scenario.assertions {
                    lines.append("        // \(assertion)")
                }
                lines.append("    }")
                lines.append("")
            }

            for condition in scenario.conditions {
                let condName = condition.isDefault ? "\(scenario.context) otherwise" : "\(scenario.context) — \(condition.condition)"
                let testName = sanitizeTestName(condName)
                lines.append("    @Test(\"\(capitalize(condName))\")")
                lines.append("    func \(testName)() {")
                for assertion in condition.assertions {
                    lines.append("        // \(assertion)")
                }
                lines.append("    }")
                lines.append("")
            }
        }

        // Sequence steps
        if let sequence = scenario.sequence {
            let seqTestName = sanitizeTestName("\(scenario.context) full sequence")
            lines.append("    @Test(\"\(capitalize(scenario.context)) full sequence\")")
            lines.append("    func \(seqTestName)() {")
            lines.append("        // Step 0: \(scenario.context)")
            for assertion in scenario.assertions {
                lines.append("        // \(assertion)")
            }
            for (i, step) in sequence.enumerated() {
                lines.append("        // Step \(i + 1): \(step.context)")
                for assertion in step.assertions {
                    lines.append("        // \(assertion)")
                }
            }
            lines.append("    }")
        }
    }

    private static func generateConcernTest(_ concern: S3Concern, into lines: inout [String]) {
        let testName = sanitizeTestName(concern.question)
        lines.append("    @Test(\"\(concern.question)\")")
        lines.append("    func \(testName)() {")
        if let expectation = concern.expectation {
            lines.append("        // Expect: \(expectation)")
        }
        if let edgeCase = concern.edgeCase {
            lines.append("        // Edge case: \(edgeCase)")
        }
        lines.append("    }")
    }

    private static func sanitizeTestName(_ input: String) -> String {
        let cleaned = input
            .replacingOccurrences(of: "[^a-zA-Z0-9 ]", with: "", options: .regularExpression)
            .split(separator: " ")
            .enumerated()
            .map { i, word in
                i == 0 ? word.lowercased() : word.prefix(1).uppercased() + word.dropFirst().lowercased()
            }
            .joined()

        return cleaned.isEmpty ? "unnamed" : cleaned
    }

    private static func capitalize(_ input: String) -> String {
        guard let first = input.first else { return input }
        return first.uppercased() + input.dropFirst()
    }
}
