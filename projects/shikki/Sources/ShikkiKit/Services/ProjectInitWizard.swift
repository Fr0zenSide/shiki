import Foundation

// MARK: - InitResult

/// The outcome of running `shikki init`.
public struct InitResult: Sendable, Equatable {
    public let motoFile: MotoFile
    public let filesCreated: [String]
    public let warnings: [String]

    public init(
        motoFile: MotoFile,
        filesCreated: [String] = [],
        warnings: [String] = []
    ) {
        self.motoFile = motoFile
        self.filesCreated = filesCreated
        self.warnings = warnings
    }
}

// MARK: - InitError

public enum InitError: Error, Sendable, Equatable {
    case motoFileAlreadyExists
    case directoryNotFound(String)
    case writeError(String)
}

// MARK: - ProjectInitWizard

/// Orchestrates project initialization: detect, generate .moto, scaffold.
/// Designed as a pure-logic engine so TUI/CLI commands can drive it.
public struct ProjectInitWizard: Sendable {

    private let detector: ProjectDetector
    // FileManager is not Sendable, use nonisolated(unsafe) for the shared default instance
    nonisolated(unsafe) private let fileManager: FileManager

    public init(
        detector: ProjectDetector = ProjectDetector(),
        fileManager: FileManager = .default
    ) {
        self.detector = detector
        self.fileManager = fileManager
    }

    // MARK: - Detection

    /// Detect project without writing anything.
    public func detect(at path: String) -> DetectedProject {
        detector.detect(at: path)
    }

    /// Generate a MotoFile from detection results.
    public func generateMotoFile(for detected: DetectedProject) -> MotoFile {
        MotoFile.from(detected: detected)
    }

    // MARK: - Scaffold

    /// Run the full init flow: detect, generate .moto, create supporting files.
    /// - Parameters:
    ///   - path: The project root directory.
    ///   - force: If true, overwrite existing .moto file.
    ///   - template: Optional template name to apply on top of detection.
    /// - Returns: The result of the initialization.
    public func initialize(
        at path: String,
        force: Bool = false,
        template: String? = nil
    ) throws -> InitResult {
        // Validate directory exists
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            throw InitError.directoryNotFound(path)
        }

        let motoPath = (path as NSString).appendingPathComponent(".moto")

        // Check for existing .moto
        if fileManager.fileExists(atPath: motoPath) && !force {
            throw InitError.motoFileAlreadyExists
        }

        // Detect project
        let detected = detector.detect(at: path)
        var motoFile = MotoFile.from(detected: detected)

        // Apply template overrides if specified
        if let template {
            applyTemplate(template, to: &motoFile)
        }

        // Write .moto file
        var filesCreated: [String] = []
        var warnings: [String] = []

        let content = motoFile.serialize()
        do {
            try content.write(toFile: motoPath, atomically: true, encoding: .utf8)
            filesCreated.append(".moto")
        } catch {
            throw InitError.writeError("Failed to write .moto: \(error.localizedDescription)")
        }

        // Create .shikki/ directory for local settings
        let shikkiDir = (path as NSString).appendingPathComponent(".shikki")
        if !fileManager.fileExists(atPath: shikkiDir) {
            do {
                try fileManager.createDirectory(atPath: shikkiDir, withIntermediateDirectories: true)
                filesCreated.append(".shikki/")
            } catch {
                warnings.append("Could not create .shikki/ directory: \(error.localizedDescription)")
            }
        }

        // Create architecture cache stub
        let cachePath = (shikkiDir as NSString).appendingPathComponent("cache.json")
        if !fileManager.fileExists(atPath: cachePath) {
            let cacheContent = generateArchitectureCache(for: detected)
            do {
                try cacheContent.write(toFile: cachePath, atomically: true, encoding: .utf8)
                filesCreated.append(".shikki/cache.json")
            } catch {
                warnings.append("Could not create cache.json: \(error.localizedDescription)")
            }
        }

        // Create settings stub
        let settingsPath = (shikkiDir as NSString).appendingPathComponent("settings.json")
        if !fileManager.fileExists(atPath: settingsPath) {
            let settingsContent = generateSettings(for: detected)
            do {
                try settingsContent.write(toFile: settingsPath, atomically: true, encoding: .utf8)
                filesCreated.append(".shikki/settings.json")
            } catch {
                warnings.append("Could not create settings.json: \(error.localizedDescription)")
            }
        }

        // Add warnings for missing features
        if !detected.hasGit {
            warnings.append("No git repository detected. Run `git init` first for full Shikki integration.")
        }
        if !detected.hasTests {
            warnings.append("No test directory detected. Shikki works best with a test suite.")
        }
        if detected.language == .unknown {
            warnings.append("Could not detect project language. Update .moto manually.")
        }

        return InitResult(
            motoFile: motoFile,
            filesCreated: filesCreated,
            warnings: warnings
        )
    }

    // MARK: - Template Application

    private func applyTemplate(_ templateName: String, to motoFile: inout MotoFile) {
        // Built-in template presets
        switch templateName.lowercased() {
        case "ios":
            motoFile.framework = ProjectFramework.swiftUI.rawValue
            motoFile.buildSystem = BuildSystem.xcodebuild.rawValue
            motoFile.architecture = MotoFile.Architecture(
                pattern: "MVVM+Coordinator",
                sourceRoot: "Sources",
                testRoot: "Tests"
            )
        case "spm", "swift-package":
            motoFile.buildSystem = BuildSystem.spm.rawValue
            motoFile.architecture = MotoFile.Architecture(
                pattern: "Modular",
                sourceRoot: "Sources",
                testRoot: "Tests"
            )
        case "web", "nextjs":
            motoFile.framework = ProjectFramework.nextjs.rawValue
            motoFile.buildSystem = BuildSystem.npm.rawValue
            motoFile.architecture = MotoFile.Architecture(
                pattern: "Pages/App Router",
                sourceRoot: "src",
                testRoot: "__tests__"
            )
        case "api", "express":
            motoFile.framework = ProjectFramework.express.rawValue
            motoFile.architecture = MotoFile.Architecture(
                pattern: "MVC",
                sourceRoot: "src",
                testRoot: "tests"
            )
        case "cli":
            motoFile.architecture = MotoFile.Architecture(
                pattern: "Command",
                sourceRoot: "Sources",
                testRoot: "Tests"
            )
        default:
            break // Unknown template -- no-op
        }
    }

    // MARK: - File Generation

    private func generateArchitectureCache(for detected: DetectedProject) -> String {
        """
        {
          "version": 1,
          "project": "\(detected.name)",
          "language": "\(detected.language.rawValue)",
          "generated_at": "\(ISO8601DateFormatter.standard.string(from: Date()))",
          "modules": [],
          "entry_points": [],
          "dependencies": []
        }
        """
    }

    private func generateSettings(for detected: DetectedProject) -> String {
        """
        {
          "version": 1,
          "auto_test": true,
          "auto_lint": \(detected.language != .unknown),
          "watch_paths": ["\(detected.language == .swift ? "Sources" : "src")"],
          "ignore_paths": [".build", "node_modules", ".git", "__pycache__", "target"],
          "notifications": {
            "on_test_failure": true,
            "on_build_failure": true,
            "on_agent_idle": true
          }
        }
        """
    }
}
