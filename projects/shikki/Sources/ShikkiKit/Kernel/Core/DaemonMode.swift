import Foundation

/// Operating mode for the Shikki daemon.
///
/// - `persistent`: Long-running daemon kept alive by the OS (launchd KeepAlive / systemd Restart=always).
/// - `scheduled`: Oneshot process invoked on a timer (launchd StartInterval / systemd timer unit).
public enum DaemonMode: String, Sendable {
    case persistent
    case scheduled
}
