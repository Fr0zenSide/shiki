import Foundation

// MARK: - InitResult

/// The outcome of running `shi init`.
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

        // iOS-specific scaffolding: .mcp.json + XcodeGen project.yml
        let isIOS = template?.lowercased() == "ios"
            || detected.framework == .swiftUI
            || detected.framework == .uiKit
        if isIOS {
            let iosResult = scaffoldIOSProject(at: path, projectName: detected.name)
            filesCreated.append(contentsOf: iosResult.filesCreated)
            warnings.append(contentsOf: iosResult.warnings)
        }

        // Install git hooks if git repo exists
        if detected.hasGit {
            let hooksResult = installGitHooks(at: path)
            filesCreated.append(contentsOf: hooksResult.filesCreated)
            warnings.append(contentsOf: hooksResult.warnings)
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

    // MARK: - iOS Scaffolding

    /// Scaffold iOS-specific files: .mcp.json (Xcode tools + Apple docs) and XcodeGen project.yml.
    private func scaffoldIOSProject(at path: String, projectName: String) -> (filesCreated: [String], warnings: [String]) {
        var filesCreated: [String] = []
        var warnings: [String] = []

        // 1. Create .mcp.json with xcode-tools + sosumi (Apple docs)
        let mcpPath = (path as NSString).appendingPathComponent(".mcp.json")
        if !fileManager.fileExists(atPath: mcpPath) {
            do {
                try Self.iosMCPConfig.write(toFile: mcpPath, atomically: true, encoding: .utf8)
                filesCreated.append(".mcp.json")
            } catch {
                warnings.append("Could not create .mcp.json: \(error.localizedDescription)")
            }
        }

        // 2. Create XcodeGen project.yml if no .xcodeproj exists
        let hasXcodeProj = (try? fileManager.contentsOfDirectory(atPath: path))?
            .contains(where: { $0.hasSuffix(".xcodeproj") }) ?? false
        let projectYmlPath = (path as NSString).appendingPathComponent("project.yml")

        if !hasXcodeProj && !fileManager.fileExists(atPath: projectYmlPath) {
            let yml = Self.generateXcodeGenYml(projectName: projectName)
            do {
                try yml.write(toFile: projectYmlPath, atomically: true, encoding: .utf8)
                filesCreated.append("project.yml")
            } catch {
                warnings.append("Could not create project.yml: \(error.localizedDescription)")
            }

            // Check if xcodegen is available
            let whichProcess = Process()
            whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            whichProcess.arguments = ["which", "xcodegen"]
            whichProcess.standardOutput = FileHandle.nullDevice
            whichProcess.standardError = FileHandle.nullDevice
            try? whichProcess.run()
            whichProcess.waitUntilExit()

            if whichProcess.terminationStatus != 0 {
                warnings.append("XcodeGen not found. Install: brew install xcodegen. Then run: xcodegen generate")
            } else {
                // Auto-generate .xcodeproj
                let genProcess = Process()
                genProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                genProcess.arguments = ["xcodegen", "generate"]
                genProcess.currentDirectoryURL = URL(fileURLWithPath: path)
                genProcess.standardOutput = FileHandle.nullDevice
                genProcess.standardError = FileHandle.nullDevice
                try? genProcess.run()
                genProcess.waitUntilExit()

                if genProcess.terminationStatus == 0 {
                    filesCreated.append("\(projectName).xcodeproj (generated)")
                } else {
                    warnings.append("XcodeGen failed — run `xcodegen generate` manually after reviewing project.yml")
                }
            }
        }

        return (filesCreated, warnings)
    }

    /// MCP config for iOS projects: Xcode tools + Apple documentation (sosumi).
    static let iosMCPConfig = """
    {
      "mcpServers": {
        "xcode-tools": {
          "command": "xcrun",
          "args": ["mcpbridge"]
        },
        "sosumi": {
          "command": "npx",
          "args": ["-y", "mcp-remote", "https://sosumi.ai/mcp"]
        }
      }
    }
    """

    /// Generate a minimal XcodeGen project.yml for an iOS app.
    static func generateXcodeGenYml(projectName: String) -> String {
        """
        name: \(projectName)
        options:
          bundleIdPrefix: one.obyw
          deploymentTarget:
            iOS: "17.0"
          xcodeVersion: "16.0"
          groupSortPosition: top

        settings:
          base:
            SWIFT_VERSION: "6.0"
            GENERATE_INFOPLIST_FILE: true

        targets:
          \(projectName):
            type: application
            platform: iOS
            sources:
              - path: Sources
                group: Sources
            settings:
              base:
                PRODUCT_BUNDLE_IDENTIFIER: one.obyw.\(projectName.lowercased())
                INFOPLIST_KEY_UIApplicationSceneManifest_Generation: true
                INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents: true
                INFOPLIST_KEY_UILaunchScreen_Generation: true
                INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad: "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"

          \(projectName)Tests:
            type: bundle.unit-test
            platform: iOS
            sources:
              - path: Tests
                group: Tests
            dependencies:
              - target: \(projectName)
            settings:
              base:
                PRODUCT_BUNDLE_IDENTIFIER: one.obyw.\(projectName.lowercased()).tests
        """
    }

    // MARK: - Git Hooks

    /// Install Shikki git hooks (git flow guard).
    private func installGitHooks(at path: String) -> (filesCreated: [String], warnings: [String]) {
        var filesCreated: [String] = []
        var warnings: [String] = []

        let hooksDir = (path as NSString).appendingPathComponent(".git/hooks")
        guard fileManager.fileExists(atPath: hooksDir) else {
            warnings.append("Git hooks directory not found — skipping hook installation.")
            return (filesCreated, warnings)
        }

        let preCommitPath = (hooksDir as NSString).appendingPathComponent("pre-commit")

        // Don't overwrite existing hooks (user may have custom ones)
        if fileManager.fileExists(atPath: preCommitPath) {
            // Check if it's already a Shikki hook
            if let content = try? String(contentsOfFile: preCommitPath, encoding: .utf8),
               content.contains("Git Flow Guard") {
                return (filesCreated, warnings)
            }
            warnings.append("Existing pre-commit hook found — Shikki git flow guard NOT installed. Add manually or use --force.")
            return (filesCreated, warnings)
        }

        let hookContent = Self.gitFlowPreCommitHook
        do {
            try hookContent.write(toFile: preCommitPath, atomically: true, encoding: .utf8)
            // Make executable
            let attrs: [FileAttributeKey: Any] = [.posixPermissions: 0o755]
            try fileManager.setAttributes(attrs, ofItemAtPath: preCommitPath)
            filesCreated.append(".git/hooks/pre-commit")
        } catch {
            warnings.append("Could not install git flow hook: \(error.localizedDescription)")
        }

        return (filesCreated, warnings)
    }

    /// The pre-commit hook content that enforces git flow.
    static let gitFlowPreCommitHook = """
    #!/bin/sh
    # Git Flow Guard — installed by shi init
    # Reject direct commits on develop/main. Only merge commits allowed.

    BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null)
    GIT_DIR=$(git rev-parse --git-dir)

    # --- develop: only merge commits allowed ---
    if [ "$BRANCH" = "develop" ]; then
        if [ -f "$GIT_DIR/MERGE_HEAD" ]; then
            exit 0
        fi
        echo ""
        echo "  BLOCKED: Direct commit on 'develop' is not allowed."
        echo "  Create a feature branch: git checkout -b feature/my-change"
        echo "  To bypass (emergency only): git commit --no-verify"
        echo ""
        exit 1
    fi

    # --- main: only merges from release/* or hotfix/* ---
    if [ "$BRANCH" = "main" ]; then
        if [ -f "$GIT_DIR/MERGE_HEAD" ]; then
            MERGE_SOURCE=$(git name-rev --name-only "$(cat "$GIT_DIR/MERGE_HEAD")" 2>/dev/null)
            case "$MERGE_SOURCE" in
                release/*|hotfix/*|remotes/origin/release/*|remotes/origin/hotfix/*)
                    exit 0
                    ;;
                *)
                    echo ""
                    echo "  BLOCKED: Merge into 'main' only from release/* or hotfix/*."
                    echo "  Source: $MERGE_SOURCE"
                    echo ""
                    exit 1
                    ;;
            esac
        fi
        echo ""
        echo "  BLOCKED: Direct commit on 'main' is not allowed."
        echo "  Only merges from release/* or hotfix/* branches."
        echo "  To bypass (emergency only): git commit --no-verify"
        echo ""
        exit 1
    fi
    """

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
