import Foundation

/// Persists tmux status bar display state (compact vs expanded) to disk.
public final class TmuxStateManager: Sendable {
    private let statePath: String
    private let lock = NSLock()
    // Protected by `lock` — safe for Sendable despite mutability.
    nonisolated(unsafe) private var _isExpanded: Bool

    public var isExpanded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isExpanded
    }

    public init(statePath: String? = nil) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.statePath = statePath ?? "\(home)/.config/shiki/tmux-state.json"
        self._isExpanded = Self.loadState(from: self.statePath)
    }

    /// Toggle between compact and expanded mode. Persists to disk.
    public func toggle() {
        lock.lock()
        _isExpanded.toggle()
        let newValue = _isExpanded
        lock.unlock()
        saveState(expanded: newValue)
    }

    // MARK: - Persistence

    private static func loadState(from path: String) -> Bool {
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let expanded = json["expanded"] as? Bool else {
            return false
        }
        return expanded
    }

    private func saveState(expanded: Bool) {
        let json: [String: Any] = ["expanded": expanded]
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return }

        let dir = (statePath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: statePath, contents: data)
    }
}
