import Testing
@testable import ShikiCore

@Suite("LifecycleState FSM")
struct LifecycleStateTests {

    @Test("Valid transition: idle -> specDrafting succeeds")
    func idleToSpecDrafting() throws {
        let validator = TransitionValidator()
        #expect(validator.isValid(from: .idle, to: .specDrafting))
    }

    @Test("Valid transition: specPendingApproval -> building succeeds")
    func specPendingApprovalToBuilding() throws {
        let validator = TransitionValidator()
        #expect(validator.isValid(from: .specPendingApproval, to: .building))
    }

    @Test("Invalid transition: idle -> building throws")
    func idleToBuildingThrows() throws {
        let validator = TransitionValidator()
        #expect(throws: TransitionError.self) {
            try validator.validate(from: .idle, to: .building)
        }
    }

    @Test("Invalid transition: done -> specDrafting throws")
    func doneToSpecDraftingThrows() throws {
        let validator = TransitionValidator()
        #expect(throws: TransitionError.self) {
            try validator.validate(from: .done, to: .specDrafting)
        }
    }

    @Test("Blocked transition: any state -> blocked succeeds")
    func anyToBlockedSucceeds() throws {
        let validator = TransitionValidator()
        for state in LifecycleState.allCases where state != .blocked {
            #expect(validator.isValid(from: state, to: .blocked))
        }
    }

    @Test("Failed transition: any state -> failed succeeds")
    func anyToFailedSucceeds() throws {
        let validator = TransitionValidator()
        for state in LifecycleState.allCases where state != .failed && state != .done {
            #expect(validator.isValid(from: state, to: .failed))
        }
    }

    @Test("Full valid path: idle through done")
    func fullValidPath() throws {
        let validator = TransitionValidator()
        let path: [LifecycleState] = [
            .idle, .specDrafting, .specPendingApproval,
            .decisionsNeeded, .building, .gating, .shipping, .done,
        ]
        for i in 0..<(path.count - 1) {
            #expect(validator.isValid(from: path[i], to: path[i + 1]))
        }
    }

    @Test("Blocked can resume to previous state")
    func blockedResumesToPrevious() throws {
        let validator = TransitionValidator()
        // blocked can go back to building (resume)
        #expect(validator.isValid(from: .blocked, to: .building))
        #expect(validator.isValid(from: .blocked, to: .specDrafting))
    }
}
