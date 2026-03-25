import Foundation

/// Renders the tmux popup command grid for `shiki menu`.
public enum MenuRenderer {

    /// Render the command grid as a string (no ANSI — tmux popup handles borders).
    public static func renderGrid() -> String {
        let lines = [
            "┌─ SHIKKI ─────────────────────────┐",
            "│  S  status      D  decide        │",
            "│  A  attach      O  observe       │",
            "│  /  search      @  chat          │",
            "│  E  edit        DR doctor        │",
            "│  UP start       DN stop          │",
            "│  R  reload      T  toggle bar    │",
            "│  Esc close                       │",
            "└──────────────────────────────────┘",
        ]
        return lines.joined(separator: "\n")
    }

    /// Map a key press to a shiki subcommand name, or nil for unknown/Esc.
    public static func commandForKey(_ key: String) -> String? {
        switch key.lowercased() {
        case "s": return "status"
        case "a": return "attach"
        case "/": return "search"
        case "e": return "edit"
        case "d": return "decide"
        case "o": return "observe"
        case "@": return "chat"
        case "r": return "reload"
        case "t": return "toggle"
        default: return nil
        }
    }
}
