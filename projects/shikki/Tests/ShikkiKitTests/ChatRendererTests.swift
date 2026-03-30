import Foundation
import Testing
@testable import ShikkiKit

@Suite("ChatRenderer — Chat TUI rendering")
struct ChatRendererTests {

    private func sampleMessages() -> [ChatMessage] {
        [
            ChatMessage(
                id: "1", target: .orchestrator,
                content: "How many slots are available?",
                isOutgoing: true, senderLabel: "You"
            ),
            ChatMessage(
                id: "2", target: .orchestrator,
                content: "1/2 slots free. maya:spm-wave3 running.",
                isOutgoing: false, senderLabel: "Orchestrator"
            ),
            ChatMessage(
                id: "3", target: .broadcast,
                content: "Status update please",
                isOutgoing: true, senderLabel: "You"
            ),
        ]
    }

    @Test("Render shows messages")
    func renderShowsMessages() {
        let output = ChatRenderer.render(
            messages: sampleMessages(),
            inputText: "",
            autocompleteResults: [],
            selectedAutocomplete: 0,
            showAutocomplete: false,
            width: 70,
            height: 20
        )
        let stripped = TerminalSnapshot.stripANSI(output)
        #expect(stripped.contains("How many slots"))
        #expect(stripped.contains("1/2 slots free"))
        #expect(stripped.contains("Status update"))
    }

    @Test("Render shows SHIKKI CHAT title")
    func renderShowsTitle() {
        let output = ChatRenderer.render(
            messages: [],
            inputText: "",
            autocompleteResults: [],
            selectedAutocomplete: 0,
            showAutocomplete: false,
            width: 70,
            height: 20
        )
        let stripped = TerminalSnapshot.stripANSI(output)
        #expect(stripped.contains("SHIKKI CHAT"))
    }

    @Test("Render shows input placeholder when empty")
    func renderShowsPlaceholder() {
        let output = ChatRenderer.render(
            messages: [],
            inputText: "",
            autocompleteResults: [],
            selectedAutocomplete: 0,
            showAutocomplete: false,
            width: 70,
            height: 20
        )
        let stripped = TerminalSnapshot.stripANSI(output)
        #expect(stripped.contains("@target message"))
    }

    @Test("Render shows autocomplete popup")
    func renderShowsAutocomplete() {
        let autocomplete = [
            (label: "@orchestrator", description: "Main orchestrator"),
            (label: "@Sensei", description: "CTO review persona"),
        ]
        let output = ChatRenderer.render(
            messages: [],
            inputText: "@",
            autocompleteResults: autocomplete,
            selectedAutocomplete: 0,
            showAutocomplete: true,
            width: 70,
            height: 20
        )
        let stripped = TerminalSnapshot.stripANSI(output)
        #expect(stripped.contains("@orchestrator"))
        #expect(stripped.contains("@Sensei"))
    }

    @Test("Render shows footer hints")
    func renderShowsFooter() {
        let output = ChatRenderer.render(
            messages: [],
            inputText: "",
            autocompleteResults: [],
            selectedAutocomplete: 0,
            showAutocomplete: false,
            width: 70,
            height: 20
        )
        let stripped = TerminalSnapshot.stripANSI(output)
        #expect(stripped.contains("Enter send"))
        #expect(stripped.contains("Tab autocomplete"))
        #expect(stripped.contains("Esc close"))
    }

    @Test("Outgoing messages show target prefix")
    func outgoingShowsTarget() {
        let msg = ChatMessage(
            id: "1", target: .persona(.investigate),
            content: "Review this",
            isOutgoing: true, senderLabel: "You"
        )
        let formatted = ChatRenderer.formatMessage(msg, maxWidth: 60)
        let stripped = TerminalSnapshot.stripANSI(formatted)
        #expect(stripped.contains("@investigate"))
    }

    @Test("Incoming messages show sender label")
    func incomingShowsSender() {
        let msg = ChatMessage(
            id: "2", target: .orchestrator,
            content: "Done",
            isOutgoing: false, senderLabel: "Orchestrator"
        )
        let formatted = ChatRenderer.formatMessage(msg, maxWidth: 60)
        let stripped = TerminalSnapshot.stripANSI(formatted)
        #expect(stripped.contains("Orchestrator:"))
    }
}
