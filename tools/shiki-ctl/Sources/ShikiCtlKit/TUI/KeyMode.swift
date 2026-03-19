import Foundation

// MARK: - Logical Actions

public enum InputAction: Equatable, Sendable {
    // Navigation
    case next
    case prev
    case first
    case last
    case pageDown
    case pageUp
    case forward        // next tab / section
    case back           // previous tab / escape

    // Actions
    case select         // enter / open
    case approve
    case comment
    case requestChanges
    case summary
    case search
    case diff
    case fix
    case quit
    case help
}

// MARK: - Key Modes

public enum KeyMode: String, Codable, Sendable {
    case emacs
    case vim
    case arrows

    /// Map a raw KeyEvent to a logical InputAction, or nil if unmapped.
    public func mapAction(for key: KeyEvent) -> InputAction? {
        // Universal mappings (all modes)
        switch key {
        case .enter: return .select
        case .char("a"): return .approve
        case .char("c"): return .comment
        case .char("r"): return .requestChanges
        case .char("s"): return .summary
        case .char("d"): return .diff
        case .char("F"): return .fix
        case .char("/"): return .search
        case .char("?"): return .help
        default: break
        }

        // Mode-specific mappings
        switch self {
        case .emacs:
            return emacsMap(key)
        case .vim:
            return vimMap(key)
        case .arrows:
            return arrowsMap(key)
        }
    }

    // MARK: - Emacs

    private func emacsMap(_ key: KeyEvent) -> InputAction? {
        switch key {
        case .char("\u{0E}"): return .next       // Ctrl-N
        case .char("\u{10}"): return .prev       // Ctrl-P
        case .char("\u{06}"): return .forward    // Ctrl-F
        case .char("\u{02}"): return .back       // Ctrl-B
        case .char("\u{16}"): return .pageDown   // Ctrl-V
        case .char("\u{13}"): return .search     // Ctrl-S
        case .up: return .prev
        case .down: return .next
        case .escape: return .back
        case .char("q"): return .quit
        default: return nil
        }
    }

    // MARK: - Vim

    private func vimMap(_ key: KeyEvent) -> InputAction? {
        switch key {
        case .char("j"): return .next
        case .char("k"): return .prev
        case .char("h"): return .back
        case .char("l"): return .forward
        case .char("g"): return .first
        case .char("G"): return .last
        case .up: return .prev
        case .down: return .next
        case .escape: return .back
        case .char("q"): return .quit
        default: return nil
        }
    }

    // MARK: - Arrows (simple mode)

    private func arrowsMap(_ key: KeyEvent) -> InputAction? {
        switch key {
        case .up: return .prev
        case .down: return .next
        case .left: return .back
        case .right: return .forward
        case .escape: return .back
        case .char("q"): return .quit
        default: return nil
        }
    }
}
