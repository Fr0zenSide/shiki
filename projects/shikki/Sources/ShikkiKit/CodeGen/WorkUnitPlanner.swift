import Foundation

/// A parallelizable unit of work for an agent.
///
/// Each WorkUnit represents a set of files an agent must implement,
/// given a protocol layer as contract and architecture cache as context.
public struct WorkUnit: Sendable, Codable, Identifiable {
    public var id: String
    /// Human-readable description of what this unit implements.
    public var description: String
    /// Files this agent must create/modify.
    public var files: [FileSpec]
    /// Protocols this unit must implement.
    public var protocolNames: [String]
    /// Types this unit must create.
    public var typeNames: [String]
    /// Test files that verify this unit.
    public var testScope: [String]
    /// Git branch name for the worktree.
    public var worktreeBranch: String
    /// Priority order (lower = earlier in merge order).
    public var priority: Int

    public init(
        id: String,
        description: String = "",
        files: [FileSpec] = [],
        protocolNames: [String] = [],
        typeNames: [String] = [],
        testScope: [String] = [],
        worktreeBranch: String = "",
        priority: Int = 0
    ) {
        self.id = id
        self.description = description
        self.files = files
        self.protocolNames = protocolNames
        self.typeNames = typeNames
        self.testScope = testScope
        self.worktreeBranch = worktreeBranch
        self.priority = priority
    }
}

/// Result of work unit planning.
public struct WorkPlan: Sendable {
    /// The work units to dispatch.
    public let units: [WorkUnit]
    /// Whether the plan uses parallel dispatch or sequential.
    public let strategy: DispatchStrategy
    /// Explanation of why this strategy was chosen.
    public let rationale: String

    public init(units: [WorkUnit], strategy: DispatchStrategy, rationale: String = "") {
        self.units = units
        self.strategy = strategy
        self.rationale = rationale
    }
}

/// How work units should be dispatched.
public enum DispatchStrategy: String, Sendable, Codable {
    /// Do it inline, no agents needed (2-5 files).
    case sequential
    /// 2-3 agents, split by module (5-15 files).
    case parallel
    /// N agents, one per logical module (15+ files).
    case massiveParallel
}

/// Plans how to split a ``ProtocolLayer`` into parallelizable ``WorkUnit``s.
///
/// Smart splitting rules (from challenge session):
/// - **2-5 files**: don't spawn agents, do it directly
/// - **5-15 files**: 2-3 agents max, split by module boundary
/// - **15+ files**: N agents, one per logical module
public struct WorkUnitPlanner: Sendable {

    public init() {}

    /// Create a work plan from a protocol layer.
    ///
    /// - Parameters:
    ///   - layer: The verified protocol layer.
    ///   - cache: Optional architecture cache for module-aware splitting.
    ///   - baseBranch: The branch to create worktrees from (default: current).
    public func plan(
        _ layer: ProtocolLayer,
        cache: ArchitectureCache? = nil,
        baseBranch: String = "HEAD"
    ) -> WorkPlan {
        let totalFiles = countImplementationFiles(layer)
        let strategy = determineStrategy(fileCount: totalFiles)

        switch strategy {
        case .sequential:
            return planSequential(layer, baseBranch: baseBranch)
        case .parallel:
            return planParallel(layer, cache: cache, baseBranch: baseBranch)
        case .massiveParallel:
            return planMassiveParallel(layer, cache: cache, baseBranch: baseBranch)
        }
    }

    // MARK: - Strategy Selection

    func determineStrategy(fileCount: Int) -> DispatchStrategy {
        if fileCount <= 5 {
            return .sequential
        } else if fileCount <= 15 {
            return .parallel
        } else {
            return .massiveParallel
        }
    }

    func countImplementationFiles(_ layer: ProtocolLayer) -> Int {
        // Count from file specs, or estimate from protocols + types
        if !layer.fileSpecs.isEmpty {
            return layer.fileSpecs.count
        }
        // Each protocol gets a file, each type gets a file, each protocol gets a test
        return layer.protocols.count + layer.types.count + layer.protocols.count
    }

    // MARK: - Sequential Plan

    func planSequential(_ layer: ProtocolLayer, baseBranch: String) -> WorkPlan {
        let branchName = sanitizeBranch("codegen/\(layer.featureName)")

        // Everything in one unit
        var allFiles: [FileSpec] = []
        for proto in layer.protocols {
            allFiles.append(FileSpec(
                path: proto.targetFile,
                role: .protocol,
                description: "Protocol: \(proto.name)"
            ))
        }
        for type in layer.types {
            allFiles.append(FileSpec(
                path: type.targetFile,
                role: type.kind == .enum ? .model : .implementation,
                description: "Type: \(type.name)"
            ))
        }
        // Add explicit file specs from TDDP
        for spec in layer.fileSpecs where !allFiles.contains(where: { $0.path == spec.path }) {
            allFiles.append(spec)
        }

        let unit = WorkUnit(
            id: "unit-1",
            description: "Implement \(layer.featureName) (all files)",
            files: allFiles,
            protocolNames: layer.protocols.map(\.name),
            typeNames: layer.types.map(\.name),
            testScope: layer.fileSpecs.filter { $0.role == .test }.map(\.path),
            worktreeBranch: branchName,
            priority: 0
        )

        return WorkPlan(
            units: [unit],
            strategy: .sequential,
            rationale: "\(countImplementationFiles(layer)) files — inline execution, no agent spawn overhead"
        )
    }

    // MARK: - Parallel Plan

    func planParallel(_ layer: ProtocolLayer, cache: ArchitectureCache?, baseBranch: String) -> WorkPlan {
        // Split by logical grouping: protocols/models first, then implementations
        var units: [WorkUnit] = []

        // Unit 1: Protocol layer + core models (always first — others depend on it)
        let protoFiles = layer.protocols.map { proto in
            FileSpec(path: proto.targetFile, role: .protocol, description: "Protocol: \(proto.name)")
        }
        let modelFiles = layer.types.filter { $0.kind == .struct || $0.kind == .enum }.map { type in
            FileSpec(path: type.targetFile, role: .model, description: "Model: \(type.name)")
        }

        if !protoFiles.isEmpty || !modelFiles.isEmpty {
            let branchName = sanitizeBranch("codegen/\(layer.featureName)/protocols")
            units.append(WorkUnit(
                id: "unit-protocols",
                description: "Protocol layer + core models for \(layer.featureName)",
                files: protoFiles + modelFiles,
                protocolNames: layer.protocols.map(\.name),
                typeNames: layer.types.filter { $0.kind == .struct || $0.kind == .enum }.map(\.name),
                testScope: [],
                worktreeBranch: branchName,
                priority: 0
            ))
        }

        // Remaining files: split into groups by module or logical boundary
        let implFiles = layer.fileSpecs.filter { $0.role == .implementation }
        let testFiles = layer.fileSpecs.filter { $0.role == .test }
        let mockFiles = layer.fileSpecs.filter { $0.role == .mock }

        if !implFiles.isEmpty || !mockFiles.isEmpty {
            // Group by directory (module proxy)
            let grouped = groupByDirectory(implFiles + mockFiles)
            for (idx, (dir, files)) in grouped.enumerated() {
                let branchName = sanitizeBranch("codegen/\(layer.featureName)/impl-\(idx + 1)")
                let implTypes = layer.types.filter { type in
                    files.contains { $0.path.contains(type.name) }
                }
                units.append(WorkUnit(
                    id: "unit-impl-\(idx + 1)",
                    description: "Implementation: \(dir.isEmpty ? "main" : dir)",
                    files: files,
                    protocolNames: [],
                    typeNames: implTypes.map(\.name),
                    testScope: testFiles.filter { tf in
                        files.contains { f in
                            // Match test to impl by name similarity
                            let implName = URL(fileURLWithPath: f.path).deletingPathExtension().lastPathComponent
                            return tf.path.contains(implName)
                        }
                    }.map(\.path),
                    worktreeBranch: branchName,
                    priority: idx + 1
                ))
            }
        }

        // Test unit (if tests aren't already assigned to impl units)
        let unassignedTests = testFiles.filter { test in
            !units.contains { $0.testScope.contains(test.path) }
        }
        if !unassignedTests.isEmpty {
            let branchName = sanitizeBranch("codegen/\(layer.featureName)/tests")
            units.append(WorkUnit(
                id: "unit-tests",
                description: "Tests for \(layer.featureName)",
                files: unassignedTests,
                protocolNames: [],
                typeNames: [],
                testScope: unassignedTests.map(\.path),
                worktreeBranch: branchName,
                priority: units.count
            ))
        }

        // If we only got the protocol unit, fall back to sequential
        if units.count <= 1 {
            return planSequential(layer, baseBranch: baseBranch)
        }

        return WorkPlan(
            units: units,
            strategy: .parallel,
            rationale: "\(countImplementationFiles(layer)) files → \(units.count) work units, split by module boundary"
        )
    }

    // MARK: - Massive Parallel Plan

    func planMassiveParallel(_ layer: ProtocolLayer, cache: ArchitectureCache?, baseBranch: String) -> WorkPlan {
        // Same as parallel but with finer granularity — one unit per module
        let plan = planParallel(layer, cache: cache, baseBranch: baseBranch)

        // If parallel already produced enough units, keep it
        if plan.units.count >= 3 {
            return WorkPlan(
                units: plan.units,
                strategy: .massiveParallel,
                rationale: "\(countImplementationFiles(layer)) files → \(plan.units.count) agents, one per logical module"
            )
        }

        // Otherwise split further — each file gets its own unit
        var units: [WorkUnit] = []

        // Protocol unit always first
        let protoFiles = layer.protocols.map { proto in
            FileSpec(path: proto.targetFile, role: .protocol, description: "Protocol: \(proto.name)")
        }
        if !protoFiles.isEmpty {
            units.append(WorkUnit(
                id: "unit-protocols",
                description: "Protocol layer for \(layer.featureName)",
                files: protoFiles,
                protocolNames: layer.protocols.map(\.name),
                typeNames: [],
                testScope: [],
                worktreeBranch: sanitizeBranch("codegen/\(layer.featureName)/protocols"),
                priority: 0
            ))
        }

        // One unit per remaining file spec
        for (idx, spec) in layer.fileSpecs.enumerated() where spec.role != .protocol {
            let branchName = sanitizeBranch("codegen/\(layer.featureName)/file-\(idx + 1)")
            units.append(WorkUnit(
                id: "unit-file-\(idx + 1)",
                description: spec.description.isEmpty ? spec.path : spec.description,
                files: [spec],
                protocolNames: [],
                typeNames: [],
                testScope: [],
                worktreeBranch: branchName,
                priority: idx + 1
            ))
        }

        return WorkPlan(
            units: units,
            strategy: .massiveParallel,
            rationale: "\(countImplementationFiles(layer)) files → \(units.count) agents for maximum parallelism"
        )
    }

    // MARK: - Helpers

    func groupByDirectory(_ files: [FileSpec]) -> [(String, [FileSpec])] {
        let grouped = Dictionary(grouping: files) { spec -> String in
            let url = URL(fileURLWithPath: spec.path)
            return url.deletingLastPathComponent().path
        }
        return grouped.sorted { $0.key < $1.key }
    }

    func sanitizeBranch(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "_", with: "-")
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/-")).inverted)
            .joined()
    }
}
