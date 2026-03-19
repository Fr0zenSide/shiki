import Foundation
import Testing
@testable import ShikiCtlKit

@Suite("Dependency Tree — Data Model")
struct DependencyTreeModelTests {

    @Test("Create tree with waves and dependencies")
    func createTree() {
        var tree = DependencyTree(baseBranch: "develop", baseCommit: "abc123")
        tree.addWave(WaveNode(name: "Wave A", branch: "feature/s3-parser", estimatedTests: 18))
        tree.addWave(WaveNode(name: "Wave B", branch: "feature/tmux-plugin", estimatedTests: 8))
        tree.addWave(WaveNode(name: "Wave E", branch: "feature/event-router", estimatedTests: 30, dependsOn: ["Wave A"]))

        #expect(tree.waves.count == 3)
        #expect(tree.waves[2].dependsOn == ["Wave A"])
    }

    @Test("Parallel waves detected")
    func parallelWaves() {
        var tree = DependencyTree(baseBranch: "develop", baseCommit: "abc123")
        tree.addWave(WaveNode(name: "A", branch: "a", estimatedTests: 5))
        tree.addWave(WaveNode(name: "B", branch: "b", estimatedTests: 5))
        tree.addWave(WaveNode(name: "C", branch: "c", estimatedTests: 5))

        let parallel = tree.parallelWaves()
        #expect(parallel.count == 3) // all independent
    }

    @Test("Sequential waves respect dependencies")
    func sequentialWaves() {
        var tree = DependencyTree(baseBranch: "develop", baseCommit: "abc123")
        tree.addWave(WaveNode(name: "A", branch: "a", estimatedTests: 5))
        tree.addWave(WaveNode(name: "B", branch: "b", estimatedTests: 5, dependsOn: ["A"]))

        let parallel = tree.parallelWaves()
        #expect(parallel.count == 1) // only A is parallel
        #expect(parallel[0].name == "A")
    }

    @Test("Update wave status")
    func updateStatus() {
        var tree = DependencyTree(baseBranch: "develop", baseCommit: "abc123")
        tree.addWave(WaveNode(name: "A", branch: "a", estimatedTests: 5))

        tree.updateStatus(waveName: "A", status: .inProgress)
        #expect(tree.waves[0].status == .inProgress)

        tree.updateStatus(waveName: "A", status: .done(tests: 5))
        if case .done(let tests) = tree.waves[0].status {
            #expect(tests == 5)
        }
    }
}

@Suite("Dependency Tree — TPDD Integration")
struct DependencyTreeTPDDTests {

    @Test("Wave has test plan from S3 spec")
    func waveWithTestPlan() {
        let wave = WaveNode(
            name: "Wave A", branch: "feature/s3-parser",
            estimatedTests: 18, testPlanS3: """
            When parser receives a When block:
              → extract context and assertions
            """
        )
        #expect(wave.testPlanS3 != nil)
        #expect(wave.testPlanS3!.contains("When parser"))
    }

    @Test("Total estimated tests across tree")
    func totalTests() {
        var tree = DependencyTree(baseBranch: "develop", baseCommit: "abc123")
        tree.addWave(WaveNode(name: "A", branch: "a", estimatedTests: 18))
        tree.addWave(WaveNode(name: "B", branch: "b", estimatedTests: 8))
        tree.addWave(WaveNode(name: "C", branch: "c", estimatedTests: 10))

        #expect(tree.totalEstimatedTests == 36)
    }

    @Test("Completion percentage")
    func completionPercentage() {
        var tree = DependencyTree(baseBranch: "develop", baseCommit: "abc123")
        tree.addWave(WaveNode(name: "A", branch: "a", estimatedTests: 10))
        tree.addWave(WaveNode(name: "B", branch: "b", estimatedTests: 10))

        tree.updateStatus(waveName: "A", status: .done(tests: 10))

        #expect(tree.completionPercentage == 50)
    }
}

@Suite("Dependency Tree — Serialization")
struct DependencyTreeSerializationTests {

    @Test("Tree is Codable")
    func treeCodable() throws {
        var tree = DependencyTree(baseBranch: "develop", baseCommit: "abc123")
        tree.addWave(WaveNode(name: "A", branch: "a", estimatedTests: 5, dependsOn: ["X"]))

        let data = try JSONEncoder().encode(tree)
        let decoded = try JSONDecoder().decode(DependencyTree.self, from: data)
        #expect(decoded.waves.count == 1)
        #expect(decoded.baseBranch == "develop")
    }
}
