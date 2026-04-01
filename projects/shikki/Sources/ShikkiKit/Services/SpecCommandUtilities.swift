import Foundation

/// Shared utility functions for spec CLI commands.
///
/// Extracted from duplicated helpers across SpecListCommand, SpecReadCommand,
/// SpecReviewCommand, SpecValidateCommand, SpecProgressCommand, and SpecMigrateCommand.
public enum SpecCommandUtilities: Sendable {

    /// Find the `features/` directory by walking up from cwd.
    /// Falls back to `<cwd>/features` if not found.
    public static func findFeaturesDirectory() -> String {
        var dir = FileManager.default.currentDirectoryPath
        while dir != "/" {
            let featuresPath = "\(dir)/features"
            if FileManager.default.fileExists(atPath: featuresPath) {
                return featuresPath
            }
            dir = (dir as NSString).deletingLastPathComponent
        }
        return "\(FileManager.default.currentDirectoryPath)/features"
    }

    /// Write text to stdout (non-blocking).
    public static func writeStdout(_ text: String) {
        FileHandle.standardOutput.write(Data(text.utf8))
    }

    /// Write text to stderr (non-blocking).
    public static func writeStderr(_ text: String) {
        FileHandle.standardError.write(Data(text.utf8))
    }

    /// Resolve a spec path from user input.
    /// - If absolute, return as-is.
    /// - If contains `/`, return as-is (relative path with directory).
    /// - Otherwise, prefix with the features directory.
    public static func resolveSpecPath(_ input: String, in directory: String) -> String {
        if input.hasPrefix("/") { return input }
        if input.contains("/") { return input }
        return "\(directory)/\(input)"
    }

    /// Today's date as a "yyyy-MM-dd" string.
    public static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    /// Extract the first `# ` heading from markdown content as a title.
    public static func extractTitle(from content: String) -> String? {
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}
