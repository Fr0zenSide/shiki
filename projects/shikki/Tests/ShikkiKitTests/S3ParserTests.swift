import Foundation
import Testing
@testable import ShikkiKit

@Suite("S3 Parser — When blocks")
struct S3ParserWhenTests {

    @Test("Parse simple When block with assertions")
    func simpleWhenBlock() throws {
        let input = """
        # Test Spec

        When user opens the app:
          → show onboarding screen
          → skip button visible after 3 seconds
        """
        let spec = try S3Parser.parse(input)
        #expect(spec.title == "Test Spec")
        #expect(spec.sections.count == 1)
        let scenario = spec.sections[0].scenarios[0]
        #expect(scenario.context == "user opens the app")
        #expect(scenario.assertions.count == 2)
        #expect(scenario.assertions[0] == "show onboarding screen")
        #expect(scenario.assertions[1] == "skip button visible after 3 seconds")
    }

    @Test("Parse multiple When blocks")
    func multipleWhenBlocks() throws {
        let input = """
        # Spec

        When session starts:
          → state should be spawning

        When session transitions:
          → history should record actor
        """
        let spec = try S3Parser.parse(input)
        #expect(spec.sections[0].scenarios.count == 2)
    }
}

@Suite("S3 Parser — Conditions")
struct S3ParserConditionTests {

    @Test("Parse if conditions under When")
    func ifConditions() throws {
        let input = """
        # Spec

        When user submits form:
          if credentials are valid:
            → create session
            → redirect to dashboard
          if email not found:
            → show error message
          otherwise:
            → show generic error
        """
        let spec = try S3Parser.parse(input)
        let scenario = spec.sections[0].scenarios[0]
        #expect(scenario.conditions.count == 3)
        #expect(scenario.conditions[0].condition == "credentials are valid")
        #expect(scenario.conditions[0].assertions.count == 2)
        #expect(scenario.conditions[1].condition == "email not found")
        #expect(scenario.conditions[2].isDefault)
    }

    @Test("Parse depending on switch")
    func dependingOn() throws {
        let input = """
        # Spec

        When status changes:
          depending on the new status:
            "active"    → unlock all features
            "trial"     → show countdown
            "expired"   → show paywall
        """
        let spec = try S3Parser.parse(input)
        let scenario = spec.sections[0].scenarios[0]
        #expect(scenario.conditions.count == 3)
        #expect(scenario.conditions[0].condition == "active")
        #expect(scenario.conditions[0].assertions[0] == "unlock all features")
    }

    @Test("Standalone assertions mixed with conditions")
    func mixedAssertionsAndConditions() throws {
        let input = """
        # Spec

        When upload completes:
          → show success indicator
          if file is too large:
            → show size warning
        """
        let spec = try S3Parser.parse(input)
        let scenario = spec.sections[0].scenarios[0]
        #expect(scenario.assertions.count == 1)
        #expect(scenario.assertions[0] == "show success indicator")
        #expect(scenario.conditions.count == 1)
    }
}

@Suite("S3 Parser — Loops")
struct S3ParserLoopTests {

    @Test("Parse for each block")
    func forEachBlock() throws {
        let input = """
        # Spec

        For each field in [name, email, password]:
          when {field} is empty:
            → show "{field} is required"
          when {field} is valid:
            → show green checkmark
        """
        let spec = try S3Parser.parse(input)
        let scenario = spec.sections[0].scenarios[0]
        #expect(scenario.loopVariable == "field")
        #expect(scenario.loopValues == ["name", "email", "password"])
    }

    @Test("Loop values preserve whitespace trimming")
    func loopValuesTrimmed() throws {
        let input = """
        # Spec

        For each state in [ spawning , working , done ]:
          when transition to {state}:
            → should succeed
        """
        let spec = try S3Parser.parse(input)
        let scenario = spec.sections[0].scenarios[0]
        #expect(scenario.loopValues == ["spawning", "working", "done"])
    }
}

@Suite("S3 Parser — Concerns")
struct S3ParserConcernTests {

    @Test("Parse concern with expect and edge case")
    func fullConcern() throws {
        let input = """
        # Spec

        ? What if journal file is locked?
          expect: write throws, does not corrupt
          edge case: NFS mount with stale lock
          severity: medium
        """
        let spec = try S3Parser.parse(input)
        #expect(spec.concerns.count == 1)
        #expect(spec.concerns[0].question == "What if journal file is locked?")
        #expect(spec.concerns[0].expectation == "write throws, does not corrupt")
        #expect(spec.concerns[0].edgeCase == "NFS mount with stale lock")
        #expect(spec.concerns[0].severity == "medium")
    }

    @Test("Parse concern with only question")
    func minimalConcern() throws {
        let input = """
        # Spec

        ? Is this really needed?
        """
        let spec = try S3Parser.parse(input)
        #expect(spec.concerns.count == 1)
        #expect(spec.concerns[0].question == "Is this really needed?")
        #expect(spec.concerns[0].expectation == nil)
    }

    @Test("Parse multiple concerns")
    func multipleConcerns() throws {
        let input = """
        # Spec

        ? First concern
          expect: handled

        ? Second concern
          severity: high
        """
        let spec = try S3Parser.parse(input)
        #expect(spec.concerns.count == 2)
    }
}

@Suite("S3 Parser — Sections")
struct S3ParserSectionTests {

    @Test("H2 headers create sections")
    func sectionsFromHeaders() throws {
        let input = """
        # Main Spec

        ## Authentication

        When user logs in:
          → create session

        ## Authorization

        When user accesses admin:
          → check permissions
        """
        let spec = try S3Parser.parse(input)
        #expect(spec.sections.count == 2)
        #expect(spec.sections[0].title == "Authentication")
        #expect(spec.sections[1].title == "Authorization")
    }

    @Test("Scenarios without section go to default")
    func defaultSection() throws {
        let input = """
        # Spec

        When something happens:
          → do something
        """
        let spec = try S3Parser.parse(input)
        #expect(spec.sections.count == 1)
        #expect(spec.sections[0].title == "Spec")
    }
}

@Suite("S3 Parser — Sequences")
struct S3ParserSequenceTests {

    @Test("Parse then sequence steps")
    func thenSequence() throws {
        let input = """
        # Spec

        When user starts onboarding:
          → show welcome
          then user taps Next:
            → show features
          then user taps Get Started:
            → show signup form
        """
        let spec = try S3Parser.parse(input)
        let scenario = spec.sections[0].scenarios[0]
        #expect(scenario.assertions.count == 1)
        #expect(scenario.sequence != nil)
        #expect(scenario.sequence?.count == 2)
        #expect(scenario.sequence?[0].context == "user taps Next")
    }
}

@Suite("S3 Parser — Annotations")
struct S3ParserAnnotationTests {

    @Test("Parse @slow and @priority annotations")
    func annotations() throws {
        let input = """
        # Spec

        @slow @priority(high)
        When large upload completes:
          → should finish within 60 seconds
        """
        let spec = try S3Parser.parse(input)
        let scenario = spec.sections[0].scenarios[0]
        #expect(scenario.annotations.contains("slow"))
        #expect(scenario.annotations.contains("priority(high)"))
    }
}

@Suite("S3 Test Generator")
struct S3TestGeneratorTests {

    @Test("Generate test function names from scenarios")
    func generateFunctionNames() throws {
        let input = """
        # Session Lifecycle

        When session starts:
          → state should be spawning

        When invalid transition attempted:
          → should throw error
        """
        let spec = try S3Parser.parse(input)
        let output = S3TestGenerator.generate(spec)
        #expect(output.contains("@Suite(\"Session Lifecycle\")"))
        #expect(output.contains("@Test(\"Session starts\")"))
        #expect(output.contains("@Test(\"Invalid transition attempted\")"))
    }

    @Test("Generate parameterized test from for each")
    func generateParameterized() throws {
        let input = """
        # Spec

        For each field in [name, email]:
          when {field} is empty:
            → show error
        """
        let spec = try S3Parser.parse(input)
        let output = S3TestGenerator.generate(spec)
        #expect(output.contains("arguments:") || output.contains("[\"name\", \"email\"]"))
    }

    @Test("Generate edge case tests from concerns")
    func generateConcernTests() throws {
        let input = """
        # Spec

        ? What if file is locked?
          expect: throws without corruption
        """
        let spec = try S3Parser.parse(input)
        let output = S3TestGenerator.generate(spec)
        #expect(output.contains("file is locked"))
    }
}

@Suite("S3 Round-trip")
struct S3RoundTripTests {

    @Test("Parse → generate → parseable output")
    func roundTrip() throws {
        let input = """
        # Auth Flow

        ## Login

        When user submits credentials:
          if valid:
            → create session
          otherwise:
            → show error

        ## Concerns

        ? What about rate limiting?
          expect: block after 5 failed attempts
          severity: high
        """
        let spec = try S3Parser.parse(input)
        #expect(spec.title == "Auth Flow")
        #expect(spec.sections.count >= 1)
        #expect(spec.concerns.count == 1)

        let generated = S3TestGenerator.generate(spec)
        #expect(!generated.isEmpty)
        #expect(generated.contains("@Suite"))
        #expect(generated.contains("@Test"))
    }
}
