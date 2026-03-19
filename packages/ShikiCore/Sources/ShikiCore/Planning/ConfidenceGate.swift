import Foundation

/// Analyzes file overlap between waves to determine if they can run in parallel.
public struct ConfidenceGate: Sendable {

    public init() {}

    /// Returns true if two waves can safely run in parallel (no file overlap).
    public static func canRunInParallel(_ a: WaveNode, _ b: WaveNode) -> Bool {
        let aFiles = Set(a.files)
        let bFiles = Set(b.files)
        return aFiles.isDisjoint(with: bFiles)
    }

    /// Given a list of waves, return groups that can run in parallel.
    public static func parallelGroups(_ waves: [WaveNode]) -> [[WaveNode]] {
        var groups: [[WaveNode]] = []
        var remaining = waves

        while !remaining.isEmpty {
            var group: [WaveNode] = [remaining.removeFirst()]
            var i = 0
            while i < remaining.count {
                let candidate = remaining[i]
                if group.allSatisfy({ canRunInParallel($0, candidate) }) {
                    group.append(remaining.remove(at: i))
                } else {
                    i += 1
                }
            }
            groups.append(group)
        }
        return groups
    }
}
