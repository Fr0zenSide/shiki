import Foundation
import Testing
@testable import ShikkiKit

@Suite("S3 Parser — Edge cases")
struct S3ParserEdgeCaseTests {

    @Test("Arrow syntax (->) works as alternative to unicode arrow")
    func asciiArrowSyntax() throws {
        let input = """
        # Spec

        When user types:
          -> autocomplete shows
          -> cursor stays in place
        """
        let spec = try S3Parser.parse(input)
        let scenario = spec.sections[0].scenarios[0]
        #expect(scenario.assertions.count == 2)
        #expect(scenario.assertions[0] == "autocomplete shows")
    }

    @Test("Mixed arrow syntaxes in same block")
    func mixedArrowSyntax() throws {
        let input = """
        # Spec

        When user types:
          → first assertion
          -> second assertion
        """
        let spec = try S3Parser.parse(input)
        let scenario = spec.sections[0].scenarios[0]
        #expect(scenario.assertions.count == 2)
    }

    @Test("Empty spec produces empty sections")
    func emptySpec() throws {
        let input = """
        # Empty Spec
        """
        let spec = try S3Parser.parse(input)
        #expect(spec.title == "Empty Spec")
        #expect(spec.sections.isEmpty)
        #expect(spec.concerns.isEmpty)
    }

    @Test("Only title, no content")
    func onlyTitle() throws {
        let input = "# My Title"
        let spec = try S3Parser.parse(input)
        #expect(spec.title == "My Title")
        #expect(spec.sections.isEmpty)
    }

    @Test("Untitled spec with When block")
    func untitledSpec() throws {
        let input = """
        When something:
          → happens
        """
        let spec = try S3Parser.parse(input)
        #expect(spec.title == "Untitled Spec")
        #expect(spec.sections.count == 1)
        #expect(spec.sections[0].title == "Untitled Spec")
    }

    @Test("Concerns section header does not create a section")
    func concernsSectionIsSpecial() throws {
        let input = """
        # Spec

        ## Auth

        When login:
          → session

        ## Concerns

        ? Something
          expect: handled
        """
        let spec = try S3Parser.parse(input)
        #expect(spec.sections.count == 1)
        #expect(spec.sections[0].title == "Auth")
        #expect(spec.concerns.count == 1)
    }

    @Test("Deep nesting — conditions inside depending on ignored in favor of depending cases")
    func dependingOnCases() throws {
        let input = """
        # Spec

        When mode changes:
          depending on current mode:
            "edit" → enable editing tools
            "view" → show read-only toolbar
            "preview" → render markdown
        """
        let spec = try S3Parser.parse(input)
        let scenario = spec.sections[0].scenarios[0]
        #expect(scenario.conditions.count == 3)
        #expect(scenario.conditions[0].condition == "edit")
        #expect(scenario.conditions[1].condition == "view")
        #expect(scenario.conditions[2].condition == "preview")
    }

    @Test("For each with trailing colon on list")
    func forEachTrailingColon() throws {
        let input = """
        # Spec

        For each item in [a, b, c]:
          when {item} works:
            → passes
        """
        let spec = try S3Parser.parse(input)
        let scenario = spec.sections[0].scenarios[0]
        #expect(scenario.loopValues == ["a", "b", "c"])
    }

    @Test("Multiple sections with empty sections")
    func multipleSections() throws {
        let input = """
        # Spec

        ## Section A

        When a:
          → does a

        ## Section B

        When b:
          → does b

        ## Section C

        When c:
          → does c
        """
        let spec = try S3Parser.parse(input)
        #expect(spec.sections.count == 3)
        #expect(spec.sections[0].scenarios.count == 1)
        #expect(spec.sections[1].scenarios.count == 1)
        #expect(spec.sections[2].scenarios.count == 1)
    }

    @Test("Annotations are carried to correct scenario")
    func annotationsAttachToNextScenario() throws {
        let input = """
        # Spec

        @slow
        When long operation:
          → takes a while

        When quick operation:
          → instant
        """
        let spec = try S3Parser.parse(input)
        #expect(spec.sections[0].scenarios[0].annotations == ["slow"])
        #expect(spec.sections[0].scenarios[1].annotations.isEmpty)
    }

    @Test("Multiple annotations on separate lines")
    func multiLineAnnotations() throws {
        let input = """
        # Spec

        @slow
        @flaky
        @priority(high)
        When complex test:
          → works sometimes
        """
        let spec = try S3Parser.parse(input)
        let scenario = spec.sections[0].scenarios[0]
        #expect(scenario.annotations.contains("slow"))
        #expect(scenario.annotations.contains("flaky"))
        #expect(scenario.annotations.contains("priority(high)"))
    }

    @Test("Concern without metadata fields")
    func bareMinimalConcern() throws {
        let input = """
        # Spec

        ? Is this a valid concern?
        """
        let spec = try S3Parser.parse(input)
        #expect(spec.concerns.count == 1)
        #expect(spec.concerns[0].question == "Is this a valid concern?")
        #expect(spec.concerns[0].expectation == nil)
        #expect(spec.concerns[0].edgeCase == nil)
        #expect(spec.concerns[0].severity == nil)
    }

    @Test("Full lifecycle example from spec doc")
    func fullLifecycleExample() throws {
        let input = """
        # Session Lifecycle Spec

        ## State Machine

        When a new session is created:
          → state should be "spawning"
          → attention zone should be "pending"
          → transition history should be empty

        When session transitions to working:
          → state should change from "spawning" to "working"
          → transition history should record actor and reason

        For each valid transition in [spawning→working, working→prOpen, prOpen→approved, approved→merged]:
          when transition is requested:
            → should succeed without error
            → history should record the transition

        When session receives invalid transition (done → working):
          → should throw invalidTransition error
          → state should remain "done"

        ## Budget

        When session spend reaches daily budget:
          → shouldBudgetPause should return true

          if budget is 0 (unlimited):
            → shouldBudgetPause should return false regardless of spend

        ## Concerns

        ? What if two registries observe the same tmux pane?
          expect: both register it, but only one should own lifecycle transitions
          edge case: split-brain during network partition between processes
          severity: medium
        """
        let spec = try S3Parser.parse(input)
        #expect(spec.title == "Session Lifecycle Spec")
        #expect(spec.sections.count == 2)
        #expect(spec.sections[0].title == "State Machine")
        #expect(spec.sections[0].scenarios.count == 3) // 2 when + 1 foreach (absorbs trailing when as sub-condition)
        #expect(spec.sections[1].title == "Budget")
        #expect(spec.sections[1].scenarios.count == 1)
        #expect(spec.concerns.count == 1)
        #expect(spec.concerns[0].severity == "medium")
    }

    @Test("Then sequence with multiple assertions per step")
    func thenSequenceMultipleAssertions() throws {
        let input = """
        # Spec

        When checkout flow starts:
          → show cart summary
          → show total
          then user enters shipping:
            → validate address
            → calculate shipping cost
          then user confirms payment:
            → charge card
            → send receipt
            → redirect to confirmation
        """
        let spec = try S3Parser.parse(input)
        let scenario = spec.sections[0].scenarios[0]
        #expect(scenario.assertions.count == 2)
        #expect(scenario.sequence?.count == 2)
        #expect(scenario.sequence?[0].assertions.count == 2)
        #expect(scenario.sequence?[1].assertions.count == 3)
    }
}

@Suite("S3 Test Generator — Edge cases")
struct S3TestGeneratorEdgeCaseTests {

    @Test("Generated output contains import statements")
    func hasImports() throws {
        let input = """
        # Test

        When x:
          → y
        """
        let spec = try S3Parser.parse(input)
        let output = S3TestGenerator.generate(spec)
        #expect(output.contains("import Testing"))
        #expect(output.contains("import Foundation"))
    }

    @Test("Suite name derived from spec title")
    func suiteNameFromTitle() throws {
        let input = """
        # My Feature Tests

        When a:
          → b
        """
        let spec = try S3Parser.parse(input)
        let output = S3TestGenerator.generate(spec)
        #expect(output.contains("@Suite(\"My Feature Tests\")"))
        #expect(output.contains("struct MyFeatureTestsTests"))
    }

    @Test("Section headings become MARK comments")
    func sectionMarks() throws {
        let input = """
        # Spec

        ## Auth

        When login:
          → session

        ## Profile

        When update:
          → saved
        """
        let spec = try S3Parser.parse(input)
        let output = S3TestGenerator.generate(spec)
        #expect(output.contains("// MARK: - Auth"))
        #expect(output.contains("// MARK: - Profile"))
    }

    @Test("Conditions generate separate test functions")
    func conditionsGenerateSeparateFunctions() throws {
        let input = """
        # Spec

        When submit:
          if valid:
            → save
          otherwise:
            → error
        """
        let spec = try S3Parser.parse(input)
        let output = S3TestGenerator.generate(spec)
        // Should have two @Test attributes
        let testCount = output.components(separatedBy: "@Test(").count - 1
        #expect(testCount == 2)
    }

    @Test("Sequence generates integration test with steps")
    func sequenceGeneratesIntegrationTest() throws {
        let input = """
        # Spec

        When flow starts:
          → step 0
          then user continues:
            → step 1
        """
        let spec = try S3Parser.parse(input)
        let output = S3TestGenerator.generate(spec)
        #expect(output.contains("full sequence"))
        #expect(output.contains("Step 0"))
        #expect(output.contains("Step 1"))
    }

    @Test("Concern with expectation generates edge case test")
    func concernGeneratesTest() throws {
        let input = """
        # Spec

        ? What if disk is full?
          expect: graceful error, no data loss
          edge case: mid-write crash
        """
        let spec = try S3Parser.parse(input)
        let output = S3TestGenerator.generate(spec)
        #expect(output.contains("Edge Cases (from Concerns)"))
        #expect(output.contains("disk is full"))
        #expect(output.contains("Expect: graceful error"))
        #expect(output.contains("Edge case: mid-write crash"))
    }

    @Test("Concern without expectation does not generate test")
    func concernWithoutExpectNoTest() throws {
        let input = """
        # Spec

        ? Just a question
        """
        let spec = try S3Parser.parse(input)
        let output = S3TestGenerator.generate(spec)
        #expect(!output.contains("Just a question"))
    }

    @Test("Parameterized test includes arguments array")
    func parameterizedArguments() throws {
        let input = """
        # Spec

        For each role in [admin, editor, viewer]:
          when {role} accesses settings:
            → show appropriate options
        """
        let spec = try S3Parser.parse(input)
        let output = S3TestGenerator.generate(spec)
        #expect(output.contains("arguments: [\"admin\", \"editor\", \"viewer\"]"))
        #expect(output.contains("role: String"))
    }

    @Test("Empty spec generates minimal valid Swift")
    func emptySpecOutput() throws {
        let input = """
        # Empty
        """
        let spec = try S3Parser.parse(input)
        let output = S3TestGenerator.generate(spec)
        #expect(output.contains("@Suite(\"Empty\")"))
        #expect(output.contains("struct EmptyTests"))
        #expect(output.contains("}"))
    }
}

@Suite("S3 Round-trip — Extended")
struct S3RoundTripExtendedTests {

    @Test("Complex spec round-trips through parse and generate")
    func complexRoundTrip() throws {
        let input = """
        # Shopping Cart

        ## Product Selection

        When user adds item to cart:
          → cart count increments
          → total price updates
          → undo button appears

        When user removes last item:
          → show empty cart message
          → hide checkout button

        ## Checkout

        When user proceeds to checkout:
          if cart is empty:
            → block navigation
            → show "Add items first"
          if cart has items:
            → show order summary
            → pre-fill saved address

        ## Discounts

        When discount code applied:
          depending on code type:
            "percentage" → reduce total by percentage
            "fixed" → subtract fixed amount
            "bogo" → add free item to cart

        ## Concerns

        ? What if price changes between adding and checkout?
          expect: show price change notification
          edge case: item goes out of stock during checkout
          severity: high

        ? What about currency conversion?
          expect: use exchange rate at checkout time
          severity: medium
        """
        let spec = try S3Parser.parse(input)
        #expect(spec.title == "Shopping Cart")
        #expect(spec.sections.count == 3) // Concerns section excluded
        #expect(spec.concerns.count == 2)

        let generated = S3TestGenerator.generate(spec)
        #expect(generated.contains("@Suite(\"Shopping Cart\")"))
        #expect(generated.contains("Product Selection"))
        #expect(generated.contains("Checkout"))
        #expect(generated.contains("Discounts"))

        // Statistics
        let stats = S3Statistics.from(spec)
        #expect(stats.scenarioCount == 4)
        #expect(stats.concernCount == 2)
        #expect(stats.testableCount > 0)
    }

    @Test("Validation then parse consistency")
    func validationThenParse() throws {
        let input = """
        # Valid Spec

        When user logs in:
          → session starts
          if admin:
            → show admin panel

        ? Rate limiting?
          expect: block after 5 fails
        """
        let validation = S3Validator.validate(input)
        #expect(validation.isValid)

        let spec = try S3Parser.parse(input)
        #expect(spec.sections.count == 1)
        #expect(spec.concerns.count == 1)

        let stats = S3Statistics.from(spec)
        #expect(stats.testableCount == 3) // 1 standalone + 1 condition + 1 concern
    }
}
