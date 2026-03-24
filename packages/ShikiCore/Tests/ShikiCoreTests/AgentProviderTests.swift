import Testing
import Foundation
@testable import ShikiCore

@Suite("AgentProvider")
struct AgentProviderTests {

    @Test("AgentProviderOptions defaults are sensible")
    func agentOptionsDefaults() {
        let options = AgentProviderOptions()
        #expect(options.model == nil)
        #expect(options.maxTokens == nil)
        #expect(options.outputFormat == .json)
        #expect(options.allowedTools.isEmpty)
    }

    @Test("AgentProviderResult captures all fields")
    func agentResultFields() {
        let result = AgentProviderResult(
            output: "{\"result\": \"ok\"}",
            exitCode: 0,
            tokensUsed: 1500,
            duration: .seconds(3)
        )
        #expect(result.output == "{\"result\": \"ok\"}")
        #expect(result.exitCode == 0)
        #expect(result.tokensUsed == 1500)
        #expect(result.duration == .seconds(3))
    }

    @Test("ClaudeProvider builds correct command line args")
    func claudeProviderCommandArgs() async throws {
        let provider = ClaudeProvider()
        let options = AgentProviderOptions(outputFormat: .json)
        let args = provider.buildArguments(prompt: "hello world", options: options)

        #expect(args.contains("-p"))
        #expect(args.contains("hello world"))
        #expect(args.contains("--output-format"))
        #expect(args.contains("json"))
    }

    @Test("ClaudeProvider includes model when specified")
    func claudeProviderModelArg() async throws {
        let provider = ClaudeProvider()
        let options = AgentProviderOptions(model: "opus", outputFormat: .text)
        let args = provider.buildArguments(prompt: "test", options: options)

        #expect(args.contains("--model"))
        #expect(args.contains("opus"))
    }

    @Test("ClaudeProvider includes allowed tools")
    func claudeProviderAllowedTools() async throws {
        let provider = ClaudeProvider()
        let options = AgentProviderOptions(allowedTools: ["Read", "Write", "Bash"])
        let args = provider.buildArguments(prompt: "test", options: options)

        #expect(args.contains("--allowedTools"))
        #expect(args.contains("Read,Write,Bash"))
    }

    @Test("AgentProviderOptions outputFormat encodes correctly")
    func outputFormatEncoding() {
        #expect(AgentProviderOptions.OutputFormat.json.rawValue == "json")
        #expect(AgentProviderOptions.OutputFormat.text.rawValue == "text")
    }
}
