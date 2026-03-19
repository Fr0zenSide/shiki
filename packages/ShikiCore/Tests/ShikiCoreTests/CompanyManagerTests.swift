import Testing
import Foundation
@testable import ShikiCore

@Suite("CompanyManager")
struct CompanyManagerTests {

    @Test("Register and retrieve lifecycle")
    func registerAndRetrieve() async {
        let manager = CompanyManager()
        let lifecycle = await manager.register(featureId: "feat-1")
        let retrieved = await manager.lifecycle(for: "feat-1")

        #expect(retrieved != nil)
        #expect(await lifecycle.featureId == "feat-1")
        #expect(await lifecycle.state == .idle)
    }

    @Test("Remove completed lifecycle")
    func removeCompleted() async {
        let manager = CompanyManager()
        await manager.register(featureId: "feat-1")
        #expect(await manager.activeCount == 1)

        await manager.remove(featureId: "feat-1")
        #expect(await manager.activeCount == 0)
        #expect(await manager.lifecycle(for: "feat-1") == nil)
    }

    @Test("activeCount reflects current state")
    func activeCountReflectsState() async {
        let manager = CompanyManager()
        #expect(await manager.activeCount == 0)

        await manager.register(featureId: "feat-1")
        await manager.register(featureId: "feat-2")
        #expect(await manager.activeCount == 2)

        await manager.remove(featureId: "feat-1")
        #expect(await manager.activeCount == 1)
    }
}
