import Foundation
import Testing
@testable import ShikkiKit

@Suite("Progressive Watchdog")
struct WatchdogTests {

    @Test("Warn level triggers at threshold")
    func warnAtThreshold() {
        let watchdog = Watchdog(config: .default)
        let action = watchdog.evaluate(
            idleSeconds: 120, // 2 min idle
            state: .working,
            contextPct: 50
        )
        #expect(action == .warn)
    }

    @Test("Nudge level after extended idle")
    func nudgeAfterExtendedIdle() {
        let watchdog = Watchdog(config: .default)
        let action = watchdog.evaluate(
            idleSeconds: 300, // 5 min
            state: .working,
            contextPct: 50
        )
        #expect(action == .nudge)
    }

    @Test("AI triage at high idle")
    func aiTriageAtHighIdle() {
        let watchdog = Watchdog(config: .default)
        let action = watchdog.evaluate(
            idleSeconds: 600, // 10 min
            state: .working,
            contextPct: 50
        )
        #expect(action == .aiTriage)
    }

    @Test("Terminate at critical idle")
    func terminateAtCritical() {
        let watchdog = Watchdog(config: .default)
        let action = watchdog.evaluate(
            idleSeconds: 900, // 15 min
            state: .working,
            contextPct: 50
        )
        #expect(action == .terminate)
    }

    @Test("Skip escalation for awaitingApproval")
    func skipForAwaitingApproval() {
        let watchdog = Watchdog(config: .default)
        let action = watchdog.evaluate(
            idleSeconds: 900, // Would be terminate normally
            state: .awaitingApproval,
            contextPct: 50
        )
        #expect(action == .none)
    }

    @Test("Skip escalation for budgetPaused")
    func skipForBudgetPaused() {
        let watchdog = Watchdog(config: .default)
        let action = watchdog.evaluate(
            idleSeconds: 900,
            state: .budgetPaused,
            contextPct: 50
        )
        #expect(action == .none)
    }

    @Test("Context pressure triggers warn early")
    func contextPressureWarn() {
        let watchdog = Watchdog(config: .default)
        let action = watchdog.evaluate(
            idleSeconds: 60, // Only 1 min idle
            state: .working,
            contextPct: 85 // High context usage
        )
        #expect(action == .warn)
    }

    @Test("No action when idle is short")
    func noActionShortIdle() {
        let watchdog = Watchdog(config: .default)
        let action = watchdog.evaluate(
            idleSeconds: 30,
            state: .working,
            contextPct: 20
        )
        #expect(action == .none)
    }

    @Test("Custom thresholds")
    func customThresholds() {
        let config = WatchdogConfig(
            warnSeconds: 60,
            nudgeSeconds: 120,
            triageSeconds: 180,
            terminateSeconds: 240,
            contextPressureThreshold: 90
        )
        let watchdog = Watchdog(config: config)
        let action = watchdog.evaluate(idleSeconds: 70, state: .working, contextPct: 50)
        #expect(action == .warn)
    }

    @Test("Named failure modes")
    func namedFailureModes() {
        #expect(WatchdogFailureMode.hierarchyBypass.description.contains("HIERARCHY"))
        #expect(WatchdogFailureMode.specWriting.description.contains("SPEC"))
        #expect(WatchdogFailureMode.prematureMerge.description.contains("MERGE"))
        #expect(WatchdogFailureMode.scopeExplosion.description.contains("SCOPE"))
    }
}
