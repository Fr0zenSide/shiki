import Foundation

// MARK: - Inline Base16 Types (temporary until DSKintsugiTUI import)

/// Minimal Base16 color — duplicates DSKintsugiCore.Base16Color for CLI use
/// until Package.swift wires the dependency.
public struct InlineBase16Color: Sendable, Equatable {
    public let r: UInt8
    public let g: UInt8
    public let b: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    public init?(hex: String) {
        let clean = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard clean.count == 6,
              let value = UInt32(clean, radix: 16) else { return nil }
        self.r = UInt8((value >> 16) & 0xFF)
        self.g = UInt8((value >> 8) & 0xFF)
        self.b = UInt8(value & 0xFF)
    }

    public var hex: String {
        String(format: "%02x%02x%02x", r, g, b)
    }

    public var ansiBg: String {
        "\u{1B}[48;2;\(r);\(g);\(b)m"
    }
}

/// Minimal Base16 theme — duplicates DSKintsugiCore.TUITheme.
public struct InlineBase16Theme: Sendable {
    public let name: String
    public let slug: String
    public let base00: InlineBase16Color
    public let base01: InlineBase16Color
    public let base02: InlineBase16Color
    public let base03: InlineBase16Color
    public let base04: InlineBase16Color
    public let base05: InlineBase16Color
    public let base06: InlineBase16Color
    public let base07: InlineBase16Color
    public let base08: InlineBase16Color
    public let base09: InlineBase16Color
    public let base0A: InlineBase16Color
    public let base0B: InlineBase16Color
    public let base0C: InlineBase16Color
    public let base0D: InlineBase16Color
    public let base0E: InlineBase16Color
    public let base0F: InlineBase16Color

    public init(
        name: String, slug: String,
        base00: InlineBase16Color, base01: InlineBase16Color,
        base02: InlineBase16Color, base03: InlineBase16Color,
        base04: InlineBase16Color, base05: InlineBase16Color,
        base06: InlineBase16Color, base07: InlineBase16Color,
        base08: InlineBase16Color, base09: InlineBase16Color,
        base0A: InlineBase16Color, base0B: InlineBase16Color,
        base0C: InlineBase16Color, base0D: InlineBase16Color,
        base0E: InlineBase16Color, base0F: InlineBase16Color
    ) {
        self.name = name
        self.slug = slug
        self.base00 = base00; self.base01 = base01
        self.base02 = base02; self.base03 = base03
        self.base04 = base04; self.base05 = base05
        self.base06 = base06; self.base07 = base07
        self.base08 = base08; self.base09 = base09
        self.base0A = base0A; self.base0B = base0B
        self.base0C = base0C; self.base0D = base0D
        self.base0E = base0E; self.base0F = base0F
    }

    /// All 16 slots in order (base00..base0F).
    public var allSlots: [InlineBase16Color] {
        [base00, base01, base02, base03, base04, base05, base06, base07,
         base08, base09, base0A, base0B, base0C, base0D, base0E, base0F]
    }
}

// MARK: - Built-in Themes (inline, mirrors DSKintsugiCore.BuiltInThemes)

public enum InlineBuiltInThemes {

    public static let dracula = InlineBase16Theme(
        name: "Dracula",
        slug: "dracula",
        base00: InlineBase16Color(hex: "282a36")!,
        base01: InlineBase16Color(hex: "3a3c4e")!,
        base02: InlineBase16Color(hex: "44475a")!,
        base03: InlineBase16Color(hex: "6272a4")!,
        base04: InlineBase16Color(hex: "b0b8d1")!,
        base05: InlineBase16Color(hex: "f8f8f2")!,
        base06: InlineBase16Color(hex: "f0f0ec")!,
        base07: InlineBase16Color(hex: "ffffff")!,
        base08: InlineBase16Color(hex: "ff5555")!,
        base09: InlineBase16Color(hex: "ffb86c")!,
        base0A: InlineBase16Color(hex: "f1fa8c")!,
        base0B: InlineBase16Color(hex: "50fa7b")!,
        base0C: InlineBase16Color(hex: "8be9fd")!,
        base0D: InlineBase16Color(hex: "6272a4")!,
        base0E: InlineBase16Color(hex: "bd93f9")!,
        base0F: InlineBase16Color(hex: "a16946")!
    )

    public static let catppuccinMocha = InlineBase16Theme(
        name: "Catppuccin Mocha",
        slug: "catppuccin-mocha",
        base00: InlineBase16Color(hex: "1e1e2e")!,
        base01: InlineBase16Color(hex: "181825")!,
        base02: InlineBase16Color(hex: "313244")!,
        base03: InlineBase16Color(hex: "45475a")!,
        base04: InlineBase16Color(hex: "585b70")!,
        base05: InlineBase16Color(hex: "cdd6f4")!,
        base06: InlineBase16Color(hex: "f5e0dc")!,
        base07: InlineBase16Color(hex: "b4befe")!,
        base08: InlineBase16Color(hex: "f38ba8")!,
        base09: InlineBase16Color(hex: "fab387")!,
        base0A: InlineBase16Color(hex: "f9e2af")!,
        base0B: InlineBase16Color(hex: "a6e3a1")!,
        base0C: InlineBase16Color(hex: "94e2d5")!,
        base0D: InlineBase16Color(hex: "89b4fa")!,
        base0E: InlineBase16Color(hex: "cba6f7")!,
        base0F: InlineBase16Color(hex: "f2cdcd")!
    )

    public static let tokyoNight = InlineBase16Theme(
        name: "Tokyo Night",
        slug: "tokyo-night",
        base00: InlineBase16Color(hex: "1a1b26")!,
        base01: InlineBase16Color(hex: "16161e")!,
        base02: InlineBase16Color(hex: "2f3549")!,
        base03: InlineBase16Color(hex: "444b6a")!,
        base04: InlineBase16Color(hex: "787c99")!,
        base05: InlineBase16Color(hex: "a9b1d6")!,
        base06: InlineBase16Color(hex: "cbccd1")!,
        base07: InlineBase16Color(hex: "d5d6db")!,
        base08: InlineBase16Color(hex: "f7768e")!,
        base09: InlineBase16Color(hex: "ff9e64")!,
        base0A: InlineBase16Color(hex: "e0af68")!,
        base0B: InlineBase16Color(hex: "9ece6a")!,
        base0C: InlineBase16Color(hex: "2ac3de")!,
        base0D: InlineBase16Color(hex: "7aa2f7")!,
        base0E: InlineBase16Color(hex: "bb9af7")!,
        base0F: InlineBase16Color(hex: "c0caf5")!
    )

    public static let all: [String: InlineBase16Theme] = [
        dracula.slug: dracula,
        catppuccinMocha.slug: catppuccinMocha,
        tokyoNight.slug: tokyoNight,
    ]
}

// MARK: - Theme Config Manager

/// Reads/writes theme config and manages theme discovery.
/// Mirrors DSKintsugiCore.ThemeLoader logic inline until the import is wired.
public enum ThemeConfigManager {

    // MARK: - Config Read/Write

    /// Read the active theme slug from config.yaml.
    public static func readActiveThemeName(configPath: String? = nil) -> String? {
        let path = configPath ?? defaultConfigPath()
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }
        for line in content.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("theme:") {
                let value = trimmed.dropFirst("theme:".count)
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "\"", with: "")
                    .replacingOccurrences(of: "'", with: "")
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }

    /// Set the active theme in config.yaml, creating the file if needed.
    public static func setActiveTheme(_ slug: String, configPath: String? = nil) throws {
        let path = configPath ?? defaultConfigPath()
        let fm = FileManager.default

        // Ensure directory exists
        let dir = (path as NSString).deletingLastPathComponent
        try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

        var lines: [String] = []
        var foundThemeLine = false

        if let content = try? String(contentsOfFile: path, encoding: .utf8) {
            for line in content.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("theme:") {
                    lines.append("theme: \(slug)")
                    foundThemeLine = true
                } else {
                    lines.append(line)
                }
            }
        }

        if !foundThemeLine {
            lines.append("theme: \(slug)")
        }

        // Remove trailing empty lines, then ensure final newline
        while let last = lines.last, last.isEmpty {
            lines.removeLast()
        }

        let output = lines.joined(separator: "\n") + "\n"
        try output.write(toFile: path, atomically: true, encoding: .utf8)
    }

    // MARK: - Theme Discovery

    /// List all themes: built-in + custom YAML files from themes directory.
    public static func listAllThemes(
        themesDir: String? = nil
    ) -> [(theme: InlineBase16Theme, isBuiltIn: Bool)] {
        var result: [(InlineBase16Theme, Bool)] = []

        // Built-in themes in display order
        result.append((InlineBuiltInThemes.dracula, true))
        result.append((InlineBuiltInThemes.catppuccinMocha, true))
        result.append((InlineBuiltInThemes.tokyoNight, true))

        // User themes from ~/.shikki/themes/
        let userDir = themesDir ?? defaultThemesDirectory()
        let fm = FileManager.default
        guard fm.fileExists(atPath: userDir),
              let files = try? fm.contentsOfDirectory(atPath: userDir) else {
            return result
        }

        for file in files.sorted() where file.hasSuffix(".yaml") || file.hasSuffix(".yml") {
            let slug = String(file.prefix(while: { $0 != "." }))
            // Skip if it shadows a built-in
            guard InlineBuiltInThemes.all[slug] == nil else { continue }

            let path = "\(userDir)/\(file)"
            if let theme = parseBase16YAML(at: path, fallbackSlug: slug) {
                result.append((theme, false))
            }
        }

        return result
    }

    /// Resolve a theme by slug from all available themes.
    public static func resolveTheme(
        _ slug: String,
        themesDir: String? = nil
    ) -> InlineBase16Theme? {
        if let builtIn = InlineBuiltInThemes.all[slug] {
            return builtIn
        }
        let userDir = themesDir ?? defaultThemesDirectory()
        for ext in ["yaml", "yml"] {
            let path = "\(userDir)/\(slug).\(ext)"
            if FileManager.default.fileExists(atPath: path) {
                return parseBase16YAML(at: path, fallbackSlug: slug)
            }
        }
        return nil
    }

    // MARK: - Swatch Rendering

    /// Render a 32-char swatch (16 slots x 2 chars each) using 24-bit ANSI bg colors.
    public static func renderSwatch(_ theme: InlineBase16Theme) -> String {
        let slots = theme.allSlots
        var swatch = ""
        for slot in slots {
            swatch += slot.ansiBg + "  "
        }
        swatch += ANSI.reset
        return swatch
    }

    // MARK: - tmTheme Generation

    /// Generate a minimal TextMate .tmTheme XML for bat integration.
    public static func generateTmTheme(from theme: InlineBase16Theme) -> String {
        let bg = "#\(theme.base00.hex)"
        let fg = "#\(theme.base05.hex)"
        let caret = "#\(theme.base05.hex)"
        let selection = "#\(theme.base02.hex)"
        let lineHighlight = "#\(theme.base01.hex)"

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!-- Auto-generated by shikki — do not edit -->
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>name</key><string>Shikki Active</string>
            <key>settings</key>
            <array>
                <dict>
                    <key>settings</key>
                    <dict>
                        <key>background</key><string>\(bg)</string>
                        <key>foreground</key><string>\(fg)</string>
                        <key>caret</key><string>\(caret)</string>
                        <key>selection</key><string>\(selection)</string>
                        <key>lineHighlight</key><string>\(lineHighlight)</string>
                    </dict>
                </dict>
                <dict>
                    <key>scope</key><string>comment</string>
                    <key>settings</key><dict><key>foreground</key><string>#\(theme.base03.hex)</string></dict>
                </dict>
                <dict>
                    <key>scope</key><string>string</string>
                    <key>settings</key><dict><key>foreground</key><string>#\(theme.base0B.hex)</string></dict>
                </dict>
                <dict>
                    <key>scope</key><string>keyword</string>
                    <key>settings</key><dict><key>foreground</key><string>#\(theme.base0E.hex)</string></dict>
                </dict>
                <dict>
                    <key>scope</key><string>constant.numeric</string>
                    <key>settings</key><dict><key>foreground</key><string>#\(theme.base09.hex)</string></dict>
                </dict>
                <dict>
                    <key>scope</key><string>entity.name</string>
                    <key>settings</key><dict><key>foreground</key><string>#\(theme.base0D.hex)</string></dict>
                </dict>
                <dict>
                    <key>scope</key><string>variable</string>
                    <key>settings</key><dict><key>foreground</key><string>#\(theme.base08.hex)</string></dict>
                </dict>
                <dict>
                    <key>scope</key><string>support</string>
                    <key>settings</key><dict><key>foreground</key><string>#\(theme.base0C.hex)</string></dict>
                </dict>
            </array>
        </dict>
        </plist>
        """
    }

    // MARK: - YAML Parser (mirrors ThemeLoader.parseBase16YAML)

    /// Parse a Base16 YAML scheme file into an InlineBase16Theme.
    public static func parseBase16YAML(at path: String, fallbackSlug: String) -> InlineBase16Theme? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }

        var slots: [String: InlineBase16Color] = [:]
        var schemeName: String?

        for line in content.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#") else { continue }

            let parts = trimmed.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }

            let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            let rawValue = parts[1].trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "'", with: "")
                .trimmingCharacters(in: .whitespaces)

            if key == "scheme" {
                schemeName = rawValue
                continue
            }

            if key.hasPrefix("base0") || key.hasPrefix("base1"),
               key.count == 6,
               let color = InlineBase16Color(hex: rawValue) {
                slots[key] = color
            }
        }

        // Require all 16 slots
        let required = (0...15).map { String(format: "base%02x", $0) }
        for slot in required {
            guard slots[slot] != nil else { return nil }
        }

        let displayName = schemeName ?? fallbackSlug

        return InlineBase16Theme(
            name: displayName,
            slug: fallbackSlug,
            base00: slots["base00"]!, base01: slots["base01"]!,
            base02: slots["base02"]!, base03: slots["base03"]!,
            base04: slots["base04"]!, base05: slots["base05"]!,
            base06: slots["base06"]!, base07: slots["base07"]!,
            base08: slots["base08"]!, base09: slots["base09"]!,
            base0A: slots["base0a"]!, base0B: slots["base0b"]!,
            base0C: slots["base0c"]!, base0D: slots["base0d"]!,
            base0E: slots["base0e"]!, base0F: slots["base0f"]!
        )
    }

    // MARK: - Paths

    public static func defaultConfigPath() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.shikki/config.yaml"
    }

    public static func defaultThemesDirectory() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.shikki/themes"
    }
}
