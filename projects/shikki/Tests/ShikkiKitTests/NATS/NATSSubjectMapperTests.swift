import Foundation
import Testing
@testable import ShikkiKit

// MARK: - Event Category Mapping Tests

@Suite("NATSSubjectMapper — Event Categories")
struct NATSSubjectMapperCategoryTests {

    @Test("Lifecycle events map to lifecycle category")
    func lifecycleEvents() {
        let lifecycleTypes: [EventType] = [
            .sessionStart, .sessionEnd, .sessionTransition, .contextCompaction,
            .heartbeat, .companyDispatched, .companyStale, .companyRelaunched,
            .budgetExhausted, .testRun, .buildResult,
        ]

        for eventType in lifecycleTypes {
            let category = NATSSubjectMapper.category(for: eventType)
            #expect(
                category == .lifecycle,
                "Expected \(eventType) to map to lifecycle, got \(category)"
            )
        }
    }

    @Test("Decision events map to decision category")
    func decisionEvents() {
        let decisionTypes: [EventType] = [
            .decisionPending, .decisionAnswered, .decisionUnblocked,
        ]

        for eventType in decisionTypes {
            #expect(NATSSubjectMapper.category(for: eventType) == .decision)
        }
    }

    @Test("Ship events map to ship category")
    func shipEvents() {
        let shipTypes: [EventType] = [
            .shipStarted, .shipGateStarted, .shipGatePassed,
            .shipGateFailed, .shipCompleted, .shipAborted,
        ]

        for eventType in shipTypes {
            #expect(NATSSubjectMapper.category(for: eventType) == .ship)
        }
    }

    @Test("CodeGen events map to codegen category")
    func codeGenEvents() {
        let codegenTypes: [EventType] = [
            .codeGenStarted, .codeGenSpecParsed, .codeGenContractVerified,
            .codeGenPlanCreated, .codeGenAgentDispatched, .codeGenAgentCompleted,
            .codeGenMergeStarted, .codeGenMergeCompleted, .codeGenFixStarted,
            .codeGenFixCompleted, .codeGenPipelineCompleted, .codeGenPipelineFailed,
        ]

        for eventType in codegenTypes {
            #expect(NATSSubjectMapper.category(for: eventType) == .codegen)
        }
    }

    @Test("PR events map to agent category")
    func prEvents() {
        let prTypes: [EventType] = [
            .prCacheBuilt, .prRiskAssessed, .prVerdictSet,
            .prFixSpawned, .prFixCompleted,
        ]

        for eventType in prTypes {
            #expect(NATSSubjectMapper.category(for: eventType) == .agent)
        }
    }

    @Test("Scheduler events map to scheduler category")
    func schedulerEvents() {
        let schedulerTypes: [EventType] = [
            .scheduledTaskFired, .scheduledTaskCompleted,
            .scheduledTaskFailed, .corroborationSweep,
        ]

        for eventType in schedulerTypes {
            #expect(NATSSubjectMapper.category(for: eventType) == .scheduler)
        }
    }

    @Test("Observatory events map to observatory category")
    func observatoryEvents() {
        let observatoryTypes: [EventType] = [
            .decisionMade, .architectureChoice, .tradeOffEvaluated,
            .blockerHit, .blockerResolved, .milestoneReached, .redFlag,
            .contextSaved, .agentReportGenerated,
        ]

        for eventType in observatoryTypes {
            #expect(NATSSubjectMapper.category(for: eventType) == .observatory)
        }
    }

    @Test("Git events map to git category")
    func gitEvents() {
        #expect(NATSSubjectMapper.category(for: .codeChange) == .git)
    }

    @Test("Notification events map to system category")
    func notificationEvents() {
        #expect(NATSSubjectMapper.category(for: .notificationSent) == .system)
        #expect(NATSSubjectMapper.category(for: .notificationActioned) == .system)
    }

    @Test("Custom events map to system category")
    func customEvents() {
        #expect(NATSSubjectMapper.category(for: .custom("anything")) == .system)
    }
}

// MARK: - Subject String Tests

@Suite("NATSSubjectMapper — Subject Strings")
struct NATSSubjectMapperSubjectTests {

    @Test("Event subject includes company and category")
    func eventSubjectFormat() {
        let subject = NATSSubjectMapper.subject(for: .shipStarted, company: "maya")
        #expect(subject == "shikki.events.maya.ship")
    }

    @Test("Subject from event uses scope for company")
    func subjectFromEventUsesScope() {
        let event = ShikkiEvent(
            source: .orchestrator,
            type: .shipStarted,
            scope: .project(slug: "wabisabi")
        )
        let subject = NATSSubjectMapper.subject(for: event)
        #expect(subject == "shikki.events.wabisabi.ship")
    }

    @Test("Subject from event with global scope uses default company")
    func subjectFromEventGlobalScope() {
        let event = ShikkiEvent(
            source: .system,
            type: .heartbeat,
            scope: .global
        )
        let subject = NATSSubjectMapper.subject(for: event, defaultCompany: "global")
        #expect(subject == "shikki.events.global.lifecycle")
    }

    @Test("Subject from session scope extracts company prefix")
    func subjectFromSessionScope() {
        let event = ShikkiEvent(
            source: .agent(id: "a1", name: nil),
            type: .codeGenStarted,
            scope: .session(id: "maya:session-abc")
        )
        let subject = NATSSubjectMapper.subject(for: event)
        #expect(subject == "shikki.events.maya.codegen")
    }

    @Test("Session scope without colon yields default company")
    func sessionScopeWithoutColon() {
        let event = ShikkiEvent(
            source: .system,
            type: .heartbeat,
            scope: .session(id: "plain-session-id")
        )
        let subject = NATSSubjectMapper.subject(for: event, defaultCompany: "fallback")
        #expect(subject == "shikki.events.fallback.lifecycle")
    }
}

// MARK: - Special Subject Tests

@Suite("NATSSubjectMapper — Special Subjects")
struct NATSSubjectMapperSpecialTests {

    @Test("Command subject includes node ID")
    func commandSubject() {
        let subject = NATSSubjectMapper.commandSubject(nodeId: "node-42")
        #expect(subject == "shikki.commands.node-42")
    }

    @Test("Discovery announce subject is correct")
    func discoveryAnnounce() {
        #expect(NATSSubjectMapper.discoveryAnnounce == "shikki.discovery.announce")
    }

    @Test("Discovery query subject is correct")
    func discoveryQuery() {
        #expect(NATSSubjectMapper.discoveryQuery == "shikki.discovery.query")
    }

    @Test("Tasks available subject includes workspace")
    func tasksAvailable() {
        let subject = NATSSubjectMapper.tasksAvailable(workspace: "shiki-main")
        #expect(subject == "shikki.tasks.shiki-main.available")
    }

    @Test("Tasks claimed subject includes workspace")
    func tasksClaimed() {
        let subject = NATSSubjectMapper.tasksClaimed(workspace: "shiki-main")
        #expect(subject == "shikki.tasks.shiki-main.claimed")
    }

    @Test("Decisions pending subject is correct")
    func decisionsPending() {
        #expect(NATSSubjectMapper.decisionsPending == "shikki.decisions.pending")
    }

    @Test("All events wildcard")
    func allEventsWildcard() {
        #expect(NATSSubjectMapper.allEvents == "shikki.events.>")
    }

    @Test("Company events wildcard includes company")
    func companyEventsWildcard() {
        #expect(NATSSubjectMapper.companyEvents("maya") == "shikki.events.maya.>")
    }

    @Test("All discovery wildcard")
    func allDiscoveryWildcard() {
        #expect(NATSSubjectMapper.allDiscovery == "shikki.discovery.>")
    }
}
