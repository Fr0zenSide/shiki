import Foundation
import Testing
@testable import ShikkiKit

@Suite("S3 Validator — Structural errors")
struct S3ValidatorErrorTests {

    @Test("When block without colon is an error")
    func whenMissingColon() {
        let input = """
        # Spec

        When user opens app
          → show screen
        """
        let result = S3Validator.validate(input)
        #expect(!result.isValid)
        #expect(result.errors.count == 1)
        #expect(result.errors[0].message.contains("missing trailing colon"))
    }

    @Test("Assertion outside When is an error")
    func assertionOutsideWhen() {
        let input = """
        # Spec

        → orphan assertion
        """
        let result = S3Validator.validate(input)
        #expect(!result.isValid)
        #expect(result.errors.count == 1)
        #expect(result.errors[0].message.contains("assertion outside"))
    }

    @Test("Arrow assertion outside When is an error")
    func arrowAssertionOutsideWhen() {
        let input = """
        # Spec

        -> orphan assertion
        """
        let result = S3Validator.validate(input)
        #expect(!result.isValid)
        #expect(result.errors.count == 1)
        #expect(result.errors[0].message.contains("assertion outside"))
    }

    @Test("If condition outside When is an error")
    func ifOutsideWhen() {
        let input = """
        # Spec

        if something:
          → do thing
        """
        let result = S3Validator.validate(input)
        #expect(!result.isValid)
        #expect(result.errors.contains { $0.message.contains("if condition outside") })
    }

    @Test("Otherwise outside When is an error")
    func otherwiseOutsideWhen() {
        let input = """
        # Spec

        otherwise:
          → fallback
        """
        let result = S3Validator.validate(input)
        #expect(!result.isValid)
        #expect(result.errors.contains { $0.message.contains("otherwise outside") })
    }

    @Test("Depending on outside When is an error")
    func dependingOnOutsideWhen() {
        let input = """
        # Spec

        depending on the value:
          "a" → do something
        """
        let result = S3Validator.validate(input)
        #expect(!result.isValid)
        #expect(result.errors.contains { $0.message.contains("depending on outside") })
    }

    @Test("Then step outside When is an error")
    func thenOutsideWhen() {
        let input = """
        # Spec

        then user clicks:
          → something happens
        """
        let result = S3Validator.validate(input)
        #expect(!result.isValid)
        #expect(result.errors.contains { $0.message.contains("then step outside") })
    }

    @Test("For each without list brackets is an error")
    func forEachNoList() {
        let input = """
        # Spec

        For each item in something:
          when {item} happens:
            → do thing
        """
        let result = S3Validator.validate(input)
        #expect(!result.isValid)
        #expect(result.errors.contains { $0.message.contains("[list]") })
    }

    @Test("For each without 'in' keyword is an error")
    func forEachNoIn() {
        let input = """
        # Spec

        For each item [a, b]:
          when {item} happens:
            → do thing
        """
        let result = S3Validator.validate(input)
        #expect(!result.isValid)
        #expect(result.errors.contains { $0.message.contains("'in' keyword") })
    }
}

@Suite("S3 Validator — Warnings")
struct S3ValidatorWarningTests {

    @Test("When block with no content triggers warning")
    func emptyWhenBlock() {
        let input = """
        # Spec

        When user logs in:

        When user logs out:
          → session ends
        """
        let result = S3Validator.validate(input)
        #expect(result.isValid) // warnings don't invalidate
        #expect(result.warnings.count == 1)
        #expect(result.warnings[0].message.contains("no assertions"))
    }

    @Test("Depending on with no cases triggers warning")
    func emptyDependingOn() {
        let input = """
        # Spec

        When state changes:
          depending on the value:

        When next thing:
          → happens
        """
        let result = S3Validator.validate(input)
        #expect(result.isValid)
        #expect(result.warnings.contains { $0.message.contains("no cases") })
    }
}

@Suite("S3 Validator — Hints")
struct S3ValidatorHintTests {

    @Test("No title triggers hint")
    func noTitle() {
        let input = """
        When something happens:
          → do it
        """
        let result = S3Validator.validate(input)
        #expect(result.hints.contains { $0.message.contains("No title") })
    }

    @Test("No When blocks triggers hint")
    func noWhenBlocks() {
        let input = """
        # Empty Spec

        Just some text here.
        """
        let result = S3Validator.validate(input)
        #expect(result.hints.contains { $0.message.contains("No When blocks") })
    }
}

@Suite("S3 Validator — Valid documents")
struct S3ValidatorValidTests {

    @Test("Simple valid spec has no errors")
    func simpleValid() {
        let input = """
        # Valid Spec

        When user opens app:
          → show main screen
        """
        let result = S3Validator.validate(input)
        #expect(result.isValid)
        #expect(result.errors.isEmpty)
    }

    @Test("Complex valid spec passes")
    func complexValid() {
        let input = """
        # Session Lifecycle

        ## State Machine

        When session starts:
          → state should be spawning

        When user submits form:
          if valid:
            → create record
          otherwise:
            → show error

        ## Parameterized

        For each state in [active, paused, done]:
          when transition to {state}:
            → should succeed

        ## Sequences

        When onboarding begins:
          → show welcome
          then user taps next:
            → show features

        ## Concerns

        ? What about edge cases?
          expect: handled gracefully
          severity: low
        """
        let result = S3Validator.validate(input)
        #expect(result.isValid)
        #expect(result.errors.isEmpty)
    }

    @Test("Depending on with cases is valid")
    func dependingOnValid() {
        let input = """
        # Spec

        When status changes:
          depending on the value:
            "active" → unlock features
            "expired" → show paywall
        """
        let result = S3Validator.validate(input)
        #expect(result.isValid)
    }

    @Test("Annotations before When are valid")
    func annotationsValid() {
        let input = """
        # Spec

        @slow @priority(high)
        When large upload:
          → completes within 60s
        """
        let result = S3Validator.validate(input)
        #expect(result.isValid)
    }

    @Test("Multiple concerns are valid")
    func multipleConcernsValid() {
        let input = """
        # Spec

        When something:
          → works

        ? First concern
          expect: handled

        ? Second concern
          severity: high
        """
        let result = S3Validator.validate(input)
        #expect(result.isValid)
    }

    @Test("For each with proper list is valid")
    func forEachValid() {
        let input = """
        # Spec

        For each field in [name, email, password]:
          when {field} is empty:
            → show error
        """
        let result = S3Validator.validate(input)
        #expect(result.isValid)
    }
}
