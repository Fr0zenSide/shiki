import ArgumentParser
import Foundation
import ShikkiKit

/// `shi theme` — Manage TUI color themes (Base16).
///
/// Themes control all TUI output colors. Shikki ships with 3 built-in themes
/// (Dracula, Catppuccin Mocha, Tokyo Night) and supports custom Base16 YAML
/// files dropped into `~/.shikki/themes/`.
struct ThemeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "theme",
        abstract: "Manage TUI color themes (Base16)",
        subcommands: [
            ThemeListCommand.self,
            ThemeSetCommand.self,
        ],
        defaultSubcommand: ThemeListCommand.self
    )
}

// MARK: - List

struct ThemeListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "Show available themes with color swatch"
    )

    @Option(name: .long, help: "Custom config path (for testing)")
    var configPath: String?

    @Option(name: .long, help: "Custom themes directory (for testing)")
    var themesDir: String?

    func run() throws {
        let activeSlug = ThemeConfigManager.readActiveThemeName(configPath: configPath)
        let themes = ThemeConfigManager.listAllThemes(themesDir: themesDir)

        print("Available themes:")
        print()

        for entry in themes {
            let isActive = entry.theme.slug == (activeSlug ?? "dracula")
            let marker = isActive ? "  * " : "    "
            let sourceTag = entry.isBuiltIn ? "(built-in)" : "(custom)"
            let label = "\(entry.theme.slug) \(sourceTag)"
            let padded = label.padding(toLength: 36, withPad: " ", startingAt: 0)
            let swatch = ThemeConfigManager.renderSwatch(entry.theme)

            print("\(marker)\(padded)\(swatch)")
        }

        print()
        print("  * = active theme")
        print("  Custom themes: ~/.shikki/themes/<name>.yaml")
    }
}

// MARK: - Set

struct ThemeSetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set",
        abstract: "Set the active TUI theme"
    )

    @Argument(help: "Theme slug (e.g. dracula, catppuccin-mocha, tokyo-night)")
    var name: String

    @Option(name: .long, help: "Custom config path (for testing)")
    var configPath: String?

    @Option(name: .long, help: "Custom themes directory (for testing)")
    var themesDir: String?

    func run() async throws {
        let allThemes = ThemeConfigManager.listAllThemes(themesDir: themesDir)
        guard let matched = allThemes.first(where: { $0.theme.slug == name }) else {
            print("Theme not found: '\(name)'")
            print()
            print("Available themes:")
            for entry in allThemes {
                let sourceTag = entry.isBuiltIn ? "(built-in)" : "(custom)"
                print("  - \(entry.theme.slug) \(sourceTag)")
            }
            throw ExitCode(1)
        }

        try ThemeConfigManager.setActiveTheme(name, configPath: configPath)

        // Confirmation in the theme's accent color
        let accent = matched.theme.base0E
        let accentCode = "\u{1B}[38;2;\(accent.r);\(accent.g);\(accent.b)m"
        print("\(accentCode)Theme set to: \(matched.theme.name)\(ANSI.reset)")

        // bat tmTheme sync
        syncBatTheme(matched.theme)
    }

    private func syncBatTheme(_ theme: InlineBase16Theme) {
        // Check if bat is installed
        let batCheck = Process()
        batCheck.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        batCheck.arguments = ["which", "bat"]
        batCheck.standardOutput = FileHandle.nullDevice
        batCheck.standardError = FileHandle.nullDevice
        do {
            try batCheck.run()
            batCheck.waitUntilExit()
        } catch {
            return
        }
        guard batCheck.terminationStatus == 0 else { return }

        // Find bat config dir
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let batThemesDir = "\(home)/.config/bat/themes"
        let fm = FileManager.default

        do {
            try fm.createDirectory(atPath: batThemesDir, withIntermediateDirectories: true)
            let tmThemePath = "\(batThemesDir)/shikki-active.tmTheme"
            let xml = ThemeConfigManager.generateTmTheme(from: theme)
            try xml.write(toFile: tmThemePath, atomically: true, encoding: .utf8)

            // Rebuild bat cache
            let batBuild = Process()
            batBuild.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            batBuild.arguments = ["bat", "cache", "--build"]
            batBuild.standardOutput = FileHandle.nullDevice
            batBuild.standardError = FileHandle.nullDevice
            try batBuild.run()
            batBuild.waitUntilExit()
        } catch {
            // Non-fatal — bat sync is best-effort
        }
    }
}
