import Foundation
import Logging

// MARK: - RestartResult

/// Outcome of a restart attempt.
public enum RestartResult: Sendable {
    /// Binary was swapped successfully.
    case swapped(oldVersion: String, newVersion: String)
    /// Restart skipped (e.g., same version).
    case skipped(reason: String)
    /// Restart aborted due to a validation failure.
    case aborted(reason: String)
}

// MARK: - RestartService

/// Core restart logic for hot-reload binary swap.
///
/// Implements the two-phase restart flow:
/// - Phase 1 (old binary): resolve, validate, checkpoint, copy rollback, execv()
/// - Phase 2 (new binary): SetupGuard.check() for dep validation
///
/// All dependencies are injected for testability.
public struct RestartService: Sendable {
    public let checkpointManager: CheckpointManager
    public let setupGuard: SetupGuard
    public let binarySwapper: any BinarySwapping
    public let shellExecutor: any ShellExecuting
    public let currentVersion: String
    public let currentBinaryPath: String
    public let shikkiBinDir: String
    public let buildReleaseDir: String
    public let buildDebugDir: String
    public let tmuxSession: String
    public let tmuxRunning: Bool

    /// Tracks whether the last restart call requested dependency upgrades.
    public private(set) var lastUpgradeDepsRequested: Bool = false

    private let logger = Logger(label: "shikki.restart")

    /// Mach-O 64-bit magic bytes (big-endian).
    private static let machOMagic: [UInt8] = [0xFE, 0xED, 0xFA, 0xCF]
    /// ELF magic bytes.
    private static let elfMagic: [UInt8] = [0x7F, 0x45, 0x4C, 0x46]

    public init(
        checkpointManager: CheckpointManager,
        setupGuard: SetupGuard,
        binarySwapper: any BinarySwapping,
        shellExecutor: any ShellExecuting,
        currentVersion: String,
        currentBinaryPath: String? = nil,
        shikkiBinDir: String? = nil,
        buildReleaseDir: String? = nil,
        buildDebugDir: String? = nil,
        tmuxSession: String = "shiki",
        tmuxRunning: Bool = true
    ) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.checkpointManager = checkpointManager
        self.setupGuard = setupGuard
        self.binarySwapper = binarySwapper
        self.shellExecutor = shellExecutor
        self.currentVersion = currentVersion
        self.currentBinaryPath = currentBinaryPath ?? ProcessInfo.processInfo.arguments.first ?? ""
        self.shikkiBinDir = shikkiBinDir ?? "\(home)/.shikki/bin"
        self.buildReleaseDir = buildReleaseDir ?? ".build/release"
        self.buildDebugDir = buildDebugDir ?? ".build/debug"
        self.tmuxSession = tmuxSession
        self.tmuxRunning = tmuxRunning
    }

    // MARK: - Public API

    /// Execute the restart flow.
    /// - Parameters:
    ///   - force: Skip version comparison checks (still runs healthcheck).
    ///   - upgradeDeps: Trigger dependency upgrade post-swap.
    /// - Returns: The outcome of the restart attempt.
    public mutating func restart(force: Bool = false, upgradeDeps: Bool = false) async throws -> RestartResult {
        lastUpgradeDepsRequested = upgradeDeps

        // BR-01: tmux session must exist
        guard tmuxRunning else {
            return .aborted(reason: "No tmux session running — use 'shikki start' first")
        }

        // BR-07: Resolve new binary
        guard let newBinaryPath = Self.resolveBinary(
            shikkiBinDir: shikkiBinDir,
            buildReleaseDir: buildReleaseDir,
            buildDebugDir: buildDebugDir
        ) else {
            return .aborted(reason: "No candidate binary found")
        }

        // BR-04: Check permissions (executable)
        guard isExecutable(path: newBinaryPath) else {
            return .aborted(reason: "Binary not executable: \(newBinaryPath)")
        }

        // BR-04: Check magic bytes (Mach-O or ELF)
        guard hasValidMagicBytes(path: newBinaryPath) else {
            return .aborted(reason: "Invalid binary format (bad magic bytes): \(newBinaryPath)")
        }

        // BR-14: Mtime drift detection — abort if build in progress
        if let mtimeResult = await checkMtimeDrift(path: newBinaryPath) {
            return mtimeResult
        }

        // Get new binary version
        let newVersion: String
        do {
            let (stdout, exitCode) = try await shellExecutor.run(newBinaryPath, arguments: ["--version"])
            guard exitCode == 0 else {
                return .aborted(reason: "Failed to get version from new binary (exit \(exitCode))")
            }
            newVersion = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return .aborted(reason: "Failed to query new binary version: \(error)")
        }

        // BR-08: Version comparison
        if !force {
            if let currentSemVer = SemanticVersion(string: currentVersion),
               let newSemVer = SemanticVersion(string: newVersion) {
                if newSemVer == currentSemVer {
                    return .skipped(reason: "Binary is already at same version (\(currentVersion))")
                }

                // BR-09: Downgrade warning
                if newSemVer < currentSemVer {
                    return .aborted(reason: "Downgrade detected (\(currentVersion) → \(newVersion)). Use --force to proceed.")
                }
            } else {
                // Non-semver: compare as strings
                if currentVersion == newVersion {
                    return .skipped(reason: "Binary is already at same version (\(currentVersion))")
                }
            }
        }

        // BR-03: Healthcheck probe (always runs, even with --force)
        do {
            let (_, healthExitCode) = try await shellExecutor.run(newBinaryPath, arguments: ["--healthcheck"])
            guard healthExitCode == 0 else {
                return .aborted(reason: "Healthcheck failed for new binary (exit \(healthExitCode))")
            }
        } catch {
            return .aborted(reason: "Healthcheck probe failed: \(error)")
        }

        // BR-05: Save checkpoint before swap
        do {
            let checkpoint = Checkpoint(
                timestamp: Date(),
                hostname: ProcessInfo.processInfo.hostName,
                fsmState: .running,
                contextSnippet: "Pre-restart checkpoint (\(currentVersion) → \(newVersion))",
                dbSynced: false
            )
            try checkpointManager.save(checkpoint)
        } catch {
            return .aborted(reason: "Checkpoint save failed: \(error)")
        }

        // BR-06: Copy current binary to shikki.prev for rollback
        copyRollbackBinary(currentPath: currentBinaryPath, binDir: shikkiBinDir)

        // BR-02: Execute swap via BinarySwapping protocol
        do {
            var args = ["restart", "--phase", "post-swap"]
            if upgradeDeps {
                args.append("--upgrade-deps")
            }
            try binarySwapper.exec(path: newBinaryPath, args: args)
            // exec() returns Never on success — we only reach here in tests
        } catch BinarySwapError.swapSucceeded {
            // Test sentinel — swap "succeeded"
            return .swapped(oldVersion: currentVersion, newVersion: newVersion)
        } catch {
            // BR-13: execv() failed — old binary continues
            logger.error("Binary swap failed: \(error)")
            return .aborted(reason: "Binary swap failed: \(error)")
        }
    }

    // MARK: - Binary Resolution (BR-07)

    /// Resolve the highest-priority candidate binary.
    /// Priority: ~/.shikki/bin/shikki > .build/release/shikki > .build/debug/shikki
    public static func resolveBinary(
        shikkiBinDir: String,
        buildReleaseDir: String,
        buildDebugDir: String
    ) -> String? {
        let fm = FileManager.default
        let candidates = [
            "\(shikkiBinDir)/shikki",
            "\(buildReleaseDir)/shikki",
            "\(buildDebugDir)/shikki",
        ]
        return candidates.first { fm.fileExists(atPath: $0) }
    }

    // MARK: - Validation Helpers

    /// Check if a file is executable by the current user (BR-04).
    private func isExecutable(path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }

    /// Check for valid binary magic bytes: Mach-O (0xFEEDFACF) or ELF (0x7F454C46).
    private func hasValidMagicBytes(path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { handle.closeFile() }
        let data = handle.readData(ofLength: 4)
        guard data.count == 4 else { return false }
        let bytes = Array(data)
        return bytes == Self.machOMagic || bytes == Self.elfMagic
    }

    /// BR-14: Check if the binary file mtime is drifting (build in progress).
    /// Reads mtime twice with a 150ms gap. If the mtime changes, the file is being written.
    private func checkMtimeDrift(path: String) async -> RestartResult? {
        let fm = FileManager.default
        guard let attrs1 = try? fm.attributesOfItem(atPath: path),
              let mtime1 = attrs1[.modificationDate] as? Date else {
            return nil
        }

        // If the file was modified less than 100ms ago, it might be mid-write
        let age = Date().timeIntervalSince(mtime1)
        if age < 0.1 {
            // Wait and check again
            try? await Task.sleep(for: .milliseconds(150))
            guard let attrs2 = try? fm.attributesOfItem(atPath: path),
                  let mtime2 = attrs2[.modificationDate] as? Date else {
                return nil
            }
            if mtime2 != mtime1 {
                return .aborted(reason: "Build in progress — binary mtime is still changing")
            }
        }
        return nil
    }

    /// BR-06: Copy current binary to shikki.prev for rollback.
    private func copyRollbackBinary(currentPath: String, binDir: String) {
        let fm = FileManager.default
        let prevPath = "\(binDir)/shikki.prev"

        // Ensure bin directory exists
        try? fm.createDirectory(atPath: binDir, withIntermediateDirectories: true)

        // Remove existing .prev if present
        try? fm.removeItem(atPath: prevPath)

        // Copy current binary
        do {
            try fm.copyItem(atPath: currentPath, toPath: prevPath)
        } catch {
            logger.warning("Failed to create rollback binary: \(error)")
        }
    }
}
