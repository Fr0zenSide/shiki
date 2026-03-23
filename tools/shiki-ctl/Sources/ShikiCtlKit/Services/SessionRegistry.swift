import Foundation
import Logging

// MARK: - Discovery Protocol

/// A discovered tmux pane representing a potential session.
public struct DiscoveredSession: Sendable {
    public let windowName: String
    public let paneId: String
    public let pid: pid_t

    public init(windowName: String, paneId: String, pid: pid_t) {
        self.windowName = windowName
        self.paneId = paneId
        self.pid = pid
    }
}

/// Protocol for discovering active tmux sessions.
public protocol SessionDiscoverer: Sendable {
    func discover() async -> [DiscoveredSession]
}

// MARK: - TmuxDiscoverer

/// Discovers sessions by parsing `tmux list-panes` for the shiki session.
public struct TmuxDiscoverer: SessionDiscoverer {
    let sessionName: String

    public init(sessionName: String = "shiki") {
        self.sessionName = sessionName
    }

    public func discover() async -> [DiscoveredSession] {
        guard let output = runCapture("tmux", arguments: [
            "list-panes", "-s", "-t", sessionName,
            "-F", "#{session_name}:#{window_name} #{pane_id} #{pane_pid}",
        ]) else { return [] }
        return Self.parsePaneOutput(output, sessionName: sessionName)
    }

    /// Parse tmux list-panes output into discovered sessions.
    /// Format: "{session}:{window} {pane_id} {pid}"
    public static func parsePaneOutput(_ output: String, sessionName: String) -> [DiscoveredSession] {
        output.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }

            let parts = trimmed.split(separator: " ", maxSplits: 2)
            guard parts.count >= 2 else { return nil }

            let fullName = String(parts[0])
            let paneId = String(parts[1])
            let pid = parts.count > 2 ? pid_t(String(parts[2]).trimmingCharacters(in: .whitespaces)) ?? 0 : 0

            // Filter to our session
            let prefix = "\(sessionName):"
            guard fullName.hasPrefix(prefix) else { return nil }

            let windowName = String(fullName.dropFirst(prefix.count))
            return DiscoveredSession(windowName: windowName, paneId: paneId, pid: pid)
        }
    }

    private func runCapture(_ executable: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            // Read before waitUntilExit to avoid pipe buffer deadlock
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}

// MARK: - Registered Session

/// A tracked session in the registry.
public struct RegisteredSession: Sendable {
    public let windowName: String
    public let paneId: String
    public let pid: pid_t
    public private(set) var state: SessionState
    public private(set) var attentionZone: AttentionZone
    public var lastSeen: Date
    public var context: TaskContext?

    public init(
        windowName: String, paneId: String, pid: pid_t,
        state: SessionState = .spawning, lastSeen: Date = Date(),
        context: TaskContext? = nil
    ) {
        self.windowName = windowName
        self.paneId = paneId
        self.pid = pid
        self.state = state
        self.attentionZone = state.attentionZone
        self.lastSeen = lastSeen
        self.context = context
    }

    mutating func updateState(_ newState: SessionState) {
        state = newState
        attentionZone = newState.attentionZone
    }
}

// MARK: - SessionRegistry Actor

/// Central registry of all active sessions with discovery, reconciliation, and reaping.
public actor SessionRegistry {
    private let discoverer: SessionDiscoverer
    private let journal: SessionJournal
    private let logger: Logger
    private var sessions: [String: RegisteredSession] = [:]

    /// Windows that are infrastructure, never tracked as task sessions.
    private static let reservedWindows: Set<String> = ["orchestrator"]

    /// States that are never reaped even if stale.
    private static let protectedStates: Set<SessionState> = [.awaitingApproval, .budgetPaused]

    public init(
        discoverer: SessionDiscoverer,
        journal: SessionJournal,
        logger: Logger = Logger(label: "shiki-ctl.registry")
    ) {
        self.discoverer = discoverer
        self.journal = journal
        self.logger = logger
    }

    // MARK: - Public API

    /// 4-phase pipeline: discover → reconcile → transition → reap.
    public func refresh() async {
        let discovered = await discoverer.discover()

        // Filter out reserved windows
        let taskSessions = discovered.filter { !Self.reservedWindows.contains($0.windowName) }

        // Phase 1: Register new sessions
        for session in taskSessions {
            if sessions[session.windowName] == nil {
                sessions[session.windowName] = RegisteredSession(
                    windowName: session.windowName,
                    paneId: session.paneId,
                    pid: session.pid,
                    state: .working
                )
            } else {
                sessions[session.windowName]?.lastSeen = Date()
            }
        }

        // Phase 2: Reconcile — find missing panes
        let discoveredNames = Set(taskSessions.map(\.windowName))
        let staleness: TimeInterval = 300 // 5 minutes

        var toReap: [String] = []
        for (name, session) in sessions {
            if !discoveredNames.contains(name) {
                // Pane missing — check staleness
                let age = Date().timeIntervalSince(session.lastSeen)
                if age > staleness && !Self.protectedStates.contains(session.state) {
                    toReap.append(name)
                }
            }
        }

        // Phase 3: Reap stale sessions
        for name in toReap {
            if let session = sessions[name] {
                let checkpoint = SessionCheckpoint(
                    sessionId: name, state: .done,
                    reason: .stateTransition,
                    metadata: ["reapReason": "stale_\(Int(Date().timeIntervalSince(session.lastSeen)))s"]
                )
                try? await journal.checkpoint(checkpoint)
            }
            sessions.removeValue(forKey: name)
            logger.info("Reaped stale session: \(name)")
        }
    }

    /// Manually register a session (used by CompanyLauncher after dispatch).
    public func register(
        windowName: String, paneId: String, pid: pid_t,
        context: TaskContext
    ) {
        sessions[windowName] = RegisteredSession(
            windowName: windowName, paneId: paneId, pid: pid,
            state: .spawning, context: context
        )
    }

    /// Remove a session from the registry.
    public func deregister(windowName: String) {
        sessions.removeValue(forKey: windowName)
    }

    /// All sessions sorted by attention zone (most urgent first).
    public func sessionsByAttention() -> [RegisteredSession] {
        sessions.values.sorted { $0.attentionZone < $1.attentionZone }
    }

    /// All registered sessions (unordered).
    public var allSessions: [RegisteredSession] {
        Array(sessions.values)
    }

    // MARK: - Testing Helpers

    /// Register a session with explicit state (for tests).
    public func registerManual(
        windowName: String, paneId: String, pid: pid_t,
        state: SessionState
    ) {
        sessions[windowName] = RegisteredSession(
            windowName: windowName, paneId: paneId, pid: pid,
            state: state
        )
    }

    /// Override lastSeen for a session (for tests).
    public func setLastSeen(windowName: String, date: Date) {
        sessions[windowName]?.lastSeen = date
    }

    /// Override state for a session (for tests).
    public func setSessionState(windowName: String, state: SessionState) {
        sessions[windowName]?.updateState(state)
    }
}
