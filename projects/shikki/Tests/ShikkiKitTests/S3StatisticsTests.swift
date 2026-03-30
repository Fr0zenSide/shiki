import Foundation
import Testing
@testable import ShikkiKit

@Suite("S3 Statistics")
struct S3StatisticsTests {

    @Test("Simple scenario counts one test")
    func simpleScenario() throws {
        let input = """
        # Spec

        When user opens app:
          → show screen
          → play animation
        """
        let spec = try S3Parser.parse(input)
        let stats = S3Statistics.from(spec)
        #expect(stats.sectionCount == 1)
        #expect(stats.scenarioCount == 1)
        #expect(stats.assertionCount == 2)
        #expect(stats.conditionCount == 0)
        #expect(stats.testableCount == 1)
    }

    @Test("Conditions expand to multiple tests")
    func conditionsExpandTests() throws {
        let input = """
        # Spec

        When user submits:
          if valid:
            → save
          if invalid:
            → show error
          otherwise:
            → fallback
        """
        let spec = try S3Parser.parse(input)
        let stats = S3Statistics.from(spec)
        #expect(stats.scenarioCount == 1)
        #expect(stats.conditionCount == 3)
        #expect(stats.testableCount == 3) // one per condition
    }

    @Test("Standalone assertions plus conditions counted correctly")
    func mixedAssertionsAndConditions() throws {
        let input = """
        # Spec

        When upload completes:
          → show indicator
          if large file:
            → warn user
        """
        let spec = try S3Parser.parse(input)
        let stats = S3Statistics.from(spec)
        #expect(stats.assertionCount == 2) // 1 standalone + 1 in condition
        #expect(stats.testableCount == 2) // 1 for standalone + 1 for condition
    }

    @Test("Parameterized tests counted per condition")
    func parameterizedTests() throws {
        let input = """
        # Spec

        For each field in [name, email, password]:
          when {field} is empty:
            → show error
          when {field} is valid:
            → show checkmark
        """
        let spec = try S3Parser.parse(input)
        let stats = S3Statistics.from(spec)
        #expect(stats.parameterizedCount == 2) // two sub-whens
        #expect(stats.testableCount == 2)
    }

    @Test("Concerns with expectations count as tests")
    func concernsWithExpectations() throws {
        let input = """
        # Spec

        When something:
          → works

        ? What if file is locked?
          expect: throws gracefully

        ? Is this needed?
        """
        let spec = try S3Parser.parse(input)
        let stats = S3Statistics.from(spec)
        #expect(stats.concernCount == 2)
        #expect(stats.testableCount == 2) // 1 scenario + 1 concern with expect
    }

    @Test("Sequence steps add to assertion count")
    func sequenceAssertionCount() throws {
        let input = """
        # Spec

        When onboarding starts:
          → show welcome
          then user taps next:
            → show features
          then user taps done:
            → show dashboard
        """
        let spec = try S3Parser.parse(input)
        let stats = S3Statistics.from(spec)
        #expect(stats.assertionCount == 3) // 1 + 1 + 1
        #expect(stats.sequenceCount == 2) // 2 then steps
        #expect(stats.testableCount == 2) // 1 simple + 1 sequence integration
    }

    @Test("Multiple sections counted")
    func multipleSections() throws {
        let input = """
        # Spec

        ## Auth

        When login:
          → session created

        ## Profile

        When update name:
          → name saved
        """
        let spec = try S3Parser.parse(input)
        let stats = S3Statistics.from(spec)
        #expect(stats.sectionCount == 2)
        #expect(stats.scenarioCount == 2)
    }

    @Test("Annotations counted")
    func annotationCount() throws {
        let input = """
        # Spec

        @slow @priority(high)
        When heavy upload:
          → completes
        """
        let spec = try S3Parser.parse(input)
        let stats = S3Statistics.from(spec)
        #expect(stats.annotationCount == 2)
    }

    @Test("Summary string is well-formed")
    func summaryString() throws {
        let input = """
        # Spec

        When a:
          → x

        When b:
          → y

        ? concern
          expect: handled
        """
        let spec = try S3Parser.parse(input)
        let stats = S3Statistics.from(spec)
        let summary = stats.summary
        #expect(summary.contains("2 scenarios"))
        #expect(summary.contains("2 assertions"))
        #expect(summary.contains("1 concern"))
        #expect(summary.contains("3 tests expected"))
    }

    @Test("Empty spec yields zero stats")
    func emptySpec() throws {
        let input = """
        # Empty
        """
        let spec = try S3Parser.parse(input)
        let stats = S3Statistics.from(spec)
        #expect(stats.scenarioCount == 0)
        #expect(stats.assertionCount == 0)
        #expect(stats.testableCount == 0)
    }
}
