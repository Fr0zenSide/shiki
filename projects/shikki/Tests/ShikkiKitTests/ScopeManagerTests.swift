import Foundation
import Testing
@testable import ShikkiKit

@Suite("ScopeManager — # notation and sticky scopes")
struct ScopeManagerTests {

    @Test("Initial state has no scopes")
    func initialState() {
        let mgr = ScopeManager()
        #expect(!mgr.hasScope)
        #expect(mgr.activeScopes.isEmpty)
        #expect(mgr.label == "all")
    }

    @Test("Push project scope")
    func pushProject() {
        var mgr = ScopeManager()
        let scope = mgr.push(rawTag: "maya")
        #expect(scope?.kind == .project("maya"))
        #expect(mgr.hasScope)
        #expect(mgr.label == "#maya")
    }

    @Test("Push PR scope")
    func pushPR() {
        var mgr = ScopeManager()
        let scope = mgr.push(rawTag: "PR-6")
        #expect(scope?.kind == .pr(6))
    }

    @Test("Push wave scope")
    func pushWave() {
        var mgr = ScopeManager()
        let scope = mgr.push(rawTag: "wave3")
        #expect(scope?.kind == .wave(3))
    }

    @Test("Push today scope")
    func pushToday() {
        var mgr = ScopeManager()
        let scope = mgr.push(rawTag: "today")
        #expect(scope?.kind == .today)
    }

    @Test("Push session scope")
    func pushSession() {
        var mgr = ScopeManager()
        let scope = mgr.push(rawTag: "session-abc123")
        #expect(scope?.kind == .session("abc123"))
    }

    @Test("Multiple scopes stack")
    func multipleScopes() {
        var mgr = ScopeManager()
        _ = mgr.push(rawTag: "maya")
        _ = mgr.push(rawTag: "wave1")
        #expect(mgr.activeScopes.count == 2)
        #expect(mgr.label == "#maya #wave1")
    }

    @Test("Empty tag clears all scopes")
    func clearOnEmpty() {
        var mgr = ScopeManager()
        _ = mgr.push(rawTag: "maya")
        _ = mgr.push(rawTag: "wave1")
        let result = mgr.push(rawTag: "")
        #expect(result == nil)
        #expect(!mgr.hasScope)
        #expect(mgr.activeScopes.isEmpty)
    }

    @Test("Pop removes most recent scope")
    func popScope() {
        var mgr = ScopeManager()
        _ = mgr.push(rawTag: "maya")
        _ = mgr.push(rawTag: "wave1")
        let popped = mgr.pop()
        #expect(popped?.tag == "wave1")
        #expect(mgr.activeScopes.count == 1)
        #expect(mgr.label == "#maya")
    }

    @Test("User-defined scopes expand on push")
    func userDefined() {
        var mgr = ScopeManager()
        mgr.define(name: "auth", scopes: [
            Scope(tag: "maya", kind: .project("maya")),
            Scope(tag: "wave1", kind: .wave(1)),
        ])
        _ = mgr.push(rawTag: "auth")
        #expect(mgr.activeScopes.count == 2)
        #expect(mgr.definedScopeNames == ["auth"])
    }

    @Test("Matches filters by project scope")
    func matchesProject() {
        var mgr = ScopeManager()
        _ = mgr.push(rawTag: "maya")

        let mayaResult = PaletteResult(
            id: "session:maya:spm", title: "maya:spm-wave3",
            subtitle: "working", category: "session", icon: "*", score: 0
        )
        let wabisabiResult = PaletteResult(
            id: "session:wabisabi:onboard", title: "wabisabi:onboard",
            subtitle: "prOpen", category: "session", icon: "^", score: 0
        )

        #expect(mgr.matches(result: mayaResult))
        #expect(!mgr.matches(result: wabisabiResult))
    }

    @Test("Matches filters by PR scope")
    func matchesPR() {
        var mgr = ScopeManager()
        _ = mgr.push(rawTag: "PR-6")

        let pr6 = PaletteResult(
            id: "pr:6", title: "PR-6 Fix auth",
            subtitle: nil, category: "pr", icon: nil, score: 0
        )
        let pr7 = PaletteResult(
            id: "pr:7", title: "PR-7 Refactor",
            subtitle: nil, category: "pr", icon: nil, score: 0
        )

        #expect(mgr.matches(result: pr6))
        #expect(!mgr.matches(result: pr7))
    }

    @Test("No scope matches everything")
    func noScopeMatchesAll() {
        let mgr = ScopeManager()
        let result = PaletteResult(
            id: "anything", title: "anything",
            subtitle: nil, category: "any", icon: nil, score: 0
        )
        #expect(mgr.matches(result: result))
    }
}
