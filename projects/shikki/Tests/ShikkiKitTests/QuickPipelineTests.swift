import Foundation
import Testing
@testable import ShikkiKit

// MARK: - QuickPipeline Tests

@Suite("QuickPipeline — Quick Flow Pipeline")
struct QuickPipelineTests {

    // MARK: - ScopeDetector Tests

    @Test("Scope detector returns 0 for simple prompts")
    func scopeDetector_simplePrompt_scoreZero() {
        let detector = ScopeDetector()
        let result = detector.evaluate("fix the typo in README")
        #expect(result.score == 0)
        #expect(result.signals.isEmpty)
    }

    @Test("Scope detector flags architecture language")
    func scopeDetector_architectureLanguage_flagged() {
        let detector = ScopeDetector()
        let result = detector.evaluate("redesign the authentication system")
        #expect(result.signals.contains(.architectureLanguage))
    }

    @Test("Scope detector flags user uncertainty")
    func scopeDetector_uncertainty_flagged() {
        let detector = ScopeDetector()
        let result = detector.evaluate("maybe we should change the API, not sure if it breaks things")
        #expect(result.signals.contains(.userUncertainty))
    }

    @Test("Scope detector flags navigation keywords")
    func scopeDetector_navigation_flagged() {
        let detector = ScopeDetector()
        let result = detector.evaluate("add a new screen for user settings with coordinator")
        #expect(result.signals.contains(.newNavigation))
    }

    @Test("Scope detector flags DI keywords")
    func scopeDetector_diKeywords_flagged() {
        let detector = ScopeDetector()
        let result = detector.evaluate("register the new service in the DI container")
        #expect(result.signals.contains(.newDI))
    }

    @Test("Scope detector flags many-files keywords")
    func scopeDetector_manyFiles_flagged() {
        let detector = ScopeDetector()
        let result = detector.evaluate("rename this variable everywhere across the project")
        #expect(result.signals.contains(.manyFiles))
    }

    @Test("Scope detector scores >= 2 for complex prompts")
    func scopeDetector_complexPrompt_highScore() {
        let detector = ScopeDetector()
        let result = detector.evaluate(
            "redesign the navigation system, maybe add dependency injection container"
        )
        #expect(result.score >= 2)
    }

    @Test("Scope detector is case-insensitive")
    func scopeDetector_caseInsensitive() {
        let detector = ScopeDetector()
        let result = detector.evaluate("REDESIGN the ARCHITECTURE")
        #expect(result.signals.contains(.architectureLanguage))
    }

    // MARK: - QuickPromptBuilder Tests

    @Test("Spec prompt includes change description")
    func specPrompt_includesChange() {
        let prompt = QuickPromptBuilder.buildSpecPrompt(
            change: "fix the off-by-one error",
            projectPath: nil
        )
        #expect(prompt.contains("fix the off-by-one error"))
        #expect(prompt.contains("Quick Flow"))
        #expect(prompt.contains("Problem"))
    }

    @Test("Spec prompt includes project path when provided")
    func specPrompt_includesProjectPath() {
        let prompt = QuickPromptBuilder.buildSpecPrompt(
            change: "fix bug",
            projectPath: "/path/to/project"
        )
        #expect(prompt.contains("/path/to/project"))
    }

    @Test("Implementation prompt includes TDD rules")
    func implPrompt_includesTDD() {
        let prompt = QuickPromptBuilder.buildImplementationPrompt(
            change: "fix bug",
            spec: "the spec",
            projectPath: nil
        )
        #expect(prompt.contains("TDD"))
        #expect(prompt.contains("failing test"))
        #expect(prompt.contains("the spec"))
    }

    @Test("Review prompt includes all context")
    func reviewPrompt_includesAllContext() {
        let prompt = QuickPromptBuilder.buildReviewPrompt(
            change: "fix bug",
            spec: "the spec",
            implementation: "the impl",
            projectPath: nil
        )
        #expect(prompt.contains("fix bug"))
        #expect(prompt.contains("the spec"))
        #expect(prompt.contains("the impl"))
        #expect(prompt.contains("git diff"))
    }

    // MARK: - QuickOutputParser Tests

    @Test("Extract summary from Problem line")
    func extractSummary_fromProblem() {
        let output = """
        # Quick Spec
        - Problem: The README has a typo on line 42
        - Solution: Fix the typo
        """
        let summary = QuickOutputParser.extractSummary(from: output)
        #expect(summary == "The README has a typo on line 42")
    }

    @Test("Extract summary falls back to first non-heading line")
    func extractSummary_fallback() {
        let output = """
        # Quick Spec
        This is a simple fix for the API endpoint.
        """
        let summary = QuickOutputParser.extractSummary(from: output)
        #expect(summary == "This is a simple fix for the API endpoint.")
    }

    @Test("Extract summary returns nil for empty output")
    func extractSummary_empty() {
        let summary = QuickOutputParser.extractSummary(from: "")
        #expect(summary == nil)
    }

    @Test("Parse stats from implementation output")
    func parseStats_validOutput() {
        let output = """
        Implementation complete:
        - 3 files changed
        - 42 tests passing
        - 2 new tests added
        """
        let stats = QuickOutputParser.parseStats(from: output)
        #expect(stats.filesChanged == 3)
        #expect(stats.testsPassing == 42)
        #expect(stats.newTests == 2)
    }

    @Test("Parse stats returns zeros for missing patterns")
    func parseStats_missing() {
        let output = "Done, everything looks good."
        let stats = QuickOutputParser.parseStats(from: output)
        #expect(stats.filesChanged == 0)
        #expect(stats.testsPassing == 0)
        #expect(stats.newTests == 0)
    }

    // MARK: - QuickPipelineStep Tests

    @Test("Pipeline steps have correct descriptions")
    func pipelineSteps_descriptions() {
        #expect(QuickPipelineStep.spec.description == "step_1_spec")
        #expect(QuickPipelineStep.implementation.description == "step_2_implementation")
        #expect(QuickPipelineStep.selfReview.description == "step_3_self_review")
        #expect(QuickPipelineStep.ship.description == "step_4_ship")
    }

    @Test("Pipeline steps have correct display names")
    func pipelineSteps_displayNames() {
        #expect(QuickPipelineStep.spec.displayName == "Quick Spec")
        #expect(QuickPipelineStep.implementation.displayName == "TDD Implementation")
        #expect(QuickPipelineStep.selfReview.displayName == "Self-Review")
        #expect(QuickPipelineStep.ship.displayName == "Ship")
    }

    @Test("All 4 pipeline steps are defined")
    func pipelineSteps_count() {
        #expect(QuickPipelineStep.allCases.count == 4)
    }

    // MARK: - QuickPipeline Integration Tests

    @Test("Pipeline rejects empty prompt")
    func pipeline_emptyPrompt_throws() async {
        let agent = MockAgentProvider()
        let pipeline = QuickPipeline(agent: agent)

        do {
            _ = try await pipeline.run(prompt: "   ", yolo: false)
            Issue.record("Expected emptyPrompt error")
        } catch let error as QuickPipelineError {
            #expect(error == .emptyPrompt)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Pipeline rejects scope-too-large prompts")
    func pipeline_scopeTooLarge_throws() async {
        let agent = MockAgentProvider()
        let pipeline = QuickPipeline(agent: agent)

        do {
            _ = try await pipeline.run(
                prompt: "redesign the architecture and add new navigation flow with coordinator",
                yolo: false
            )
            Issue.record("Expected scopeTooLarge error")
        } catch let error as QuickPipelineError {
            if case .scopeTooLarge(let score, _) = error {
                #expect(score >= 2)
            } else {
                Issue.record("Expected scopeTooLarge, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Pipeline runs full flow with mock agent")
    func pipeline_fullFlow_succeeds() async throws {
        let agent = MockAgentProvider()
        agent.response = """
        - Problem: Typo in README line 42
        - Solution: Fix the typo
        - Files: README.md
        - Test plan: None needed
        - Risk: Low

        3 files changed, 10 tests passing, 1 new test
        """

        let pipeline = QuickPipeline(agent: agent)
        let result = try await pipeline.run(prompt: "fix typo in README", yolo: true)

        #expect(result.stepsCompleted == 3) // spec + impl + review
        #expect(result.summary.contains("Typo"))
        #expect(result.commitHash == nil) // caller handles commit
        #expect(result.duration > 0)
        #expect(agent.runCallCount == 3) // spec + impl + review
    }

    @Test("Pipeline handles agent failure gracefully")
    func pipeline_agentFails_throwsQuickError() async {
        let agent = MockAgentProvider()
        agent.shouldThrow = true

        let pipeline = QuickPipeline(agent: agent)

        do {
            _ = try await pipeline.run(prompt: "fix something", yolo: false)
            Issue.record("Expected agentFailed error")
        } catch let error as QuickPipelineError {
            if case .agentFailed = error {
                // expected
            } else {
                Issue.record("Expected agentFailed, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // MARK: - QuickPipelineError Equality Tests

    @Test("QuickPipelineError supports Equatable")
    func errors_areEquatable() {
        #expect(QuickPipelineError.emptyPrompt == QuickPipelineError.emptyPrompt)
        #expect(
            QuickPipelineError.scopeTooLarge(score: 3, signals: ["a"])
            == QuickPipelineError.scopeTooLarge(score: 3, signals: ["a"])
        )
        #expect(
            QuickPipelineError.agentFailed("x")
            != QuickPipelineError.agentFailed("y")
        )
    }
}
