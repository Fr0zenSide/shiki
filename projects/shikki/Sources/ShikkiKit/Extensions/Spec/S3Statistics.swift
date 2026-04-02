import Foundation

/// Summary statistics for an S3 specification.
public struct S3Statistics: Codable, Sendable, Equatable {
    public let sectionCount: Int
    public let scenarioCount: Int
    public let assertionCount: Int
    public let conditionCount: Int
    public let concernCount: Int
    public let testableCount: Int
    public let parameterizedCount: Int
    public let sequenceCount: Int
    public let annotationCount: Int

    public init(
        sectionCount: Int,
        scenarioCount: Int,
        assertionCount: Int,
        conditionCount: Int,
        concernCount: Int,
        testableCount: Int,
        parameterizedCount: Int,
        sequenceCount: Int,
        annotationCount: Int
    ) {
        self.sectionCount = sectionCount
        self.scenarioCount = scenarioCount
        self.assertionCount = assertionCount
        self.conditionCount = conditionCount
        self.concernCount = concernCount
        self.testableCount = testableCount
        self.parameterizedCount = parameterizedCount
        self.sequenceCount = sequenceCount
        self.annotationCount = annotationCount
    }

    /// Total number of generated @Test functions expected from this spec.
    public var estimatedTestCount: Int {
        testableCount
    }

    /// Summary string for TUI display.
    public var summary: String {
        var parts: [String] = []
        parts.append("\(scenarioCount) scenario\(scenarioCount == 1 ? "" : "s")")
        parts.append("\(assertionCount) assertion\(assertionCount == 1 ? "" : "s")")
        if conditionCount > 0 {
            parts.append("\(conditionCount) condition\(conditionCount == 1 ? "" : "s")")
        }
        if concernCount > 0 {
            parts.append("\(concernCount) concern\(concernCount == 1 ? "" : "s")")
        }
        parts.append("\(testableCount) test\(testableCount == 1 ? "" : "s") expected")
        return parts.joined(separator: ", ")
    }
}

// MARK: - Statistics computation

extension S3Statistics {

    /// Compute statistics from a parsed S3 spec.
    public static func from(_ spec: S3Spec) -> S3Statistics {
        var scenarioCount = 0
        var assertionCount = 0
        var conditionCount = 0
        var testableCount = 0
        var parameterizedCount = 0
        var sequenceCount = 0
        var annotationCount = 0

        for section in spec.sections {
            for scenario in section.scenarios {
                scenarioCount += 1
                assertionCount += scenario.assertions.count
                conditionCount += scenario.conditions.count
                annotationCount += scenario.annotations.count

                if let seq = scenario.sequence {
                    sequenceCount += seq.count
                    for step in seq {
                        assertionCount += step.assertions.count
                    }
                }

                for condition in scenario.conditions {
                    assertionCount += condition.assertions.count
                }

                // Count expected @Test functions
                if scenario.loopVariable != nil {
                    // Parameterized: one test per condition (sub-when)
                    let count = max(scenario.conditions.count, 1)
                    testableCount += count
                    parameterizedCount += count
                } else if scenario.conditions.isEmpty {
                    // Simple: one test
                    testableCount += 1
                    // Sequence adds one more integration test
                    if scenario.sequence != nil {
                        testableCount += 1
                    }
                } else {
                    // One test per condition
                    testableCount += scenario.conditions.count
                    // Plus one for standalone assertions if present
                    if !scenario.assertions.isEmpty {
                        testableCount += 1
                    }
                    // Sequence adds one more integration test
                    if scenario.sequence != nil {
                        testableCount += 1
                    }
                }
            }
        }

        // Concerns with expectations generate tests
        let concernsWithTests = spec.concerns.filter { $0.expectation != nil }.count
        testableCount += concernsWithTests

        return S3Statistics(
            sectionCount: spec.sections.count,
            scenarioCount: scenarioCount,
            assertionCount: assertionCount,
            conditionCount: conditionCount,
            concernCount: spec.concerns.count,
            testableCount: testableCount,
            parameterizedCount: parameterizedCount,
            sequenceCount: sequenceCount,
            annotationCount: annotationCount
        )
    }
}
