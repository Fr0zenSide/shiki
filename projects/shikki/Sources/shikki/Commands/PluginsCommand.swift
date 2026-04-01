import ArgumentParser
import Foundation
import ShikkiKit

/// `shikki plugins` — Manage Shikki plugins: list, install, uninstall, verify.
struct PluginsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "plugins",
        abstract: "Manage Shikki plugins",
        subcommands: [
            ListPlugins.self,
            InstallPlugin.self,
            UninstallPlugin.self,
            VerifyPlugin.self,
        ],
        defaultSubcommand: ListPlugins.self
    )
}

// MARK: - List

extension PluginsCommand {
    struct ListPlugins: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "Show installed plugins with certification level"
        )

        func run() async throws {
            let registry = PluginRegistry()
            let results = await registry.loadFromDirectory(PluginRegistry.defaultPluginsDirectory)
            let plugins = await registry.installed()

            if plugins.isEmpty {
                print("\u{1B}[2mNo plugins installed.\u{1B}[0m")
                print("  Install a plugin: shikki plugins install <path-or-url>")
                return
            }

            print("\u{1B}[1m\u{1B}[36mInstalled Plugins\u{1B}[0m")
            print(String(repeating: "\u{2500}", count: 60))
            print()

            let maxName = plugins.map(\.displayName.count).max() ?? 10

            for plugin in plugins {
                let certBadge = certificationBadge(plugin.certification?.level)
                let padded = plugin.displayName.padding(toLength: maxName + 2, withPad: " ", startingAt: 0)
                let version = "v\(plugin.version)"
                let commands = plugin.commands.map(\.name).joined(separator: ", ")
                print("  \(certBadge) \(padded) \(version)  [\(commands)]")
            }

            print()
            print("\(plugins.count) plugin(s) installed")

            // Report any load failures
            let failures = results.compactMap { result -> String? in
                if case .failed(let dir, let error) = result {
                    return "  \u{1B}[33m! \(dir): \(error)\u{1B}[0m"
                }
                return nil
            }
            if !failures.isEmpty {
                print()
                for failure in failures {
                    print(failure)
                }
            }
        }

        private func certificationBadge(_ level: CertificationLevel?) -> String {
            switch level {
            case .enterpriseSafe: return "\u{1B}[32m\u{2605}\u{1B}[0m"     // green star
            case .shikkiCertified: return "\u{1B}[36m\u{2713}\u{1B}[0m"    // cyan check
            case .communityReviewed: return "\u{1B}[33m\u{25CB}\u{1B}[0m"  // yellow circle
            case .uncertified, .none: return "\u{1B}[2m\u{2013}\u{1B}[0m"  // dim dash
            }
        }
    }
}

// MARK: - Install

extension PluginsCommand {
    struct InstallPlugin: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "install",
            abstract: "Install a plugin from a local path or marketplace URL"
        )

        @Argument(help: "Path to plugin directory or marketplace URL")
        var source: String

        func run() async throws {
            let registry = PluginRegistry()
            let fm = FileManager.default

            // Determine source type
            if source.hasPrefix("http://") || source.hasPrefix("https://") {
                // Marketplace URL — not yet implemented
                print("\u{1B}[33mMarketplace installation not yet available.\u{1B}[0m")
                print("  Use a local path instead: shikki plugins install /path/to/plugin")
                throw ExitCode(1)
            }

            // Local path installation
            let manifestPath = (source as NSString).appendingPathComponent("manifest.json")
            guard fm.fileExists(atPath: manifestPath) else {
                print("\u{1B}[31mNo manifest.json found at: \(source)\u{1B}[0m")
                print("  Expected: \(manifestPath)")
                throw ExitCode(1)
            }

            do {
                let manifest = try await registry.loadManifest(from: manifestPath)

                // Validate manifest structure (including checksum presence)
                try manifest.validate()

                // Copy plugin to plugins directory
                let destDir = (PluginRegistry.defaultPluginsDirectory as NSString)
                    .appendingPathComponent(manifest.id.rawValue.replacingOccurrences(of: "/", with: "-"))

                if fm.fileExists(atPath: destDir) {
                    try fm.removeItem(atPath: destDir)
                }
                try fm.createDirectory(
                    atPath: (destDir as NSString).deletingLastPathComponent,
                    withIntermediateDirectories: true
                )
                try fm.copyItem(atPath: source, toPath: destDir)

                // Register with checksum verification
                try await registry.register(manifest: manifest, expectedChecksum: manifest.checksum)

                print("\u{1B}[32mInstalled \(manifest.displayName) v\(manifest.version)\u{1B}[0m")
                print("  ID: \(manifest.id)")
                print("  Commands: \(manifest.commands.map(\.name).joined(separator: ", "))")
            } catch {
                print("\u{1B}[31mInstallation failed: \(error)\u{1B}[0m")
                throw ExitCode(1)
            }
        }
    }
}

// MARK: - Uninstall

extension PluginsCommand {
    struct UninstallPlugin: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "uninstall",
            abstract: "Remove an installed plugin"
        )

        @Argument(help: "Plugin ID to uninstall (e.g. shikki/creative-studio)")
        var pluginID: String

        func run() async throws {
            let registry = PluginRegistry()
            let fm = FileManager.default

            // Load existing plugins
            _ = await registry.loadFromDirectory(PluginRegistry.defaultPluginsDirectory)

            let id = PluginID(pluginID)

            guard let manifest = await registry.plugin(id: id) else {
                print("\u{1B}[31mPlugin '\(pluginID)' is not installed.\u{1B}[0m")
                throw ExitCode(1)
            }

            // Remove from registry
            do {
                try await registry.unregister(id: id)
            } catch {
                print("\u{1B}[31mFailed to unregister: \(error)\u{1B}[0m")
                throw ExitCode(1)
            }

            // Remove plugin directory
            let pluginDir = (PluginRegistry.defaultPluginsDirectory as NSString)
                .appendingPathComponent(pluginID.replacingOccurrences(of: "/", with: "-"))

            if fm.fileExists(atPath: pluginDir) {
                try fm.removeItem(atPath: pluginDir)
            }

            print("\u{1B}[32mUninstalled \(manifest.displayName)\u{1B}[0m")
        }
    }
}

// MARK: - Verify

extension PluginsCommand {
    struct VerifyPlugin: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "verify",
            abstract: "Check checksum and certification of an installed plugin"
        )

        @Argument(help: "Plugin ID to verify (e.g. shikki/creative-studio)")
        var pluginID: String

        func run() async throws {
            let registry = PluginRegistry()

            // Load existing plugins
            _ = await registry.loadFromDirectory(PluginRegistry.defaultPluginsDirectory)

            let id = PluginID(pluginID)

            guard let manifest = await registry.plugin(id: id) else {
                print("\u{1B}[31mPlugin '\(pluginID)' is not installed.\u{1B}[0m")
                throw ExitCode(1)
            }

            print("\u{1B}[1mPlugin Verification: \(manifest.displayName)\u{1B}[0m")
            print(String(repeating: "\u{2500}", count: 50))
            print()

            // Checksum
            print("  Checksum: \(manifest.checksum)")

            // Certification
            if let cert = manifest.certification {
                let levelStr: String
                switch cert.level {
                case .uncertified: levelStr = "\u{1B}[2muncertified\u{1B}[0m"
                case .communityReviewed: levelStr = "\u{1B}[33mcommunity-reviewed\u{1B}[0m"
                case .shikkiCertified: levelStr = "\u{1B}[36mshikki-certified\u{1B}[0m"
                case .enterpriseSafe: levelStr = "\u{1B}[32menterprise-safe\u{1B}[0m"
                }
                print("  Certification: \(levelStr)")

                if let certBy = cert.certifiedBy {
                    print("  Certified by: \(certBy)")
                }
                if let certAt = cert.certifiedAt {
                    let formatter = ISO8601DateFormatter()
                    print("  Certified at: \(formatter.string(from: certAt))")
                }
                if cert.isExpired {
                    print("  \u{1B}[31mCertification EXPIRED\u{1B}[0m")
                } else if let expiresAt = cert.expiresAt {
                    let formatter = ISO8601DateFormatter()
                    print("  Expires: \(formatter.string(from: expiresAt))")
                }
                if let sig = cert.signature {
                    print("  Signature: \(sig.prefix(16))...")
                }
            } else {
                print("  Certification: \u{1B}[2mnone\u{1B}[0m")
            }

            // Version compatibility
            let compatible = manifest.isCompatible(
                with: SemanticVersion(major: 0, minor: 3, patch: 0)
            )
            print("  Compatible: \(compatible ? "\u{1B}[32myes\u{1B}[0m" : "\u{1B}[31mno\u{1B}[0m")")
            print("  Min version: \(manifest.minimumShikkiVersion)")
        }
    }
}
