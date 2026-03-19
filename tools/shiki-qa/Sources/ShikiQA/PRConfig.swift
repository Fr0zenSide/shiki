import Foundation

/// Configuration for PR review, loaded from ~/.config/shiki/review.yml
/// Falls back to sensible defaults if file doesn't exist.
public struct PRConfig: Codable, Sendable {
    public var keyMode: KeyMode
    public var defaultView: String
    public var editor: String
    public var diffTool: String
    public var fuzzyFinder: String
    public var searchEngine: String

    public static let `default` = PRConfig(
        keyMode: .emacs,
        defaultView: "risk-map",
        editor: "$EDITOR",
        diffTool: "delta",
        fuzzyFinder: "fzf",
        searchEngine: "qmd"
    )

    /// Load config from ~/.config/shiki/review.yml, or return defaults.
    public static func load() -> PRConfig {
        let configPath = NSHomeDirectory() + "/.config/shiki/review.yml"
        guard let data = FileManager.default.contents(atPath: configPath),
              let content = String(data: data, encoding: .utf8) else {
            return .default
        }

        // Simple YAML key: value parser (no external dependency)
        var config = PRConfig.default
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), trimmed.contains(":") else { continue }
            let parts = trimmed.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)

            switch key {
            case "keyMode":
                if let mode = KeyMode(rawValue: value) { config.keyMode = mode }
            case "defaultView":
                config.defaultView = value
            case "editor":
                config.editor = value
            case "diffTool":
                config.diffTool = value
            case "fuzzyFinder":
                config.fuzzyFinder = value
            case "searchEngine":
                config.searchEngine = value
            default:
                break
            }
        }
        return config
    }
}
