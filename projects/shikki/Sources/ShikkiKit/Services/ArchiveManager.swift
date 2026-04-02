import Foundation

// MARK: - ArchiveManager

/// Manages archive paths, log capture, and pruning for TestFlight builds.
public struct ArchiveManager: Sendable {

    public static var baseDir: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.shikki/archives"
    }

    public static var logDir: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.shikki/logs"
    }

    private let baseDir: String
    private let logDir: String

    public init(baseDir: String? = nil, logDir: String? = nil) {
        self.baseDir = baseDir ?? Self.baseDir
        self.logDir = logDir ?? Self.logDir
    }

    /// Build the archive path for a given app version+build.
    /// Format: ~/.shikki/archives/<slug>/<version>+<build>/<slug>.xcarchive
    public func archivePath(slug: String, version: String, build: Int) -> String {
        "\(baseDir)/\(slug)/\(version)+\(build)/\(slug).xcarchive"
    }

    /// Build the export path (directory containing .ipa).
    /// Format: ~/.shikki/archives/<slug>/<version>+<build>/
    public func exportPath(slug: String, version: String, build: Int) -> String {
        "\(baseDir)/\(slug)/\(version)+\(build)"
    }

    /// Build the log file path for an archive attempt.
    public func logPath(slug: String, timestamp: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let ts = formatter.string(from: timestamp)
        return "\(logDir)/\(slug)-archive-\(ts).log"
    }

    /// Ensure archive and log directories exist.
    public func ensureDirectories(slug: String, version: String, build: Int) throws {
        let archiveDir = (archivePath(slug: slug, version: version, build: build) as NSString)
            .deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: archiveDir, withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            atPath: logDir, withIntermediateDirectories: true
        )
    }

    /// Prune old archives, keeping only the last `keep` per app.
    public func prune(slug: String, keep: Int = 5) throws {
        let appDir = "\(baseDir)/\(slug)"
        let fm = FileManager.default

        guard fm.fileExists(atPath: appDir) else { return }

        let contents = try fm.contentsOfDirectory(atPath: appDir)
            .sorted() // Lexicographic sort puts older versions first
        let excess = contents.count - keep

        if excess > 0 {
            for dir in contents.prefix(excess) {
                let fullPath = "\(appDir)/\(dir)"
                try fm.removeItem(atPath: fullPath)
            }
        }
    }

    /// Parse xcodebuild errors from a log file. Returns top N error lines.
    public func parseErrors(from logContent: String, maxErrors: Int = 3) -> [String] {
        let lines = logContent.split(separator: "\n")
        var errors: [String] = []

        for line in lines {
            let s = String(line)
            if s.contains(": error:") ||
                s.contains("Code Sign error") ||
                s.contains("No provisioning profile") ||
                s.contains("module") && s.contains("not found") {
                errors.append(s.trimmingCharacters(in: .whitespaces))
                if errors.count >= maxErrors {
                    break
                }
            }
        }

        return errors
    }

    /// Categorize an archive failure for a human-readable hint.
    public func diagnosisHint(from logContent: String) -> String {
        if logContent.contains("Code Sign error") || logContent.contains("No provisioning profile") {
            return "Signing issue detected. Run: shi doctor --signing"
        }
        if logContent.contains("module") && logContent.contains("not found") {
            return "Missing module. Check your SPM dependencies or framework search paths."
        }
        if logContent.contains(": error:") {
            return "Compilation error. Check the full log for details."
        }
        return "Unknown failure. Check the full log."
    }
}
