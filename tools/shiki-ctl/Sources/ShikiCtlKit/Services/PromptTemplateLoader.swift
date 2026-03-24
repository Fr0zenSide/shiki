import Foundation
import Logging

/// Loads and renders Mustache-lite autopilot prompt templates.
///
/// Resolution chain (most specific wins):
/// 1. Workspace: `{workspacePath}/.shiki/autopilot-prompt.md`
/// 2. User: `~/.config/shiki/autopilot-prompt.md`
/// 3. Bundled: SPM resource bundle `autopilot-prompt.md`
/// 4. Hardcoded: compiled-in constant (last resort)
///
/// Supports hot-reload: caches template + mtime, re-reads on change.
public final class PromptTemplateLoader: Sendable {

    /// Source of the resolved template.
    public enum TemplateSource: Equatable, Sendable {
        case workspace(String)
        case user(String)
        case bundled
        case hardcoded
    }

    private let workspacePath: String?
    private let logger: Logger

    // Cache state — protected by lock
    private let cache: CacheStorage

    public init(
        workspacePath: String? = nil,
        logger: Logger = Logger(label: "shiki-ctl.prompt-template")
    ) {
        self.workspacePath = workspacePath
        self.logger = logger
        self.cache = CacheStorage()
    }

    // MARK: - Public API

    /// Resolve the template from the fallback chain. Caches result, hot-reloads on file change.
    public func loadTemplate() -> (template: String, source: TemplateSource) {
        // Check workspace override
        if let wsPath = workspacePath {
            let wsFile = (wsPath as NSString).appendingPathComponent(".shiki/autopilot-prompt.md")
            if let result = loadFileIfChanged(path: wsFile, source: .workspace(wsFile)) {
                return result
            }
        }

        // Check user override
        let userFile = (NSHomeDirectory() as NSString).appendingPathComponent(".config/shiki/autopilot-prompt.md")
        if let result = loadFileIfChanged(path: userFile, source: .user(userFile)) {
            return result
        }

        // Check bundled resource
        if let bundledURL = Bundle.module.url(forResource: "autopilot-prompt", withExtension: "md"),
           let content = try? String(contentsOf: bundledURL, encoding: .utf8) {
            return (content, .bundled)
        }

        // Hardcoded fallback
        return (Self.hardcodedTemplate, .hardcoded)
    }

    /// Replace `{{variable}}` placeholders with values from the dictionary.
    /// Unknown placeholders are left as-is (no crash, no removal).
    public func render(template: String, variables: [String: String]) -> String {
        var result = template
        for (key, value) in variables {
            result = result.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        return result
    }

    // MARK: - File Loading with Cache

    private func loadFileIfChanged(path: String, source: TemplateSource) -> (String, TemplateSource)? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }

        let mtime = modificationDate(atPath: path)
        if let cached = cache.get(for: path), cached.mtime == mtime {
            return (cached.content, source)
        }

        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        cache.set(for: path, entry: CacheEntry(content: content, mtime: mtime))
        logger.debug("Loaded prompt template from: \(path)")
        return (content, source)
    }

    private func modificationDate(atPath path: String) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date
    }

    // MARK: - Thread-safe Cache

    private final class CacheStorage: @unchecked Sendable {
        private var entries: [String: CacheEntry] = [:]
        private let lock = NSLock()

        func get(for path: String) -> CacheEntry? {
            lock.lock()
            defer { lock.unlock() }
            return entries[path]
        }

        func set(for path: String, entry: CacheEntry) {
            lock.lock()
            defer { lock.unlock() }
            entries[path] = entry
        }
    }

    private struct CacheEntry {
        let content: String
        let mtime: Date?
    }

    // MARK: - Hardcoded Fallback

    /// The compiled-in default — never deleted, always available.
    public static let hardcodedTemplate = """
    You are an autonomous agent for the "{{companySlug}}" company in the Shiki orchestrator.

    ORCHESTRATOR API: {{apiBaseURL}}

    YOUR WORKFLOW:
    {{claimInstruction}}
    2. Work on the claimed task in this project directory
    3. If you need a human decision, create one: POST /api/decision-queue with {"companyId":"{{companyId}}","taskId":"<task-id>","tier":1,"question":"<your question>"}
    4. When done, update the task: PATCH /api/task-queue/<task-id> with {"status":"completed","result":{"summary":"what you did"}}
    5. Claim the next task and repeat

    HEARTBEAT (every 60s):
    POST /api/orchestrator/heartbeat with:
    {"companyId":"{{companyId}}","sessionId":"<your-session-id>","data":{
      "contextPct": <your current context usage %>,
      "compactionCount": <times you have been compacted this session>,
      "taskInProgress": "<current task title>"
    }}

    RULES:
    - Follow TDD: write failing test first, then implement
    - Run the full test suite after every change
    - Use /pre-pr before any PR
    - Send heartbeats every 60s with context data
    - If you hit a blocker that needs human input, create a T1 decision and move to the next task
    - Never push to main directly — use feature branches and PRs to develop

    START NOW: claim your first task and begin working.
    """
}
