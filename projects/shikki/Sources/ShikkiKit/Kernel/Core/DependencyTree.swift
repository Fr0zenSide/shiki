import Foundation

// MARK: - Wave Status

public enum WaveStatus: Codable, Sendable, Equatable {
    case pending
    case inProgress
    case done(tests: Int)
    case failed(reason: String)
}

// MARK: - Wave Node

/// A single wave in the dependency tree.
public struct WaveNode: Codable, Sendable {
    public let name: String
    public let branch: String
    public var estimatedTests: Int
    public var dependsOn: [String]
    public var status: WaveStatus
    public var testPlanS3: String?
    public var files: [String]

    public init(
        name: String, branch: String, estimatedTests: Int = 0,
        dependsOn: [String] = [], status: WaveStatus = .pending,
        testPlanS3: String? = nil, files: [String] = []
    ) {
        self.name = name
        self.branch = branch
        self.estimatedTests = estimatedTests
        self.dependsOn = dependsOn
        self.status = status
        self.testPlanS3 = testPlanS3
        self.files = files
    }
}

// MARK: - Dependency Tree

/// The full dependency tree for a multi-wave implementation plan.
public struct DependencyTree: Codable, Sendable {
    public let baseBranch: String
    public let baseCommit: String
    public var waves: [WaveNode]

    public init(baseBranch: String, baseCommit: String, waves: [WaveNode] = []) {
        self.baseBranch = baseBranch
        self.baseCommit = baseCommit
        self.waves = waves
    }

    // MARK: - Mutation

    public mutating func addWave(_ wave: WaveNode) {
        waves.append(wave)
    }

    public mutating func updateStatus(waveName: String, status: WaveStatus) {
        if let idx = waves.firstIndex(where: { $0.name == waveName }) {
            waves[idx].status = status
        }
    }

    // MARK: - Queries

    /// Waves that can run in parallel (no unmet dependencies).
    public func parallelWaves() -> [WaveNode] {
        let completedNames = Set(waves.compactMap { wave -> String? in
            if case .done = wave.status { return wave.name }
            return nil
        })

        return waves.filter { wave in
            guard wave.status == .pending else { return false }
            return wave.dependsOn.allSatisfy { completedNames.contains($0) || $0.isEmpty }
        }
    }

    /// Total estimated tests across all waves.
    public var totalEstimatedTests: Int {
        waves.reduce(0) { $0 + $1.estimatedTests }
    }

    /// Completion percentage (0-100).
    public var completionPercentage: Int {
        let total = waves.count
        guard total > 0 else { return 0 }
        let done = waves.filter {
            if case .done = $0.status { return true }
            return false
        }.count
        return (done * 100) / total
    }

    /// The final branch — position here = full implementation.
    public var finalBranch: String? {
        waves.last?.branch
    }

    // MARK: - Rendering

    /// Render the tree as a text diagram.
    public func render() -> String {
        var lines: [String] = []
        lines.append("DEPENDENCY TREE")
        lines.append(String(repeating: "═", count: 50))
        lines.append("")
        lines.append("  \(baseBranch) (\(baseCommit.prefix(7))) ─── base")

        for (i, wave) in waves.enumerated() {
            let connector = i == waves.count - 1 ? "└─" : "├─"
            let statusIcon: String
            switch wave.status {
            case .pending: statusIcon = "►"
            case .inProgress: statusIcon = "●"
            case .done: statusIcon = "✓"
            case .failed: statusIcon = "✗"
            }

            let deps = wave.dependsOn.isEmpty ? "" : " (after \(wave.dependsOn.joined(separator: ", ")))"
            lines.append("    \(connector)\(statusIcon) \(wave.name): \(wave.branch)")
            lines.append("    │   \(wave.estimatedTests) tests\(deps)")
        }

        lines.append("")
        lines.append("  Progress: \(completionPercentage)%")
        if let final = finalBranch {
            lines.append("  Final: \(final)")
        }

        return lines.joined(separator: "\n")
    }
}
