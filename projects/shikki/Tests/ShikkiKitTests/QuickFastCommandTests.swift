import Foundation
import Testing
@testable import ShikkiKit

// MARK: - Emoji Registration Tests

@Suite("Quick/Fast — Emoji Registration (BR-CA-06)")
struct QuickFastEmojiTests {

    @Test("Tornado emoji resolves to fast command")
    func tornado_resolvesToFast() {
        let command = EmojiRegistry.resolve("\u{1F32A}\u{FE0F}")
        #expect(command == "fast")
    }

    @Test("Lightning emoji resolves to quick command")
    func lightning_resolvesToQuick() {
        let command = EmojiRegistry.resolve("\u{26A1}")
        #expect(command == "quick")
    }

    @Test("Fast entry is in workflow category")
    func fastEntry_workflowCategory() {
        let entries = EmojiRegistry.all.filter { $0.command == "fast" }
        #expect(!entries.isEmpty)
        #expect(entries.allSatisfy { $0.category == .workflow })
    }

    @Test("Quick entry is in workflow category")
    func quickEntry_workflowCategory() {
        let entries = EmojiRegistry.all.filter { $0.command == "quick" }
        #expect(!entries.isEmpty)
        #expect(entries.allSatisfy { $0.category == .workflow })
    }

    @Test("Fast and quick entries accept args")
    func entries_acceptArgs() {
        let fastEntries = EmojiRegistry.all.filter { $0.command == "fast" }
        let quickEntries = EmojiRegistry.all.filter { $0.command == "quick" }
        #expect(fastEntries.allSatisfy { $0.acceptsArgs })
        #expect(quickEntries.allSatisfy { $0.acceptsArgs })
    }

    @Test("Fast and quick are not destructive")
    func entries_notDestructive() {
        let fastEntries = EmojiRegistry.all.filter { $0.command == "fast" }
        let quickEntries = EmojiRegistry.all.filter { $0.command == "quick" }
        #expect(fastEntries.allSatisfy { !$0.isDestructive })
        #expect(quickEntries.allSatisfy { !$0.isDestructive })
    }

    @Test("Reverse lookup: fast returns tornado emoji")
    func reverseLookup_fast() {
        let emoji = EmojiRegistry.byCommand["fast"]
        #expect(emoji != nil)
    }

    @Test("Reverse lookup: quick returns lightning emoji")
    func reverseLookup_quick() {
        let emoji = EmojiRegistry.byCommand["quick"]
        #expect(emoji != nil)
    }
}

// MARK: - Event Type Tests

@Suite("Quick/Fast — Event Types")
struct QuickFastEventTests {

    @Test("Quick event types exist in EventType")
    func quickEventTypes_exist() {
        let types: [EventType] = [
            .quickStarted,
            .quickStepCompleted,
            .quickCompleted,
            .quickFailed,
        ]
        #expect(types.count == 4)
    }

    @Test("Fast event types exist in EventType")
    func fastEventTypes_exist() {
        let types: [EventType] = [
            .fastStarted,
            .fastStageCompleted,
            .fastCompleted,
            .fastFailed,
        ]
        #expect(types.count == 4)
    }

    @Test("Quick events resolve to correct flame emotions")
    func quickEvents_flameEmotions() {
        #expect(FlameEmotionResolver.resolve(.quickStarted) == .focused)
        #expect(FlameEmotionResolver.resolve(.quickStepCompleted) == .focused)
        #expect(FlameEmotionResolver.resolve(.quickCompleted) == .excited)
        #expect(FlameEmotionResolver.resolve(.quickFailed) == .alarmed)
    }

    @Test("Fast events resolve to correct flame emotions")
    func fastEvents_flameEmotions() {
        #expect(FlameEmotionResolver.resolve(.fastStarted) == .focused)
        #expect(FlameEmotionResolver.resolve(.fastStageCompleted) == .focused)
        #expect(FlameEmotionResolver.resolve(.fastCompleted) == .celebrating)
        #expect(FlameEmotionResolver.resolve(.fastFailed) == .alarmed)
    }

    @Test("Quick events map to correct NATS category")
    func quickEvents_natsCategory() {
        let category = NATSSubjectMapper.eventCategory(for: .quickStarted)
        #expect(category == "quick")
    }

    @Test("Fast events map to correct NATS category")
    func fastEvents_natsCategory() {
        let category = NATSSubjectMapper.eventCategory(for: .fastStarted)
        #expect(category == "fast")
    }
}
