import Testing
@testable import ShikkiKit

// MARK: - FlameEmotionResolverTests

@Suite("FlameEmotionResolver — event type to emotion mapping")
struct FlameEmotionResolverTests {

    // MARK: Single Event Resolution

    @Test("heartbeat resolves to calm")
    func heartbeatResolves() {
        #expect(FlameEmotionResolver.resolve(.heartbeat) == .calm)
    }

    @Test("sessionStart resolves to focused")
    func sessionStartResolves() {
        #expect(FlameEmotionResolver.resolve(.sessionStart) == .focused)
    }

    @Test("codeChange resolves to focused")
    func codeChangeResolves() {
        #expect(FlameEmotionResolver.resolve(.codeChange) == .focused)
    }

    @Test("testRun resolves to focused")
    func testRunResolves() {
        #expect(FlameEmotionResolver.resolve(.testRun) == .focused)
    }

    @Test("prVerdictSet resolves to excited")
    func prVerdictResolves() {
        #expect(FlameEmotionResolver.resolve(.prVerdictSet) == .excited)
    }

    @Test("decisionAnswered resolves to excited")
    func decisionAnsweredResolves() {
        #expect(FlameEmotionResolver.resolve(.decisionAnswered) == .excited)
    }

    @Test("shipGatePassed resolves to excited")
    func shipGatePassedResolves() {
        #expect(FlameEmotionResolver.resolve(.shipGatePassed) == .excited)
    }

    @Test("budgetExhausted resolves to alarmed")
    func budgetExhaustedResolves() {
        #expect(FlameEmotionResolver.resolve(.budgetExhausted) == .alarmed)
    }

    @Test("shipGateFailed resolves to alarmed")
    func shipGateFailedResolves() {
        #expect(FlameEmotionResolver.resolve(.shipGateFailed) == .alarmed)
    }

    @Test("companyStale resolves to alarmed")
    func companyStaleResolves() {
        #expect(FlameEmotionResolver.resolve(.companyStale) == .alarmed)
    }

    @Test("shipCompleted resolves to celebrating")
    func shipCompletedResolves() {
        #expect(FlameEmotionResolver.resolve(.shipCompleted) == .celebrating)
    }

    @Test("sessionEnd resolves to calm")
    func sessionEndResolves() {
        #expect(FlameEmotionResolver.resolve(.sessionEnd) == .calm)
    }

    @Test("custom event resolves to calm")
    func customResolves() {
        #expect(FlameEmotionResolver.resolve(.custom("anything")) == .calm)
    }

    @Test("codeGenPipelineCompleted resolves to excited")
    func codeGenPipelineCompletedResolves() {
        #expect(FlameEmotionResolver.resolve(.codeGenPipelineCompleted) == .excited)
    }

    @Test("codeGenPipelineFailed resolves to alarmed")
    func codeGenPipelineFailedResolves() {
        #expect(FlameEmotionResolver.resolve(.codeGenPipelineFailed) == .alarmed)
    }

    @Test("shipAborted resolves to alarmed")
    func shipAbortedResolves() {
        #expect(FlameEmotionResolver.resolve(.shipAborted) == .alarmed)
    }

    // MARK: Multi-Event Resolution

    @Test("resolve from empty array returns calm")
    func emptyArrayResolves() {
        #expect(FlameEmotionResolver.resolve(from: []) == .calm)
    }

    @Test("resolve from mixed events picks highest priority")
    func mixedEventsResolvesHighest() {
        let events: [EventType] = [.heartbeat, .codeChange, .shipCompleted]
        #expect(FlameEmotionResolver.resolve(from: events) == .celebrating)
    }

    @Test("alarmed beats excited in priority")
    func alarmedBeatsExcited() {
        let events: [EventType] = [.prVerdictSet, .budgetExhausted]
        #expect(FlameEmotionResolver.resolve(from: events) == .alarmed)
    }

    @Test("excited beats focused in priority")
    func excitedBeatsFocused() {
        let events: [EventType] = [.codeChange, .decisionAnswered]
        #expect(FlameEmotionResolver.resolve(from: events) == .excited)
    }

    @Test("focused beats calm in priority")
    func focusedBeatsCalm() {
        let events: [EventType] = [.heartbeat, .sessionStart]
        #expect(FlameEmotionResolver.resolve(from: events) == .focused)
    }

    @Test("celebrating beats alarmed in priority")
    func celebratingBeatsAlarmed() {
        let events: [EventType] = [.shipGateFailed, .shipCompleted]
        #expect(FlameEmotionResolver.resolve(from: events) == .celebrating)
    }

    // MARK: Priority Ordering

    @Test("priority ordering is calm < focused < excited < alarmed < celebrating")
    func priorityOrdering() {
        let priorities = FlameEmotion.allCases.map { FlameEmotionResolver.priority($0) }
        #expect(priorities == priorities.sorted())
    }

    @Test("all emotions have distinct priorities")
    func distinctPriorities() {
        let priorities = FlameEmotion.allCases.map { FlameEmotionResolver.priority($0) }
        #expect(Set(priorities).count == FlameEmotion.allCases.count)
    }

    // MARK: All EventTypes Covered

    @Test("all standard event types resolve without crashing")
    func allEventTypesCovered() {
        let allTypes: [EventType] = [
            .sessionStart, .sessionEnd, .sessionTransition, .contextCompaction,
            .heartbeat, .companyDispatched, .companyStale, .companyRelaunched, .budgetExhausted,
            .decisionPending, .decisionAnswered, .decisionUnblocked,
            .codeChange, .testRun, .buildResult,
            .prCacheBuilt, .prRiskAssessed, .prVerdictSet, .prFixSpawned, .prFixCompleted,
            .notificationSent, .notificationActioned,
            .shipStarted, .shipGateStarted, .shipGatePassed, .shipGateFailed,
            .shipCompleted, .shipAborted,
            .codeGenStarted, .codeGenSpecParsed, .codeGenContractVerified,
            .codeGenPlanCreated, .codeGenAgentDispatched, .codeGenAgentCompleted,
            .codeGenMergeStarted, .codeGenMergeCompleted,
            .codeGenFixStarted, .codeGenFixCompleted,
            .codeGenPipelineCompleted, .codeGenPipelineFailed,
            .custom("test"),
        ]

        for eventType in allTypes {
            let emotion = FlameEmotionResolver.resolve(eventType)
            #expect(FlameEmotion.allCases.contains(emotion))
        }
    }
}
