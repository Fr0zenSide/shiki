import Foundation

/// Protocol for key reading — enables test injection.
/// Real implementation wraps TerminalInput + RawMode.
public protocol KeyReading: Sendable {
    func readKeyWithTimeout(ms: Int) -> KeyEvent?
}

/// Result of a countdown.
public enum CountdownResult: Equatable, Sendable {
    case completed    // Countdown reached zero
    case cancelled    // User pressed Esc (BR-16)
    case immediate    // Countdown was 0 (BR-14)
}

/// Configurable countdown timer with Esc cancel support.
/// BR-13: Default 3s, configurable 0-60.
/// BR-14: 0 = immediate.
/// BR-15: Tick shows save description via onTick closure.
/// BR-16: Esc cancels → STOPPING→RUNNING.
/// BR-17: Non-TTY disables Esc detection.
public struct CountdownTimer: Sendable {
    public static let defaultCountdown = 3

    let isInteractive: Bool
    let keyReader: (any KeyReading)?
    let onTick: @Sendable (Int) -> Void
    let sleepDuration: Duration

    public init(
        isInteractive: Bool = false,
        keyReader: (any KeyReading)? = nil,
        onTick: @escaping @Sendable (Int) -> Void = { _ in },
        sleepDuration: Duration = .seconds(1)
    ) {
        self.isInteractive = isInteractive
        self.keyReader = keyReader
        self.onTick = onTick
        self.sleepDuration = sleepDuration
    }

    /// Clamp seconds to valid range [0, 60].
    public static func clampSeconds(_ seconds: Int) -> Int {
        max(0, min(60, seconds))
    }

    /// Run the countdown. Returns result indicating completion, cancellation, or immediate.
    public func run(seconds: Int) async -> CountdownResult {
        let clamped = Self.clampSeconds(seconds)

        // BR-14: countdown 0 = immediate
        guard clamped > 0 else { return .immediate }

        for remaining in stride(from: clamped, through: 1, by: -1) {
            // BR-15: Notify tick handler
            onTick(remaining)

            // BR-16: Check for Esc key (only if interactive, BR-17)
            if isInteractive, let reader = keyReader {
                if let key = reader.readKeyWithTimeout(ms: 50), key == .escape {
                    return .cancelled
                }
            }

            // Sleep for tick duration
            if sleepDuration > .zero {
                try? await Task.sleep(for: sleepDuration)
            }
        }

        return .completed
    }
}

/// Real key reader that wraps TerminalInput with RawMode.
/// Used in production; tests inject MockKeyReader instead.
public struct TerminalKeyReader: KeyReading, Sendable {
    public init() {}

    public func readKeyWithTimeout(ms: Int) -> KeyEvent? {
        // Use poll to check if input is available within timeout
        var pollFd = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
        let ready = poll(&pollFd, 1, Int32(ms))
        guard ready > 0 else { return nil }
        return TerminalInput.readKey()
    }
}
