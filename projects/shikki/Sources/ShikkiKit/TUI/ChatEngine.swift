import Foundation

// MARK: - ChatMessage

/// A single message in the chat history.
public struct ChatMessage: Sendable, Equatable, Identifiable {
    public let id: String
    public let target: ChatTarget
    public let content: String
    public let timestamp: Date
    public let isOutgoing: Bool
    public let senderLabel: String

    public init(
        id: String = UUID().uuidString,
        target: ChatTarget,
        content: String,
        timestamp: Date = Date(),
        isOutgoing: Bool,
        senderLabel: String
    ) {
        self.id = id
        self.target = target
        self.content = content
        self.timestamp = timestamp
        self.isOutgoing = isOutgoing
        self.senderLabel = senderLabel
    }
}

// MARK: - ChatDelivery

/// Protocol for delivering messages to agents/orchestrator.
public protocol ChatDelivery: Sendable {
    func deliver(message: String, to target: ChatTarget) async -> String?
}

/// Stub delivery that echoes the message (for testing and initial TUI).
public struct EchoChatDelivery: ChatDelivery {
    public init() {}

    public func deliver(message: String, to target: ChatTarget) async -> String? {
        let label = Self.targetLabel(target)
        return "[\(label)] Acknowledged: \(message)"
    }

    static func targetLabel(_ target: ChatTarget) -> String {
        switch target {
        case .orchestrator: return "Orchestrator"
        case .agent(let id): return "Agent:\(id)"
        case .persona(let p): return "Persona:\(p.rawValue)"
        case .broadcast: return "All"
        }
    }
}

// MARK: - ChatEngine

/// Core chat engine: message routing, history, and targeting.
public actor ChatEngine {
    private var history: [ChatMessage] = []
    private let delivery: ChatDelivery
    private let maxHistory: Int

    public init(delivery: ChatDelivery = EchoChatDelivery(), maxHistory: Int = 200) {
        self.delivery = delivery
        self.maxHistory = maxHistory
    }

    /// Send a message to a target. Returns the response (if any).
    public func send(content: String, to target: ChatTarget) async -> ChatMessage? {
        // Record outgoing
        let outgoing = ChatMessage(
            target: target,
            content: content,
            isOutgoing: true,
            senderLabel: "You"
        )
        appendMessage(outgoing)

        // Deliver and get response
        guard let response = await delivery.deliver(message: content, to: target) else {
            return nil
        }

        let incoming = ChatMessage(
            target: target,
            content: response,
            isOutgoing: false,
            senderLabel: targetLabel(target)
        )
        appendMessage(incoming)
        return incoming
    }

    /// Send using parsed intent.
    public func send(intent: Intent) async -> ChatMessage? {
        let target = intent.target ?? .orchestrator
        let content = intent.message.isEmpty
            ? (intent.command ?? "")
            : intent.message
        guard !content.isEmpty else { return nil }
        return await send(content: content, to: target)
    }

    /// Full message history.
    public var messages: [ChatMessage] { history }

    /// Messages for a specific target.
    public func messages(for target: ChatTarget) -> [ChatMessage] {
        history.filter { $0.target == target }
    }

    /// Message count.
    public var messageCount: Int { history.count }

    /// Clear history.
    public func clearHistory() {
        history.removeAll()
    }

    // MARK: - Autocomplete

    /// Known targets for @ autocomplete in chat.
    public static let knownTargets: [(label: String, description: String)] = [
        ("@orchestrator", "Main orchestrator / HeartbeatLoop"),
        ("@shi", "Full team review (all personas)"),
        ("@shiki", "Full team review (all personas)"),
        ("@all", "Broadcast to all running sessions"),
        ("@Sensei", "CTO review persona"),
        ("@Hanami", "UX review persona"),
        ("@Kintsugi", "Philosophy persona"),
        ("@tech-expert", "Code review persona"),
        ("@Ronin", "Adversarial review persona"),
    ]

    /// Autocomplete suggestions for partial @ input.
    public static func autocomplete(partial: String) -> [(label: String, description: String)] {
        let query = partial.lowercased()
        if query.isEmpty { return knownTargets }
        return knownTargets.filter {
            $0.label.lowercased().contains(query)
        }
    }

    // MARK: - Private

    private func appendMessage(_ message: ChatMessage) {
        history.append(message)
        if history.count > maxHistory {
            history.removeFirst(history.count - maxHistory)
        }
    }

    private func targetLabel(_ target: ChatTarget) -> String {
        EchoChatDelivery.targetLabel(target)
    }
}
