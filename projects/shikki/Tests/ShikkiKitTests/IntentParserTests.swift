import Foundation
import Testing
@testable import ShikkiKit

@Suite("IntentParser — @who #where /what grammar")
struct IntentParserTests {

    @Test("Empty input returns empty intent")
    func emptyInput() {
        let intent = IntentParser.parse("")
        #expect(intent.target == nil)
        #expect(intent.scopes.isEmpty)
        #expect(intent.command == nil)
        #expect(intent.message == "")
    }

    @Test("Plain text becomes message")
    func plainText() {
        let intent = IntentParser.parse("Hello world")
        #expect(intent.target == nil)
        #expect(intent.scopes.isEmpty)
        #expect(intent.command == nil)
        #expect(intent.message == "Hello world")
    }

    @Test("@orchestrator resolves target")
    func atTarget() {
        let intent = IntentParser.parse("@orchestrator How many slots?")
        #expect(intent.target == .orchestrator)
        #expect(intent.message == "How many slots?")
    }

    @Test("@Sensei resolves to persona")
    func personaTarget() {
        let intent = IntentParser.parse("@Sensei review this")
        #expect(intent.target == .persona(.investigate))
        #expect(intent.message == "review this")
    }

    @Test("@all resolves to broadcast")
    func broadcastTarget() {
        let intent = IntentParser.parse("@all /status")
        #expect(intent.target == .broadcast)
        #expect(intent.command == "status")
    }

    @Test("#scope is captured")
    func singleScope() {
        let intent = IntentParser.parse("#maya check PRs")
        #expect(intent.scopes == ["maya"])
        #expect(intent.message == "check PRs")
    }

    @Test("Multiple #scopes stack")
    func multipleScopes() {
        let intent = IntentParser.parse("#maya #wave1 /review")
        #expect(intent.scopes == ["maya", "wave1"])
        #expect(intent.command == "review")
    }

    @Test("/command is captured")
    func commandCapture() {
        let intent = IntentParser.parse("/status")
        #expect(intent.command == "status")
        #expect(intent.message == "")
    }

    @Test("Full grammar: @who #where /what message")
    func fullGrammar() {
        let intent = IntentParser.parse("@Sensei #maya /review check auth flow")
        #expect(intent.target == .persona(.investigate))
        #expect(intent.scopes == ["maya"])
        #expect(intent.command == "review")
        #expect(intent.message == "check auth flow")
    }

    @Test("Quoted strings are preserved")
    func quotedStrings() {
        let intent = IntentParser.parse("@orchestrator \"do this complex thing\"")
        #expect(intent.target == .orchestrator)
        #expect(intent.message == "do this complex thing")
    }

    @Test("Agent session with colon resolves")
    func agentSession() {
        let intent = IntentParser.parse("@maya:spm-wave3 progress?")
        #expect(intent.target == .agent(sessionId: "maya:spm-wave3"))
        #expect(intent.message == "progress?")
    }

    @Test("Only first @ becomes target")
    func onlyFirstAt() {
        let intent = IntentParser.parse("@Sensei mention @Hanami")
        #expect(intent.target == .persona(.investigate))
        #expect(intent.message == "mention @Hanami")
    }

    @Test("Only first / becomes command")
    func onlyFirstSlash() {
        let intent = IntentParser.parse("/review check /path/to/file")
        #expect(intent.command == "review")
        #expect(intent.message == "check /path/to/file")
    }
}
