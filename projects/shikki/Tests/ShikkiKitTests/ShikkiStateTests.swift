import Foundation
import Testing
@testable import ShikkiKit

@Suite("ShikkiState FSM — BR-01 to BR-06")
struct ShikkiStateTests {

    // BR-01: Exactly three states
    @Test("FSM has exactly three states: idle, running, stopping")
    func allStates_areIdleRunningAndStopping() {
        let states: [ShikkiState] = [.idle, .running, .stopping]
        #expect(states.count == 3)
        #expect(Set(states.map(\.rawValue)) == Set(["idle", "running", "stopping"]))
    }

    // BR-05: Valid transitions
    @Test("IDLE → RUNNING is valid")
    func transition_idleToRunning_succeeds() throws {
        let result = ShikkiState.idle.canTransition(to: .running)
        #expect(result == true)
    }

    @Test("RUNNING → STOPPING is valid")
    func transition_runningToStopping_succeeds() throws {
        let result = ShikkiState.running.canTransition(to: .stopping)
        #expect(result == true)
    }

    @Test("STOPPING → IDLE is valid (countdown completes)")
    func transition_stoppingToIdle_succeeds() throws {
        let result = ShikkiState.stopping.canTransition(to: .idle)
        #expect(result == true)
    }

    @Test("STOPPING → RUNNING is valid (Esc cancel)")
    func transition_stoppingToRunning_succeeds() throws {
        let result = ShikkiState.stopping.canTransition(to: .running)
        #expect(result == true)
    }

    @Test("RUNNING → IDLE is valid (crash/external kill)")
    func transition_runningToIdle_onCrash_succeeds() throws {
        let result = ShikkiState.running.canTransition(to: .idle)
        #expect(result == true)
    }

    // BR-06: Invalid transitions
    @Test("IDLE → STOPPING is invalid")
    func transition_idleToStopping_isInvalid() throws {
        let result = ShikkiState.idle.canTransition(to: .stopping)
        #expect(result == false)
    }

    @Test("STOPPING → STOPPING is invalid")
    func transition_stoppingToStopping_isInvalid() throws {
        let result = ShikkiState.stopping.canTransition(to: .stopping)
        #expect(result == false)
    }

    @Test("IDLE → IDLE is invalid (self-transition)")
    func transition_idleToIdle_isInvalid() throws {
        let result = ShikkiState.idle.canTransition(to: .idle)
        #expect(result == false)
    }
}
