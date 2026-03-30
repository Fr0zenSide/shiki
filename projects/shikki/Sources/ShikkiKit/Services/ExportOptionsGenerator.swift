import Foundation

// MARK: - ExportOptionsGenerator

/// Generates ExportOptions.plist from AppConfig at archive time.
/// No manual plist maintenance required.
public struct ExportOptionsGenerator: Sendable {

    public init() {}

    /// Generate ExportOptions.plist content for the given app config.
    /// - Parameters:
    ///   - config: The app configuration
    ///   - signingStyle: "automatic" or "manual" (default: automatic)
    /// - Returns: Plist XML string
    public func generate(for config: AppConfig, signingStyle: String = "automatic") -> String {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>method</key>
            <string>\(config.exportMethod)</string>
            <key>teamID</key>
            <string>\(config.teamID)</string>
            <key>signingStyle</key>
            <string>\(signingStyle)</string>
            <key>destination</key>
            <string>export</string>
            <key>uploadSymbols</key>
            <true/>
            <key>uploadBitcode</key>
            <false/>
        </dict>
        </plist>
        """
        return plist
    }

    /// Write ExportOptions.plist to a temporary file and return the path.
    public func write(for config: AppConfig, to directory: String) throws -> String {
        let content = generate(for: config)
        let path = "\(directory)/ExportOptions.plist"

        try FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true
        )
        try content.write(toFile: path, atomically: true, encoding: .utf8)

        return path
    }
}
