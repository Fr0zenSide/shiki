import Testing
import Foundation
@testable import ShikkiCore

@Suite("DependencyTree")
struct DependencyTreeTests {

    @Test("readyWaves returns waves with all deps satisfied")
    func readyWavesReturnsSatisfied() {
        let wave1 = WaveNode(id: "w1", name: "Wave 1", branch: "f/w1", baseBranch: "develop")
        let wave2 = WaveNode(id: "w2", name: "Wave 2", branch: "f/w2", baseBranch: "develop", dependsOn: ["w1"])
        let wave3 = WaveNode(id: "w3", name: "Wave 3", branch: "f/w3", baseBranch: "develop")
        let tree = DependencyTree(waves: [wave1, wave2, wave3])

        // With no completed waves, only w1 and w3 are ready (w2 depends on w1)
        let ready = tree.readyWaves(completed: [])
        #expect(ready.map(\.id).sorted() == ["w1", "w3"])

        // After w1 completes, w2 becomes ready too
        let readyAfter = tree.readyWaves(completed: ["w1"])
        #expect(readyAfter.map(\.id).sorted() == ["w2", "w3"])
    }

    @Test("readyWaves excludes in-progress and done waves")
    func readyWavesExcludesNonPending() {
        let wave1 = WaveNode(id: "w1", name: "Wave 1", branch: "f/w1", baseBranch: "develop", status: .inProgress)
        let wave2 = WaveNode(id: "w2", name: "Wave 2", branch: "f/w2", baseBranch: "develop", status: .done)
        let wave3 = WaveNode(id: "w3", name: "Wave 3", branch: "f/w3", baseBranch: "develop", status: .pending)
        let tree = DependencyTree(waves: [wave1, wave2, wave3])

        let ready = tree.readyWaves(completed: [])
        #expect(ready.map(\.id) == ["w3"])
    }

    @Test("complete marks wave as done")
    func completeMarksWaveDone() {
        let wave1 = WaveNode(id: "w1", name: "Wave 1", branch: "f/w1", baseBranch: "develop")
        var tree = DependencyTree(waves: [wave1])

        tree.complete(waveId: "w1")
        #expect(tree.waves[0].status == .done)
    }

    @Test("Codable round-trip preserves tree structure")
    func codableRoundTrip() throws {
        let wave1 = WaveNode(id: "w1", name: "Wave 1", branch: "f/w1", baseBranch: "develop", files: ["a.swift"], testCount: 3, dependsOn: [])
        let wave2 = WaveNode(id: "w2", name: "Wave 2", branch: "f/w2", baseBranch: "develop", files: ["b.swift"], testCount: 5, dependsOn: ["w1"])
        let tree = DependencyTree(waves: [wave1, wave2])

        let data = try JSONEncoder().encode(tree)
        let decoded = try JSONDecoder().decode(DependencyTree.self, from: data)

        #expect(decoded.waves.count == 2)
        #expect(decoded.waves[0].id == "w1")
        #expect(decoded.waves[1].dependsOn == ["w1"])
        #expect(decoded.waves[0].files == ["a.swift"])
        #expect(decoded.waves[1].testCount == 5)
    }

    @Test("ConfidenceGate detects file overlap correctly")
    func confidenceGateFileOverlap() {
        let waveA = WaveNode(id: "a", name: "A", branch: "f/a", baseBranch: "develop", files: ["shared.swift", "a.swift"])
        let waveB = WaveNode(id: "b", name: "B", branch: "f/b", baseBranch: "develop", files: ["shared.swift", "b.swift"])
        let waveC = WaveNode(id: "c", name: "C", branch: "f/c", baseBranch: "develop", files: ["c.swift"])

        // A and B share "shared.swift" -> cannot run in parallel
        #expect(!ConfidenceGate.canRunInParallel(waveA, waveB))
        // A and C have no overlap -> can run in parallel
        #expect(ConfidenceGate.canRunInParallel(waveA, waveC))
        // B and C have no overlap -> can run in parallel
        #expect(ConfidenceGate.canRunInParallel(waveB, waveC))

        // parallelGroups should separate A and B
        let groups = ConfidenceGate.parallelGroups([waveA, waveB, waveC])
        #expect(groups.count == 2)
        // First group: A + C (no overlap), second group: B
        #expect(groups[0].map(\.id).sorted() == ["a", "c"])
        #expect(groups[1].map(\.id) == ["b"])
    }
}
