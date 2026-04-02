import Foundation

// MARK: - TestFlightContext

/// Shared mutable state passed between TestFlight gates within a single pipeline run.
public actor TestFlightContext {
    public var appConfig: AppConfig?
    public var buildNumber: Int = 0
    public var archivePath: String = ""
    public var exportPath: String = ""
    public var ipaPath: String = ""
    public var logPath: String = ""
    public var changelog: String = ""

    public init() {}

    public func setAppConfig(_ config: AppConfig) { appConfig = config }
    public func setBuildNumber(_ n: Int) { buildNumber = n }
    public func setArchivePath(_ p: String) { archivePath = p }
    public func setExportPath(_ p: String) { exportPath = p }
    public func setIpaPath(_ p: String) { ipaPath = p }
    public func setLogPath(_ p: String) { logPath = p }
    public func setChangelog(_ c: String) { changelog = c }
}

// MARK: - Gate 9: AppRegistryGate

/// Validates app configuration from ~/.config/shikki/apps.toml.
/// Ensures the selected app has all required fields and the project path exists.
public struct AppRegistryGate: ShipGate, Sendable {
    public let name = "AppRegistry"
    public let index = 8
    public let appSlug: String?
    public let configPath: String?
    public let tfContext: TestFlightContext

    public init(
        appSlug: String? = nil,
        configPath: String? = nil,
        tfContext: TestFlightContext
    ) {
        self.appSlug = appSlug
        self.configPath = configPath
        self.tfContext = tfContext
    }

    public func evaluate(context: ShipContext) async throws -> GateResult {
        let path = configPath ?? AppConfigRegistry.defaultPath

        let registry: AppConfigRegistry
        do {
            registry = try AppConfigRegistry.load(from: path)
        } catch let error as AppConfigError {
            return .fail(reason: error.description)
        }

        let config: AppConfig
        do {
            config = try registry.select(slug: appSlug)
        } catch let error as AppConfigError {
            return .fail(reason: error.description)
        }

        // Validate project path exists
        if !context.isDryRun {
            let projectExists = FileManager.default.fileExists(atPath: config.projectPath)
            if !projectExists {
                return .fail(
                    reason: "Project not found at \(config.projectPath). Update apps.toml."
                )
            }
        }

        await tfContext.setAppConfig(config)
        return .pass(detail: "\(config.slug) -- \(config.scheme) (\(config.teamID))")
    }
}

// MARK: - Gate 10: BuildNumberGate

/// Auto-increments the build number via agvtool.
public struct BuildNumberGate: ShipGate, Sendable {
    public let name = "BuildNumber"
    public let index = 9
    public let tfContext: TestFlightContext

    public init(tfContext: TestFlightContext) {
        self.tfContext = tfContext
    }

    public func evaluate(context: ShipContext) async throws -> GateResult {
        guard let config = await tfContext.appConfig else {
            return .fail(reason: "No app config available. AppRegistryGate must run first.")
        }

        if context.isDryRun {
            // Read current build number without modifying
            let result = try await context.shell(
                "cd \(shellEscape((config.projectPath as NSString).deletingLastPathComponent)) && agvtool what-version -terse 2>/dev/null || echo '0'"
            )
            let current = Int(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            let next = current + 1
            await tfContext.setBuildNumber(next)
            return .pass(detail: "[dry-run] Build number: \(current) -> \(next)")
        }

        // Get current build number
        let currentResult = try await context.shell(
            "cd \(shellEscape((config.projectPath as NSString).deletingLastPathComponent)) && agvtool what-version -terse 2>/dev/null || echo '0'"
        )
        let current = Int(currentResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0

        // Increment
        let projectDir = (config.projectPath as NSString).deletingLastPathComponent
        let bumpResult = try await context.shell(
            "cd \(shellEscape(projectDir)) && agvtool next-version -all"
        )
        if bumpResult.exitCode != 0 {
            return .fail(reason: "agvtool failed: \(bumpResult.stderr)")
        }

        let next = current + 1
        await tfContext.setBuildNumber(next)
        return .pass(detail: "Build number: \(current) -> \(next)")
    }
}

// MARK: - Gate 11: ArchiveGate

/// Runs xcodebuild archive with the app configuration.
public struct ArchiveGate: ShipGate, Sendable {
    public let name = "Archive"
    public let index = 10
    public let tfContext: TestFlightContext
    public let version: String
    public let archiveManager: ArchiveManager

    public init(
        tfContext: TestFlightContext,
        version: String,
        archiveManager: ArchiveManager = ArchiveManager()
    ) {
        self.tfContext = tfContext
        self.version = version
        self.archiveManager = archiveManager
    }

    public func evaluate(context: ShipContext) async throws -> GateResult {
        guard let config = await tfContext.appConfig else {
            return .fail(reason: "No app config available. AppRegistryGate must run first.")
        }

        let buildNumber = await tfContext.buildNumber
        let archivePath = archiveManager.archivePath(
            slug: config.slug, version: version, build: buildNumber
        )
        let logFile = archiveManager.logPath(slug: config.slug)

        // Prune old archives first (BR-23)
        try? archiveManager.prune(slug: config.slug, keep: 5)

        if context.isDryRun {
            await tfContext.setArchivePath(archivePath)
            await tfContext.setLogPath(logFile)
            return .pass(detail: "[dry-run] Would archive to \(archivePath)")
        }

        // Ensure directories
        try archiveManager.ensureDirectories(
            slug: config.slug, version: version, build: buildNumber
        )

        // Determine if project or workspace
        let projectFlag: String
        if config.projectPath.hasSuffix(".xcworkspace") {
            projectFlag = "-workspace \(shellEscape(config.projectPath))"
        } else {
            projectFlag = "-project \(shellEscape(config.projectPath))"
        }

        // Build xcodebuild command
        let cmd = [
            "xcodebuild archive",
            projectFlag,
            "-scheme \(shellEscape(config.scheme))",
            "-archivePath \(shellEscape(archivePath))",
            "-destination 'generic/platform=iOS'",
            "DEVELOPMENT_TEAM=\(shellEscape(config.teamID))",
            "2>&1 | tee \(shellEscape(logFile))",
        ].joined(separator: " ")

        let result = try await context.shell(cmd)

        if result.exitCode != 0 {
            // Parse errors from log
            let logContent = result.stdout
            let errors = archiveManager.parseErrors(from: logContent)
            let hint = archiveManager.diagnosisHint(from: logContent)
            let errorSummary = errors.isEmpty
                ? "Archive failed"
                : errors.joined(separator: "\n")
            return .fail(
                reason: "\(errorSummary)\n\(hint)\nFull log: \(logFile)"
            )
        }

        await tfContext.setArchivePath(archivePath)
        await tfContext.setLogPath(logFile)

        // Get archive size
        let sizeResult = try await context.shell("du -sh \(shellEscape(archivePath)) | cut -f1")
        let size = sizeResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        return .pass(detail: "Archived (\(size)): \(archivePath)")
    }
}

// MARK: - Gate 12: UploadGate

/// Exports the archive to .ipa and uploads to App Store Connect using altool.
/// Combines export + upload into a single gate for simplicity.
public struct UploadGate: ShipGate, Sendable {
    public let name = "Upload"
    public let index = 11
    public let tfContext: TestFlightContext
    public let maxRetries: Int

    public init(tfContext: TestFlightContext, maxRetries: Int = 2) {
        self.tfContext = tfContext
        self.maxRetries = maxRetries
    }

    public func evaluate(context: ShipContext) async throws -> GateResult {
        guard let config = await tfContext.appConfig else {
            return .fail(reason: "No app config available. AppRegistryGate must run first.")
        }

        let archivePath = await tfContext.archivePath
        let buildNumber = await tfContext.buildNumber

        if context.isDryRun {
            return .pass(detail: "[dry-run] Would export and upload \(config.slug) build \(buildNumber)")
        }

        // --- Export Phase ---
        let exportDir = (archivePath as NSString).deletingLastPathComponent
        let exportOptsGen = ExportOptionsGenerator()
        let exportOptsPath: String
        do {
            exportOptsPath = try exportOptsGen.write(for: config, to: exportDir)
        } catch {
            return .fail(reason: "Failed to generate ExportOptions.plist: \(error)")
        }

        let exportCmd = [
            "xcodebuild -exportArchive",
            "-archivePath \(shellEscape(archivePath))",
            "-exportPath \(shellEscape(exportDir))",
            "-exportOptionsPlist \(shellEscape(exportOptsPath))",
        ].joined(separator: " ")

        let exportResult = try await context.shell(exportCmd)
        if exportResult.exitCode != 0 {
            return .fail(
                reason: "Export failed. Archive preserved at: \(archivePath)\n\(exportResult.stderr.suffix(300))"
            )
        }

        // Find the .ipa file
        let findResult = try await context.shell("find \(shellEscape(exportDir)) -name '*.ipa' -maxdepth 1")
        let ipaPath = findResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if ipaPath.isEmpty {
            return .fail(reason: "No .ipa file found after export in \(exportDir)")
        }

        await tfContext.setExportPath(exportDir)
        await tfContext.setIpaPath(ipaPath)

        // --- Upload Phase ---
        guard let ascConfig = config.asc else {
            return .fail(reason: "No ASC key configured for \(config.slug). Run: shi ship --testflight --setup")
        }

        // Resolve API key path: Keychain first, then file fallback
        let keyPath = try await resolveKeyPath(config: config, ascConfig: ascConfig, context: context)
        if keyPath == nil {
            return .fail(
                reason: "API key not found for team \(config.teamID). Run: shi ship --testflight --setup"
            )
        }

        // Upload with retries (BR-09)
        var lastError = ""
        for attempt in 0...maxRetries {
            let uploadCmd = [
                "xcrun altool --upload-app",
                "-f \(shellEscape(ipaPath))",
                "--type ios",
                "--apiKey \(shellEscape(ascConfig.keyID))",
                "--apiIssuer \(shellEscape(ascConfig.issuerID))",
            ].joined(separator: " ")

            let uploadResult = try await context.shell(uploadCmd)
            if uploadResult.exitCode == 0 {
                return .pass(detail: "Uploaded \(config.slug) build \(buildNumber) to App Store Connect")
            }

            lastError = uploadResult.stderr.isEmpty ? uploadResult.stdout : uploadResult.stderr

            if attempt < maxRetries {
                // Wait before retry
                try await Task.sleep(for: .seconds(10))
            }
        }

        return .fail(
            reason: "Upload failed after \(maxRetries + 1) attempts. IPA preserved at: \(ipaPath)\nRetry manually with: xcrun altool --upload-app -f \(ipaPath)\nLast error: \(lastError.suffix(200))"
        )
    }

    private func resolveKeyPath(
        config: AppConfig,
        ascConfig: ASCKeyConfig,
        context: ShipContext
    ) async throws -> String? {
        // Try Keychain
        let keychainResult = try await context.shell(
            "security find-generic-password -s shikki-asc-\(shellEscape(config.teamID)) -w 2>/dev/null"
        )
        if keychainResult.exitCode == 0 && !keychainResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Key is in Keychain -- altool can reference by key ID if AuthKey file exists
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let keyDir = "\(home)/.config/shikki/keys"
            let keyFile = "\(keyDir)/AuthKey_\(ascConfig.keyID).p8"
            if FileManager.default.fileExists(atPath: keyFile) {
                return keyFile
            }
        }

        // Try file fallback
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let filePath = "\(home)/.config/shikki/keys/AuthKey_\(ascConfig.keyID).p8"
        if FileManager.default.fileExists(atPath: filePath) {
            return filePath
        }

        // Try environment variable
        let envKey = "SHIKKI_ASC_KEY_\(config.teamID)"
        if ProcessInfo.processInfo.environment[envKey] != nil {
            return "env:\(envKey)"
        }

        return nil
    }
}
