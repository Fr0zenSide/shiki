import Foundation

// MARK: - ShipLogEntry

/// A single entry in the ship log — records "why" for every release.
public struct ShipLogEntry: Sendable {
    public let date: Date
    public let version: String
    public let project: String
    public let branch: String
    public let why: String
    public let riskScore: Int
    public let gateSummary: String

    public init(
        date: Date,
        version: String,
        project: String,
        branch: String,
        why: String,
        riskScore: Int,
        gateSummary: String
    ) {
        self.date = date
        self.version = version
        self.project = project
        self.branch = branch
        self.why = why
        self.riskScore = riskScore
        self.gateSummary = gateSummary
    }
}

// MARK: - ShipLog

/// Append-only ship log at ~/.shiki/ship-log.md.
/// Records every release with a mandatory "why" field.
public struct ShipLog: Sendable {
    let path: String

    public init(path: String? = nil) {
        if let path {
            self.path = path
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            self.path = "\(home)/.shiki/ship-log.md"
        }
    }

    /// Append an entry to the ship log file.
    public func append(_ entry: ShipLogEntry) throws {
        let dateStr = entry.date.shortDisplay

        let markdown = """

        ## \(entry.version) — \(dateStr)
        - **Project**: \(entry.project)
        - **Branch**: \(entry.branch)
        - **Why**: \(entry.why)
        - **Risk**: \(entry.riskScore)
        - **Gates**: \(entry.gateSummary)

        """

        // Ensure directory exists
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        // Append or create
        if FileManager.default.fileExists(atPath: path) {
            let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
            handle.seekToEndOfFile()
            handle.write(Data(markdown.utf8))
            handle.closeFile()
        } else {
            let header = "# Ship Log\n\n"
            try (header + markdown).write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    /// Read all entries from the ship log file (raw markdown).
    public func readHistory() throws -> String {
        guard FileManager.default.fileExists(atPath: path) else {
            return "No ship log found at \(path)"
        }
        return try String(contentsOfFile: path, encoding: .utf8)
    }
}
