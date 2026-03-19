import Foundation
import Testing
@testable import ShikiCtlKit

// MARK: - Inter-Agent Messaging (5A)

@Suite("Inter-Agent Messaging")
struct AgentMessageTests {

    @Test("Agent question event routes to correct scope")
    func agentQuestionEvent() {
        let event = AgentMessages.question(
            fromSession: "sess-1", toSession: "sess-2",
            question: "What's the auth flow?"
        )
        #expect(event.type == .custom("agentQuestion"))
        #expect(event.payload["fromSession"] == .string("sess-1"))
        #expect(event.payload["toSession"] == .string("sess-2"))
    }

    @Test("Agent result event carries payload")
    func agentResultEvent() {
        let event = AgentMessages.result(
            sessionId: "sess-1",
            summary: "Tests pass, 42 green"
        )
        #expect(event.type == .custom("agentResult"))
        #expect(event.payload["summary"] == .string("Tests pass, 42 green"))
    }

    @Test("Agent handoff event includes context")
    func agentHandoffEvent() {
        let event = AgentMessages.handoff(
            fromSession: "sess-1",
            toPersona: .verify,
            context: "Implement done, needs verification"
        )
        #expect(event.type == .custom("agentHandoff"))
        #expect(event.payload["toPersona"] == .string("verify"))
    }

    @Test("Broadcast to all agents")
    func broadcastAll() {
        let event = AgentMessages.broadcast(
            message: "Context freeze in 5 minutes"
        )
        #expect(event.scope == .global)
        #expect(event.type == .custom("agentBroadcast"))
    }
}

// MARK: - Recovery Manager (5D)

@Suite("Recovery Manager")
struct RecoveryManagerTests {

    @Test("Scan finds sessions needing recovery")
    func scanFindsRecoverable() async throws {
        let journal = SessionJournal(basePath: NSTemporaryDirectory() + "shiki-recovery-\(UUID().uuidString)")

        // Write a checkpoint for a session that was working
        let checkpoint = SessionCheckpoint(
            sessionId: "crashed-sess",
            state: .working,
            reason: .stateTransition,
            metadata: ["task": "t-1"]
        )
        try? await journal.checkpoint(checkpoint)

        let manager = RecoveryManager(journal: journal)
        let recoverable = try await manager.findRecoverableSessions()

        #expect(recoverable.count == 1)
        #expect(recoverable[0].sessionId == "crashed-sess")
        #expect(recoverable[0].lastState == .working)
    }

    @Test("Completed sessions are not recoverable")
    func completedNotRecoverable() async throws {
        let journal = SessionJournal(basePath: NSTemporaryDirectory() + "shiki-recovery-\(UUID().uuidString)")

        let checkpoint = SessionCheckpoint(
            sessionId: "done-sess",
            state: .done,
            reason: .stateTransition,
            metadata: nil
        )
        try? await journal.checkpoint(checkpoint)

        let manager = RecoveryManager(journal: journal)
        let recoverable = try await manager.findRecoverableSessions()

        #expect(recoverable.isEmpty)
    }

    @Test("Recovery plan includes checkpoint context")
    func recoveryPlanHasContext() async throws {
        let journal = SessionJournal(basePath: NSTemporaryDirectory() + "shiki-recovery-\(UUID().uuidString)")

        let checkpoint = SessionCheckpoint(
            sessionId: "resume-sess",
            state: .prOpen,
            reason: .stateTransition,
            metadata: ["task": "t-5", "branch": "feature/auth"]
        )
        try? await journal.checkpoint(checkpoint)

        let manager = RecoveryManager(journal: journal)
        let plan = try await manager.buildRecoveryPlan(sessionId: "resume-sess")

        #expect(plan != nil)
        #expect(plan?.lastState == .prOpen)
        #expect(plan?.metadata?["branch"] == "feature/auth")
    }
}

// MARK: - Agent Handoff Chain (5E)

@Suite("Agent Handoff Chain")
struct AgentHandoffTests {

    @Test("Standard chain: implement → verify → review")
    func standardChain() {
        let chain = HandoffChain.standard
        #expect(chain.next(after: .implement) == .verify)
        #expect(chain.next(after: .verify) == .review)
        #expect(chain.next(after: .review) == nil) // terminal
    }

    @Test("Fix chain: fix → verify")
    func fixChain() {
        let chain = HandoffChain.fix
        #expect(chain.next(after: .fix) == .verify)
        #expect(chain.next(after: .verify) == nil)
    }

    @Test("Handoff context serialization")
    func handoffContextSerialization() throws {
        let context = HandoffContext(
            fromPersona: .implement,
            toPersona: .verify,
            specPath: ".shiki/specs/t-1.md",
            changedFiles: ["Foo.swift", "FooTests.swift"],
            testResults: "42 tests passed",
            summary: "Feature complete, needs verification"
        )

        let data = try JSONEncoder().encode(context)
        let decoded = try JSONDecoder().decode(HandoffContext.self, from: data)

        #expect(decoded.fromPersona == .implement)
        #expect(decoded.toPersona == .verify)
        #expect(decoded.changedFiles.count == 2)
    }
}
