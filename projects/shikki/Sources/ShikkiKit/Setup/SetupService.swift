import Foundation

// MARK: - SetupService

/// Runs the Shikki bootstrap flow from Swift.
/// Same logic as `setup.sh` but smarter — checks each step, skips if already done,
/// reports progress to stdout.
public struct SetupService: Sendable {

    /// The current binary version string (e.g. "0.3.0-pre").
    public let currentVersion: String

    /// Path to the setup state file (overridable for testing).
    public let statePath: String?

    /// Brew package name mapping: binary name -> brew formula.
    public static let requiredBrewPackages: [(binary: String, formula: String)] = [
        ("tmux", "tmux"),
    ]

    public static let optionalBrewPackages: [(binary: String, formula: String)] = [
        ("delta", "git-delta"),
        ("fzf", "fzf"),
        ("rg", "ripgrep"),
        ("bat", "bat"),
    ]

    /// Directories to create under `.shikki/` relative to the repo root.
    public static let workspaceDirs = [
        ".shikki",
        ".shikki/test-logs",
        ".shikki/plugins",
        ".shikki/sessions",
    ]

    public init(currentVersion: String, statePath: String? = nil) {
        self.currentVersion = currentVersion
        self.statePath = statePath
    }

    // MARK: - Bootstrap

    /// Run the full bootstrap flow. Skips steps already marked complete.
    /// Returns true if all steps succeeded.
    @discardableResult
    public func bootstrap() async -> Bool {
        var state = SetupState.load(from: statePath)
            ?? SetupState(version: currentVersion, steps: [:])

        // If version matches and all steps done, nothing to do.
        if state.version == currentVersion && state.allStepsComplete {
            return true
        }

        // Update version if it changed (re-run all steps).
        if state.version != currentVersion {
            state = SetupState(version: currentVersion, steps: [:])
        }

        printHeader("Shikki Setup")

        // Step 1: Dependencies
        if !state.isStepComplete("dependencies") {
            printStep("Checking dependencies...")
            let depsOK = await checkAndInstallDependencies()
            if depsOK {
                state.markStep("dependencies")
            }
        } else {
            printSkip("dependencies")
        }

        // Step 2: Workspace directories
        if !state.isStepComplete("workspace") {
            printStep("Creating workspace directories...")
            let created = createWorkspaceDirs()
            if created {
                state.markStep("workspace")
            }
        } else {
            printSkip("workspace")
        }

        // Step 3: Ensure .env exists (required for docker compose)
        if !state.isStepComplete("dotenv") {
            printStep("Checking .env...")
            let dotenvOK = ensureDotenv()
            if dotenvOK {
                state.markStep("dotenv")
            }
        } else {
            printSkip("dotenv")
        }

        // Step 4: PATH check
        if !state.isStepComplete("completions") {
            printStep("Checking PATH...")
            checkPath()
            state.markStep("completions")
        } else {
            printSkip("completions")
        }

        // Save progress
        do {
            try state.save(to: statePath)
        } catch {
            printError("Failed to save setup state: \(error)")
        }

        printFooter()
        return state.allStepsComplete
    }

    // MARK: - Dependency Checks

    /// Check and install required + optional brew packages.
    /// Returns true if all required packages are available.
    public func checkAndInstallDependencies() async -> Bool {
        // Check swift
        guard binaryExists("swift") else {
            printError("Swift not found. Install from https://swift.org/install")
            return false
        }
        printOK("swift")

        // Check brew
        guard binaryExists("brew") else {
            printError("Homebrew not found. Install from https://brew.sh")
            return false
        }
        printOK("brew")

        // Install required
        var allRequiredOK = true
        for pkg in Self.requiredBrewPackages {
            if binaryExists(pkg.binary) {
                printOK(pkg.binary)
            } else {
                let installed = await installBrewPackage(pkg.formula)
                if installed {
                    printOK("\(pkg.binary) (installed)")
                } else {
                    printError("\(pkg.binary) — failed to install via brew")
                    allRequiredOK = false
                }
            }
        }

        // Install optional (best-effort)
        for pkg in Self.optionalBrewPackages {
            if binaryExists(pkg.binary) {
                printOK(pkg.binary)
            } else {
                let installed = await installBrewPackage(pkg.formula)
                if installed {
                    printOK("\(pkg.binary) (installed)")
                } else {
                    printWarning("\(pkg.binary) — not installed (optional)")
                }
            }
        }

        return allRequiredOK
    }

    /// Install a Homebrew package. Returns true on success.
    public func installBrewPackage(_ formula: String) async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["brew", "install", formula]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Check if a binary is on PATH.
    public func binaryExists(_ name: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", name]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    // MARK: - Workspace

    /// Create `.shikki/` directories. Returns true on success.
    public func createWorkspaceDirs() -> Bool {
        let fm = FileManager.default
        do {
            for dir in Self.workspaceDirs {
                // Use current working directory as repo root
                let path = fm.currentDirectoryPath + "/" + dir
                if !fm.fileExists(atPath: path) {
                    try fm.createDirectory(atPath: path, withIntermediateDirectories: true)
                }
            }
            return true
        } catch {
            printError("Failed to create directories: \(error)")
            return false
        }
    }

    /// Check if ~/.local/bin is on PATH and print advice.
    public func checkPath() {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let localBin = FileManager.default.homeDirectoryForCurrentUser.path + "/.local/bin"
        if path.contains(localBin) {
            printOK("~/.local/bin in PATH")
        } else {
            printWarning("~/.local/bin not in PATH — add to ~/.zshrc:")
            printHint("  export PATH=\"$HOME/.local/bin:$PATH\"")
        }
    }

    // MARK: - Dotenv

    /// Copy .env.example to .env if missing. Returns true on success.
    public func ensureDotenv() -> Bool {
        let fm = FileManager.default
        let cwd = fm.currentDirectoryPath
        let envPath = cwd + "/.env"
        let examplePath = cwd + "/.env.example"

        if fm.fileExists(atPath: envPath) {
            printOK(".env exists")
            return true
        }

        guard fm.fileExists(atPath: examplePath) else {
            printWarning(".env.example not found — skipping")
            return true
        }

        do {
            try fm.copyItem(atPath: examplePath, toPath: envPath)
            printOK(".env created from .env.example")
            printHint("  Edit .env to set your credentials before running docker compose")
            return true
        } catch {
            printError("Failed to copy .env.example to .env: \(error)")
            return false
        }
    }

    // MARK: - Fix Missing Tools

    /// Install missing optional tools (used by `doctor --fix`).
    /// Returns names of tools that were successfully installed.
    public func fixMissingOptionalTools() async -> [String] {
        var fixed: [String] = []
        for pkg in Self.optionalBrewPackages {
            if !binaryExists(pkg.binary) {
                let installed = await installBrewPackage(pkg.formula)
                if installed {
                    fixed.append(pkg.binary)
                }
            }
        }
        return fixed
    }

    // MARK: - Output Helpers

    private func printHeader(_ title: String) {
        print("\u{1B}[1m\u{1B}[36m\(title)\u{1B}[0m")
        print(String(repeating: "\u{2500}", count: 40))
    }

    private func printStep(_ message: String) {
        print("\n  \u{1B}[1m\(message)\u{1B}[0m")
    }

    private func printOK(_ name: String) {
        print("  \u{1B}[32m\u{2713}\u{1B}[0m \(name)")
    }

    private func printWarning(_ message: String) {
        print("  \u{1B}[33m\u{26A0}\u{1B}[0m \(message)")
    }

    private func printError(_ message: String) {
        print("  \u{1B}[31m\u{2717}\u{1B}[0m \(message)")
    }

    private func printSkip(_ step: String) {
        print("  \u{1B}[2m\u{2713} \(step) (already done)\u{1B}[0m")
    }

    private func printHint(_ message: String) {
        print("  \u{1B}[2m\(message)\u{1B}[0m")
    }

    private func printFooter() {
        print("\n" + String(repeating: "\u{2500}", count: 40))
    }
}
