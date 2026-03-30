import Foundation
import Testing
@testable import ShikkiKit

@Suite("ChatEngine — Message routing and history")
struct ChatEngineTests {

    @Test("Send message and receive echo response")
    func sendAndReceive() async {
        let engine = ChatEngine(delivery: EchoChatDelivery())
        let response = await engine.send(content: "Hello", to: .orchestrator)
        #expect(response != nil)
        #expect(response?.content.contains("Acknowledged") == true)
        #expect(response?.isOutgoing == false)
    }

    @Test("Outgoing message is recorded in history")
    func outgoingRecorded() async {
        let engine = ChatEngine(delivery: EchoChatDelivery())
        _ = await engine.send(content: "Test", to: .orchestrator)
        let msgs = await engine.messages
        // Should have outgoing + incoming
        #expect(msgs.count == 2)
        #expect(msgs[0].isOutgoing)
        #expect(!msgs[1].isOutgoing)
    }

    @Test("Message count is correct")
    func messageCount() async {
        let engine = ChatEngine(delivery: EchoChatDelivery())
        _ = await engine.send(content: "One", to: .orchestrator)
        _ = await engine.send(content: "Two", to: .broadcast)
        let count = await engine.messageCount
        #expect(count == 4) // 2 outgoing + 2 responses
    }

    @Test("Filter messages by target")
    func filterByTarget() async {
        let engine = ChatEngine(delivery: EchoChatDelivery())
        _ = await engine.send(content: "To orch", to: .orchestrator)
        _ = await engine.send(content: "To all", to: .broadcast)
        let orchMsgs = await engine.messages(for: .orchestrator)
        let broadcastMsgs = await engine.messages(for: .broadcast)
        #expect(orchMsgs.count == 2) // outgoing + response
        #expect(broadcastMsgs.count == 2)
    }

    @Test("History is capped at maxHistory")
    func historyCapped() async {
        let engine = ChatEngine(delivery: EchoChatDelivery(), maxHistory: 4)
        _ = await engine.send(content: "One", to: .orchestrator)
        _ = await engine.send(content: "Two", to: .orchestrator)
        _ = await engine.send(content: "Three", to: .orchestrator)
        let count = await engine.messageCount
        // 3 sends * 2 messages each = 6, capped to 4
        #expect(count == 4)
    }

    @Test("Clear history empties all messages")
    func clearHistory() async {
        let engine = ChatEngine(delivery: EchoChatDelivery())
        _ = await engine.send(content: "Test", to: .orchestrator)
        await engine.clearHistory()
        let count = await engine.messageCount
        #expect(count == 0)
    }

    @Test("Send via intent routes correctly")
    func sendViaIntent() async {
        let engine = ChatEngine(delivery: EchoChatDelivery())
        let intent = Intent(target: .broadcast, command: nil, message: "status update")
        let response = await engine.send(intent: intent)
        #expect(response != nil)
        #expect(response?.content.contains("All") == true)
    }

    @Test("Send via intent with command falls back to command text")
    func sendViaIntentCommand() async {
        let engine = ChatEngine(delivery: EchoChatDelivery())
        let intent = Intent(target: .orchestrator, command: "status", message: "")
        let response = await engine.send(intent: intent)
        #expect(response != nil)
        #expect(response?.content.contains("status") == true)
    }

    @Test("Send via intent with empty content returns nil")
    func sendViaIntentEmpty() async {
        let engine = ChatEngine(delivery: EchoChatDelivery())
        let intent = Intent(target: nil, command: nil, message: "")
        let response = await engine.send(intent: intent)
        #expect(response == nil)
    }

    @Test("Autocomplete returns all targets for empty query")
    func autocompleteAll() {
        let results = ChatEngine.autocomplete(partial: "")
        #expect(results.count == ChatEngine.knownTargets.count)
    }

    @Test("Autocomplete filters by partial match")
    func autocompleteFilter() {
        let results = ChatEngine.autocomplete(partial: "sen")
        #expect(results.count == 1)
        #expect(results[0].label == "@Sensei")
    }

    @Test("Autocomplete is case-insensitive")
    func autocompleteCaseInsensitive() {
        let results = ChatEngine.autocomplete(partial: "ORCH")
        #expect(!results.isEmpty)
        #expect(results[0].label == "@orchestrator")
    }
}
