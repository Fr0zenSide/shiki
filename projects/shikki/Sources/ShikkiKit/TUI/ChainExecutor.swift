import Foundation

// MARK: - StepOutput

/// The result of executing a single chain step (BR-EM-CHAIN-03).
public struct StepOutput: Sendable, Equatable, Codable {
    public let command: String
    public let result: String
    public let success: Bool

    public init(command: String, result: String, success: Bool) {
        self.command = command
        self.result = result
        self.success = success
    }
}

// MARK: - ChainExecutor

/// Executes an `EmojiChain` sequentially, piping each step's output to the next (BR-EM-CHAIN-03).
///
/// This is currently a stub executor that records steps without performing real
/// command dispatch. The real executor will delegate to `ShikiCore` lifecycle
/// commands once that package is available.
public struct ChainExecutor: Sendable {

    public init() {}

    /// Execute all steps in the chain sequentially.
    /// Each step receives the previous step's output as context.
    ///
    /// - Parameter chain: The parsed emoji chain to execute.
    /// - Returns: An array of `StepOutput` values, one per step.
    public func execute(_ chain: EmojiChain) async -> [StepOutput] {
        var outputs: [StepOutput] = []
        var previousResult: String? = nil

        for step in chain.steps {
            let context = buildContext(
                step: step,
                target: chain.target,
                args: chain.rawArgs,
                previousResult: previousResult
            )
            // Stub: record the step as successful with context summary
            let output = StepOutput(
                command: step.command,
                result: context,
                success: true
            )
            outputs.append(output)
            previousResult = output.result
        }

        return outputs
    }

    // MARK: - Private

    /// Build a context string for a step, incorporating target, args, and prior output.
    private func buildContext(
        step: ChainStep,
        target: AgentTarget?,
        args: String,
        previousResult: String?
    ) -> String {
        var parts: [String] = [step.command]

        if let target {
            switch target {
            case .team:
                parts.append("@team")
            case .agent(let name):
                parts.append("@\(name)")
            case .namedTeam(let name):
                parts.append("@\(name)")
            }
        }

        if !args.isEmpty {
            parts.append(args)
        }

        if let prev = previousResult {
            parts.append("[prior: \(prev)]")
        }

        return parts.joined(separator: " ")
    }
}
