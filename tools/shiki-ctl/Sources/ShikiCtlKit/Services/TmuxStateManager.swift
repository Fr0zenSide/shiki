import Foundation

/// Powerline arrow separator position for tmux status bar.
/// Matches Dracula theme convention: left arrow () on left side, right arrow () on right side.
public enum ArrowStyle: String, Sendable {
    case none
    case left
    case right
    case both
}

/// Persists tmux status bar display state (compact vs expanded) and arrow style to disk.
public final class TmuxStateManager: Sendable {
    private let statePath: String
    private let lock = NSLock()
    // Protected by `lock` — safe for Sendable despite mutability.
    nonisolated(unsafe) private var _isExpanded: Bool
    nonisolated(unsafe) private var _arrowStyle: ArrowStyle

    public var isExpanded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isExpanded
    }

    public var arrowStyle: ArrowStyle {
        lock.lock()
        defer { lock.unlock() }
        return _arrowStyle
    }

    public init(statePath: String? = nil) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.statePath = statePath ?? "\(home)/.config/shiki/tmux-state.json"
        let state = Self.loadState(from: self.statePath)
        self._isExpanded = state.expanded
        self._arrowStyle = state.arrowStyle
    }

    /// Toggle between compact and expanded mode. Persists to disk.
    public func toggle() {
        lock.lock()
        _isExpanded.toggle()
        let state = (_isExpanded, _arrowStyle)
        lock.unlock()
        saveState(expanded: state.0, arrowStyle: state.1)
    }

    /// Set arrow style. Persists to disk.
    public func setArrowStyle(_ style: ArrowStyle) {
        lock.lock()
        _arrowStyle = style
        let state = (_isExpanded, _arrowStyle)
        lock.unlock()
        saveState(expanded: state.0, arrowStyle: state.1)
    }

    // MARK: - Persistence

    private struct PersistedState {
        var expanded: Bool
        var arrowStyle: ArrowStyle
    }

    private static func loadState(from path: String) -> PersistedState {
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return PersistedState(expanded: false, arrowStyle: .none)
        }
        let expanded = json["expanded"] as? Bool ?? false
        let arrowRaw = json["arrowStyle"] as? String ?? "none"
        let arrowStyle = ArrowStyle(rawValue: arrowRaw) ?? .none
        return PersistedState(expanded: expanded, arrowStyle: arrowStyle)
    }

    private func saveState(expanded: Bool, arrowStyle: ArrowStyle) {
        let json: [String: Any] = ["expanded": expanded, "arrowStyle": arrowStyle.rawValue]
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return }

        let dir = (statePath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: statePath, contents: data)
    }
}
