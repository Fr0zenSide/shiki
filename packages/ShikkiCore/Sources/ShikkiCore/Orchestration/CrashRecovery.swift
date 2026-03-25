import Foundation

/// Scans for stale checkpoints and recovers lifecycles.
public struct CrashRecovery: Sendable {
    let checkpointDir: String

    public init(checkpointDir: String = "~/.shiki/checkpoints") {
        self.checkpointDir = (checkpointDir as NSString).expandingTildeInPath
    }

    /// Find all checkpoint files (stale lifecycles that didn't reach .done or .failed).
    public func findRecoverable() throws -> [LifecycleCheckpoint] {
        let fm = FileManager.default
        let dir = checkpointDir
        guard fm.fileExists(atPath: dir) else { return [] }

        let files = try fm.contentsOfDirectory(atPath: dir)
            .filter { $0.hasSuffix(".json") }

        return files.compactMap { file in
            try? LifecycleCheckpoint.load(from: "\(dir)/\(file)")
        }.filter { $0.state != .done && $0.state != .failed }
    }

    /// Remove checkpoint after successful recovery or completion.
    public func removeCheckpoint(featureId: String) throws {
        let path = "\(checkpointDir)/\(featureId).json"
        if FileManager.default.fileExists(atPath: path) {
            try FileManager.default.removeItem(atPath: path)
        }
    }
}
