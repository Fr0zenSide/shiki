import Foundation
import Logging

// MARK: - Recovery Source Protocols

/// Abstraction for DB event retrieval, enabling test doubles.
public protocol EventSourceProvider: Sendable {
    func fetchEvents(since: Date, until: Date, limit: Int) async throws -> [ShikkiEvent]
    func fetchPendingDecisions() async throws -> [String]
}

/// Abstraction for checkpoint loading, enabling test doubles.
public protocol CheckpointProvider: Sendable {
    func loadCheckpoint() throws -> Checkpoint?
}

/// Abstraction for git workspace queries, enabling test doubles.
/// BR-24: Never reads file contents, diffs, or .env files.
public protocol GitWorkspaceProvider: Sendable {
    func currentBranch() async -> String?
    func recentCommits(limit: Int) async -> [CommitInfo]
    func modifiedFiles() async -> [String]
    func untrackedFiles() async -> [String]
    func worktrees() async -> [WorktreeInfo]
    func aheadBehind() async -> AheadBehind?
}

// MARK: - Default Implementations

/// Fetches events from the ShikiDB backend via curl.
public struct BackendEventSource: EventSourceProvider {
    private let baseURL: String
    private let timeoutSeconds: Int
    private let logger: Logger

    public init(
        baseURL: String = "http://localhost:3900",
        timeoutSeconds: Int = 3,
        logger: Logger = Logger(label: "shikki.recovery.db")
    ) {
        self.baseURL = baseURL
        self.timeoutSeconds = timeoutSeconds
        self.logger = logger
    }

    public func fetchEvents(since: Date, until: Date, limit: Int) async throws -> [ShikkiEvent] {
        let formatter = ISO8601DateFormatter()
        let sinceStr = formatter.string(from: since)
        let untilStr = formatter.string(from: until)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "curl", "-s",
            "-w", "\n%{http_code}",
            "--max-time", "\(timeoutSeconds)",
            "\(baseURL)/api/events?since=\(sinceStr)&until=\(untilStr)&limit=\(limit)",
        ]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0, !data.isEmpty else {
            throw RecoverySourceError.unavailable("DB unreachable (exit \(process.terminationStatus))")
        }

        // Split response body and HTTP status code
        guard let responseStr = String(data: data, encoding: .utf8) else {
            throw RecoverySourceError.unavailable("Invalid response encoding")
        }

        let lines = responseStr.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count >= 2,
              let statusCode = Int(lines.last ?? ""),
              statusCode >= 200, statusCode < 300 else {
            let code = lines.last.flatMap { Int($0) } ?? 0
            throw RecoverySourceError.httpError(code, "HTTP \(code)")
        }

        // Body is everything except the last line (status code)
        let bodyStr = lines.dropLast().joined(separator: "\n")
        guard let bodyData = bodyStr.data(using: .utf8) else {
            throw RecoverySourceError.unavailable("Invalid body encoding")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([ShikkiEvent].self, from: bodyData)
    }

    public func fetchPendingDecisions() async throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "curl", "-s",
            "--max-time", "\(timeoutSeconds)",
            "\(baseURL)/api/decision-queue/pending",
        ]

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0, !data.isEmpty else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decisions = try decoder.decode([Decision].self, from: data)
        return decisions.map(\.question)
    }
}

/// Wraps CheckpointManager for the recovery protocol.
public struct CheckpointFileProvider: CheckpointProvider {
    private let manager: CheckpointManager

    public init(manager: CheckpointManager = CheckpointManager()) {
        self.manager = manager
    }

    public func loadCheckpoint() throws -> Checkpoint? {
        try manager.load()
    }
}

/// Queries git workspace via subprocess.
/// BR-24: Never reads file contents, diffs, or .env files.
public struct GitWorkspaceReader: GitWorkspaceProvider {

    public init() {}

    public func currentBranch() async -> String? {
        runGit(["rev-parse", "--abbrev-ref", "HEAD"])
    }

    public func recentCommits(limit: Int) async -> [CommitInfo] {
        guard let output = runGit([
            "log", "--format=%H|%s|%an|%aI", "-\(limit)",
        ]) else { return [] }

        let formatter = ISO8601DateFormatter()
        return output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 3)
            guard parts.count == 4,
                  let date = formatter.date(from: String(parts[3])) else { return nil }
            return CommitInfo(
                hash: String(parts[0]),
                message: String(parts[1]),
                author: String(parts[2]),
                timestamp: date
            )
        }
    }

    public func modifiedFiles() async -> [String] {
        guard let output = runGit(["diff", "--name-only"]) else { return [] }
        return output.split(separator: "\n").map(String.init)
    }

    public func untrackedFiles() async -> [String] {
        guard let output = runGit(["ls-files", "--others", "--exclude-standard"]) else { return [] }
        return output.split(separator: "\n").map(String.init)
    }

    public func worktrees() async -> [WorktreeInfo] {
        guard let output = runGit(["worktree", "list", "--porcelain"]) else { return [] }

        var result: [WorktreeInfo] = []
        var currentPath: String?
        var currentBranch: String?

        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let str = String(line)
            if str.hasPrefix("worktree ") {
                if let path = currentPath {
                    result.append(WorktreeInfo(path: path, branch: currentBranch))
                }
                currentPath = String(str.dropFirst("worktree ".count))
                currentBranch = nil
            } else if str.hasPrefix("branch refs/heads/") {
                currentBranch = String(str.dropFirst("branch refs/heads/".count))
            }
        }

        if let path = currentPath {
            result.append(WorktreeInfo(path: path, branch: currentBranch))
        }

        return result
    }

    public func aheadBehind() async -> AheadBehind? {
        guard let output = runGit(["rev-list", "--left-right", "--count", "HEAD...@{upstream}"]) else {
            return nil
        }
        let parts = output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\t")
        guard parts.count == 2,
              let ahead = Int(parts[0]),
              let behind = Int(parts[1]) else { return nil }
        return AheadBehind(ahead: ahead, behind: behind)
    }

    private func runGit(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}

// MARK: - RecoverySourceError

public enum RecoverySourceError: Error, Sendable {
    case unavailable(String)
    case httpError(Int, String)
}

// MARK: - ContextRecoveryService

/// Three-layer recovery chain: DB -> checkpoint -> git.
/// BR-02: Each source runs independently — failure in one does not block others.
/// BR-12: DB queried with 3-second timeout.
/// R1: Events validated; corrupted data skipped gracefully.
/// R3: Git fallback only reads safe metadata (no file contents, no diffs).
public struct ContextRecoveryService: Sendable {
    private let eventSource: EventSourceProvider
    private let checkpointProvider: CheckpointProvider
    private let gitProvider: GitWorkspaceProvider
    private let logger: Logger

    public init(
        eventSource: EventSourceProvider = BackendEventSource(),
        checkpointProvider: CheckpointProvider = CheckpointFileProvider(),
        gitProvider: GitWorkspaceProvider = GitWorkspaceReader(),
        logger: Logger = Logger(label: "shikki.recovery")
    ) {
        self.eventSource = eventSource
        self.checkpointProvider = checkpointProvider
        self.gitProvider = gitProvider
        self.logger = logger
    }

    /// Recover context from all available sources.
    /// BR-02: Sources run independently; partial results merged.
    public func recover(
        window: TimeWindow,
        verbose: Bool = false
    ) async -> RecoveryContext {
        var allItems: [RecoveredItem] = []
        var sources: [SourceResult] = []
        var errors: [String] = []
        var pendingDecisions: [String] = []

        // Layer 1: ShikiDB events
        let dbResult = await recoverFromDB(window: window, verbose: verbose)
        sources.append(dbResult.source)
        allItems.append(contentsOf: dbResult.items)
        errors.append(contentsOf: dbResult.errors)
        pendingDecisions = dbResult.pendingDecisions

        // Layer 2: Local checkpoint
        let cpResult = recoverFromCheckpoint(window: window)
        sources.append(cpResult.source)
        allItems.append(contentsOf: cpResult.items)
        errors.append(contentsOf: cpResult.errors)

        // Layer 3: Git workspace
        let gitResult = await recoverFromGit(window: window)
        sources.append(gitResult.source)
        allItems.append(contentsOf: gitResult.items)
        errors.append(contentsOf: gitResult.errors)

        // Deduplicate by id, DB wins (BR-05)
        allItems = deduplicateItems(allItems)

        // Sort by timestamp (newest first)
        allItems.sort { $0.timestamp > $1.timestamp }

        // Compute confidence
        let confidence = ConfidenceScore(
            dbScore: sources.first(where: { $0.name == "db" })?.score ?? 0,
            checkpointScore: sources.first(where: { $0.name == "checkpoint" })?.score ?? 0,
            gitScore: sources.first(where: { $0.name == "git" })?.score ?? 0
        )

        // Compute staleness from most recent item
        let staleness: Staleness
        if let mostRecent = allItems.first {
            staleness = Staleness.from(lastActivity: mostRecent.timestamp)
        } else {
            staleness = .ancient
        }

        return RecoveryContext(
            timeWindow: window,
            confidence: confidence,
            staleness: staleness,
            sources: sources,
            timeline: allItems,
            workspace: gitResult.workspace,
            errors: errors,
            pendingDecisions: pendingDecisions
        )
    }

    /// Recover and format for agent injection.
    /// BR-09: Compact markdown in <context-recovery> tags. Default 2KB budget.
    public func recoverForAgent(
        window: TimeWindow,
        budget: Int = 2048
    ) async -> String {
        let context = await recover(window: window, verbose: false)
        return DiagnosticFormatter.formatAgent(context, budget: budget)
    }

    // MARK: - Layer 1: DB

    private struct DBRecoveryResult: Sendable {
        let source: SourceResult
        let items: [RecoveredItem]
        let errors: [String]
        let pendingDecisions: [String]
    }

    private func recoverFromDB(window: TimeWindow, verbose: Bool) async -> DBRecoveryResult {
        do {
            let events = try await eventSource.fetchEvents(
                since: window.since,
                until: window.until,
                limit: 200
            )

            // R1: Validate events
            let (validEvents, invalidCount) = validateEvents(events)

            // R1: If >50% invalid, mark as corrupted
            let status: SourceStatus
            if !events.isEmpty, Double(invalidCount) / Double(events.count) > 0.5 {
                status = .corrupted
            } else if invalidCount > 0 {
                status = .partial
            } else {
                status = .available
            }

            let items = validEvents.map { event in
                RecoveredItem(
                    id: event.id.uuidString,
                    timestamp: event.timestamp,
                    provenance: .db,
                    kind: itemKind(for: event.type),
                    summary: summarizeEvent(event),
                    detail: verbose ? detailForEvent(event) : nil
                )
            }

            let score = ConfidenceScore.dbSourceScore(
                eventCount: validEvents.count,
                available: status != .corrupted
            )

            var errors: [String] = []
            if invalidCount > 0 {
                errors.append("DB: \(invalidCount) event(s) failed validation")
            }

            // Fetch pending decisions
            let decisions: [String]
            do {
                decisions = try await eventSource.fetchPendingDecisions()
            } catch {
                decisions = []
            }

            return DBRecoveryResult(
                source: SourceResult(
                    name: "db",
                    status: status,
                    itemCount: validEvents.count,
                    score: score
                ),
                items: items,
                errors: errors,
                pendingDecisions: decisions
            )
        } catch {
            logger.warning("DB recovery failed: \(error)")
            let errorMsg: String
            if let recoveryError = error as? RecoverySourceError {
                switch recoveryError {
                case .unavailable(let msg):
                    errorMsg = "DB: \(msg)"
                case .httpError(let code, let msg):
                    errorMsg = "DB: HTTP \(code) — \(msg)"
                }
            } else {
                errorMsg = "DB: \(error.localizedDescription)"
            }

            return DBRecoveryResult(
                source: SourceResult(
                    name: "db",
                    status: .unavailable,
                    itemCount: 0,
                    score: 0,
                    error: errorMsg
                ),
                items: [],
                errors: [errorMsg],
                pendingDecisions: []
            )
        }
    }

    /// Validate events. Returns valid events and count of invalid ones.
    /// R1: Check id is UUID, timestamp is parseable, type is known.
    private func validateEvents(_ events: [ShikkiEvent]) -> ([ShikkiEvent], Int) {
        var valid: [ShikkiEvent] = []
        var invalidCount = 0

        for event in events {
            // id is already UUID type, timestamp is already Date — decoded successfully
            // Check for unknown custom types or other anomalies
            if case .custom(let name) = event.type, name.isEmpty {
                invalidCount += 1
                continue
            }
            valid.append(event)
        }

        return (valid, invalidCount)
    }

    // MARK: - Layer 2: Checkpoint

    private struct CheckpointRecoveryResult: Sendable {
        let source: SourceResult
        let items: [RecoveredItem]
        let errors: [String]
    }

    private func recoverFromCheckpoint(window: TimeWindow) -> CheckpointRecoveryResult {
        do {
            guard let checkpoint = try checkpointProvider.loadCheckpoint() else {
                return CheckpointRecoveryResult(
                    source: SourceResult(name: "checkpoint", status: .unavailable, itemCount: 0, score: 0),
                    items: [],
                    errors: []
                )
            }

            let withinWindow = checkpoint.timestamp >= window.since && checkpoint.timestamp <= window.until
            let score = ConfidenceScore.checkpointSourceScore(exists: true, withinWindow: withinWindow)

            var items: [RecoveredItem] = []

            // Extract FSM state
            items.append(RecoveredItem(
                id: "checkpoint-state-\(checkpoint.timestamp.timeIntervalSince1970)",
                timestamp: checkpoint.timestamp,
                provenance: .checkpoint,
                kind: .checkpoint,
                summary: "FSM state: \(checkpoint.fsmState.rawValue)",
                detail: checkpoint.contextSnippet
            ))

            // Extract session stats if available
            if let stats = checkpoint.sessionStats {
                items.append(RecoveredItem(
                    id: "checkpoint-session-\(checkpoint.timestamp.timeIntervalSince1970)",
                    timestamp: stats.startedAt,
                    provenance: .checkpoint,
                    kind: .checkpoint,
                    summary: "Session on \(stats.branch): \(stats.commitCount) commits, \(stats.linesChanged) lines changed"
                ))
            }

            return CheckpointRecoveryResult(
                source: SourceResult(
                    name: "checkpoint",
                    status: .available,
                    itemCount: items.count,
                    score: score
                ),
                items: items,
                errors: []
            )
        } catch {
            logger.warning("Checkpoint recovery failed: \(error)")
            return CheckpointRecoveryResult(
                source: SourceResult(
                    name: "checkpoint",
                    status: .unavailable,
                    itemCount: 0,
                    score: 0,
                    error: "Checkpoint: \(error.localizedDescription)"
                ),
                items: [],
                errors: ["Checkpoint: \(error.localizedDescription)"]
            )
        }
    }

    // MARK: - Layer 3: Git

    private struct GitRecoveryResult: Sendable {
        let source: SourceResult
        let items: [RecoveredItem]
        let errors: [String]
        let workspace: WorkspaceSnapshot
    }

    private func recoverFromGit(window: TimeWindow) async -> GitRecoveryResult {
        let branch = await gitProvider.currentBranch()
        let commits = await gitProvider.recentCommits(limit: 10)
        let modified = await gitProvider.modifiedFiles()
        let untracked = await gitProvider.untrackedFiles()
        let trees = await gitProvider.worktrees()
        let ab = await gitProvider.aheadBehind()

        let workspace = WorkspaceSnapshot(
            branch: branch,
            recentCommits: commits,
            modifiedFiles: modified,
            untrackedFiles: untracked,
            worktrees: trees,
            aheadBehind: ab
        )

        // Filter commits within time window
        let windowCommits = commits.filter { $0.timestamp >= window.since && $0.timestamp <= window.until }
        let hasCommits = !windowCommits.isEmpty
        let isDirty = !modified.isEmpty || !untracked.isEmpty
        let score = ConfidenceScore.gitSourceScore(hasCommits: hasCommits, isDirty: isDirty)

        var items: [RecoveredItem] = []

        for commit in windowCommits {
            items.append(RecoveredItem(
                id: "git-\(commit.hash)",
                timestamp: commit.timestamp,
                provenance: .git,
                kind: .commit,
                summary: commit.message
            ))
        }

        // Add modified files as a single item if dirty
        if isDirty {
            let fileCount = modified.count + untracked.count
            items.append(RecoveredItem(
                timestamp: Date(),
                provenance: .git,
                kind: .file,
                summary: "\(fileCount) file(s) with uncommitted changes"
            ))
        }

        let status: SourceStatus = (branch != nil) ? .available : .unavailable

        return GitRecoveryResult(
            source: SourceResult(
                name: "git",
                status: status,
                itemCount: items.count,
                score: score
            ),
            items: items,
            errors: [],
            workspace: workspace
        )
    }

    // MARK: - Helpers

    /// Deduplicate items by id. DB provenance wins (BR-05).
    private func deduplicateItems(_ items: [RecoveredItem]) -> [RecoveredItem] {
        var seen: [String: RecoveredItem] = [:]
        for item in items {
            if let existing = seen[item.id] {
                // DB wins over other provenances
                if item.provenance == .db && existing.provenance != .db {
                    seen[item.id] = item
                }
                // Otherwise keep existing
            } else {
                seen[item.id] = item
            }
        }
        return Array(seen.values)
    }

    private func itemKind(for type: EventType) -> ItemKind {
        switch type {
        case .decisionPending, .decisionAnswered, .decisionUnblocked:
            return .decision
        default:
            return .event
        }
    }

    private func summarizeEvent(_ event: ShikkiEvent) -> String {
        var parts: [String] = []
        parts.append("[\(stringForEventType(event.type))]")

        if let branch = event.metadata?.branch {
            parts.append("on \(branch)")
        }

        // Add a payload summary
        if !event.payload.isEmpty {
            let keys = event.payload.keys.sorted().prefix(3).joined(separator: ", ")
            parts.append("(\(keys))")
        }

        return parts.joined(separator: " ")
    }

    private func detailForEvent(_ event: ShikkiEvent) -> String? {
        guard !event.payload.isEmpty else { return nil }
        let pairs = event.payload.sorted(by: { $0.key < $1.key }).map { key, value in
            "\(key): \(stringForEventValue(value))"
        }
        return pairs.joined(separator: ", ")
    }

    private func stringForEventType(_ type: EventType) -> String {
        switch type {
        case .sessionStart: return "sessionStart"
        case .sessionEnd: return "sessionEnd"
        case .sessionTransition: return "sessionTransition"
        case .contextCompaction: return "contextCompaction"
        case .heartbeat: return "heartbeat"
        case .codeChange: return "codeChange"
        case .testRun: return "testRun"
        case .buildResult: return "buildResult"
        case .decisionPending: return "decisionPending"
        case .decisionAnswered: return "decisionAnswered"
        case .decisionUnblocked: return "decisionUnblocked"
        case .shipStarted: return "shipStarted"
        case .shipCompleted: return "shipCompleted"
        case .custom(let name): return "custom(\(name))"
        default: return "event"
        }
    }

    private func stringForEventValue(_ value: EventValue) -> String {
        switch value {
        case .string(let s): return s.count > 100 ? "string(\(s.count) chars)" : s
        case .int(let i): return "\(i)"
        case .double(let d): return "\(d)"
        case .bool(let b): return "\(b)"
        case .null: return "null"
        }
    }
}
