import Testing
@testable import ShikkiKit

@Suite("ChainExecutor — Sequential Chain Execution (BR-EM-CHAIN-03)")
struct ChainExecutorTests {

    private let executor = ChainExecutor()

    // MARK: - Single Command Chain

    @Test("Single command chain executes and returns one output")
    func singleCommandChain() async {
        let chain = EmojiChain(
            steps: [ChainStep(emoji: "🌟", command: "challenge")],
            target: nil,
            rawArgs: ""
        )
        let outputs = await executor.execute(chain)
        #expect(outputs.count == 1)
        #expect(outputs[0].command == "challenge")
        #expect(outputs[0].success == true)
        #expect(outputs[0].result.contains("challenge"))
    }

    // MARK: - Multi-Command Chain

    @Test("Multi-command chain executes in order")
    func multiCommandChain() async {
        let chain = EmojiChain(
            steps: [
                ChainStep(emoji: "🌟", command: "challenge"),
                ChainStep(emoji: "🧠", command: "brain"),
            ],
            target: nil,
            rawArgs: ""
        )
        let outputs = await executor.execute(chain)
        #expect(outputs.count == 2)
        #expect(outputs[0].command == "challenge")
        #expect(outputs[1].command == "brain")
        // Second step should reference prior output
        #expect(outputs[1].result.contains("[prior:"))
    }

    @Test("Three-step chain pipes context through all steps")
    func threeStepChain() async {
        let chain = EmojiChain(
            steps: [
                ChainStep(emoji: "🌟", command: "challenge"),
                ChainStep(emoji: "🧠", command: "brain"),
                ChainStep(emoji: "📦", command: "ship"),
            ],
            target: nil,
            rawArgs: ""
        )
        let outputs = await executor.execute(chain)
        #expect(outputs.count == 3)
        #expect(outputs[0].command == "challenge")
        #expect(outputs[1].command == "brain")
        #expect(outputs[2].command == "ship")
        // First step has no prior context
        #expect(!outputs[0].result.contains("[prior:"))
        // Third step references second step's output
        #expect(outputs[2].result.contains("[prior:"))
    }

    // MARK: - Empty Chain

    @Test("Empty chain returns empty result")
    func emptyChain() async {
        let chain = EmojiChain(steps: [], target: nil, rawArgs: "")
        let outputs = await executor.execute(chain)
        #expect(outputs.isEmpty)
    }

    // MARK: - Target Propagation

    @Test("Chain with team target includes @team in context")
    func chainWithTeamTarget() async {
        let chain = EmojiChain(
            steps: [ChainStep(emoji: "🌟", command: "challenge")],
            target: .team,
            rawArgs: ""
        )
        let outputs = await executor.execute(chain)
        #expect(outputs.count == 1)
        #expect(outputs[0].result.contains("@team"))
    }

    @Test("Chain with agent target includes @agent in context")
    func chainWithAgentTarget() async {
        let chain = EmojiChain(
            steps: [ChainStep(emoji: "🧠", command: "brain")],
            target: .agent("Sensei"),
            rawArgs: ""
        )
        let outputs = await executor.execute(chain)
        #expect(outputs[0].result.contains("@Sensei"))
    }

    @Test("Chain with named team target includes @team-name in context")
    func chainWithNamedTeamTarget() async {
        let chain = EmojiChain(
            steps: [ChainStep(emoji: "🧠", command: "brain")],
            target: .namedTeam("tech"),
            rawArgs: ""
        )
        let outputs = await executor.execute(chain)
        #expect(outputs[0].result.contains("@tech"))
    }

    // MARK: - Args Propagation

    @Test("Chain with rawArgs includes them in context")
    func chainWithArgs() async {
        let chain = EmojiChain(
            steps: [ChainStep(emoji: "🔍", command: "research")],
            target: nil,
            rawArgs: "CRDTs"
        )
        let outputs = await executor.execute(chain)
        #expect(outputs[0].result.contains("CRDTs"))
    }

    @Test("All outputs report success in stub executor")
    func allOutputsSucceed() async {
        let chain = EmojiChain(
            steps: [
                ChainStep(emoji: "🌟", command: "challenge"),
                ChainStep(emoji: "🧠", command: "brain"),
            ],
            target: .team,
            rawArgs: "test args"
        )
        let outputs = await executor.execute(chain)
        for output in outputs {
            #expect(output.success == true)
        }
    }
}
