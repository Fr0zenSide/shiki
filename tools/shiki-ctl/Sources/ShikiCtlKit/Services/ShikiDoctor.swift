import Foundation

// MARK: - Diagnostic Types

/// Categories of health checks.
public enum DiagnosticCategory: String, Sendable, CaseIterable {
    case binary    // Required CLI tools on PATH
    case docker    // Docker/Colima status
    case backend   // Backend API health
    case sessions  // Stale/orphaned sessions
    case config    // Config file validity
    case disk      // Disk space
    case git       // Git repo integrity
}

/// Status of a diagnostic check.
public enum DiagnosticStatus: String, Sendable {
    case ok
    case warning
    case error

    public var severity: Int {
        switch self {
        case .ok: 0
        case .warning: 1
        case .error: 2
        }
    }
}

/// Result of a single diagnostic check.
public struct DiagnosticResult: Sendable {
    public let name: String
    public let category: DiagnosticCategory
    public let status: DiagnosticStatus
    public let message: String
    public let fixCommand: String?

    public init(
        name: String, category: DiagnosticCategory,
        status: DiagnosticStatus, message: String,
        fixCommand: String? = nil
    ) {
        self.name = name
        self.category = category
        self.status = status
        self.message = message
        self.fixCommand = fixCommand
    }
}

// MARK: - ShikiDoctor

/// Runs diagnostics on the Shiki environment.
/// `shiki doctor` — check everything. `shiki doctor --fix` — auto-repair.
public struct ShikiDoctor: Sendable {

    /// Required binaries that must be on PATH.
    public static let requiredBinaries = ["git", "tmux", "claude"]

    /// Optional binaries that enhance the experience.
    public static let optionalBinaries = ["delta", "fzf", "rg", "bat", "qmd"]

    public init() {}

    /// Check if a binary is available.
    public func checkBinary(_ name: String) async -> DiagnosticResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", name]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                return DiagnosticResult(
                    name: name, category: .binary,
                    status: .ok, message: "\(name) found"
                )
            }
        } catch {}

        let isRequired = Self.requiredBinaries.contains(name)
        return DiagnosticResult(
            name: name, category: .binary,
            status: isRequired ? .error : .warning,
            message: "\(name) not found",
            fixCommand: "brew install \(name)"
        )
    }

    /// Run all binary checks.
    public func checkAllBinaries() async -> [DiagnosticResult] {
        var results: [DiagnosticResult] = []
        for binary in Self.requiredBinaries + Self.optionalBinaries {
            results.append(await checkBinary(binary))
        }
        return results
    }

    /// Check disk space (warn if < 5GB free).
    public func checkDiskSpace() -> DiagnosticResult {
        let home = FileManager.default.homeDirectoryForCurrentUser
        guard let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let available = values.volumeAvailableCapacityForImportantUsage else {
            return DiagnosticResult(
                name: "disk", category: .disk,
                status: .warning, message: "Could not check disk space"
            )
        }

        let gbFree = Double(available) / 1_073_741_824
        if gbFree < 5 {
            return DiagnosticResult(
                name: "disk", category: .disk,
                status: .warning,
                message: String(format: "Low disk space: %.1f GB free", gbFree)
            )
        }

        return DiagnosticResult(
            name: "disk", category: .disk,
            status: .ok,
            message: String(format: "%.1f GB free", gbFree)
        )
    }

    /// Run full diagnostic suite.
    public func runAll() async -> [DiagnosticResult] {
        var results = await checkAllBinaries()
        results.append(checkDiskSpace())
        return results.sorted { $0.status.severity > $1.status.severity }
    }
}
