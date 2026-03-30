import Foundation

// MARK: - S3 Models

/// A parsed S3 specification.
public struct S3Spec: Codable, Sendable {
    public let title: String
    public var sections: [S3Section]
    public var concerns: [S3Concern]

    public init(title: String, sections: [S3Section] = [], concerns: [S3Concern] = []) {
        self.title = title
        self.sections = sections
        self.concerns = concerns
    }
}

/// A section within a spec (maps to ## headers).
public struct S3Section: Codable, Sendable {
    public let title: String
    public var scenarios: [S3Scenario]

    public init(title: String, scenarios: [S3Scenario] = []) {
        self.title = title
        self.scenarios = scenarios
    }
}

/// A test scenario (When block).
public struct S3Scenario: Codable, Sendable {
    public let context: String
    public var assertions: [String]
    public var conditions: [S3Condition]
    public var annotations: [String]
    public var loopVariable: String?
    public var loopValues: [String]?
    public var sequence: [S3SequenceStep]?

    public init(
        context: String, assertions: [String] = [], conditions: [S3Condition] = [],
        annotations: [String] = [], loopVariable: String? = nil,
        loopValues: [String]? = nil, sequence: [S3SequenceStep]? = nil
    ) {
        self.context = context
        self.assertions = assertions
        self.conditions = conditions
        self.annotations = annotations
        self.loopVariable = loopVariable
        self.loopValues = loopValues
        self.sequence = sequence
    }
}

/// A condition branch (if/otherwise/depending on case).
public struct S3Condition: Codable, Sendable {
    public let condition: String
    public var assertions: [String]
    public let isDefault: Bool

    public init(condition: String, assertions: [String] = [], isDefault: Bool = false) {
        self.condition = condition
        self.assertions = assertions
        self.isDefault = isDefault
    }
}

/// A sequence step (then block).
public struct S3SequenceStep: Codable, Sendable {
    public let context: String
    public var assertions: [String]

    public init(context: String, assertions: [String] = []) {
        self.context = context
        self.assertions = assertions
    }
}

/// A concern (? block).
public struct S3Concern: Codable, Sendable {
    public let question: String
    public var expectation: String?
    public var edgeCase: String?
    public var severity: String?

    public init(question: String, expectation: String? = nil, edgeCase: String? = nil, severity: String? = nil) {
        self.question = question
        self.expectation = expectation
        self.edgeCase = edgeCase
        self.severity = severity
    }
}

// MARK: - S3 Parser

/// Parses S3 (Shiki Spec Syntax) markdown into structured test specifications.
public enum S3Parser {

    public static func parse(_ markdown: String) throws -> S3Spec {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var title = "Untitled Spec"
        var sections: [S3Section] = []
        var concerns: [S3Concern] = []
        var currentSection: S3Section?
        var currentScenario: S3Scenario?
        var currentCondition: S3Condition?
        var currentConcern: S3Concern?
        var currentSequence: [S3SequenceStep]?
        var currentSeqStep: S3SequenceStep?
        var pendingAnnotations: [String] = []
        var inDependingOn = false

        func flushCondition() {
            if let cond = currentCondition {
                currentScenario?.conditions.append(cond)
                currentCondition = nil
            }
        }

        func flushSeqStep() {
            if let step = currentSeqStep {
                if currentSequence == nil { currentSequence = [] }
                currentSequence?.append(step)
                currentSeqStep = nil
            }
        }

        func flushScenario() {
            flushCondition()
            flushSeqStep()
            if var scenario = currentScenario {
                scenario.sequence = currentSequence
                currentSection?.scenarios.append(scenario)
                currentScenario = nil
                currentSequence = nil
            }
            inDependingOn = false
        }

        func flushSection() {
            flushScenario()
            if let section = currentSection {
                sections.append(section)
                currentSection = nil
            }
        }

        func flushConcern() {
            if let concern = currentConcern {
                concerns.append(concern)
                currentConcern = nil
            }
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // H1 title
            if trimmed.hasPrefix("# ") && !trimmed.hasPrefix("## ") {
                title = String(trimmed.dropFirst(2))
                // Don't create default section here — wait for first scenario
                continue
            }

            // H2 section
            if trimmed.hasPrefix("## ") {
                flushConcern()
                flushSection()
                let sectionTitle = String(trimmed.dropFirst(3))
                if sectionTitle.lowercased() == "concerns" {
                    // Concerns section — don't create a scenario section
                    continue
                }
                currentSection = S3Section(title: sectionTitle)
                continue
            }

            // Annotations (@slow, @priority(high))
            if trimmed.hasPrefix("@") && !trimmed.hasPrefix("@:") && currentScenario == nil {
                let annotations = trimmed.split(separator: " ").map { token in
                    String(token.dropFirst()) // remove @
                }
                pendingAnnotations.append(contentsOf: annotations)
                continue
            }

            // Concern (? line)
            if trimmed.hasPrefix("? ") {
                flushConcern()
                flushScenario()
                currentConcern = S3Concern(question: String(trimmed.dropFirst(2)))
                continue
            }

            // Concern metadata
            if let concern = currentConcern {
                if trimmed.hasPrefix("expect:") {
                    currentConcern?.expectation = String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                    continue
                }
                if trimmed.hasPrefix("edge case:") {
                    currentConcern?.edgeCase = String(trimmed.dropFirst(10)).trimmingCharacters(in: .whitespaces)
                    continue
                }
                if trimmed.hasPrefix("severity:") {
                    currentConcern?.severity = String(trimmed.dropFirst(9)).trimmingCharacters(in: .whitespaces)
                    continue
                }
                if trimmed.isEmpty && concern.question.isEmpty == false {
                    // Blank line after concern content — might end the concern
                    continue
                }
            }

            // For each loop
            if trimmed.lowercased().hasPrefix("for each ") {
                flushConcern()
                flushScenario()
                if currentSection == nil {
                    currentSection = S3Section(title: title)
                }
                let rest = String(trimmed.dropFirst(9)) // "for each " = 9 chars
                if let inRange = rest.range(of: " in ") {
                    let variable = String(rest[rest.startIndex..<inRange.lowerBound])
                    let listPart = String(rest[inRange.upperBound...])
                    let values = parseListValues(listPart)
                    currentScenario = S3Scenario(
                        context: "for each \(variable)",
                        annotations: pendingAnnotations,
                        loopVariable: variable,
                        loopValues: values
                    )
                    pendingAnnotations = []
                }
                continue
            }

            // When block (also handles "when" inside for each)
            if trimmed.lowercased().hasPrefix("when ") && trimmed.hasSuffix(":") {
                flushConcern()
                let context = String(trimmed.dropFirst(5).dropLast()) // remove "when " and ":"

                if currentScenario?.loopVariable != nil {
                    // Inside a for-each — this is a sub-scenario, treat as condition
                    flushCondition()
                    currentCondition = S3Condition(condition: context)
                } else {
                    flushScenario()
                    if currentSection == nil {
                        currentSection = S3Section(title: title)
                    }
                    currentScenario = S3Scenario(context: context, annotations: pendingAnnotations)
                    pendingAnnotations = []
                }
                continue
            }

            // Then sequence
            if trimmed.lowercased().hasPrefix("then ") && trimmed.hasSuffix(":") {
                flushCondition()
                flushSeqStep()
                let context = String(trimmed.dropFirst(5).dropLast())
                currentSeqStep = S3SequenceStep(context: context)
                continue
            }

            // Depending on
            if trimmed.lowercased().hasPrefix("depending on ") {
                inDependingOn = true
                continue
            }

            // Depending on case: "value" → outcome
            if inDependingOn && trimmed.contains("→") {
                let parts = trimmed.split(separator: "→", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                if parts.count == 2 {
                    let caseName = parts[0].trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
                    let assertion = parts[1]
                    currentScenario?.conditions.append(
                        S3Condition(condition: caseName, assertions: [assertion])
                    )
                }
                continue
            }

            // If condition
            if trimmed.lowercased().hasPrefix("if ") && trimmed.hasSuffix(":") {
                flushCondition()
                let condition = String(trimmed.dropFirst(3).dropLast())
                currentCondition = S3Condition(condition: condition)
                continue
            }

            // Otherwise
            if trimmed.lowercased() == "otherwise:" {
                flushCondition()
                currentCondition = S3Condition(condition: "otherwise", isDefault: true)
                continue
            }

            // Assertion (→ or ->)
            if trimmed.hasPrefix("→ ") || trimmed.hasPrefix("-> ") {
                let assertion = trimmed.hasPrefix("→ ") ?
                    String(trimmed.dropFirst(2)) : String(trimmed.dropFirst(3))

                if let _ = currentSeqStep {
                    currentSeqStep?.assertions.append(assertion)
                } else if let _ = currentCondition {
                    currentCondition?.assertions.append(assertion)
                } else if let _ = currentScenario {
                    currentScenario?.assertions.append(assertion)
                }
                continue
            }
        }

        // Flush remaining
        flushConcern()
        flushSection()

        // If no sections were created but we have scenarios in the default section
        if sections.isEmpty && currentSection == nil {
            return S3Spec(title: title, sections: [], concerns: concerns)
        }

        return S3Spec(title: title, sections: sections, concerns: concerns)
    }

    private static func parseListValues(_ input: String) -> [String] {
        let cleaned = input
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]:"))
            .trimmingCharacters(in: .whitespaces)
        return cleaned.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }
}
