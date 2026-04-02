import Foundation

/// Tracks file modification times for incremental cache rebuilds.
///
/// Takes snapshots of a directory and compares them to detect
/// which files changed, enabling incremental-only rebuilds.
public struct CacheInvalidationTracker: Sendable {

    public init() {}

    /// Create a snapshot of all Swift files in a directory.
    ///
    /// Records the modification date for each `.swift` file found
    /// (non-recursively for the given directory, recursively for subdirs).
    ///
    /// - Parameter directory: Absolute path to scan.
    /// - Returns: A ``FileSnapshot`` capturing current mtimes.
    public func snapshot(directory: String) throws -> FileSnapshot {
        let fm = FileManager.default
        let dirURL = URL(fileURLWithPath: directory)

        guard fm.fileExists(atPath: directory) else {
            return FileSnapshot(files: [:])
        }

        var fileMtimes: [String: Date] = [:]

        if let enumerator = fm.enumerator(
            at: dirURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension == "swift" else { continue }
                let resourceValues = try fileURL.resourceValues(forKeys: [.contentModificationDateKey])
                if let mtime = resourceValues.contentModificationDate {
                    fileMtimes[fileURL.path] = mtime
                }
            }
        }

        return FileSnapshot(files: fileMtimes)
    }

    /// Compare two snapshots and return paths of files that changed.
    ///
    /// A file is "changed" if:
    /// - It exists in `new` but not in `old` (added)
    /// - Its mtime in `new` differs from `old` (modified)
    /// - It exists in `old` but not in `new` (deleted — included for cache invalidation)
    ///
    /// - Parameters:
    ///   - old: The previous snapshot.
    ///   - new: The current snapshot.
    /// - Returns: Array of absolute file paths that changed.
    public func changedFiles(old: FileSnapshot, new: FileSnapshot) -> [String] {
        var changed: Set<String> = []

        // Check for new or modified files
        for (path, newMtime) in new.files {
            if let oldMtime = old.files[path] {
                if newMtime != oldMtime {
                    changed.insert(path)
                }
            } else {
                // New file
                changed.insert(path)
            }
        }

        // Check for deleted files
        for path in old.files.keys where new.files[path] == nil {
            changed.insert(path)
        }

        return changed.sorted()
    }

    /// Return all file paths in a snapshot (for force rebuild).
    ///
    /// - Parameter snapshot: The snapshot to extract files from.
    /// - Returns: All file paths in the snapshot.
    public func allFiles(in snapshot: FileSnapshot) -> [String] {
        snapshot.files.keys.sorted()
    }
}

/// A snapshot of file modification times at a point in time.
public struct FileSnapshot: Sendable, Codable, Equatable {
    /// Map of absolute file path -> modification date.
    public var files: [String: Date]

    public init(files: [String: Date] = [:]) {
        self.files = files
    }
}
