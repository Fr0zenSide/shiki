import Foundation
import Logging

// MARK: - AgentSession

/// Tracks a dispatched agent session.
public struct AgentSession: Sendable, Identifiable {
    public let id: String
    public let featureId: String
    public let provider: any AgentProvider
    public let prompt: String
    public let workingDirectory: URL
    public let startedAt: Date
    public var result: AgentResult?
    public var status: AgentSessionStatus

    public init(
        id: String = UUID().uuidString,
        featureId: String,
        provider: any AgentProvider,
        prompt: String,
        workingDirectory: URL,
        startedAt: Date = Date()
    ) {
        self.id = id
        self.featureId = featureId
        self.provider = provider
        self.prompt = prompt
        self.workingDirectory = workingDirectory
        self.startedAt = startedAt
        self.status = .running
    }
}

// MARK: - AgentSessionStatus

public enum AgentSessionStatus: String, Sendable {
    case running
    case completed
    case failed
    case cancelled
}

// MARK: - ShikiAgentClient

/// Actor that manages agent dispatch, resume, and cancellation.
/// Central point for all agent interactions in the lifecycle.
public actor ShikiAgentClient {
    private var sessions: [String: AgentSession] = [:]
    private let persister: (any EventPersisting)?
    private let logger = Logger(label: "shiki.core.agent-client")

    public init(persister: (any EventPersisting)? = nil) {
        self.persister = persister
    }

    /// Dispatch a new agent session. Returns the session ID.
    public func dispatch(
        featureId: String,
        provider: any AgentProvider,
        prompt: String,
        workingDirectory: URL,
        options: AgentOptions = AgentOptions()
    ) async throws -> String {
        let session = AgentSession(
            featureId: featureId,
            provider: provider,
            prompt: prompt,
            workingDirectory: workingDirectory
        )

        sessions[session.id] = session

        if let persister {
            let payload = CoreEvent.agentDispatched(
                featureId: featureId,
                agentName: provider.name,
                prompt: prompt
            )
            await persister.persist(payload)
        }

        // Run the agent asynchronously
        let sessionId = session.id
        let result: AgentResult
        do {
            result = try await provider.dispatch(
                prompt: prompt,
                workingDirectory: workingDirectory,
                options: options
            )
        } catch {
            sessions[sessionId]?.status = .failed

            if let persister {
                let payload = CoreEvent.agentFailed(
                    featureId: featureId,
                    agentName: provider.name,
                    error: error.localizedDescription
                )
                await persister.persist(payload)
            }

            throw error
        }

        sessions[sessionId]?.result = result
        sessions[sessionId]?.status = result.exitCode == 0 ? .completed : .failed

        if let persister {
            let payload = CoreEvent.agentCompleted(
                featureId: featureId,
                agentName: provider.name,
                exitCode: result.exitCode
            )
            await persister.persist(payload)
        }

        return sessionId
    }

    /// Cancel an active agent session.
    public func cancel(sessionId: String) async {
        guard let session = sessions[sessionId], session.status == .running else {
            return
        }

        await session.provider.cancel()
        sessions[sessionId]?.status = .cancelled
    }

    /// Get the status of a session.
    public func session(id: String) -> AgentSession? {
        sessions[id]
    }

    /// Get all sessions for a feature.
    public func sessions(featureId: String) -> [AgentSession] {
        sessions.values.filter { $0.featureId == featureId }
    }

    /// Get all active (running) sessions.
    public var activeSessions: [AgentSession] {
        sessions.values.filter { $0.status == .running }
    }

    /// Count of active sessions.
    public var activeCount: Int {
        activeSessions.count
    }

    /// Remove completed/failed/cancelled sessions.
    public func cleanup() {
        sessions = sessions.filter { $0.value.status == .running }
    }
}
