import Dispatch
import Foundation

/// Installs POSIX signal handlers for daemon lifecycle management.
///
/// - **SIGTERM / SIGINT**: Trigger graceful shutdown (stop services, write PID, exit).
/// - **SIGHUP**: Trigger config reload (re-read `~/.shikki/config.yaml`, update theme).
///
/// Uses `DispatchSource.makeSignalSource` for SIGHUP (async-safe) and
/// `signal()` for SIGTERM/SIGINT (immediate process-level handling).
///
/// Thread-safe: all callbacks are `@Sendable`. Can be called multiple times;
/// each call replaces the previous handlers.
public enum DaemonSignalHandler {

    // MARK: - State

    /// Retained dispatch sources to prevent deallocation.
    /// Protected by `lock` -- `nonisolated(unsafe)` tells the compiler
    /// that external synchronization is in place (Swift 6 strict concurrency).
    private static let lock = NSLock()
    nonisolated(unsafe) private static var sighupSource: DispatchSourceSignal?
    nonisolated(unsafe) private static var sigtermSource: DispatchSourceSignal?
    nonisolated(unsafe) private static var sigintSource: DispatchSourceSignal?

    // MARK: - Public API

    /// Install signal handlers for daemon mode.
    ///
    /// - Parameters:
    ///   - onShutdown: Called when SIGTERM or SIGINT is received. Must be safe to call from any thread.
    ///   - onReload: Called when SIGHUP is received. Should re-read config and update state.
    public static func install(
        onShutdown: @escaping @Sendable () -> Void,
        onReload: @escaping @Sendable () -> Void
    ) {
        lock.lock()
        defer { lock.unlock() }

        // Cancel any existing sources
        sighupSource?.cancel()
        sigtermSource?.cancel()
        sigintSource?.cancel()

        // Ignore default signal handling so DispatchSource can intercept
        signal(SIGHUP, SIG_IGN)
        signal(SIGTERM, SIG_IGN)
        signal(SIGINT, SIG_IGN)

        // SIGHUP -> config reload
        let hupSource = DispatchSource.makeSignalSource(signal: SIGHUP, queue: .global())
        hupSource.setEventHandler {
            onReload()
        }
        hupSource.resume()
        sighupSource = hupSource

        // SIGTERM -> graceful shutdown
        let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
        termSource.setEventHandler {
            onShutdown()
        }
        termSource.resume()
        sigtermSource = termSource

        // SIGINT -> graceful shutdown (Ctrl-C)
        let intSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
        intSource.setEventHandler {
            onShutdown()
        }
        intSource.resume()
        sigintSource = intSource
    }
}
