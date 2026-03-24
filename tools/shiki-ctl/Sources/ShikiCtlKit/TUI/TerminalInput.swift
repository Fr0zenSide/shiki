import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// MARK: - Key Events

public enum KeyEvent: Equatable, Sendable {
    case up
    case down
    case left
    case right
    case enter
    case escape
    case tab
    case backspace
    case space          // 0x20 — batch toggle
    case ctrlZ          // 0x1A — undo
    case delete         // forward delete (CSI 3~)
    case char(Character)
    case unknown
}

// MARK: - Raw Terminal Mode

public struct RawMode {
    private var original: termios

    /// Enable raw mode on stdin. Call `restore()` when done.
    public init() {
        original = termios()
        tcgetattr(STDIN_FILENO, &original)

        var raw = original
        // Disable canonical mode + echo
        raw.c_lflag &= ~UInt(ICANON | ECHO)
        // Read 1 byte at a time, no timeout
        raw.c_cc.16 = 1  // VMIN
        raw.c_cc.17 = 0  // VTIME
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
    }

    /// Restore original terminal settings.
    public func restore() {
        var orig = original
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &orig)
    }
}

// MARK: - Key Reading

public enum TerminalInput {

    /// Read a single key event from stdin. Blocks until input is available.
    public static func readKey() -> KeyEvent {
        var buf: [UInt8] = [0]
        let n = read(STDIN_FILENO, &buf, 1)
        guard n == 1 else { return .unknown }

        switch buf[0] {
        case 0x1B: // Escape or escape sequence
            return parseEscapeSequence()
        case 0x0A, 0x0D: // Enter
            return .enter
        case 0x09: // Tab
            return .tab
        case 0x1A: // Ctrl-Z
            return .ctrlZ
        case 0x20: // Space
            return .space
        case 0x7F, 0x08: // Backspace / Delete
            return .backspace
        default:
            let scalar = Unicode.Scalar(buf[0])
            return .char(Character(scalar))
        }
    }

    private static func parseEscapeSequence() -> KeyEvent {
        // Check if more bytes are available (escape sequence vs bare Escape)
        var buf: [UInt8] = [0]

        // Use a non-blocking read with a short timeout
        var pollFd = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
        let ready = poll(&pollFd, 1, 50) // 50ms timeout
        guard ready > 0 else { return .escape }

        let n = read(STDIN_FILENO, &buf, 1)
        guard n == 1 else { return .escape }

        if buf[0] == UInt8(ascii: "[") {
            // CSI sequence
            var csiBuf: [UInt8] = [0]
            let cn = read(STDIN_FILENO, &csiBuf, 1)
            guard cn == 1 else { return .escape }

            switch csiBuf[0] {
            case UInt8(ascii: "A"): return .up
            case UInt8(ascii: "B"): return .down
            case UInt8(ascii: "C"): return .right
            case UInt8(ascii: "D"): return .left
            case UInt8(ascii: "3"):
                // Forward delete: ESC [ 3 ~
                var tildeBuf: [UInt8] = [0]
                let tn = read(STDIN_FILENO, &tildeBuf, 1)
                if tn == 1, tildeBuf[0] == UInt8(ascii: "~") {
                    return .delete
                }
                return .unknown
            default: return .unknown
            }
        }

        return .unknown
    }
}
