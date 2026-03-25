import Foundation

/// A tree of waves with parent links. Each wave can run in parallel
/// unless it depends on another wave.
public struct DependencyTree: Codable, Sendable {
    public var waves: [WaveNode]

    public init(waves: [WaveNode] = []) {
        self.waves = waves
    }

    /// Returns waves that can execute now (all dependencies satisfied).
    public func readyWaves(completed: Set<String>) -> [WaveNode] {
        waves.filter { wave in
            !completed.contains(wave.id) &&
            wave.status != .done &&
            wave.status != .inProgress &&
            wave.dependsOn.allSatisfy { completed.contains($0) }
        }
    }

    /// Mark a wave as completed.
    public mutating func complete(waveId: String) {
        if let idx = waves.firstIndex(where: { $0.id == waveId }) {
            waves[idx].status = .done
        }
    }
}
