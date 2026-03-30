import Foundation
import Testing
@testable import ShikkiKit

@Suite("Chat — Agent Targeting Resolution")
struct ChatTargetingTests {

    @Test("@ resolves to orchestrator by default")
    func defaultTarget() {
        let target = ChatTargetResolver.resolve("@orchestrator")
        #expect(target == .orchestrator)
    }

    @Test("@agent:session resolves to specific agent")
    func agentTarget() {
        let target = ChatTargetResolver.resolve("@maya:spm-wave3")
        #expect(target == .agent(sessionId: "maya:spm-wave3"))
    }

    @Test("@Sensei resolves to persona")
    func personaTarget() {
        let target = ChatTargetResolver.resolve("@Sensei")
        #expect(target == .persona(.investigate)) // Sensei = CTO review
    }

    @Test("@all resolves to broadcast")
    func broadcastTarget() {
        let target = ChatTargetResolver.resolve("@all")
        #expect(target == .broadcast)
    }

    @Test("Unknown target returns nil")
    func unknownTarget() {
        let target = ChatTargetResolver.resolve("hello")
        #expect(target == nil)
    }
}

@Suite("Prompt Composer — Ghost Text")
struct PromptComposerTests {

    @Test("After When: ghost shows assertion arrow")
    func ghostAfterWhen() {
        let ghost = PromptComposer.ghostText(afterLine: "When user opens app:")
        #expect(ghost == "  → show what happens")
    }

    @Test("After assertion: ghost shows another assertion")
    func ghostAfterAssertion() {
        let ghost = PromptComposer.ghostText(afterLine: "  → show onboarding")
        #expect(ghost == "  → next expected outcome")
    }

    @Test("After blank line: ghost shows When")
    func ghostAfterBlank() {
        let ghost = PromptComposer.ghostText(afterLine: "")
        #expect(ghost == "When / For each / ? / ## ")
    }

    @Test("After ## header: ghost shows section name hint")
    func ghostAfterHash() {
        let ghost = PromptComposer.ghostText(afterLine: "## ")
        #expect(ghost == "Section name")
        // After a filled section header, no ghost needed
        let ghostFilled = PromptComposer.ghostText(afterLine: "## Authentication")
        #expect(ghostFilled == "Section name")
    }

    @Test("@ trigger detected in text")
    func atTriggerDetected() {
        #expect(PromptComposer.detectTrigger(in: "Using @Security") == .at("Security"))
    }

    @Test("/ trigger detected in text")
    func slashTriggerDetected() {
        #expect(PromptComposer.detectTrigger(in: "Based on /d:auth") == .search("d:auth"))
    }
}
