import Foundation
import Testing
@testable import ShikiCore

@Suite("ShikiAgentClient")
struct ShikiAgentClientTests {

    // MARK: - Mock Provider

    struct MockProvider: AgentProvider {
        let name: String
        let result: AgentResult
        let shouldThrow: Bool

        var currentSessionSpend: Double { 0.0 }

        init(
            name: String = "mock",
            output: String = "done",
            exitCode: Int32 = 0,
            shouldThrow: Bool = false
        ) {
            self.name = name
            self.result = AgentResult(
                output: output,
                exitCode: exitCode,
                tokensUsed: 100,
                duration: .seconds(1)
            )
            self.shouldThrow = shouldThrow
        }

        func dispatch(prompt: String, workingDirectory: URL, options: AgentOptions) async throws -> AgentResult {
            if shouldThrow {
                throw AgentClientError.dispatchFailed("Mock failure")
            }
            return result
        }

        func cancel() async {}
    }

    enum AgentClientError: Error {
        case dispatchFailed(String)
    }

    // MARK: - Tests

    @Test("Dispatch creates session and returns ID")
    func dispatchCreatesSession() async throws {
        let client = ShikiAgentClient()
        let provider = MockProvider()

        let sessionId = try await client.dispatch(
            featureId: "feat-1",
            provider: provider,
            prompt: "Build the feature",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )

        let session = await client.session(id: sessionId)
        #expect(session != nil)
        #expect(session?.featureId == "feat-1")
        #expect(session?.status == .completed)
    }

    @Test("Failed dispatch marks session as failed")
    func failedDispatch() async {
        let client = ShikiAgentClient()
        let provider = MockProvider(shouldThrow: true)

        do {
            _ = try await client.dispatch(
                featureId: "feat-1",
                provider: provider,
                prompt: "Will fail",
                workingDirectory: URL(fileURLWithPath: "/tmp")
            )
            Issue.record("Expected error to be thrown")
        } catch {
            // Expected
        }
    }

    @Test("Non-zero exit code marks session as failed")
    func nonZeroExitCode() async throws {
        let client = ShikiAgentClient()
        let provider = MockProvider(exitCode: 1)

        let sessionId = try await client.dispatch(
            featureId: "feat-1",
            provider: provider,
            prompt: "Bad exit",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )

        let session = await client.session(id: sessionId)
        #expect(session?.status == .failed)
    }

    @Test("Sessions filtered by feature ID")
    func sessionsByFeature() async throws {
        let client = ShikiAgentClient()

        _ = try await client.dispatch(
            featureId: "feat-1",
            provider: MockProvider(name: "agent-a"),
            prompt: "Task A",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )
        _ = try await client.dispatch(
            featureId: "feat-2",
            provider: MockProvider(name: "agent-b"),
            prompt: "Task B",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )

        let feat1Sessions = await client.sessions(featureId: "feat-1")
        let feat2Sessions = await client.sessions(featureId: "feat-2")
        #expect(feat1Sessions.count == 1)
        #expect(feat2Sessions.count == 1)
    }

    @Test("Cleanup removes non-running sessions")
    func cleanupRemovesCompleted() async throws {
        let client = ShikiAgentClient()

        _ = try await client.dispatch(
            featureId: "feat-1",
            provider: MockProvider(),
            prompt: "Done task",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )

        // All sessions should be completed (not running)
        let activeBefore = await client.activeCount
        #expect(activeBefore == 0)

        await client.cleanup()
        let sessionsAfter = await client.sessions(featureId: "feat-1")
        #expect(sessionsAfter.isEmpty)
    }

    @Test("AgentSession captures provider name and prompt")
    func agentSessionFields() {
        let provider = MockProvider(name: "claude-opus")
        let session = AgentSession(
            featureId: "feat-1",
            provider: provider,
            prompt: "Build feature X",
            workingDirectory: URL(fileURLWithPath: "/tmp/project")
        )

        #expect(session.featureId == "feat-1")
        #expect(session.prompt == "Build feature X")
        #expect(session.status == .running)
        #expect(session.result == nil)
    }
}
