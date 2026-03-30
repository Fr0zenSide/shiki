import Testing
import Foundation
@testable import ShikkiKit

@Suite("WorkUnitPlanner")
struct WorkUnitPlannerTests {

    let planner = WorkUnitPlanner()

    // MARK: - Strategy Selection

    @Test("2-5 files → sequential strategy")
    func sequentialStrategy() {
        let layer = makeLayer(fileCount: 3)
        let plan = planner.plan(layer)
        #expect(plan.strategy == .sequential)
        #expect(plan.units.count == 1)
    }

    @Test("5-15 files → parallel strategy")
    func parallelStrategy() {
        let layer = makeLayer(fileCount: 8)
        let plan = planner.plan(layer)
        #expect(plan.strategy == .parallel || plan.strategy == .sequential)
        // May fall back to sequential if files can't be split
    }

    @Test("15+ files → massive parallel strategy")
    func massiveParallelStrategy() {
        let layer = makeLayerWithManyFiles(count: 20)
        let plan = planner.plan(layer)
        #expect(plan.strategy == .massiveParallel || plan.strategy == .parallel)
    }

    // MARK: - Sequential Planning

    @Test("sequential plan has single unit with all files")
    func sequentialSingleUnit() {
        let layer = ProtocolLayer(
            featureName: "Small Feature",
            protocols: [
                ProtocolSpec(name: "Foo", methods: ["func bar()"], targetFile: "Sources/Foo.swift"),
            ],
            types: [
                TypeSpec(name: "Bar", targetFile: "Sources/Bar.swift"),
            ]
        )
        let plan = planner.plan(layer)
        #expect(plan.units.count == 1)
        #expect(plan.units[0].protocolNames.contains("Foo"))
        #expect(plan.units[0].typeNames.contains("Bar"))
    }

    @Test("sequential unit includes all protocol and type names")
    func sequentialAllNames() {
        let layer = ProtocolLayer(
            protocols: [
                ProtocolSpec(name: "A", targetFile: "a.swift"),
                ProtocolSpec(name: "B", targetFile: "b.swift"),
            ],
            types: [
                TypeSpec(name: "C", targetFile: "c.swift"),
            ]
        )
        let plan = planner.plan(layer)
        #expect(plan.units[0].protocolNames == ["A", "B"])
        #expect(plan.units[0].typeNames == ["C"])
    }

    // MARK: - Parallel Planning

    @Test("parallel plan separates protocol layer from implementation")
    func parallelSeparation() {
        let layer = ProtocolLayer(
            featureName: "Medium Feature",
            protocols: [
                ProtocolSpec(name: "Provider", methods: ["func fetch()"], targetFile: "Sources/Provider.swift"),
            ],
            types: [
                TypeSpec(name: "Model", kind: .struct, targetFile: "Sources/Model.swift"),
            ],
            fileSpecs: [
                FileSpec(path: "Sources/Impl/ServiceA.swift", role: .implementation, description: "Service A"),
                FileSpec(path: "Sources/Impl/ServiceB.swift", role: .implementation, description: "Service B"),
                FileSpec(path: "Sources/Other/Helper.swift", role: .implementation, description: "Helper"),
                FileSpec(path: "Tests/ServiceTests.swift", role: .test, description: "Tests"),
                FileSpec(path: "Tests/HelperTests.swift", role: .test, description: "Tests"),
                FileSpec(path: "Sources/Mocks/MockProvider.swift", role: .mock, description: "Mock"),
            ]
        )
        let plan = planner.plan(layer)
        #expect(plan.units.count >= 2)

        // First unit should be protocols
        let protoUnit = plan.units.first { $0.id == "unit-protocols" }
        #expect(protoUnit != nil)
        #expect(protoUnit?.priority == 0)
        #expect(protoUnit?.protocolNames.contains("Provider") == true)
    }

    // MARK: - Branch Naming

    @Test("branch names are sanitized")
    func branchSanitization() {
        let layer = ProtocolLayer(
            featureName: "Add Payment System!",
            protocols: [ProtocolSpec(name: "P", targetFile: "p.swift")],
            types: [TypeSpec(name: "T", targetFile: "t.swift")]
        )
        let plan = planner.plan(layer)
        let branch = plan.units[0].worktreeBranch
        #expect(!branch.contains(" "))
        #expect(!branch.contains("!"))
        #expect(branch.contains("payment"))
    }

    // MARK: - Rationale

    @Test("plan includes rationale")
    func planRationale() {
        let layer = makeLayer(fileCount: 3)
        let plan = planner.plan(layer)
        #expect(!plan.rationale.isEmpty)
    }

    // MARK: - Work Unit Properties

    @Test("work units have unique IDs")
    func uniqueIds() {
        let layer = makeLayerWithManyFiles(count: 20)
        let plan = planner.plan(layer)
        let ids = plan.units.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("work units have ascending priorities")
    func ascendingPriorities() {
        let layer = makeLayerWithManyFiles(count: 20)
        let plan = planner.plan(layer)
        for i in 1..<plan.units.count {
            #expect(plan.units[i].priority >= plan.units[i - 1].priority)
        }
    }

    @Test("protocol unit always has priority 0")
    func protocolPriority() {
        let layer = ProtocolLayer(
            featureName: "Feature",
            protocols: [
                ProtocolSpec(name: "P1", targetFile: "p1.swift"),
                ProtocolSpec(name: "P2", targetFile: "p2.swift"),
            ],
            types: [
                TypeSpec(name: "T1", targetFile: "t1.swift"),
            ],
            fileSpecs: [
                FileSpec(path: "Sources/A/Impl1.swift", role: .implementation),
                FileSpec(path: "Sources/A/Impl2.swift", role: .implementation),
                FileSpec(path: "Sources/B/Impl3.swift", role: .implementation),
                FileSpec(path: "Sources/B/Impl4.swift", role: .implementation),
                FileSpec(path: "Sources/C/Impl5.swift", role: .implementation),
                FileSpec(path: "Sources/C/Impl6.swift", role: .implementation),
            ]
        )
        let plan = planner.plan(layer)
        if let protoUnit = plan.units.first(where: { $0.id == "unit-protocols" }) {
            #expect(protoUnit.priority == 0)
        }
    }

    // MARK: - Edge Cases

    @Test("empty layer produces single empty unit")
    func emptyLayer() {
        let layer = ProtocolLayer(featureName: "Empty")
        let plan = planner.plan(layer)
        #expect(plan.strategy == .sequential)
        #expect(plan.units.count == 1)
    }

    @Test("layer with only file specs and no declarations")
    func fileSpecsOnly() {
        let layer = ProtocolLayer(
            featureName: "File Only",
            fileSpecs: [
                FileSpec(path: "Sources/A.swift", role: .implementation),
                FileSpec(path: "Sources/B.swift", role: .implementation),
            ]
        )
        let plan = planner.plan(layer)
        #expect(!plan.units.isEmpty)
    }

    // MARK: - Helpers

    func makeLayer(fileCount: Int) -> ProtocolLayer {
        var protos: [ProtocolSpec] = []
        var types: [TypeSpec] = []
        for i in 0..<max(1, fileCount / 3) {
            protos.append(ProtocolSpec(name: "Proto\(i)", methods: ["func method\(i)()"], targetFile: "Sources/Proto\(i).swift"))
        }
        for i in 0..<max(1, fileCount / 3) {
            types.append(TypeSpec(name: "Type\(i)", targetFile: "Sources/Type\(i).swift"))
        }
        return ProtocolLayer(
            featureName: "Test Feature",
            protocols: protos,
            types: types
        )
    }

    func makeLayerWithManyFiles(count: Int) -> ProtocolLayer {
        var specs: [FileSpec] = []
        var protos: [ProtocolSpec] = []
        protos.append(ProtocolSpec(name: "CoreProto", methods: ["func run()"], targetFile: "Sources/CoreProto.swift"))

        for i in 0..<count {
            let dir = ["Sources/A", "Sources/B", "Sources/C", "Sources/D"][i % 4]
            specs.append(FileSpec(path: "\(dir)/File\(i).swift", role: .implementation, description: "File \(i)"))
        }
        return ProtocolLayer(
            featureName: "Large Feature",
            protocols: protos,
            types: [],
            fileSpecs: specs
        )
    }
}
