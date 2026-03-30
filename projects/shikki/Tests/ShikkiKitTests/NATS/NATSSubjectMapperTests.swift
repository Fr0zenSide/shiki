import Foundation
import Testing
@testable import ShikkiKit

@Suite("NATSSubjectMapper")
struct NATSSubjectMapperTests {

    // MARK: - Event Type to Category Mapping

    @Test("Lifecycle events map to lifecycle category")
    func lifecycleEvents() {
        #expect(NATSSubjectMapper.eventCategory(for: .sessionStart) == "lifecycle")
        #expect(NATSSubjectMapper.eventCategory(for: .sessionEnd) == "lifecycle")
        #expect(NATSSubjectMapper.eventCategory(for: .sessionTransition) == "lifecycle")
        #expect(NATSSubjectMapper.eventCategory(for: .contextCompaction) == "lifecycle")
        #expect(NATSSubjectMapper.eventCategory(for: .contextSaved) == "lifecycle")
    }

    @Test("Heartbeat maps to heartbeat category")
    func heartbeatCategory() {
        #expect(NATSSubjectMapper.eventCategory(for: .heartbeat) == "heartbeat")
    }

    @Test("Orchestration events map to orchestration category")
    func orchestrationEvents() {
        #expect(NATSSubjectMapper.eventCategory(for: .companyDispatched) == "orchestration")
        #expect(NATSSubjectMapper.eventCategory(for: .companyStale) == "orchestration")
        #expect(NATSSubjectMapper.eventCategory(for: .companyRelaunched) == "orchestration")
        #expect(NATSSubjectMapper.eventCategory(for: .budgetExhausted) == "orchestration")
    }

    @Test("Decision events map to decision category")
    func decisionEvents() {
        #expect(NATSSubjectMapper.eventCategory(for: .decisionPending) == "decision")
        #expect(NATSSubjectMapper.eventCategory(for: .decisionAnswered) == "decision")
        #expect(NATSSubjectMapper.eventCategory(for: .decisionUnblocked) == "decision")
        #expect(NATSSubjectMapper.eventCategory(for: .decisionMade) == "decision")
        #expect(NATSSubjectMapper.eventCategory(for: .architectureChoice) == "decision")
        #expect(NATSSubjectMapper.eventCategory(for: .tradeOffEvaluated) == "decision")
    }

    @Test("Code events map to code category")
    func codeEvents() {
        #expect(NATSSubjectMapper.eventCategory(for: .codeChange) == "code")
        #expect(NATSSubjectMapper.eventCategory(for: .testRun) == "code")
        #expect(NATSSubjectMapper.eventCategory(for: .buildResult) == "code")
    }

    @Test("PR events map to pr category")
    func prEvents() {
        #expect(NATSSubjectMapper.eventCategory(for: .prCacheBuilt) == "pr")
        #expect(NATSSubjectMapper.eventCategory(for: .prRiskAssessed) == "pr")
        #expect(NATSSubjectMapper.eventCategory(for: .prVerdictSet) == "pr")
        #expect(NATSSubjectMapper.eventCategory(for: .prFixSpawned) == "pr")
        #expect(NATSSubjectMapper.eventCategory(for: .prFixCompleted) == "pr")
    }

    @Test("Ship events map to ship category")
    func shipEvents() {
        #expect(NATSSubjectMapper.eventCategory(for: .shipStarted) == "ship")
        #expect(NATSSubjectMapper.eventCategory(for: .shipGateStarted) == "ship")
        #expect(NATSSubjectMapper.eventCategory(for: .shipGatePassed) == "ship")
        #expect(NATSSubjectMapper.eventCategory(for: .shipGateFailed) == "ship")
        #expect(NATSSubjectMapper.eventCategory(for: .shipCompleted) == "ship")
        #expect(NATSSubjectMapper.eventCategory(for: .shipAborted) == "ship")
    }

    @Test("CodeGen events map to codegen category")
    func codeGenEvents() {
        #expect(NATSSubjectMapper.eventCategory(for: .codeGenStarted) == "codegen")
        #expect(NATSSubjectMapper.eventCategory(for: .codeGenPipelineCompleted) == "codegen")
        #expect(NATSSubjectMapper.eventCategory(for: .codeGenPipelineFailed) == "codegen")
    }

    @Test("Scheduler events map to scheduler category")
    func schedulerEvents() {
        #expect(NATSSubjectMapper.eventCategory(for: .scheduledTaskFired) == "scheduler")
        #expect(NATSSubjectMapper.eventCategory(for: .scheduledTaskCompleted) == "scheduler")
        #expect(NATSSubjectMapper.eventCategory(for: .scheduledTaskFailed) == "scheduler")
        #expect(NATSSubjectMapper.eventCategory(for: .corroborationSweep) == "scheduler")
    }

    @Test("Observatory events map to appropriate categories")
    func observatoryEvents() {
        #expect(NATSSubjectMapper.eventCategory(for: .blockerHit) == "blocker")
        #expect(NATSSubjectMapper.eventCategory(for: .blockerResolved) == "blocker")
        #expect(NATSSubjectMapper.eventCategory(for: .milestoneReached) == "milestone")
        #expect(NATSSubjectMapper.eventCategory(for: .redFlag) == "alert")
        #expect(NATSSubjectMapper.eventCategory(for: .agentReportGenerated) == "report")
    }

    @Test("Custom events map to custom category")
    func customEvents() {
        #expect(NATSSubjectMapper.eventCategory(for: .custom("myEvent")) == "custom")
    }

    // MARK: - Full Subject Construction

    @Test("subject(for:company:) builds correct NATS subject")
    func subjectConstruction() {
        let subject = NATSSubjectMapper.subject(for: .companyDispatched, company: "maya")
        #expect(subject == "shikki.events.maya.orchestration")
    }

    @Test("companyWildcard builds correct pattern")
    func companyWildcard() {
        #expect(NATSSubjectMapper.companyWildcard("maya") == "shikki.events.maya.>")
    }

    @Test("allEvents is the global wildcard")
    func allEventsWildcard() {
        #expect(NATSSubjectMapper.allEvents == "shikki.events.>")
    }

    // MARK: - Channel-to-Subject Mapping

    @Test("Empty channel maps to all-events wildcard")
    func emptyChannelMapsToAll() {
        #expect(NATSEventTransport.channelToSubject("") == "shikki.events.>")
        #expect(NATSEventTransport.channelToSubject("*") == "shikki.events.>")
        #expect(NATSEventTransport.channelToSubject("  ") == "shikki.events.>")
    }

    @Test("Single-token channel maps to company wildcard")
    func singleTokenChannel() {
        #expect(NATSEventTransport.channelToSubject("maya") == "shikki.events.maya.>")
        #expect(NATSEventTransport.channelToSubject("shiki") == "shikki.events.shiki.>")
    }

    @Test("Dotted channel maps to exact subject under prefix")
    func dottedChannel() {
        #expect(NATSEventTransport.channelToSubject("maya.agent") == "shikki.events.maya.agent")
        #expect(NATSEventTransport.channelToSubject("maya.lifecycle") == "shikki.events.maya.lifecycle")
    }
}
