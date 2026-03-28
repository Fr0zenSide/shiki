import Testing
@testable import ShikkiKit

@Suite("ChainParser — Emoji Chaining (BR-EM-CHAIN-01..11)")
struct ChainParserTests {

    // MARK: - BR-EM-CHAIN-01: Chain Parsing

    @Test("Two emoji chain parses into two steps")
    func twoEmojiChain() {
        let result = ChainParser.parse("🌟🧠")
        guard case .chain(let chain) = result else {
            Issue.record("Expected .chain, got \(result)")
            return
        }
        #expect(chain.steps.count == 2)
        #expect(chain.steps[0].command == "challenge")
        #expect(chain.steps[1].command == "brain")
        #expect(chain.target == nil)
    }

    @Test("Triple emoji chain parses into three steps")
    func tripleEmojiChain() {
        let result = ChainParser.parse("🌟🧠📦")
        guard case .chain(let chain) = result else {
            Issue.record("Expected .chain, got \(result)")
            return
        }
        #expect(chain.steps.count == 3)
        #expect(chain.steps[0].command == "challenge")
        #expect(chain.steps[1].command == "brain")
        #expect(chain.steps[2].command == "ship")
    }

    // MARK: - BR-EM-CHAIN-02: Agent Targeting

    @Test("Chain with @t target resolves to .team")
    func chainWithTeamTarget() {
        let result = ChainParser.parse("🌟🧠@t")
        guard case .chain(let chain) = result else {
            Issue.record("Expected .chain, got \(result)")
            return
        }
        #expect(chain.steps.count == 2)
        #expect(chain.target == .team)
    }

    @Test("Chain with @Sensei target resolves to .agent")
    func chainWithAgentTarget() {
        let result = ChainParser.parse("🧠@Sensei")
        guard case .chain(let chain) = result else {
            Issue.record("Expected .chain, got \(result)")
            return
        }
        #expect(chain.steps.count == 1)
        #expect(chain.target == .agent("Sensei"))
    }

    @Test("Chain with @tech target resolves to .namedTeam")
    func chainWithNamedTeamTarget() {
        let result = ChainParser.parse("🧠@tech")
        guard case .chain(let chain) = result else {
            Issue.record("Expected .chain, got \(result)")
            return
        }
        #expect(chain.target == .namedTeam("tech"))
    }

    // MARK: - BR-EM-CHAIN-08: Args

    @Test("Chain with trailing args captures them")
    func chainWithArgs() {
        let result = ChainParser.parse("🔍🌟@t https://github.com/foo/bar")
        guard case .chain(let chain) = result else {
            Issue.record("Expected .chain, got \(result)")
            return
        }
        #expect(chain.steps.count == 2)
        #expect(chain.steps[0].command == "research")
        #expect(chain.steps[1].command == "challenge")
        #expect(chain.target == .team)
        #expect(chain.rawArgs == "https://github.com/foo/bar")
    }

    // MARK: - BR-EM-CHAIN-05: Repetition

    @Test("Same emoji repeated 3 times produces 3 steps")
    func repetitionThreeTimes() {
        let result = ChainParser.parse("🌟🌟🌟")
        guard case .chain(let chain) = result else {
            Issue.record("Expected .chain, got \(result)")
            return
        }
        #expect(chain.steps.count == 3)
        #expect(chain.steps.allSatisfy { $0.command == "challenge" })
    }

    @Test("Same emoji repeated 4 times is rejected")
    func repetitionCapExceeded() {
        let result = ChainParser.parse("🌟🌟🌟🌟")
        guard case .error(let message) = result else {
            Issue.record("Expected .error, got \(result)")
            return
        }
        #expect(message.contains("repetition limit"))
    }

    // MARK: - BR-EM-CHAIN-06: Destructive Emoji

    @Test("Destructive emoji in chain is rejected")
    func destructiveInChainRejected() {
        let result = ChainParser.parse("❌🚀")
        guard case .error(let message) = result else {
            Issue.record("Expected .error, got \(result)")
            return
        }
        #expect(message.contains("Destructive"))
    }

    // MARK: - Backward Compatibility

    @Test("Single emoji without target returns singleCommand")
    func singleEmojiNotChain() {
        let result = ChainParser.parse("🥕")
        guard case .singleCommand(let step) = result else {
            Issue.record("Expected .singleCommand, got \(result)")
            return
        }
        #expect(step.command == "doctor")
    }

    // MARK: - BR-EM-CHAIN-11: Team Aliases

    @Test("Tech team alias expands to correct members")
    func teamAliasExpansion() {
        let members = TeamAliases.resolve("tech")
        #expect(members == ["Sensei", "Ronin", "Katana", "Kenshi", "Metsuke"])
    }

    @Test("Sensei is in all built-in teams")
    func senseiInAllTeams() {
        for name in TeamAliases.allTeamNames {
            let members = TeamAliases.resolve(name)
            #expect(members?.contains("Sensei") == true, "Sensei missing from team \(name)")
        }
    }

    // MARK: - BR-EM-CHAIN-04: Bash Separator

    @Test("Bash separator — only first token is parsed, rest is args")
    func bashSeparatorNotParsed() {
        // "🗡️@Ronin PR#42 && shikki 🧠@Sensei" — parser only sees first token
        let result = ChainParser.parse("🗡️@Ronin PR#42 && shikki 🧠@Sensei")
        guard case .chain(let chain) = result else {
            Issue.record("Expected .chain, got \(result)")
            return
        }
        #expect(chain.steps.count == 1)
        #expect(chain.steps[0].command == "review")
        #expect(chain.target == .agent("Ronin"))
        #expect(chain.rawArgs.contains("PR#42"))
    }

    // MARK: - ChainExecutor Stub

    @Test("ChainExecutor produces outputs for each step")
    func executorProducesOutputs() async {
        let chain = EmojiChain(
            steps: [
                ChainStep(emoji: "🌟", command: "challenge"),
                ChainStep(emoji: "🧠", command: "brain"),
            ],
            target: .team,
            rawArgs: "test prompt"
        )
        let executor = ChainExecutor()
        let outputs = await executor.execute(chain)
        #expect(outputs.count == 2)
        #expect(outputs[0].command == "challenge")
        #expect(outputs[0].success == true)
        #expect(outputs[1].command == "brain")
        #expect(outputs[1].success == true)
        // Second step should reference prior output
        #expect(outputs[1].result.contains("[prior:"))
    }
}
