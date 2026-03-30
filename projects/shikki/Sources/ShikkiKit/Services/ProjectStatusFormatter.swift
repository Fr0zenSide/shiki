import Foundation

/// Formats project context (language version + test status) for tmux status bar.
public enum ProjectStatusFormatter {

    /// Detected project information.
    public struct ProjectInfo: Sendable {
        public let language: Language
        public let version: String?
        public let projectName: String?

        public init(language: Language, version: String? = nil, projectName: String? = nil) {
            self.language = language
            self.version = version
            self.projectName = projectName
        }
    }

    /// Test results from last run.
    public struct TestStatus: Sendable {
        public let passed: Int
        public let total: Int
        public let failed: Int

        public var allPassing: Bool { failed == 0 && total > 0 }

        public init(passed: Int, total: Int, failed: Int) {
            self.passed = passed
            self.total = total
            self.failed = failed
        }
    }

    public enum Language: String, Sendable {
        case swift, go, rust, node, python, kotlin, java, deno, unknown

        public var icon: String {
            switch self {
            case .swift:   return ""
            case .go:      return ""
            case .rust:    return ""
            case .node:    return ""
            case .python:  return ""
            case .kotlin:  return ""
            case .java:    return ""
            case .deno:    return "🦕"
            case .unknown: return ""
            }
        }
    }

    // MARK: - Dracula ANSI Colors

    private static let purple = "\u{1B}[38;2;189;147;249m"
    private static let green  = "\u{1B}[38;2;80;250;123m"
    private static let yellow = "\u{1B}[38;2;241;250;140m"
    private static let red    = "\u{1B}[38;2;255;85;85m"
    private static let cyan   = "\u{1B}[38;2;139;233;253m"
    private static let fg     = "\u{1B}[38;2;248;248;242m"
    private static let dim    = "\u{1B}[38;2;98;114;164m"
    private static let reset  = "\u{1B}[0m"

    // MARK: - Format

    /// Project context for tmux: " 6.0 ✓310/310"
    public static func format(
        project: ProjectInfo?,
        tests: TestStatus?,
        arrowStyle: ArrowStyle = .none
    ) -> String {
        guard let project = project else {
            return MiniStatusFormatter.wrapWithArrows("\(dim)no project\(reset)", style: arrowStyle)
        }

        var parts: [String] = []

        // Language icon + version
        let icon = project.language.icon
        if let version = project.version {
            parts.append("\(cyan)\(icon) \(version)\(reset)")
        } else {
            parts.append("\(cyan)\(icon)\(reset)")
        }

        // Test status
        if let tests = tests {
            if tests.allPassing {
                parts.append("\(green)✓\(tests.passed)/\(tests.total)\(reset)")
            } else if tests.failed > 0 {
                parts.append("\(red)✗\(tests.passed)/\(tests.total)\(reset)")
            } else {
                parts.append("\(dim)?\(tests.total)\(reset)")
            }
        }

        let content = parts.joined(separator: " ")
        return MiniStatusFormatter.wrapWithArrows(content, style: arrowStyle)
    }

    // MARK: - Detection

    /// Detect project language from directory contents.
    public static func detectProject(at path: String) -> ProjectInfo? {
        let fm = FileManager.default

        // Swift (Package.swift or *.xcodeproj)
        if fm.fileExists(atPath: "\(path)/Package.swift") {
            let version = shell("swift --version 2>/dev/null | head -1 | sed 's/.*version //' | sed 's/ .*//'")
            let name = extractPackageName(at: path)
            return ProjectInfo(language: .swift, version: version.isEmpty ? nil : version, projectName: name)
        }

        // Go
        if fm.fileExists(atPath: "\(path)/go.mod") {
            let version = shell("go version 2>/dev/null | awk '{print $3}' | sed 's/go//'")
            return ProjectInfo(language: .go, version: version.isEmpty ? nil : version)
        }

        // Rust
        if fm.fileExists(atPath: "\(path)/Cargo.toml") {
            let version = shell("rustc --version 2>/dev/null | awk '{print $2}'")
            return ProjectInfo(language: .rust, version: version.isEmpty ? nil : version)
        }

        // Node
        if fm.fileExists(atPath: "\(path)/package.json") {
            // Check if it's Deno
            if fm.fileExists(atPath: "\(path)/deno.json") || fm.fileExists(atPath: "\(path)/deno.jsonc") {
                let version = shell("deno --version 2>/dev/null | head -1 | awk '{print $2}'")
                return ProjectInfo(language: .deno, version: version.isEmpty ? nil : version)
            }
            let version = shell("node --version 2>/dev/null | sed 's/v//'")
            return ProjectInfo(language: .node, version: version.isEmpty ? nil : version)
        }

        // Python
        if fm.fileExists(atPath: "\(path)/pyproject.toml") || fm.fileExists(atPath: "\(path)/setup.py") {
            let version = shell("python3 --version 2>/dev/null | awk '{print $2}'")
            return ProjectInfo(language: .python, version: version.isEmpty ? nil : version)
        }

        // Kotlin
        if fm.fileExists(atPath: "\(path)/build.gradle.kts") {
            let version = shell("kotlin -version 2>/dev/null | awk '{print $3}'")
            return ProjectInfo(language: .kotlin, version: version.isEmpty ? nil : version)
        }

        // Java
        if fm.fileExists(atPath: "\(path)/pom.xml") || fm.fileExists(atPath: "\(path)/build.gradle") {
            let version = shell("java --version 2>/dev/null | head -1 | awk '{print $2}'")
            return ProjectInfo(language: .java, version: version.isEmpty ? nil : version)
        }

        return nil
    }

    /// Read cached test results. Tests are expensive — we cache the result and refresh on demand.
    /// Cache file: ~/.config/shiki/test-cache/<project-hash>.json
    public static func readCachedTests(at path: String) -> TestStatus? {
        let hash = path.data(using: .utf8)?.hashValue ?? 0
        let cachePath = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.config/shiki/test-cache/\(abs(hash)).json"

        guard let data = FileManager.default.contents(atPath: cachePath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let passed = json["passed"] as? Int,
              let total = json["total"] as? Int,
              let failed = json["failed"] as? Int else {
            return nil
        }
        return TestStatus(passed: passed, total: total, failed: failed)
    }

    /// Write test results to cache.
    public static func cacheTestResults(_ status: TestStatus, at path: String) {
        let hash = path.data(using: .utf8)?.hashValue ?? 0
        let cacheDir = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.config/shiki/test-cache"
        let cachePath = "\(cacheDir)/\(abs(hash)).json"

        let json: [String: Any] = ["passed": status.passed, "total": status.total, "failed": status.failed]
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return }

        try? FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: cachePath, contents: data)
    }

    // MARK: - Helpers

    private static func extractPackageName(at path: String) -> String? {
        let packagePath = "\(path)/Package.swift"
        guard let content = try? String(contentsOfFile: packagePath, encoding: .utf8) else { return nil }
        // Match: name: "SomeName"
        if let range = content.range(of: #"name:\s*"([^"]+)""#, options: .regularExpression) {
            let match = content[range]
            if let nameRange = match.range(of: #""([^"]+)""#, options: .regularExpression) {
                return String(match[nameRange]).replacingOccurrences(of: "\"", with: "")
            }
        }
        return nil
    }

    private static func shell(_ command: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
